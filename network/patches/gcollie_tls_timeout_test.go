package dnscache

import (
	"context"
	"testing"
	"time"
)

func TestGCollieTLSHandshakeTimeout(t *testing.T) {
	for _, goos := range []string{"android", "linux", "darwin", "windows", "ios"} {
		want := 5 * time.Second
		if goos == "android" { want = 15 * time.Second }
		if got := gcollieTLSHandshakeTimeout(goos); got != want { t.Fatalf("%s: got %v want %v", goos, got, want) }
		deadline := time.Now().Add(time.Second)
		parent, cancel := context.WithDeadline(context.Background(), deadline)
		child, stop := context.WithTimeout(parent, gcollieTLSHandshakeTimeout(goos))
		if got, ok := child.Deadline(); !ok || !got.Equal(deadline) { t.Fatalf("%s: parent deadline lost", goos) }
		cancel()
		if child.Err() != context.Canceled { t.Fatalf("%s: parent cancellation lost", goos) }
		stop()
	}
}
