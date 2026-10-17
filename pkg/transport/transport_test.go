package transport

import (
	"context"
	"net"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"rssh/pkg/crypto"
	"rssh/pkg/signaling"
)

func TestSessionYamuxEncrypted(t *testing.T) {
	pipeClient, pipeHost := net.Pipe()
	defer pipeClient.Close()
	defer pipeHost.Close()

	keys := &crypto.SessionKeys{
		HostToClientKey: make([]byte, 32),
		ClientToHostKey: make([]byte, 32),
		VerificationKey: make([]byte, 32),
	}
	for i := range keys.HostToClientKey {
		keys.HostToClientKey[i] = byte(i)
		keys.ClientToHostKey[i] = byte(i + 1)
		keys.VerificationKey[i] = byte(i + 2)
	}

	var (
		hostSession   *Session
		clientSession *Session
		errHost       error
		errClient     error
		wg            sync.WaitGroup
	)

	wg.Add(2)
	go func() {
		defer wg.Done()
		hostSession, errHost = NewSession(pipeHost, keys, true, TransportTypeRelay)
	}()

	go func() {
		defer wg.Done()
		clientSession, errClient = NewSession(pipeClient, keys, false, TransportTypeRelay)
	}()

	wg.Wait()
	if errHost != nil {
		t.Fatalf("host session init failed: %v", errHost)
	}
	defer hostSession.Close()

	if errClient != nil {
		t.Fatalf("client session init failed: %v", errClient)
	}
	defer clientSession.Close()

	// Open stream from client
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	streamCh := make(chan net.Conn, 1)
	go func() {
		stream, err := hostSession.AcceptStream()
		if err == nil {
			streamCh <- stream
		}
	}()

	clientStream, err := clientSession.OpenStream(ctx)
	if err != nil {
		t.Fatalf("failed to open yamux stream from client: %v", err)
	}
	defer clientStream.Close()

	hostStream := <-streamCh
	defer hostStream.Close()

	// Test streaming data over multiplexer
	msg := []byte("Testing yamux multiplexed channel data transmission!")
	go func() {
		_, _ = clientStream.Write(msg)
	}()

	buf := make([]byte, 128)
	n, err := hostStream.Read(buf)
	if err != nil {
		t.Fatalf("host stream read failed: %v", err)
	}
	if string(buf[:n]) != string(msg) {
		t.Fatalf("expected '%s', got '%s'", msg, buf[:n])
	}
}

func TestFullOrchestrationSignalingPAKE(t *testing.T) {
	server := signaling.NewServer()
	httpServer := httptest.NewServer(server)
	defer httpServer.Close()

	wsURL := "ws" + strings.TrimPrefix(httpServer.URL, "http")

	// Host dials server
	hostClient, err := signaling.Dial(wsURL)
	if err != nil {
		t.Fatalf("host dial failed: %v", err)
	}
	defer hostClient.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()

	hostID := "777-888-999"
	pin := "1234"

	if err := hostClient.RegisterHost(ctx, hostID); err != nil {
		t.Fatalf("host register failed: %v", err)
	}

	incomingSessionCh := make(chan string, 1)
	hostClient.SetHandlers(
		func(sessionID string) {
			incomingSessionCh <- sessionID
		},
		nil, nil, nil, nil,
	)

	// User client dials server
	userClient, err := signaling.Dial(wsURL)
	if err != nil {
		t.Fatalf("user dial failed: %v", err)
	}
	defer userClient.Close()

	clientSessionID, err := userClient.ConnectTarget(ctx, hostID)
	if err != nil {
		t.Fatalf("user connect failed: %v", err)
	}

	hostSessionID := <-incomingSessionCh

	// Run Orchestration in parallel on both sides
	var (
		hostSess   *Session
		clientSess *Session
		errH       error
		errC       error
		wg         sync.WaitGroup
	)

	wg.Add(2)
	go func() {
		defer wg.Done()
		hostSess, errH = OrchestrateHost(ctx, hostClient, hostSessionID, pin, 100*time.Millisecond)
	}()

	go func() {
		defer wg.Done()
		clientSess, errC = OrchestrateClient(ctx, userClient, clientSessionID, pin, 100*time.Millisecond)
	}()

	wg.Wait()
	if errH != nil {
		t.Fatalf("orchestrate host failed: %v", errH)
	}
	defer hostSess.Close()

	if errC != nil {
		t.Fatalf("orchestrate client failed: %v", errC)
	}
	defer clientSess.Close()

	// Verify we can open and communicate over yamux stream
	go func() {
		st, err := hostSess.AcceptStream()
		if err == nil {
			_, _ = st.Write([]byte("pong from host"))
		}
	}()

	cStream, err := clientSess.OpenStream(ctx)
	if err != nil {
		t.Fatalf("open stream failed: %v", err)
	}
	defer cStream.Close()

	buf := make([]byte, 64)
	n, err := cStream.Read(buf)
	if err != nil {
		t.Fatalf("read stream failed: %v", err)
	}
	if string(buf[:n]) != "pong from host" {
		t.Fatalf("unexpected reply: %s", buf[:n])
	}
}
