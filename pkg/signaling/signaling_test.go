package signaling

import (
	"context"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestSignalingAndRelay(t *testing.T) {
	server := NewServer()
	httpServer := httptest.NewServer(server)
	defer httpServer.Close()

	wsURL := "ws" + strings.TrimPrefix(httpServer.URL, "http")

	// 1. Host dials server
	hostClient, err := Dial(wsURL)
	if err != nil {
		t.Fatalf("failed to dial host client: %v", err)
	}
	defer hostClient.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	hostID := "482-910-334"
	err = hostClient.RegisterHost(ctx, hostID)
	if err != nil {
		t.Fatalf("host registration failed: %v", err)
	}

	// Channel to wait for incoming session on host
	var (
		sessionIDHost string
		hostRelayConn *RelayConn
		wgSession     sync.WaitGroup
	)
	wgSession.Add(1)

	hostClient.SetHandlers(
		func(sessionID string) {
			sessionIDHost = sessionID
			hostRelayConn = NewRelayConn(hostClient, sessionID)
			wgSession.Done()
		},
		nil,
		nil,
		func(sessionID, data string) {
			if hostRelayConn != nil {
				_ = hostRelayConn.PushIncomingData(data)
			}
		},
		nil,
	)

	// 2. Client dials server
	userClient, err := Dial(wsURL)
	if err != nil {
		t.Fatalf("failed to dial user client: %v", err)
	}
	defer userClient.Close()

	// 3. Client connects to Host ID
	sessionIDClient, err := userClient.ConnectTarget(ctx, hostID)
	if err != nil {
		t.Fatalf("client connection to host failed: %v", err)
	}

	clientRelayConn := NewRelayConn(userClient, sessionIDClient)
	userClient.SetHandlers(
		nil,
		nil,
		nil,
		func(sessionID, data string) {
			_ = clientRelayConn.PushIncomingData(data)
		},
		nil,
	)

	// Wait for host to receive incoming session
	wgSession.Wait()

	if sessionIDHost != sessionIDClient {
		t.Fatalf("session IDs do not match: host=%s, client=%s", sessionIDHost, sessionIDClient)
	}

	// 4. Test Relay communication between Client and Host
	messageToHost := []byte("hello host via relay")
	go func() {
		_, _ = clientRelayConn.Write(messageToHost)
	}()

	recvBuf := make([]byte, 128)
	n, err := hostRelayConn.Read(recvBuf)
	if err != nil {
		t.Fatalf("host relay read failed: %v", err)
	}
	if string(recvBuf[:n]) != string(messageToHost) {
		t.Fatalf("expected '%s', got '%s'", messageToHost, recvBuf[:n])
	}

	// Reverse direction: Host writes to Client
	messageToClient := []byte("welcome client!")
	go func() {
		_, _ = hostRelayConn.Write(messageToClient)
	}()

	n, err = clientRelayConn.Read(recvBuf)
	if err != nil {
		t.Fatalf("client relay read failed: %v", err)
	}
	if string(recvBuf[:n]) != string(messageToClient) {
		t.Fatalf("expected '%s', got '%s'", messageToClient, recvBuf[:n])
	}
}

func TestConnectToOfflineHost(t *testing.T) {
	server := NewServer()
	httpServer := httptest.NewServer(server)
	defer httpServer.Close()

	wsURL := "ws" + strings.TrimPrefix(httpServer.URL, "http")

	client, err := Dial(wsURL)
	if err != nil {
		t.Fatalf("failed to dial client: %v", err)
	}
	defer client.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	_, err = client.ConnectTarget(ctx, "999-999-999")
	if err == nil {
		t.Fatal("expected error connecting to non-existent host")
	}
}
