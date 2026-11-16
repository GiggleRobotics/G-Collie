// G-Collie embedded tailnet transport. Account login stays with Tailscale.
package core

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/http/httputil"
	"net/netip"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"tailscale.com/envknob"
	"tailscale.com/tsnet"
)

type State struct {
	State       string      `json:"state"`
	AuthURL     string      `json:"authURL,omitempty"`
	Address     string      `json:"address,omitempty"`
	Error       string      `json:"error,omitempty"`
	Computers   []Computer  `json:"computers,omitempty"`
	Diagnostics Diagnostics `json:"diagnostics"`
}

// Diagnostics never retains upstream log text, arguments, URLs, addresses or keys.
// All keys/labels are selected from fixed enumerations, so memory use is bounded.
type Diagnostics struct {
	UptimeSeconds       int64                    `json:"uptimeSeconds"`
	LogCount            uint64                   `json:"logCount"`
	LastStage           string                   `json:"lastStage,omitempty"`
	LastErrorClass      string                   `json:"lastErrorClass,omitempty"`
	LastEventAgeSeconds int64                    `json:"lastEventAgeSeconds"`
	Counts              map[string]uint64        `json:"counts"`
	Network             MobileNetworkDiagnostics `json:"network"`
}
type MobileNetworkDiagnostics struct {
	InterfaceType string `json:"interfaceType"`
	DNSv4         int    `json:"dnsV4"`
	DNSv6         int    `json:"dnsV6"`
	AddressV4     int    `json:"addressV4"`
	AddressV6     int    `json:"addressV6"`
	PrivateDNS    bool   `json:"privateDNS"`
}

var mobileDiagnosticMu sync.Mutex
var mobileDiagnosticNetwork MobileNetworkDiagnostics

// RecordMobileNetwork takes only counts and an allowlisted link category.
func RecordMobileNetwork(kind string, dns4, dns6, addr4, addr6 int, privateDNS bool) {
	switch kind {
	case "vpn", "mobile", "wifi", "ethernet", "none":
	default:
		kind = "other"
	}
	clamp := func(n int) int {
		if n < 0 {
			return 0
		}
		if n > 16 {
			return 16
		}
		return n
	}
	mobileDiagnosticMu.Lock()
	mobileDiagnosticNetwork = MobileNetworkDiagnostics{kind, clamp(dns4), clamp(dns6), clamp(addr4), clamp(addr6), privateDNS}
	mobileDiagnosticMu.Unlock()
}

type diagnosticBuffer struct {
	mu                sync.Mutex
	started           time.Time
	lastEvent         time.Time
	count             uint64
	stage, errorClass string
	counts            map[string]uint64
}

func logClassification(message string) (stage, class string) {
	text := strings.ToLower(message)
	stage = "other"
	switch {
	case strings.Contains(text, "dns") || strings.Contains(text, "lookup "):
		stage = "dns"
	case strings.Contains(text, "control"):
		stage = "control"
	case strings.Contains(text, "derp"):
		stage = "derp"
	case strings.Contains(text, "netmon") || strings.Contains(text, "linkchange"):
		stage = "netmon"
	case strings.Contains(text, "auth") || strings.Contains(text, "login"):
		stage = "auth"
	case strings.Contains(text, "magicsock") || strings.Contains(text, "wgengine") || strings.Contains(text, "netstack"):
		stage = "engine"
	}
	class = "none"
	switch {
	case strings.Contains(text, "timeout") || strings.Contains(text, "deadline exceeded"):
		class = "timeout"
	case strings.Contains(text, "no such host") || strings.Contains(text, "server misbehaving"):
		class = "name-resolution"
	case strings.Contains(text, "unreachable") || strings.Contains(text, "no route to host"):
		class = "unreachable"
	case strings.Contains(text, "connection refused"):
		class = "refused"
	case strings.Contains(text, "tls") || strings.Contains(text, "certificate"):
		class = "tls"
	case strings.Contains(text, "error") || strings.Contains(text, "failed"):
		class = "other"
	}
	return
}
func (d *diagnosticBuffer) logf(format string, args ...any) {
	// The temporary formatted string is classified then discarded, never stored/logged.
	stage, class := logClassification(fmt.Sprintf(format, args...))
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.started.IsZero() {
		d.started = time.Now()
	}
	if d.counts == nil {
		d.counts = make(map[string]uint64)
	}
	d.count++
	d.stage = stage
	d.errorClass = class
	d.lastEvent = time.Now()
	d.counts[stage+"/"+class]++
}
func (d *diagnosticBuffer) snapshot() Diagnostics {
	d.mu.Lock()
	defer d.mu.Unlock()
	counts := make(map[string]uint64, len(d.counts))
	for k, v := range d.counts {
		counts[k] = v
	}
	var uptime, age int64
	if !d.started.IsZero() {
		uptime = int64(time.Since(d.started).Seconds())
	}
	if !d.lastEvent.IsZero() {
		age = int64(time.Since(d.lastEvent).Seconds())
	}
	mobileDiagnosticMu.Lock()
	network := mobileDiagnosticNetwork
	mobileDiagnosticMu.Unlock()
	return Diagnostics{uptime, d.count, d.stage, d.errorClass, age, counts, network}
}

