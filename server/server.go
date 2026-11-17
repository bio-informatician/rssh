package main

import (
	"bufio"
	"crypto/sha1"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

const guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

type Client struct {
	conn net.Conn
	addr string
}

type Server struct {
	sync.Mutex
	clients map[*Client]bool
}

type ChatMessage struct {
	Type   string `json:"type"`
	Sender string `json:"sender"`
	Room   string `json:"room,omitempty"`
	Text   string `json:"text"`
	Time   string `json:"time,omitempty"`
}

func main() {
	port := ":8765"
	s := &Server{clients: make(map[*Client]bool)}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if strings.ToLower(r.Header.Get("Upgrade")) != "websocket" {
			w.WriteHeader(http.StatusOK)
			w.Write([]byte("Rakhssh Chat Server is running. Connect via WebSocket at ws://<host>:8765\n"))
			return
		}

		key := r.Header.Get("Sec-WebSocket-Key")
		if key == "" {
			http.Error(w, "Bad Request", http.StatusBadRequest)
			return
		}

		h := sha1.New()
		h.Write([]byte(key + guid))
		accept := base64.StdEncoding.EncodeToString(h.Sum(nil))

		hj, ok := w.(http.Hijacker)
		if !ok {
			http.Error(w, "Hijacking not supported", http.StatusInternalServerError)
			return
		}

		conn, bufrw, err := hj.Hijack()
		if err != nil {
			return
		}

		response := "HTTP/1.1 101 Switching Protocols\r\n" +
			"Upgrade: websocket\r\n" +
			"Connection: Upgrade\r\n" +
			"Sec-WebSocket-Accept: " + accept + "\r\n\r\n"
		bufrw.WriteString(response)
		bufrw.Flush()

		client := &Client{conn: conn, addr: conn.RemoteAddr().String()}
		s.addClient(client)
		defer s.removeClient(client)

		fmt.Printf("\n[+] Client connected: %s (Active: %d)\n", client.addr, s.count())

		for {
			msg, err := readMessage(bufrw.Reader)
			if err != nil {
				break
			}
			fmt.Printf("\r[%s]: %s\n> ", client.addr, msg)
			s.broadcast(msg, client)
		}
		fmt.Printf("\n[-] Client disconnected: %s\n> ", client.addr)
	})

	fmt.Println("================================================================")
	fmt.Printf("   🚀 Rakhssh Go WebSocket Chat Server running on %s\n", port)
	fmt.Println("================================================================")

	go func() {
		scanner := bufio.NewScanner(os.Stdin)
		for scanner.Scan() {
			text := strings.TrimSpace(scanner.Text())
			if text != "" {
				payload, _ := json.Marshal(ChatMessage{
					Type:   "chat",
					Sender: "Go Server Terminal",
					Text:   text,
					Time:   time.Now().Format("15:04"),
				})
				s.broadcast(string(payload), nil)
			}
			fmt.Print("> ")
		}
	}()

	fmt.Print("> ")
	http.ListenAndServe(port, nil)
}

func (s *Server) addClient(c *Client) {
	s.Lock()
	defer s.Unlock()
	s.clients[c] = true
}

func (s *Server) removeClient(c *Client) {
	s.Lock()
	defer s.Unlock()
	delete(s.clients, c)
	c.conn.Close()
}

func (s *Server) count() int {
	s.Lock()
	defer s.Unlock()
	return len(s.clients)
}

func (s *Server) broadcast(msg string, sender *Client) {
	frame := encodeFrame(msg)
	s.Lock()
	defer s.Unlock()
	for c := range s.clients {
		if c != sender {
			c.conn.Write(frame)
		}
	}
}

func encodeFrame(msg string) []byte {
	b := []byte(msg)
	length := len(b)
	frame := []byte{0x81}

	if length <= 125 {
		frame = append(frame, byte(length))
	} else if length <= 65535 {
		frame = append(frame, 126)
		buf := make([]byte, 2)
		binary.BigEndian.PutUint16(buf, uint16(length))
		frame = append(frame, buf...)
	} else {
		frame = append(frame, 127)
		buf := make([]byte, 8)
		binary.BigEndian.PutUint64(buf, uint64(length))
		frame = append(frame, buf...)
	}
	return append(frame, b...)
}

func readMessage(r *bufio.Reader) (string, error) {
	b1, err := r.ReadByte()
	if err != nil {
		return "", err
	}
	b2, err := r.ReadByte()
	if err != nil {
		return "", err
	}

	opcode := b1 & 0x0F
	if opcode == 0x8 {
		return "", io.EOF
	}

	isMasked := (b2 & 0x80) != 0
	payloadLen := int(b2 & 0x7F)

	if payloadLen == 126 {
		var l uint16
		binary.Read(r, binary.BigEndian, &l)
		payloadLen = int(l)
	} else if payloadLen == 127 {
		var l uint64
		binary.Read(r, binary.BigEndian, &l)
		payloadLen = int(l)
	}

	var mask []byte
	if isMasked {
		mask = make([]byte, 4)
		io.ReadFull(r, mask)
	}

	data := make([]byte, payloadLen)
	_, err = io.ReadFull(r, data)
	if err != nil {
		return "", err
	}

	if isMasked {
		for i := 0; i < payloadLen; i++ {
			data[i] ^= mask[i%4]
		}
	}

	return string(data), nil
}
