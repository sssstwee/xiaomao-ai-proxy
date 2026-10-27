package main

import (
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

func TestSubscriptionProxyWorksWithoutVPNAndClosesIndependently(t *testing.T) {
	oldInit, oldConfig, oldRunning, oldMode, oldStatus := isInit, currentConfig, isRunning, tunnel.Mode(), tunnel.Status()
	defer func() {
		closeSubscriptionProxies()
		isInit, currentConfig, isRunning = oldInit, oldConfig, oldRunning
		tunnel.SetMode(oldMode)
		if oldStatus == tunnel.Running {
			tunnel.OnRunning()
		} else if oldStatus == tunnel.Inner {
			tunnel.OnInnerLoading()
		} else {
			tunnel.OnSuspend()
		}
	}()

	isInit, currentConfig = false, nil
	if port := handleStartSubscriptionProxy(); port != 0 {
		t.Fatalf("started proxy without an initialized configuration: %d", port)
	}
	isInit, currentConfig, isRunning = true, &config.Config{}, false
	tunnel.UpdateProxies(map[string]C.Proxy{"DIRECT": adapter.NewProxy(outbound.NewDirect())}, nil)
	tunnel.SetMode(tunnel.Direct)
	tunnel.OnRunning()
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(w, "updated configuration")
	}))
	defer target.Close()

	first, second := handleStartSubscriptionProxy(), handleStartSubscriptionProxy()
	if first == 0 || second == 0 || first == second {
		t.Fatalf("expected independent ephemeral ports, got %d and %d", first, second)
	}
	get := func(port int) string {
		t.Helper()
		proxyURL, _ := url.Parse(fmt.Sprintf("http://127.0.0.1:%d", port))
		transport := &http.Transport{Proxy: http.ProxyURL(proxyURL), DisableKeepAlives: true}
		defer transport.CloseIdleConnections()
		client := &http.Client{Transport: transport, Timeout: 3 * time.Second}
		response, err := client.Get(target.URL)
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
		body, err := io.ReadAll(response.Body)
		if err != nil || response.StatusCode != http.StatusOK {
			t.Fatalf("proxy response: status=%d, error=%v", response.StatusCode, err)
		}
		return string(body)
	}
	if got := get(first); got != "updated configuration" {
		t.Fatalf("unexpected response %q", got)
	}
	if isRunning {
		t.Fatal("subscription request started the VPN listener")
	}
	if !handleStopSubscriptionProxy(first) {
		t.Fatal("could not stop first listener")
	}
	if conn, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", first), time.Second); err == nil {
		conn.Close()
		t.Fatal("first listener remains open")
	}
	if got := get(second); got != "updated configuration" {
		t.Fatalf("closing one listener affected the other: %q", got)
	}
	isRunning = true
	if !handleStopSubscriptionProxy(second) || !isRunning {
		t.Fatal("closing subscription proxy changed the running VPN state")
	}
}
