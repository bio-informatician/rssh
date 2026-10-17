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

func TestSingleSessionLockBusy(t *testing.T) {
	server := NewServer()
	defer server.Close()
	httpServer := httptest.NewServer(server)
	defer httpServer.Close()

	wsURL := "ws" + strings.TrimPrefix(httpServer.URL, "http")

	hostID := "555-666-777"
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// 1. Host registers
	hostClient, err := Dial(wsURL)
	if err != nil {
		t.Fatalf("host dial failed: %v", err)
	}
	defer hostClient.Close()

	if err := hostClient.RegisterHost(ctx, hostID); err != nil {
		t.Fatalf("host register failed: %v", err)
	}

	// 2. Client 1 connects -> should succeed
	client1, err := Dial(wsURL)
	if err != nil {
		t.Fatalf("client 1 dial failed: %v", err)
	}
	defer client1.Close()

	sess1, err := client1.ConnectTarget(ctx, hostID)
	if err != nil {
		t.Fatalf("client 1 connect failed: %v", err)
	}
	if sess1 == "" {
		t.Fatal("empty session 1 ID")
	}

	// 3. Client 2 attempts to connect to same Host while busy -> MUST be rejected with ErrHostBusy
	client2, err := Dial(wsURL)
	if err != nil {
		t.Fatalf("client 2 dial failed: %v", err)
	}
	defer client2.Close()

	_, err = client2.ConnectTarget(ctx, hostID)
	if err == nil || !strings.Contains(err.Error(), ErrHostBusy) {
		t.Fatalf("expected ErrHostBusy for dual connection attempt, got: %v", err)
	}

	// 4. Client 1 terminates/closes session
	_ = client1.WriteMessage(&Message{Type: TypeClose, SessionID: sess1})
	time.Sleep(50 * time.Millisecond)

	// 5. Now Client 2 connects -> should succeed because host lock is released
	sess2, err := client2.ConnectTarget(ctx, hostID)
	if err != nil {
		t.Fatalf("client 2 connect after release failed: %v", err)
	}
	if sess2 == "" {
		t.Fatal("empty session 2 ID")
	}
}

func TestRemoteTermination(t *testing.T) {
	server := NewServer()
	defer server.Close()
	httpServer := httptest.NewServer(server)
	defer httpServer.Close()

	wsURL := "ws" + strings.TrimPrefix(httpServer.URL, "http")

	hostID := "333-444-555"
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	hostClient, err := Dial(wsURL)
	if err != nil {
		t.Fatalf("host dial failed: %v", err)
	}
	defer hostClient.Close()

	if err := hostClient.RegisterHost(ctx, hostID); err != nil {
		t.Fatalf("host register failed: %v", err)
	}

	termHostCh := make(chan string, 1)
	hostClient.SetTerminationHandler(func(sessionID, reason string) {
		termHostCh <- reason
	})

	client, err := Dial(wsURL)
	if err != nil {
		t.Fatalf("client dial failed: %v", err)
	}
	defer client.Close()

	termClientCh := make(chan string, 1)
	client.SetTerminationHandler(func(sessionID, reason string) {
		termClientCh <- reason
	})

	sessID, err := client.ConnectTarget(ctx, hostID)
	if err != nil {
		t.Fatalf("client connect failed: %v", err)
	}

	// Server revokes session remotely
	server.TerminateSession(sessID, "admin revoked session")

	select {
	case reason := <-termClientCh:
		if reason != "admin revoked session" {
			t.Fatalf("client received unexpected reason: %s", reason)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("client did not receive terminate message")
	}

	select {
	case reason := <-termHostCh:
		if reason != "admin revoked session" {
			t.Fatalf("host received unexpected reason: %s", reason)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("host did not receive terminate message")
	}
}

func TestSessionTimeouts(t *testing.T) {
	// Idle timeout: 100ms, Max duration: 300ms
	server := NewServerWithOptions(100*time.Millisecond, 300*time.Millisecond)
	defer server.Close()
	httpServer := httptest.NewServer(server)
	defer httpServer.Close()

	wsURL := "ws" + strings.TrimPrefix(httpServer.URL, "http")

	hostID := "111-999-888"
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	hostClient, err := Dial(wsURL)
	if err != nil {
		t.Fatalf("host dial failed: %v", err)
	}
	defer hostClient.Close()

	_ = hostClient.RegisterHost(ctx, hostID)

	termCh := make(chan string, 1)
	client, err := Dial(wsURL)
	if err != nil {
		t.Fatalf("client dial failed: %v", err)
	}
	defer client.Close()

	client.SetTerminationHandler(func(sessionID, reason string) {
		termCh <- reason
	})

	_, err = client.ConnectTarget(ctx, hostID)
	if err != nil {
		t.Fatalf("connect target failed: %v", err)
	}

	// Do nothing and wait for idle timeout (100ms) to fire via monitor loop
	select {
	case reason := <-termCh:
		if !strings.Contains(reason, "idle timeout") {
			t.Fatalf("expected idle timeout reason, got: %s", reason)
		}
	case <-time.After(4 * time.Second):
		t.Fatal("idle timeout did not trigger terminate within deadline")
	}
}

