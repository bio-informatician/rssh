// Copyright (C) 2026 Rakhssh Contributors - AGPLv3
package chat

import (
	"bufio"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"strings"
	"sync"
	"time"
)

const (
	ColorReset  = "\033[0m"
	ColorBold   = "\033[1m"
	ColorDim    = "\033[2m"
	ColorGreen  = "\033[1;32m" // You
	ColorCyan   = "\033[1;36m" // Peer
	ColorYellow = "\033[1;33m" // System / Info
	ColorRed    = "\033[1;31m" // Alerts / Disconnect
)

// MsgType indicates the control or content type of a message
type MsgType string

const (
	MsgTypeText  MsgType = "text"
	MsgTypeLeave MsgType = "leave"
)

// Message is an ephemeral in-memory payload transferred over the secure stream
type Message struct {
	Type      MsgType `json:"type"`
	Sender    string  `json:"sender"`
	Text      string  `json:"text"`
	Timestamp int64   `json:"ts"`
}

// WriteMessage serializes a 2-byte length-prefixed JSON message onto the stream
func WriteMessage(w io.Writer, msg Message) error {
	data, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	lenBuf := make([]byte, 2)
	binary.BigEndian.PutUint16(lenBuf, uint16(len(data)))
	if _, err := w.Write(lenBuf); err != nil {
		return err
	}
	_, err = w.Write(data)
	return err
}

// ReadMessage deserializes a length-prefixed JSON message from the stream
func ReadMessage(r io.Reader) (Message, error) {
	lenBuf := make([]byte, 2)
	if _, err := io.ReadFull(r, lenBuf); err != nil {
		return Message{}, err
	}
	length := binary.BigEndian.Uint16(lenBuf)
	data := make([]byte, length)
	if _, err := io.ReadFull(r, data); err != nil {
		return Message{}, err
	}
	var msg Message
	err := json.Unmarshal(data, &msg)
	return msg, err
}

// PrintBanner outputs the ephemeral session header
func PrintBanner(w io.Writer, peerAlias string) {
	fmt.Fprintf(w, "%s════════════════════════════════════════════════════════════%s\n", ColorCyan, ColorReset)
	fmt.Fprintf(w, "%s💬 Rakhssh Ephemeral E2EE Chat%s\n", ColorBold, ColorReset)
	fmt.Fprintf(w, "   ├── Peer        : %s%s%s\n", ColorCyan, peerAlias, ColorReset)
	fmt.Fprintf(w, "   ├── Encryption  : Zero-Knowledge PAKE + ChaCha20-Poly1305\n")
	fmt.Fprintf(w, "   ├── Persistence : %sNone (Destroyed upon session exit)%s\n", ColorGreen, ColorReset)
	fmt.Fprintf(w, "   └── Commands    : Type %s/exit%s to leave\n", ColorYellow, ColorReset)
	fmt.Fprintf(w, "%s════════════════════════════════════════════════════════════%s\n\n", ColorCyan, ColorReset)
}

// RunChat manages the bi-directional terminal chat session over an encrypted net.Conn or yamux.Stream
func RunChat(conn io.ReadWriteCloser, localAlias, peerAlias string, in io.Reader, out io.Writer) error {
	defer conn.Close()

	PrintBanner(out, peerAlias)

	doneCh := make(chan struct{})
	var closeOnce sync.Once
	closeSession := func() {
		closeOnce.Do(func() {
			close(doneCh)
		})
	}

	// Prompt helper
	renderPrompt := func() {
		fmt.Fprintf(out, "%sYou > %s", ColorGreen, ColorReset)
	}

	// 1. Receiver goroutine: reads incoming messages from peer
	go func() {
		defer closeSession()
		for {
			msg, err := ReadMessage(conn)
			if err != nil {
				select {
				case <-doneCh:
					return
				default:
					fmt.Fprintf(out, "\r\033[K%s[!] Session ended or peer disconnected.%s\n", ColorYellow, ColorReset)
					return
				}
			}

			if msg.Type == MsgTypeLeave {
				fmt.Fprintf(out, "\r\033[K%s[!] %s left the chat.%s\n", ColorYellow, peerAlias, ColorReset)
				return
			}

			t := time.Unix(msg.Timestamp, 0).Format("15:04:05")
			// \r\033[K clears the current line (which contains the prompt), prints message, and reprints prompt
			fmt.Fprintf(out, "\r\033[K%s[%s]%s %s%s%s: %s\n", ColorDim, t, ColorReset, ColorCyan, peerAlias, ColorReset, msg.Text)
			renderPrompt()
		}
	}()

	// 2. Sender loop: reads user input from stdin
	scanner := bufio.NewScanner(in)
	renderPrompt()

	for {
		select {
		case <-doneCh:
			return nil
		default:
		}

		if !scanner.Scan() {
			break
		}
		text := strings.TrimSpace(scanner.Text())
		if text == "" {
			renderPrompt()
			continue
		}

		if text == "/exit" || text == "/quit" {
			_ = WriteMessage(conn, Message{
				Type:      MsgTypeLeave,
				Sender:    localAlias,
				Timestamp: time.Now().Unix(),
			})
			fmt.Fprintf(out, "\n%s[-] Exited chat.%s\n", ColorYellow, ColorReset)
			closeSession()
			return nil
		}

		now := time.Now()
		msg := Message{
			Type:      MsgTypeText,
			Sender:    localAlias,
			Text:      text,
			Timestamp: now.Unix(),
		}

		if err := WriteMessage(conn, msg); err != nil {
			fmt.Fprintf(out, "\n%s[!] Failed to send message: %v%s\n", ColorRed, err, ColorReset)
			closeSession()
			return err
		}

		// Reformat local message cleanly
		t := now.Format("15:04:05")
		fmt.Fprintf(out, "%s[%s]%s %sYou%s: %s\n", ColorDim, t, ColorReset, ColorGreen, ColorReset, text)
		renderPrompt()
	}

	closeSession()
	return nil
}
