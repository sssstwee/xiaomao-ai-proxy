//go:build openharmony

package core

import (
	"errors"
	"net"
	"testing"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/listener/sing_tun"
	rule "github.com/metacubex/mihomo/rules/common"
)

type testOhosCallbacks struct {
	protected bool
	queried   bool
}

func (callbacks *testOhosCallbacks) Protect(int) bool { return callbacks.protected }
func (callbacks *testOhosCallbacks) ResolveUid(int, string, string) int {
	callbacks.queried = true
	return 20012345
}
func (*testOhosCallbacks) ResolvePackage(int) string { return "com.example.client" }

type testOhosSocket struct {
	err error
}

func (socket testOhosSocket) Control(callback func(uintptr)) error {
	if socket.err != nil {
		return socket.err
	}
	callback(42)
	return nil
}
func (testOhosSocket) Read(func(uintptr) bool) error  { return nil }
func (testOhosSocket) Write(func(uintptr) bool) error { return nil }

func TestOhosNeverWritesTheSystemClock(t *testing.T) {
	if systemTimeWritable {
		t.Fatal("OHOS must not rely on runtime.GOOS to permit system clock writes")
	}
	cfg := withPlatformLimits(&config.Config{
		NTP: &config.NTP{Enable: true, WriteToSystem: true},
	})
	if !cfg.NTP.Enable || cfg.NTP.WriteToSystem {
		t.Fatal("OHOS must keep NTP enabled without writing the system clock")
	}
}

func TestOhosRefusedSocketProtectionFailsTheDial(t *testing.T) {
	callbacks := &testOhosCallbacks{}
	handler := TunHandler{listener: &sing_tun.Listener{}, callbacks: callbacks}
	if err := handler.protectSocket(testOhosSocket{}); !errors.Is(err, errSocketNotProtected) {
		t.Fatalf("unprotected socket error = %v", err)
	}
	callbacks.protected = true
	if err := handler.protectSocket(testOhosSocket{}); err != nil {
		t.Fatal(err)
	}
	failure := errors.New("socket closed")
	if err := handler.protectSocket(testOhosSocket{err: failure}); !errors.Is(err, failure) {
		t.Fatalf("socket control error = %v", err)
	}
}

func TestOhosApi26UsesNativeUidResolution(t *testing.T) {
	previous := sdkVersion.Load()
	t.Cleanup(func() { sdkVersion.Store(previous) })
	sdkVersion.Store(26)
	callbacks := &testOhosCallbacks{}
	handler := TunHandler{listener: &sing_tun.Listener{}, callbacks: callbacks}
	uid, name := handler.handleResolveProcess(
		&net.TCPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 12345},
		&net.TCPAddr{IP: net.IPv4(192, 0, 2, 1), Port: 443},
	)
	if !callbacks.queried || uid != 20012345 || name != "com.example.client" {
		t.Fatalf("native UID lookup = (%d, %q), queried=%v", uid, name, callbacks.queried)
	}
}

func TestOhosUidRuleUsesTheNativeUid(t *testing.T) {
	uidRule, err := rule.NewUid("20012345", "DIRECT")
	if err != nil {
		t.Fatal(err)
	}
	matched, adapter := uidRule.Match(&constant.Metadata{Uid: 20012345}, constant.RuleMatchHelper{})
	if !matched || adapter != "DIRECT" {
		t.Fatalf("native UID rule match = (%v, %q)", matched, adapter)
	}
}
