// Copyright (C) 2026 Rakhssh Contributors - AGPLv3
package main

import (
	"context"
	"net"
	"net/http"
	"testing"
	"time"
)

func TestSetupServerAndListen(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen failed: %v", err)
	}
	defer ln.Close()

	addr := ln.Addr().String()
	server, httpServer := setupServer(addr, 5*time.Minute, 1*time.Hour)
	defer server.Close()

	if httpServer.Addr != addr {
		t.Errorf("httpServer.Addr = %s, want %s", httpServer.Addr, addr)
	}
	if httpServer.Handler == nil {
		t.Error("httpServer.Handler is nil")
	}

	errCh := make(chan error, 1)
	go func() {
		err := httpServer.Serve(ln)
		if err != nil && err != http.ErrServerClosed {
			errCh <- err
		}
	}()

	// Query health / base endpoint
	resp, err := http.Get("http://" + addr)
	if err != nil {
		t.Fatalf("GET / failed: %v", err)
	}
	defer resp.Body.Close()

	// Shutdown server
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := httpServer.Shutdown(ctx); err != nil {
		t.Fatalf("Shutdown failed: %v", err)
	}
}
