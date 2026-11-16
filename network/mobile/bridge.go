//go:build android

package main

/*
#include <stdlib.h>
*/
import "C"
import (
	"gcollie/network/core"
	"os"
	"path/filepath"
	"sync"
)

var mu sync.Mutex
var node *core.Node

func result(e error) *C.char {
	if e != nil {
		return C.CString(core.Failure(e))
	}
	return C.CString(`{"ok":true}`)
}

//export GCStart
func GCStart(dir *C.char) *C.char {
	mu.Lock()
	defer mu.Unlock()
	if node != nil {
		// Status/Open call Start too: do not inject a link event on every poll.
		// GCConfigureNetwork owns actual-link and explicit recovery changes.
		return result(nil)
	}
	var e error
	base := C.GoString(dir)
	for _, folder := range []string{"logs", "cache", "tmp"} {
		if e = os.MkdirAll(filepath.Join(base, folder), 0700); e != nil {
			return result(e)
		}
	}
	os.Setenv("TS_LOGS_DIR", filepath.Join(base, "logs"))
	os.Setenv("XDG_CACHE_HOME", filepath.Join(base, "cache"))
	os.Setenv("TMPDIR", filepath.Join(base, "tmp"))
	node, e = core.New(base, "g-collie-phone")
	return result(e)
}

//export GCStatus
func GCStatus() *C.char {
	mu.Lock()
	defer mu.Unlock()
	if node == nil {
		return C.CString(`{"state":"Stopped"}`)
	}
	return C.CString(core.JSON(node.Status()))
}

//export GCLogin
func GCLogin() *C.char {
	mu.Lock()
	defer mu.Unlock()
	if node == nil {
		return C.CString(`{"error":"网络尚未启动"}`)
	}
	return result(node.Login())
}

//export GCOpen
func GCOpen(raw *C.char) *C.char {
	mu.Lock()
	defer mu.Unlock()
	if node == nil {
		return C.CString(`{"error":"网络尚未启动"}`)
	}
	g, e := node.Open(C.GoString(raw))
	if e != nil {
		return result(e)
	}
	return C.CString(core.JSON(g))
}

//export GCLogout
func GCLogout() *C.char {
	mu.Lock()
	defer mu.Unlock()
	if node == nil {
		return result(nil)
	}
	return result(node.Logout())
}

//export GCStop
func GCStop() {
	mu.Lock()
	defer mu.Unlock()
	if node != nil {
		node.Close()
		node = nil
	}
}
func main() {}

//export GCConfigureNetwork
func GCConfigureNetwork(raw *C.char) *C.char {
	mu.Lock()
	defer mu.Unlock()
	changed, err := configureNetwork(C.GoString(raw))
	if err == nil && changed && node != nil {
		node.NetworkChanged()
	}
	if err != nil {
		return result(err)
	}
	return C.CString(core.JSON(map[string]any{"ok": true, "changed": changed}))
}
