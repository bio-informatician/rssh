package crypto

import (
	"bytes"
	"io"
	"net"
	"testing"
)

func TestPAKEHandshakeSuccess(t *testing.T) {
	pin := "8492"

	// 1. Host starts PAKE
	hostPAKE, hostMsg, err := StartHostPAKE(pin)
	if err != nil {
		t.Fatalf("StartHostPAKE failed: %v", err)
	}

	// 2. Client responds to Host message
	clientMsg, clientKeys, err := RespondClientPAKE(pin, hostMsg)
	if err != nil {
		t.Fatalf("RespondClientPAKE failed: %v", err)
	}

	// 3. Host finishes PAKE
	hostKeys, err := hostPAKE.FinishHostPAKE(clientMsg)
	if err != nil {
		t.Fatalf("FinishHostPAKE failed: %v", err)
	}

	// Verify both sides derived matching keys
	if !bytes.Equal(hostKeys.HostToClientKey, clientKeys.HostToClientKey) {
		t.Fatal("HostToClientKey mismatch")
	}
	if !bytes.Equal(hostKeys.ClientToHostKey, clientKeys.ClientToHostKey) {
		t.Fatal("ClientToHostKey mismatch")
	}
	if !bytes.Equal(hostKeys.VerificationKey, clientKeys.VerificationKey) {
		t.Fatal("VerificationKey mismatch")
	}

	// Verify auth tag
	challenge := []byte("rssh_handshake_auth_check")
	tag := ComputeAuthTag(clientKeys.VerificationKey, challenge)
	if !VerifyAuthTag(hostKeys.VerificationKey, challenge, tag) {
		t.Fatal("Auth tag verification failed")
	}
}

func TestPAKEHandshakeWrongPIN(t *testing.T) {
	hostPin := "8492"
	clientPin := "9999"

	hostPAKE, hostMsg, err := StartHostPAKE(hostPin)
	if err != nil {
		t.Fatalf("StartHostPAKE failed: %v", err)
	}

	clientMsg, clientKeys, err := RespondClientPAKE(clientPin, hostMsg)
	if err != nil {
		// Some PAKE implementations fail during Update if parameters diverge
		return
	}

	hostKeys, err := hostPAKE.FinishHostPAKE(clientMsg)
	if err != nil {
		return
	}

	// Keys must not match
	if bytes.Equal(hostKeys.HostToClientKey, clientKeys.HostToClientKey) {
		t.Fatal("Keys matched despite different PINs!")
	}

	// Verification tag check must fail
	challenge := []byte("rssh_handshake_auth_check")
	tag := ComputeAuthTag(clientKeys.VerificationKey, challenge)
	if VerifyAuthTag(hostKeys.VerificationKey, challenge, tag) {
		t.Fatal("Auth tag verification unexpectedly passed with wrong PIN!")
	}
}

func TestSecureConnPipe(t *testing.T) {
	// Create simulated network pipe
	pipeClient, pipeHost := net.Pipe()
	defer pipeClient.Close()
	defer pipeHost.Close()

	keys := &SessionKeys{
		HostToClientKey: make([]byte, 32),
		ClientToHostKey: make([]byte, 32),
		VerificationKey: make([]byte, 32),
	}
	for i := range keys.HostToClientKey {
		keys.HostToClientKey[i] = byte(i)
		keys.ClientToHostKey[i] = byte(i + 10)
		keys.VerificationKey[i] = byte(i + 20)
	}

	hostConn, err := NewSecureConn(pipeHost, keys, true)
	if err != nil {
		t.Fatalf("failed to create host secure conn: %v", err)
	}
	clientConn, err := NewSecureConn(pipeClient, keys, false)
	if err != nil {
		t.Fatalf("failed to create client secure conn: %v", err)
	}

	// Test 1: Client writes to Host
	msgFromClient := []byte("Hello from client through ChaCha20-Poly1305!")
	go func() {
		if _, err := clientConn.Write(msgFromClient); err != nil {
			t.Errorf("client write failed: %v", err)
		}
	}()

	recvBuf := make([]byte, 1024)
	n, err := hostConn.Read(recvBuf)
	if err != nil {
		t.Fatalf("host read failed: %v", err)
	}
	if string(recvBuf[:n]) != string(msgFromClient) {
		t.Fatalf("expected '%s', got '%s'", msgFromClient, recvBuf[:n])
	}

	// Test 2: Host writes to Client with large payload (>MaxFrameSize)
	largeData := make([]byte, MaxFrameSize*2+500)
	for i := range largeData {
		largeData[i] = byte(i % 256)
	}

	go func() {
		if _, err := hostConn.Write(largeData); err != nil {
			t.Errorf("host write large data failed: %v", err)
		}
	}()

	receivedLarge := make([]byte, len(largeData))
	if _, err := io.ReadFull(clientConn, receivedLarge); err != nil {
		t.Fatalf("client read large data failed: %v", err)
	}

	if !bytes.Equal(largeData, receivedLarge) {
		t.Fatal("large data mismatch after transfer")
	}
}
