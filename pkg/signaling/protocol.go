package signaling

// Message types for signaling & relay
const (
	TypeRegister   = "register"
	TypeRegistered = "registered"
	TypeConnect    = "connect"
	TypeConnected  = "connected"
	TypeIncoming   = "incoming"
	TypePAKE       = "pake"
	TypeSignal     = "signal"
	TypeRelay      = "relay"
	TypeError      = "error"
	TypePing       = "ping"
	TypePong       = "pong"
	TypeClose      = "close"
	TypeTerminate  = "terminate"

	ErrHostBusy = "host is busy with another active session"
)

// Message is the standard JSON packet exchanged over WebSocket
type Message struct {
	Type      string `json:"type"`
	ID        string `json:"id,omitempty"`
	TargetID  string `json:"target_id,omitempty"`
	SessionID string `json:"session_id,omitempty"`
	Data      string `json:"data,omitempty"`
	Error     string `json:"error,omitempty"`
	Status    string `json:"status,omitempty"`
}
