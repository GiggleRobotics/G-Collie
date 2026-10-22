package core

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
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
