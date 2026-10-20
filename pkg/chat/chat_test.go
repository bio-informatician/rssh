// Copyright (C) 2026 Rakhssh Contributors - AGPLv3
package chat

import (
	"bytes"
	"io"
	"net"
	"strings"
	"testing"
	"time"
)

func TestMessageSerialization(t *testing.T) {
	var buf bytes.Buffer
	orig := Message{
		Type:      MsgTypeText,
		Sender:    "Alice",
		Text:      "Hello World!",
		Timestamp: time.Now().Unix(),
	}

	if err := WriteMessage(&buf, orig); err != nil {
		t.Fatalf("WriteMessage failed: %v", err)
	}

	readBack, err := ReadMessage(&buf)
	if err != nil {
		t.Fatalf("ReadMessage failed: %v", err)
	}

	if readBack.Type != orig.Type || readBack.Sender != orig.Sender || readBack.Text != orig.Text {
		t.Fatalf("mismatch: got %+v, want %+v", readBack, orig)
	}
}

func TestRunChatExchange(t *testing.T) {
	c1, c2 := net.Pipe()

	aliceInReader, aliceInWriter := io.Pipe()
	aliceOut := &bytes.Buffer{}

	bobInReader, bobInWriter := io.Pipe()
	bobOut := &bytes.Buffer{}

	errCh := make(chan error, 2)

	// Run Alice
	go func() {
		errCh <- RunChat(c1, "Alice", "Bob", aliceInReader, aliceOut)
	}()

	// Run Bob
	go func() {
		errCh <- RunChat(c2, "Bob", "Alice", bobInReader, bobOut)
	}()

	// Alice sends message to Bob
	time.Sleep(50 * time.Millisecond)
	_, _ = aliceInWriter.Write([]byte("Hello Bob!\n"))

	// Bob sends message to Alice
	time.Sleep(50 * time.Millisecond)
	_, _ = bobInWriter.Write([]byte("Hey Alice!\n"))

	time.Sleep(50 * time.Millisecond)

	// Alice exits
	_, _ = aliceInWriter.Write([]byte("/exit\n"))

	_ = aliceInWriter.Close()
	_ = bobInWriter.Close()

	// Wait for routines
	for i := 0; i < 2; i++ {
		select {
		case err := <-errCh:
			if err != nil {
				t.Fatalf("RunChat returned error: %v", err)
			}
		case <-time.After(2 * time.Second):
			t.Fatal("chat session timed out")
		}
	}

	aliceOutput := aliceOut.String()
	bobOutput := bobOut.String()

	if !strings.Contains(bobOutput, "Hello Bob!") {
		t.Fatalf("Bob did not receive message: %s", bobOutput)
	}
	if !strings.Contains(aliceOutput, "Hey Alice!") {
		t.Fatalf("Alice did not receive message: %s", aliceOutput)
	}
}
