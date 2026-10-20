// Copyright (C) 2026 Rakhssh Contributors - AGPLv3
package crypto


import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"

	"github.com/schollz/pake/v3"
	"golang.org/x/crypto/hkdf"
)

const (
	defaultCurve = "siec"
	roleHost     = 0
	roleClient   = 1
)

// PAKEHost manages the host side of a SPAKE2 exchange
type PAKEHost struct {
	pakeSession *pake.Pake
}

// SessionKeys contains directional keys and verification tokens
type SessionKeys struct {
	HostToClientKey []byte
	ClientToHostKey []byte
	VerificationKey []byte
}

// DeriveKeys derives directional AEAD keys and an auth token from the shared PAKE key
func DeriveKeys(sharedKey []byte) (*SessionKeys, error) {
	if len(sharedKey) == 0 {
		return nil, errors.New("empty shared key")
	}

	h2c := make([]byte, 32)
	c2h := make([]byte, 32)
	vfy := make([]byte, 32)

	// Derive Host -> Client key
	h2cReader := hkdf.New(sha256.New, sharedKey, nil, []byte("rssh_host_to_client_v1"))
	if _, err := io.ReadFull(h2cReader, h2c); err != nil {
		return nil, fmt.Errorf("failed to derive h2c key: %w", err)
	}

	// Derive Client -> Host key
	c2hReader := hkdf.New(sha256.New, sharedKey, nil, []byte("rssh_client_to_host_v1"))
	if _, err := io.ReadFull(c2hReader, c2h); err != nil {
		return nil, fmt.Errorf("failed to derive c2h key: %w", err)
	}

	// Derive Verification key
	vfyReader := hkdf.New(sha256.New, sharedKey, nil, []byte("rssh_verification_v1"))
	if _, err := io.ReadFull(vfyReader, vfy); err != nil {
		return nil, fmt.Errorf("failed to derive verification key: %w", err)
	}

	return &SessionKeys{
		HostToClientKey: h2c,
		ClientToHostKey: c2h,
		VerificationKey: vfy,
	}, nil
}

// ComputeAuthTag creates an HMAC authentication tag using the verification key
func ComputeAuthTag(verificationKey []byte, message []byte) []byte {
	mac := hmac.New(sha256.New, verificationKey)
	mac.Write(message)
	return mac.Sum(nil)
}

// VerifyAuthTag validates an HMAC authentication tag
func VerifyAuthTag(verificationKey []byte, message []byte, expectedTag []byte) bool {
	actual := ComputeAuthTag(verificationKey, message)
	return hmac.Equal(actual, expectedTag)
}

// validatePAKEMsg validates that an incoming PAKE message is a non-empty valid JSON object
// before passing it to pake.Update, preventing nil-pointer panics from malformed payloads.
func validatePAKEMsg(msg []byte) error {
	if len(msg) == 0 {
		return errors.New("empty PAKE message")
	}
	var raw json.RawMessage
	if err := json.Unmarshal(msg, &raw); err != nil {
		return fmt.Errorf("PAKE message is not valid JSON: %w", err)
	}
	// Must be a JSON object, not null, array, or scalar
	if len(raw) == 0 || raw[0] != '{' {
		return errors.New("PAKE message must be a JSON object")
	}
	return nil
}

// StartHostPAKE initializes the Host PAKE exchange and returns the first message to send to the client
func StartHostPAKE(pin string) (*PAKEHost, []byte, error) {
	p, err := pake.InitCurve([]byte(pin), roleHost, defaultCurve)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to init host pake: %w", err)
	}
	return &PAKEHost{pakeSession: p}, p.Bytes(), nil
}

// RespondClientPAKE takes the host's initial message, computes the client's response message,
// and derives the session keys. It validates the message before calling Update to prevent panics.
func RespondClientPAKE(pin string, hostMsg []byte) (clientMsg []byte, keys *SessionKeys, err error) {
	if err := validatePAKEMsg(hostMsg); err != nil {
		return nil, nil, fmt.Errorf("invalid host PAKE message: %w", err)
	}

	p, err := pake.InitCurve([]byte(pin), roleClient, defaultCurve)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to init client pake: %w", err)
	}

	if err := p.Update(hostMsg); err != nil {
		return nil, nil, fmt.Errorf("failed client update: %w", err)
	}

	rawKey, err := p.SessionKey()
	if err != nil {
		return nil, nil, fmt.Errorf("failed to derive client session key: %w", err)
	}

	keys, err = DeriveKeys(rawKey)
	if err != nil {
		return nil, nil, err
	}

	return p.Bytes(), keys, nil
}

// FinishHostPAKE finishes the host PAKE exchange with the client's response and derives the session keys.
// It validates the message before calling Update to prevent panics.
func (h *PAKEHost) FinishHostPAKE(clientMsg []byte) (*SessionKeys, error) {
	if err := validatePAKEMsg(clientMsg); err != nil {
		return nil, fmt.Errorf("invalid client PAKE message: %w", err)
	}

	if err := h.pakeSession.Update(clientMsg); err != nil {
		return nil, fmt.Errorf("failed host update: %w", err)
	}

	rawKey, err := h.pakeSession.SessionKey()
	if err != nil {
		return nil, fmt.Errorf("failed to derive host session key: %w", err)
	}

	return DeriveKeys(rawKey)
}

// ConfirmationNonceLen is the length of the per-session key-confirmation nonce.
const ConfirmationNonceLen = 16

// BuildConfirmationTag generates the HMAC key-confirmation tag that proves both peers
// derived the same session key from the same PIN.
// The tag is: HMAC-SHA256(verificationKey, "rssh-confirm" || direction || nonce)
// direction must be either "host" or "client".
func BuildConfirmationTag(verificationKey []byte, direction string, nonce []byte) []byte {
	mac := hmac.New(sha256.New, verificationKey)
	mac.Write([]byte("rssh-confirm"))
	mac.Write([]byte(direction))
	mac.Write(nonce)
	return mac.Sum(nil)
}

// GenerateConfirmationNonce returns a fresh random nonce for key confirmation.
func GenerateConfirmationNonce() ([]byte, error) {
	b := make([]byte, ConfirmationNonceLen)
	if _, err := rand.Read(b); err != nil {
		return nil, err
	}
	return b, nil
}
