package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"rssh/pkg/signaling"
)

func main() {
	addr := flag.String("addr", ":8443", "Server listen address (e.g. :8443 or :443)")
	certFile := flag.String("cert", "", "Path to TLS certificate file")
	keyFile := flag.String("key", "", "Path to TLS private key file")
	idleTimeout := flag.Duration("idle-timeout", 30*time.Minute, "Session idle timeout (e.g. 30m)")
	maxDuration := flag.Duration("max-duration", 2*time.Hour, "Maximum absolute session duration (e.g. 2h)")
	flag.Parse()

	server, httpServer := setupServer(*addr, *idleTimeout, *maxDuration)
	defer server.Close()

	go func() {
		log.Printf("🐎⚡ Rakhssh Signaling & Relay Server listening on %s", *addr)
		var err error
		if *certFile != "" && *keyFile != "" {
			err = httpServer.ListenAndServeTLS(*certFile, *keyFile)
		} else {
			err = httpServer.ListenAndServe()
		}
		if err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server error: %v", err)
		}
	}()

	// Graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	<-sigChan

	log.Println("\nShutting down server gracefully...")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := httpServer.Shutdown(ctx); err != nil {
		fmt.Printf("Shutdown error: %v\n", err)
	}
	log.Println("Server stopped.")
}

func setupServer(addr string, idleTimeout, maxDuration time.Duration) (*signaling.Server, *http.Server) {
	server := signaling.NewServerWithOptions(idleTimeout, maxDuration)
	httpServer := &http.Server{
		Addr:         addr,
		Handler:      server,
		ReadTimeout:  120 * time.Second,
		WriteTimeout: 120 * time.Second,
	}
	return server, httpServer
}