type Computer struct {
	Name    string `json:"name"`
	Address string `json:"address"`
}
type Gateway struct {
	URL          string `json:"url"`
	Token        string `json:"token"`
	RemoteOrigin string `json:"remoteOrigin"`
}
type Node struct {
	ts          *tsnet.Server
	mu          sync.Mutex
	listener    net.Listener
	gateway     *http.Server
	gatewayInfo Gateway
	server      *http.Server
	address     string
	closed      bool
	diagnostics diagnosticBuffer
}

func New(dir, hostname string) (*Node, error) {
	if err := os.MkdirAll(dir, 0700); err != nil {
		return nil, err
	}
	if err := os.Chmod(dir, 0700); err != nil {
		return nil, err
	}
	// No auth keys or OAuth secrets are embedded. Keep upstream diagnostics local.
	envknob.SetNoLogsNoSupport()
	os.Unsetenv("TS_AUTHKEY")
	os.Unsetenv("TS_CLIENT_SECRET")
	os.Unsetenv("TS_ID_TOKEN")
	n := &Node{diagnostics: diagnosticBuffer{started: time.Now()}}
	n.ts = &tsnet.Server{Dir: dir, Hostname: hostname, UserLogf: n.diagnostics.logf, Logf: n.diagnostics.logf}
	if err := n.ts.Start(); err != nil {
		n.ts.Close()
		return nil, err
	}
	return n, nil
}

// Android supplies interface changes explicitly; its fallback poll is ten minutes.
// Preserve node keys, the netmap and active gateways when the default link changes.
func (n *Node) NetworkChanged() {
	n.diagnostics.logf("netmon refresh requested")
	if monitor, ok := n.ts.Sys().NetMon.GetOK(); ok {
		monitor.InjectEvent()
	}
}

