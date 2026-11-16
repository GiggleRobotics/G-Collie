package main

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"errors"
	"gcollie/network/core"
	"net"
	"strings"
	"sync"
	"sync/atomic"
	"tailscale.com/net/dnscache"
	"tailscale.com/net/netmon"
)

var interfaceMu sync.RWMutex
var interfaceOnce sync.Once
var mobileDNS []string
var privateDNSName string
var dnsCursor atomic.Uint64
var lastConfiguration string
var mobileInterfaces = []netmon.Interface{{Interface: &net.Interface{Index: 1, Name: "lo", MTU: 65536, Flags: net.FlagUp | net.FlagLoopback | net.FlagRunning}, AltAddrs: []net.Addr{&net.IPNet{IP: net.IPv4(127, 0, 0, 1), Mask: net.CIDRMask(8, 32)}}}}

func configureNetwork(raw string) (bool, error) {
	var value struct {
		Name           string   `json:"name"`
		MTU            int      `json:"mtu"`
		Addresses      []string `json:"addresses"`
		Gateway        string   `json:"gateway"`
		DNS            []string `json:"dns"`
		PrivateDNSName string   `json:"privateDNSName"`
		InterfaceType  string   `json:"interfaceType"`
	}
	if err := json.Unmarshal([]byte(raw), &value); err != nil {
		return false, err
	}
	if raw == lastConfiguration {
		return false, nil
	}
	interfaceOnce.Do(func() {
		// Android libc can omit AAAA even when the active network has working IPv6.
		// Query both families through that network's DNS; control and DERP dialers
		// retain upstream Happy Eyeballs and TLS hostname verification.
		dnscache.Get().Forward = &net.Resolver{PreferGo: true, Dial: dialMobileDNS}
		netmon.RegisterInterfaceGetter(func() ([]netmon.Interface, error) {
			interfaceMu.RLock()
			defer interfaceMu.RUnlock()
			return append([]netmon.Interface(nil), mobileInterfaces...), nil
		})
	})
	interfaceMu.Lock()
	mobileDNS = nil
	dns4, dns6, addr4, addr6 := 0, 0, 0, 0
	for _, raw := range value.DNS {
		if ip := net.ParseIP(raw); ip != nil {
			mobileDNS = append(mobileDNS, ip.String())
			if ip.To4() != nil {
				dns4++
			} else {
				dns6++
			}
		}
	}
	privateDNSName = value.PrivateDNSName
	mobileInterfaces = append([]netmon.Interface(nil), mobileInterfaces[:1]...)
	if value.Name != "" {
		addrs := []net.Addr{}
		for _, a := range value.Addresses {
			ip, prefix, e := net.ParseCIDR(a)
			if e == nil {
				prefix.IP = ip
				if ip.To4() != nil {
					addr4++
				} else {
					addr6++
				}
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
	kind := value.InterfaceType
	if kind == "" {
		switch {
		case value.Name == "":
			kind = "none"
		case strings.HasPrefix(value.Name, "tun") || strings.HasPrefix(value.Name, "ppp") || strings.HasPrefix(value.Name, "wg"):
			kind = "vpn"
		case strings.HasPrefix(value.Name, "rmnet") || strings.HasPrefix(value.Name, "ccmni") || strings.HasPrefix(value.Name, "wwan"):
			kind = "mobile"
		case strings.HasPrefix(value.Name, "wlan"):
			kind = "wifi"
		default:
			kind = "other"
		}
	}
	core.RecordMobileNetwork(kind, dns4, dns6, addr4, addr6, value.PrivateDNSName != "")

	netmon.UpdateLastKnownDefaultRouteInterface(value.Name)
	netmon.UpdateLastKnownDefaultGateway(value.Gateway)
	lastConfiguration = raw
	return true, nil
}

// Read the current link on every query so Wi-Fi/cellular changes need no node reset.
func dialMobileDNS(ctx context.Context, network, _ string) (net.Conn, error) {
	interfaceMu.RLock()
	servers := append([]string(nil), mobileDNS...)
	name := privateDNSName
	interfaceMu.RUnlock()
	if len(servers) == 0 {
		return nil, errors.New("Android active network has no DNS server")
	}
	server := servers[(dnsCursor.Add(1)-1)%uint64(len(servers))]
	if name != "" {
		// Respect Android's explicitly configured Private DNS provider.
		d := tls.Dialer{Config: &tls.Config{ServerName: name, MinVersion: tls.VersionTLS12}}
		return d.DialContext(ctx, "tcp", net.JoinHostPort(server, "853"))
	}
	return (&net.Dialer{}).DialContext(ctx, network, net.JoinHostPort(server, "53"))
}
