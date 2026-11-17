package core

import (
	"context"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/http/httptrace"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestTarget(t *testing.T) {
	for _, raw := range []string{"http://127.0.0.1:4310", "file:///etc/passwd", "https://evil.test", "http://100.64.0.1@evil.test", "http://100.63.255.255:4310"} {
		if _, e := Target(raw); e == nil {
			t.Fatal(raw)
		}
	}
	for _, raw := range []string{"http://100.109.240.57:4310/#pair=secret", "https://computer.tail123.ts.net:8443", "http://[fd7a:115c:a1e0::1]:4310"} {
		if _, e := Target(raw); e != nil {
			t.Fatal(raw, e)
		}
	}
}
func TestGatewayGuardAndCookies(t *testing.T) {
	called := 0
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called++
		if strings.Contains(r.Header.Get("Cookie"), gateCookie) || r.Header.Get("Authorization") != "" {
			t.Error("gateway credential leaked")
		}
		if r.Header.Get("Origin") != "http://"+r.Host {
			t.Error("wrong upstream origin")
		}
		http.SetCookie(w, &http.Cookie{Name: "gcollie_device", Value: "device", Secure: true, HttpOnly: true, SameSite: http.SameSiteStrictMode, Path: "/"})
		w.Write([]byte("ok"))
	}))
	defer upstream.Close()
	u, _ := url.Parse(upstream.URL)
	h := GatewayHandler(u, "session-secret", "http://127.0.0.1:43871", http.DefaultTransport)
	for _, bad := range []struct{ cookie, origin, host string }{{"", "", "127.0.0.1:43871"}, {gateCookie + "=wrong", "", "127.0.0.1:43871"}, {gateCookie + "=session-secret", "https://evil.test", "127.0.0.1:43871"}, {gateCookie + "=session-secret", "", "evil.test"}} {
		r := httptest.NewRequest("GET", "http://"+bad.host+"/api/local", nil)
		r.Header.Set("Cookie", bad.cookie)
		r.Header.Set("Origin", bad.origin)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != 403 {
			t.Fatal(w.Code)
		}
	}
	if called != 0 {
		t.Fatal("rejected requests reached upstream")
	}
	r := httptest.NewRequest("POST", "http://127.0.0.1:43871/api/auth/pair", strings.NewReader(`{}`))
	r.Header.Set("Cookie", gateCookie+"=session-secret; gcollie_device=old")
	r.Header.Set("Authorization", "Bearer must-not-forward")
	r.Header.Set("Origin", "http://127.0.0.1:43871")
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != 200 || called != 1 {
		t.Fatal(w.Code, called)
	}
	c := w.Result().Cookies()[0]
	if c.Secure || !c.HttpOnly || c.SameSite != http.SameSiteStrictMode {
		t.Fatal("incorrect local cookie scope")
	}
}

func TestServiceProbe(t *testing.T) {
	for _, tc := range []struct {
		name, body, location string
		status               int
		good                 bool
	}{
		{name: "service", body: `{"ok":true,"version":"0.3.1"}`, status: 200, good: true},
		{name: "wrong service", body: `{"ok":true}`, status: 200},
		{name: "offline", body: `offline`, status: 503},
		{name: "redirect", location: "http://127.0.0.1/", status: 302},
	} {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != "/healthz" || r.URL.RawQuery != "" {
					t.Error("pairing data forwarded to probe")
				}
				if tc.location != "" {
					w.Header().Set("Location", tc.location)
				}
				w.WriteHeader(tc.status)
				w.Write([]byte(tc.body))
			}))
			defer server.Close()
			target, _ := url.Parse(server.URL + "/#pair=private")
			if err := probe(server.Client(), target); (err == nil) != tc.good {
				t.Fatalf("probe: %v", err)
			}
		})
	}
}

