package main

import (
	"encoding/json"
	"net"
	"sync"
	"tailscale.com/net/netmon"
)

var interfaceMu sync.RWMutex
var interfaceOnce sync.Once
var mobileInterfaces = []netmon.Interface{{Interface: &net.Interface{Index: 1, Name: "lo", MTU: 65536, Flags: net.FlagUp | net.FlagLoopback | net.FlagRunning}, AltAddrs: []net.Addr{&net.IPNet{IP: net.IPv4(127, 0, 0, 1), Mask: net.CIDRMask(8, 32)}}}}

func configureNetwork(raw string) error {
	var value struct {
		Name      string   `json:"name"`
		MTU       int      `json:"mtu"`
		Addresses []string `json:"addresses"`
		Gateway   string   `json:"gateway"`
	}
	if err := json.Unmarshal([]byte(raw), &value); err != nil {
		return err
	}
	interfaceOnce.Do(func() {
		netmon.RegisterInterfaceGetter(func() ([]netmon.Interface, error) {
			interfaceMu.RLock()
			defer interfaceMu.RUnlock()
			return append([]netmon.Interface(nil), mobileInterfaces...), nil
		})
	})
	interfaceMu.Lock()
	mobileInterfaces = mobileInterfaces[:1]
	if value.Name != "" {
		addrs := []net.Addr{}
		for _, a := range value.Addresses {
			ip, prefix, e := net.ParseCIDR(a)
			if e == nil {
				prefix.IP = ip
				addrs = append(addrs, prefix)
			}
		}
		mtu := value.MTU
		if mtu <= 0 {
			mtu = 1500
		}
		mobileInterfaces = append(mobileInterfaces, netmon.Interface{Interface: &net.Interface{Index: 2, Name: value.Name, MTU: mtu, Flags: net.FlagUp | net.FlagRunning | net.FlagBroadcast}, AltAddrs: addrs})
	}
	interfaceMu.Unlock()
	netmon.UpdateLastKnownDefaultRouteInterface(value.Name)
	netmon.UpdateLastKnownDefaultGateway(value.Gateway)
	return nil
}