func (n *Node) Status() State {
	c, err := n.ts.LocalClient()
	if err != nil {
		return State{State: "error", Error: err.Error(), Diagnostics: n.diagnostics.snapshot()}
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	s, err := c.Status(ctx)
	if err != nil {
		return State{State: "error", Error: err.Error(), Diagnostics: n.diagnostics.snapshot()}
	}
	n.mu.Lock()
	address := n.address
	n.mu.Unlock()
	auth := ""
	if u, e := url.Parse(s.AuthURL); e == nil && u.Scheme == "https" && u.Host == "login.tailscale.com" {
		auth = u.String()
	}
	computers := []Computer{}
	for _, peer := range s.Peer {
		if !peer.Online || !strings.HasPrefix(peer.HostName, "g-collie-computer") {
			continue
		}
		for _, ip := range peer.TailscaleIPs {
			if ip.Is4() {
				computers = append(computers, Computer{Name: peer.HostName, Address: fmt.Sprintf("http://%s:4310", ip)})
				break
			}
		}
	}
	return State{State: s.BackendState, AuthURL: auth, Address: address, Computers: computers, Diagnostics: n.diagnostics.snapshot()}
}
func (n *Node) Login() error {
	c, e := n.ts.LocalClient()
	if e != nil {
		return e
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	return c.StartLoginInteractive(ctx)
}
func (n *Node) Logout() error {
	n.mu.Lock()
	if n.gateway != nil {
		n.gateway.Close()
		n.gateway = nil
		n.gatewayInfo = Gateway{}
	}
	if n.server != nil {
		n.server.Close()
		n.server = nil
	}
	n.address = ""
	n.mu.Unlock()
	c, e := n.ts.LocalClient()
	if e != nil {
		return e
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	return c.Logout(ctx)
}
func (n *Node) Close() {
	n.mu.Lock()
	if n.closed {
		n.mu.Unlock()
		return
	}
	n.closed = true
	if n.gateway != nil {
		n.gateway.Close()
	}
	if n.server != nil {
		n.server.Close()
	}
	n.mu.Unlock()
	n.ts.Close()
}
func JSON(v any) string      { b, _ := json.Marshal(v); return string(b) }
func Failure(e error) string { return JSON(map[string]string{"error": e.Error()}) }

// Tailnet destinations only: never become a general proxy for a supplied URL.
func Target(raw string) (*url.URL, error) {
	u, e := url.Parse(raw)
	if e != nil || u == nil {
		return nil, errors.New("无效电脑地址")
	}
	if (u.Scheme != "https" && u.Scheme != "http") || u.User != nil || u.Hostname() == "" || u.Opaque != "" {
		return nil, errors.New("请输入 Tailscale 电脑地址")
	}
	host := strings.ToLower(u.Hostname())
	valid := strings.HasSuffix(host, ".ts.net")
	if ip, e := netip.ParseAddr(host); e == nil {
		valid = netip.MustParsePrefix("100.64.0.0/10").Contains(ip) || netip.MustParsePrefix("fd7a:115c:a1e0::/48").Contains(ip)
	}
	if !valid {
		return nil, errors.New("内置连接仅允许 Tailscale IP 或 .ts.net 域名")
	}
	if u.Port() != "" {
		if _, e := net.LookupPort("tcp", u.Port()); e != nil {
			return nil, errors.New("无效端口")
		}
	}
	return u, nil
}
func Origin(u *url.URL) string { return u.Scheme + "://" + u.Host }

const gateCookie = "gcollie_gateway"

func stripGate(r *http.Request) {
	cookies := r.Cookies()
	r.Header.Del("Cookie")
	for _, c := range cookies {
		if c.Name != gateCookie {
			r.AddCookie(c)
		}
	}
}
func GatewayHandler(target *url.URL, token, localOrigin string, transport http.RoundTripper) http.Handler {
	proxy := httputil.NewSingleHostReverseProxy(target)
	proxy.Transport = transport
	proxy.FlushInterval = -1
	original := proxy.Director
	proxy.Director = func(r *http.Request) {
		original(r)
		r.Host = target.Host
		stripGate(r)
		r.Header.Del("Authorization")
		r.Header.Del("Forwarded")
		r.Header.Del("X-Forwarded-Host")
		r.Header.Del("X-Forwarded-Proto")
		r.Header.Del("X-Forwarded-For")
		if r.Header.Get("Origin") != "" {
			r.Header.Set("Origin", Origin(target))
		}
	}
	proxy.ModifyResponse = func(r *http.Response) error {
		// The upstream hop is WireGuard (+ TLS for HTTPS). The local hop is guarded
		// loopback HTTP so secure cookies are re-scoped to this private WebView jar.
		cookies := r.Cookies()
		r.Header.Del("Set-Cookie")
		for _, c := range cookies {
			if c.Name == gateCookie {
				continue
			}
			c.Secure = false
			c.Domain = ""
			r.Header.Add("Set-Cookie", c.String())
		}
		if location := r.Header.Get("Location"); location != "" {
			u, e := url.Parse(location)
			if e != nil {
				return e
			}
			if u.IsAbs() {
				if Origin(u) != Origin(target) {
					return errors.New("跨站跳转需在外部浏览器打开")
				}
				u.Scheme = ""
				u.Host = ""
				r.Header.Set("Location", u.String())
			}
		}
		return nil
	}
	proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, e error) {
		http.Error(w, "电脑连接失败，请检查设备在线状态及网络访问权限", http.StatusBadGateway)
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		c, e := r.Cookie(gateCookie)
		if e != nil || subtle.ConstantTimeCompare([]byte(c.Value), []byte(token)) != 1 {
			http.Error(w, "Forbidden", 403)
			return
		}
		if r.Host != strings.TrimPrefix(localOrigin, "http://") {
			http.Error(w, "Forbidden", 403)
			return
		}
		if origin := r.Header.Get("Origin"); origin != "" && origin != localOrigin {
			http.Error(w, "Forbidden", 403)
			return
		}
		proxy.ServeHTTP(w, r)
	})
}

// Check the selected service before creating a gateway; never follow redirects.
func probe(client *http.Client, target *url.URL) error {
	ctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
	defer cancel()
	health := *target
	health.Path = "/healthz"
	health.RawPath = ""
	health.RawQuery = ""
	health.Fragment = ""
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, health.String(), nil)
	if err != nil {
		return errors.New("电脑地址无效，请重新选择")
	}
	copy := *client
	copy.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	response, err := copy.Do(request)
	if err != nil {
		return fmt.Errorf("无法访问电脑 %s。请确认电脑在线、G-Collie 服务已启动，且两台设备在同一网络并允许互访。正式版本端口为 4310。", target.Host)
	}
	defer response.Body.Close()
	var value struct {
		OK      bool   `json:"ok"`
		Version string `json:"version"`
	}
	if response.StatusCode != http.StatusOK || json.NewDecoder(http.MaxBytesReader(nil, response.Body, 4096)).Decode(&value) != nil || !value.OK || value.Version == "" {
		return errors.New("该地址没有响应 G-Collie 服务，请从电脑的“内置远程连接”复制完整地址，检查协议和端口")
	}
	return nil
}
func (n *Node) Open(raw string) (Gateway, error) {
	target, e := Target(raw)
	if e != nil {
		return Gateway{}, e
	}
	if n.Status().State != "Running" {
		return Gateway{}, errors.New("请先登录内置 Tailscale 并等待连接")
	}
	if e := probe(n.ts.HTTPClient(), target); e != nil {
		return Gateway{}, e
	}
	return n.openGateway(target, n.ts.HTTPClient().Transport)
}

