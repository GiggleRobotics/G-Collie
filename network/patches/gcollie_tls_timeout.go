// G-Collie modification to tailscale.com v1.104.1. See README.md in this patch directory.
package dnscache

import "time"

// Keep the upstream limit except on Android, where VPN-mediated TLS handshakes
// can legitimately exceed five seconds. WithTimeout still honors earlier deadlines.
func gcollieTLSHandshakeTimeout(goos string) time.Duration {
	if goos == "android" {
		return 15 * time.Second
	}
	return 5 * time.Second
}
