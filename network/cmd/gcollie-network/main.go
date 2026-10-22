package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"gcollie/network/core"
	"net/http"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"
)

func main() {
	dir := flag.String("dir", "", "Private network state directory")
	port := flag.Int("port", 4310, "Local console port")
	flag.Parse()
	if *dir == "" {
		fmt.Fprintln(os.Stderr, "missing --dir")
		os.Exit(2)
	}
	n, e := core.New(*dir, "g-collie-computer")
	if e != nil {
		fmt.Fprintln(os.Stderr, "network initialization failed")
		os.Exit(1)
	}
	defer n.Close()
	var output sync.Mutex
	send := func(v any) { output.Lock(); defer output.Unlock(); fmt.Println(core.JSON(v)) }
	done := make(chan os.Signal, 1)
	signal.Notify(done, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		scanner := bufio.NewScanner(os.Stdin)
		scanner.Buffer(make([]byte, 4096), 8192)
		for scanner.Scan() {
			var cmd struct {
				Action string `json:"action"`
			}
			if json.Unmarshal(scanner.Bytes(), &cmd) != nil {
				continue
			}
			var err error
			switch cmd.Action {
			case "login":
				err = n.Login()
			case "logout":
				err = n.Logout()
			}
			if err != nil {
				send(map[string]string{"error": err.Error()})
			}
		}
		done <- syscall.SIGTERM
	}()
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	serving := false
	serveErrors := make(chan error, 1)
	for {
		select {
		case <-done:
			return
		case <-serveErrors:
			serving = false
		case <-ticker.C:
			s := n.Status()
			send(s)
			if s.State == "Running" && !serving {
				serving = true
				go func() {
					err := n.Serve(*port)
					if err != nil && !errors.Is(err, http.ErrServerClosed) {
						send(map[string]string{"error": "私有网络监听失败"})
					}
					serveErrors <- err
				}()
			}
		}
	}
}