func (n *Node) openGateway(target *url.URL, transport http.RoundTripper) (Gateway, error) {
	n.mu.Lock()
	defer n.mu.Unlock()
	if n.closed {
		return Gateway{}, errors.New("网络模块已关闭")
	}
	suffix := target.RequestURI()
	if suffix == "" {
		suffix = "/"
	}
	if target.Fragment != "" {
		suffix += "#" + target.EscapedFragment()
	}
	if n.gateway != nil && n.gatewayInfo.RemoteOrigin == Origin(target) {
		info := n.gatewayInfo
		info.URL += suffix
		return info, nil
	}
	upstream := *target
	upstream.Path = ""
	upstream.RawQuery = ""
	upstream.Fragment = ""
	listener, e := net.Listen("tcp4", "127.0.0.1:0")
	if e != nil {
		return Gateway{}, e
	}
	origin := "http://" + listener.Addr().String()
	secret := make([]byte, 32)
	if _, e = rand.Read(secret); e != nil {
		listener.Close()
		return Gateway{}, e
	}
	token := hex.EncodeToString(secret)
	gateway := &http.Server{Handler: GatewayHandler(&upstream, token, origin, transport), ReadHeaderTimeout: 10 * time.Second, IdleTimeout: 90 * time.Second}
	if n.gateway != nil {
		n.gateway.Close()
	}
	n.gateway = gateway
	n.gatewayInfo = Gateway{URL: origin, Token: token, RemoteOrigin: Origin(target)}
	go gateway.Serve(listener)
	info := n.gatewayInfo
	info.URL += suffix
	return info, nil
}
func (n *Node) Serve(port int) error {
	listener, e := n.ts.Listen("tcp", fmt.Sprintf(":%d", port))
	if e != nil {
		return e
	}
	c, e := n.ts.LocalClient()
	if e != nil {
		listener.Close()
		return e
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	s, e := c.StatusWithoutPeers(ctx)
	if e != nil || len(s.TailscaleIPs) == 0 {
		listener.Close()
		return errors.New("未获取私有网络地址")
	}
	target, _ := url.Parse(fmt.Sprintf("http://127.0.0.1:%d", port))
	proxy := httputil.NewSingleHostReverseProxy(target)
	proxy.FlushInterval = -1
	// ReverseProxy adds X-Forwarded-For, keeping local bootstrap unavailable remotely.
	server := &http.Server{Handler: proxy, ReadHeaderTimeout: 10 * time.Second}
	n.mu.Lock()
	if n.closed {
		n.mu.Unlock()
		listener.Close()
		return errors.New("网络已关闭")
	}
	n.server = server
	n.address = fmt.Sprintf("http://%s:%d", s.TailscaleIPs[0], port)
	n.mu.Unlock()
	return server.Serve(listener)
}