func TestSameTargetReconnectPreservesInFlightDownload(t *testing.T) {
	release := make(chan struct{})
	var once sync.Once
	finish := func() { once.Do(func() { close(release) }) }
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Length", "65536")
		w.Write([]byte("x"))
		w.(http.Flusher).Flush()
		<-release
		w.Write(make([]byte, 65535))
	}))
	defer upstream.Close()
	defer finish()
	target, _ := url.Parse(upstream.URL)
	node := &Node{}
	defer func() {
		if node.gateway != nil {
			node.gateway.Close()
		}
	}()
	first, err := node.openGateway(target, http.DefaultTransport)
	if err != nil {
		t.Fatal(err)
	}
	request, _ := http.NewRequest("GET", first.URL+"/download", nil)
	request.AddCookie(&http.Cookie{Name: gateCookie, Value: first.Token})
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	second, err := node.openGateway(target, http.DefaultTransport)
	if err != nil {
		t.Fatal(err)
	}
	finish()
	body, err := io.ReadAll(response.Body)
	if err != nil || len(body) != 65536 {
		t.Fatalf("same-target reconnect truncated active download: bytes=%d err=%v", len(body), err)
	}
	if first != second {
		t.Fatal("same-target reconnect replaced gateway address or credential")
	}
}

func TestConcurrentReconnectAndTargetSwitch(t *testing.T) {
	node := &Node{}
	defer func() {
		if node.gateway != nil {
			node.gateway.Close()
		}
	}()
	target, _ := url.Parse("http://100.64.0.1:4310/")
	first, err := node.openGateway(target, http.DefaultTransport)
	if err != nil {
		t.Fatal(err)
	}
	var group sync.WaitGroup
	for i := 0; i < 20; i++ {
		group.Add(1)
		go func() {
			defer group.Done()
			next, err := node.openGateway(target, http.DefaultTransport)
			if err != nil || next != first {
				t.Errorf("reconnect changed gateway: %v", err)
			}
		}()
	}
	group.Wait()
	other, _ := url.Parse("http://100.64.0.2:4310/")
	next, err := node.openGateway(other, http.DefaultTransport)
	if err != nil {
		t.Fatal(err)
	}
	if next.Token == first.Token || next.URL == first.URL {
		t.Fatal("target switch reused old gateway")
	}
	req, _ := http.NewRequest("GET", next.URL, nil)
	req.AddCookie(&http.Cookie{Name: gateCookie, Value: first.Token})
	response, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusForbidden {
		t.Fatalf("old credential accepted: %d", response.StatusCode)
	}
}

func TestDiagnosticsClassifyWithoutRetainingSensitiveText(t *testing.T) {
	var d diagnosticBuffer
	d.logf("control: lookup %s failed: %s", "private-host.100.123.1.2", "deadline exceeded https://login.tailscale.com/a/token-secret?authURL=private")
	s := d.snapshot()
	if s.LogCount != 1 || s.LastStage != "dns" || s.LastErrorClass != "timeout" || s.Counts["dns/timeout"] != 1 {
		t.Fatalf("wrong safe classification: %+v", s)
	}
	raw := JSON(s)
	for _, secret := range []string{"private-host", "100.123.1.2", "login.tailscale.com", "token-secret", "authURL", "deadline exceeded"} {
		if strings.Contains(raw, secret) {
			t.Fatalf("diagnostic retained source text %q", secret)
		}
	}
	s.Counts["injected-hostname"] = 12
	if _, ok := d.snapshot().Counts["injected-hostname"]; ok {
		t.Fatal("snapshot mutated internal counters")
	}
}

func TestDiagnosticsStayBoundedAcrossConcurrentLogs(t *testing.T) {
	var d diagnosticBuffer
	var group sync.WaitGroup
	for i := 0; i < 8; i++ {
		group.Add(1)
		go func() {
			defer group.Done()
			for j := 0; j < 500; j++ {
				d.logf("unknown-private-label-%d secret=%d", j, j)
			}
		}()
	}
	group.Wait()
	s := d.snapshot()
	if s.LogCount != 4000 || len(s.Counts) > 49 || s.Counts["other/none"] != 4000 {
		t.Fatalf("unbounded or lost diagnostics: %+v", s)
	}
}

