// Copyright (C) 2026 Rakhssh Contributors - AGPLv3
package id

import (
	"crypto/ed25519"
	"crypto/rand"
	"path/filepath"
	"testing"
)

func TestEd25519IdentityAndDerivation(t *testing.T) {
	tmpDir := t.TempDir()
	keyPath := filepath.Join(tmpDir, "test_identity.key")

	id1, err := LoadOrCreateIdentity(keyPath)
	if err != nil {
		t.Fatalf("LoadOrCreateIdentity failed: %v", err)
	}

	if !ValidateID(id1.ID) {
		t.Fatalf("derived ID is invalid: %s", id1.ID)
	}

	// Loading again must return exact same key and ID
	id2, err := LoadOrCreateIdentity(keyPath)
	if err != nil {
		t.Fatalf("reload identity failed: %v", err)
	}

	if id1.ID != id2.ID {
		t.Fatalf("ID changed on reload: %s != %s", id1.ID, id2.ID)
	}
}

func TestTOFUKnownHosts(t *testing.T) {
	tmpDir := t.TempDir()
	khPath := filepath.Join(tmpDir, "test_known_hosts")

	kh := NewTOFUKnownHosts(khPath)

	pub1, _, _ := ed25519.GenerateKey(rand.Reader)
	hostID1 := DeriveIDFromPubKey(pub1)

	// First use -> trusted + firstUse = true
	trusted, firstUse, err := kh.VerifyOrTrust(hostID1, pub1)
	if err != nil || !trusted || !firstUse {
		t.Fatalf("expected TOFU trust on first use, got: trusted=%v, firstUse=%v, err=%v", trusted, firstUse, err)
	}

	// Subsequent use with same key -> trusted = true, firstUse = false
	trusted, firstUse, err = kh.VerifyOrTrust(hostID1, pub1)
	if err != nil || !trusted || firstUse {
		t.Fatalf("expected cached trust, got: trusted=%v, firstUse=%v, err=%v", trusted, firstUse, err)
	}

	// Same host ID but different pubkey -> should fail with MITM warning
	pub2, _, _ := ed25519.GenerateKey(rand.Reader)
	trusted, _, err = kh.VerifyOrTrust(hostID1, pub2)
	if trusted || err == nil {
		t.Fatal("expected error on key change / MITM attempt")
	}
}
