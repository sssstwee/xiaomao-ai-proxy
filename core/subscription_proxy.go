package main

import (
	"net"
	"strconv"
	"sync"
	"time"

	"github.com/metacubex/mihomo/adapter/inbound"
	proxyhttp "github.com/metacubex/mihomo/listener/http"
	"github.com/metacubex/mihomo/tunnel"
)

// These temporary listeners are independent of the system VPN listener.
// Each request owns an ephemeral loopback-only HTTP proxy and closes it after
// use. Multiple requests can finish independently without stopping the VPN.
var subscriptionProxies = struct {
	sync.Mutex
	listeners map[int]*proxyhttp.Listener
}{listeners: make(map[int]*proxyhttp.Listener)}

func handleStartSubscriptionProxy() int {
	runLock.Lock()
	defer runLock.Unlock()
	if !isInit || currentConfig == nil {
		return 0
	}
	proxy, err := proxyhttp.NewWithAuthenticate(
		"127.0.0.1:0", tunnel.Tunnel, false,
		inbound.WithInName("DEFAULT-HTTP"), inbound.WithSpecialRules(""),
	)
	if err != nil {
		return 0
	}
	_, rawPort, err := net.SplitHostPort(proxy.Address())
	if err != nil {
		proxy.Close()
		return 0
	}
	port, err := strconv.Atoi(rawPort)
	if err != nil || port <= 0 {
		proxy.Close()
		return 0
	}
	subscriptionProxies.Lock()
	subscriptionProxies.listeners[port] = proxy
	subscriptionProxies.Unlock()
	// A crashed or suspended UI must not leave a bootstrap listener running.
	time.AfterFunc(3*time.Minute, func() {
		subscriptionProxies.Lock()
		if subscriptionProxies.listeners[port] != proxy {
			subscriptionProxies.Unlock()
			return
		}
		delete(subscriptionProxies.listeners, port)
		subscriptionProxies.Unlock()
		proxy.Close()
	})
	return port
}

func handleStopSubscriptionProxy(port int) bool {
	subscriptionProxies.Lock()
	proxy := subscriptionProxies.listeners[port]
	delete(subscriptionProxies.listeners, port)
	subscriptionProxies.Unlock()
	if proxy == nil {
		return false
	}
	return proxy.Close() == nil
}

func closeSubscriptionProxies() {
	subscriptionProxies.Lock()
	defer subscriptionProxies.Unlock()
	for port, proxy := range subscriptionProxies.listeners {
		proxy.Close()
		delete(subscriptionProxies.listeners, port)
	}
}