func TestMobileDiagnosticsOnlyExposeAllowlistedTypeAndCounts(t *testing.T) {
	mobileDiagnosticMu.Lock()
	previous := mobileDiagnosticNetwork
	mobileDiagnosticMu.Unlock()
	defer func() { mobileDiagnosticMu.Lock(); mobileDiagnosticNetwork = previous; mobileDiagnosticMu.Unlock() }()
	RecordMobileNetwork("private-interface-100.64.1.2", 999, -3, 2, 1, true)
	var d diagnosticBuffer
	s := d.snapshot()
	if s.Network.InterfaceType != "other" || s.Network.DNSv4 != 16 || s.Network.DNSv6 != 0 || s.Network.AddressV4 != 2 || !s.Network.PrivateDNS {
		t.Fatalf("unexpected safe network data: %+v", s.Network)
	}
	if strings.Contains(JSON(s), "private-interface") {
		t.Fatal("interface address/name leaked")
	}
	for _, kind := range []string{"vpn", "mobile", "wifi", "ethernet", "none"} {
		RecordMobileNetwork(kind, 1, 2, 1, 2, false)
		if d.snapshot().Network.InterfaceType != kind {
			t.Fatal("valid category lost")
		}
	}
}

type diagnosticTransport func(*http.Request) (*http.Response, error)

func (f diagnosticTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func TestOpenProbeDiagnostics(t *testing.T) {
	for _, tc := range []struct {
		name, stage, class string
		transport          diagnosticTransport
	}{
		{"dns", "dns", "name-resolution", func(r *http.Request) (*http.Response, error) {
			httptrace.ContextClientTrace(r.Context()).DNSStart(httptrace.DNSStartInfo{Host: "private-host"})
			return nil, &net.DNSError{Err: "private-secret", Name: "private-host"}
		}},
		{"timeout", "connect", "timeout", func(r *http.Request) (*http.Response, error) { return nil, context.DeadlineExceeded }},
		{"response", "response", "timeout", func(r *http.Request) (*http.Response, error) {
			httptrace.ContextClientTrace(r.Context()).GotConn(httptrace.GotConnInfo{})
			return nil, context.DeadlineExceeded
		}},
		{"http", "response", "http-status", func(r *http.Request) (*http.Response, error) {
			return &http.Response{StatusCode: 403, Body: io.NopCloser(strings.NewReader("private-secret")), Header: make(http.Header)}, nil
		}},
		{"invalid", "body", "invalid-response", func(r *http.Request) (*http.Response, error) {
			return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader("private-secret")), Header: make(http.Header)}, nil
		}},
		{"ready", "health", "none", func(r *http.Request) (*http.Response, error) {
			return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"ok":true,"version":"test"}`)), Header: make(http.Header)}, nil
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			target, _ := url.Parse("http://100.64.0.1:4310/#pair=private-secret")
			var d diagnosticBuffer
			err := probeObserved(&http.Client{Transport: tc.transport}, target, func(stage, class string) { d.recordOpen(stage, class, time.Now()) })
			if (err == nil) != (tc.class == "none") {
				t.Fatalf("unexpected outcome: %v", err)
			}
			d.logf("ordinary log after failed open")
			result := d.snapshot()
			if result.Open.Stage != tc.stage || result.Open.ErrorClass != tc.class || result.Open.Attempts != 1 {
				t.Fatalf("wrong diagnostic: %+v", result.Open)
			}
			encoded, _ := json.Marshal(result)
			for _, secret := range []string{"private-secret", "100.64.0.1", "private-host", "pair="} {
				if strings.Contains(string(encoded), secret) {
					t.Fatal("diagnostic leaked private text")
				}
			}
		})
	}
}
func TestOpenTargetFailureDiagnostic(t *testing.T) {
	n := &Node{}
	_, err := n.Open("http://private-host/#pair=private-secret")
	if err == nil {
		t.Fatal("invalid target accepted")
	}
	d := n.diagnostics.snapshot().Open
	if d.Stage != "target" || d.ErrorClass != "invalid-target" || d.Attempts != 1 {
		t.Fatalf("wrong diagnostic: %+v", d)
	}
}

func TestOpenProbeRealTraceTimeout(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { <-r.Context().Done() }))
	defer server.Close()
	target, _ := url.Parse(server.URL)
	client := server.Client()
	client.Timeout = 30 * time.Millisecond
	var stage, class string
	if err := probeObserved(client, target, func(s, c string) { stage, class = s, c }); err == nil {
		t.Fatal("expected timeout")
	}
	if stage != "response" || class != "timeout" {
		t.Fatalf("unexpected trace classification %s/%s", stage, class)
	}
}
