package core

import (
	"context"
	"errors"
	"io"
	"net"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

type staleTransport struct {
	constant.ProxyAdapter
	typeOf constant.AdapterType
	stale  bool
	closed bool
}

func (p *staleTransport) Type() constant.AdapterType { return p.typeOf }

func (p *staleTransport) Close() error {
	p.closed = true
	p.stale = false
	return nil
}

func (p *staleTransport) DialContext(ctx context.Context, metadata *constant.Metadata) (constant.Conn, error) {
	if p.stale {
		return nil, errors.New("old network transport is still cached")
	}
	return p.ProxyAdapter.DialContext(ctx, metadata)
}

func TestNetworkResetReleasesReusableHy2TransportWithoutClosingTerminalClients(t *testing.T) {
	hy2 := &staleTransport{
		ProxyAdapter: outbound.NewDirectWithOption(outbound.DirectOption{Name: "hy2"}),
		typeOf:       constant.Hysteria2,
		stale:        true,
	}
	anyTLS := &staleTransport{
		ProxyAdapter: outbound.NewDirectWithOption(outbound.DirectOption{Name: "anytls"}),
		typeOf:       constant.AnyTLS,
	}
	tunnel.UpdateProxies(map[string]constant.Proxy{
		"hy2": adapter.NewProxy(hy2), "anytls": adapter.NewProxy(anyTLS),
	}, nil)
	t.Cleanup(func() { tunnel.UpdateProxies(nil, nil) })
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = listener.Close() })
	address := listener.Addr().(*net.TCPAddr)
	metadata := &constant.Metadata{Host: "127.0.0.1", DstPort: uint16(address.Port)}
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if conn, err := hy2.DialContext(ctx, metadata); err == nil {
		_ = conn.Close()
		t.Fatal("stale transport unexpectedly dialed")
	}
	handleResetNetwork()
	conn, err := hy2.DialContext(ctx, metadata)
	if err != nil {
		t.Fatalf("dial after network reset: %v", err)
	}
	_ = conn.Close()
	if !hy2.closed || anyTLS.closed {
		t.Errorf("transport reset: Hy2 closed=%t, terminal AnyTLS closed=%t", hy2.closed, anyTLS.closed)
	}
}

func TestProxyOnlyTrafficLeavesOutADirectProxyOfAnyName(t *testing.T) {
	direct := outbound.NewDirectWithOption(outbound.DirectOption{Name: "直连"})
	reject := outbound.NewRejectWithOption(outbound.RejectOption{Name: "HK"})
	tunnel.UpdateProxies(map[string]constant.Proxy{
		"直连": adapter.NewProxy(direct),
		"HK": adapter.NewProxy(reject),
	}, nil)
	t.Cleanup(func() { tunnel.UpdateProxies(nil, nil) })

	for _, test := range []struct {
		outbound constant.ProxyAdapter
		proxied  int64
	}{
		{direct, 0},
		{reject, 5},
	} {
		statistic.DefaultManager.ResetStatistic()
		local, remote := net.Pipe()
		go func() { _, _ = io.Copy(io.Discard, remote) }()
		tracker := statistic.NewTCPTracker(
			outbound.NewConn(local, test.outbound),
			statistic.DefaultManager,
			&constant.Metadata{},
			nil,
			0,
			0,
			true,
		)

		if _, err := tracker.Write([]byte("hello")); err != nil {
			t.Fatalf("write through %s: %v", test.outbound.Name(), err)
		}
		_ = tracker.Close()
		_ = remote.Close()

		all, _ := statistic.DefaultManager.TotalTraffic(false)
		proxied, _ := statistic.DefaultManager.TotalTraffic(true)
		if all != 5 || proxied != test.proxied {
			t.Errorf("%s: total %d, proxied %d; want 5 and %d", test.outbound.Name(), all, proxied, test.proxied)
		}
	}
	statistic.DefaultManager.ResetStatistic()
}
