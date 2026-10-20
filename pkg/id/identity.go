// Copyright (C) 2026 Rakhssh Contributors - AGPLv3
package id

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

// Identity represents a local cryptographic Ed25519 identity
type Identity struct {
	PrivateKey ed25519.PrivateKey
	PublicKey  ed25519.PublicKey
	ID         string // Deterministic 9-digit ID derived from public key
}

// LoadOrCreateIdentity loads or creates ~/.config/rssh/identity.key
func LoadOrCreateIdentity(path string) (*Identity, error) {
	if path == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			home = "."
		}
		path = filepath.Join(home, ".config", "rssh", "identity.key")
	}

	data, err := os.ReadFile(path)
	if err == nil && len(data) == ed25519.PrivateKeySize {
		priv := ed25519.PrivateKey(data)
		pub := priv.Public().(ed25519.PublicKey)
		return &Identity{
			PrivateKey: priv,
			PublicKey:  pub,
			ID:         DeriveIDFromPubKey(pub),
		}, nil
	}

	// Generate new Ed25519 keypair
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("failed to generate ed25519 key: %w", err)
	}

	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return nil, fmt.Errorf("failed to create identity dir: %w", err)
	}

	if err := os.WriteFile(path, priv, 0600); err != nil {
		return nil, fmt.Errorf("failed to save identity key: %w", err)
	}

	return &Identity{
		PrivateKey: priv,
		PublicKey:  pub,
		ID:         DeriveIDFromPubKey(pub),
	}, nil
}

// DeriveIDFromPubKey computes a non-spoofable 9-digit ID from an Ed25519 public key
func DeriveIDFromPubKey(pub ed25519.PublicKey) string {
	sum := sha256.Sum256(pub)
	val := binary.BigEndian.Uint64(sum[:8]) % 1000000000
	return fmt.Sprintf("%03d-%03d-%03d", val/1000000, (val/1000)%1000, val%1000)
}

// TOFUKnownHosts manages Trust-On-First-Use caching of host public keys
type TOFUKnownHosts struct {
	path  string
	hosts map[string]string // hostID -> hex(pubkey)
	mu    sync.RWMutex
}

// NewTOFUKnownHosts loads ~/.config/rssh/known_hosts
func NewTOFUKnownHosts(path string) *TOFUKnownHosts {
	if path == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			home = "."
		}
		path = filepath.Join(home, ".config", "rssh", "known_hosts")
	}

	kh := &TOFUKnownHosts{
		path:  path,
		hosts: make(map[string]string),
	}
	kh.load()
	return kh
}

func (k *TOFUKnownHosts) load() {
	k.mu.Lock()
	defer k.mu.Unlock()

	data, err := os.ReadFile(k.path)
	if err != nil {
		return
	}

	lines := strings.Split(string(data), "\n")
	for _, l := range lines {
		l = strings.TrimSpace(l)
		if l == "" || strings.HasPrefix(l, "#") {
			continue
		}
		parts := strings.Fields(l)
		if len(parts) >= 2 {
			k.hosts[parts[0]] = parts[1]
		}
	}
}

// VerifyOrTrust checks if the given host ID matches cached public key, or records it if first seen
func (k *TOFUKnownHosts) VerifyOrTrust(hostID string, pubKey ed25519.PublicKey) (trusted bool, firstUse bool, err error) {
	k.mu.Lock()
	defer k.mu.Unlock()

	pubHex := hex.EncodeToString(pubKey)
	expectedID := DeriveIDFromPubKey(pubKey)
	if expectedID != hostID {
		return false, false, fmt.Errorf("cryptographic ID mismatch: expected %s, got %s", expectedID, hostID)
	}

	cachedPub, exists := k.hosts[hostID]
	if !exists {
		// Trust On First Use
		k.hosts[hostID] = pubHex
		_ = k.saveLocked()
		return true, true, nil
	}

	if cachedPub != pubHex {
		return false, false, fmt.Errorf("WARNING: Host identity key changed for %s! Possible Man-In-The-Middle attack", hostID)
	}

	return true, false, nil
}

func (k *TOFUKnownHosts) saveLocked() error {
	_ = os.MkdirAll(filepath.Dir(k.path), 0700)
	var sb strings.Builder
	sb.WriteString("# Rakhssh known_hosts (TOFU cache)\n")
	for hid, pub := range k.hosts {
		sb.WriteString(fmt.Sprintf("%s %s\n", hid, pub))
	}
	return os.WriteFile(k.path, []byte(sb.String()), 0600)
}
