// Copyright (C) 2026 Rakhssh Contributors - AGPLv3
package id

import (
	"strings"
	"testing"
)

func TestFormatAndCleanID(t *testing.T) {
	raw := "123456789"
	formatted := FormatID(raw)
	if formatted != "123-456-789" {
		t.Fatalf("expected 123-456-789, got %s", formatted)
	}

	cleaned := CleanID(formatted)
	if cleaned != raw {
		t.Fatalf("expected %s, got %s", raw, cleaned)
	}
}

func TestValidateID(t *testing.T) {
	cases := []struct {
		input string
		valid bool
	}{
		{"123-456-789", true},
		{"123456789", true},
		{"123-45-6789", true},
		{"123", false},
		{"1234567890", false},
		{"abc-def-ghi", false},
	}

	for _, c := range cases {
		if ValidateID(c.input) != c.valid {
			t.Errorf("ValidateID(%s) expected %v, got %v", c.input, c.valid, ValidateID(c.input))
		}
	}
}

func TestGenerateRandomID(t *testing.T) {
	idStr, err := GenerateRandomID()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !ValidateID(idStr) {
		t.Fatalf("generated ID invalid: %s", idStr)
	}
	parts := strings.Split(idStr, "-")
	if len(parts) != 3 || len(parts[0]) != 3 || len(parts[1]) != 3 || len(parts[2]) != 3 {
		t.Fatalf("improperly formatted ID: %s", idStr)
	}
}

func TestGeneratePersistentID(t *testing.T) {
	id1 := GeneratePersistentID()
	id2 := GeneratePersistentID()
	if id1 != id2 {
		t.Fatalf("persistent ID changed between calls: %s != %s", id1, id2)
	}
	if !ValidateID(id1) {
		t.Fatalf("persistent ID invalid: %s", id1)
	}
}

func TestGeneratePIN(t *testing.T) {
	pin4, err := GeneratePIN(4)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(pin4) != 4 {
		t.Fatalf("expected 4-digit PIN, got %s", pin4)
	}

	pin6, err := GeneratePIN(6)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(pin6) != 6 {
		t.Fatalf("expected 6-digit PIN, got %s", pin6)
	}
}

func TestNormalizeID(t *testing.T) {
	norm, err := NormalizeID(" 482910334 ")
	if err != nil {
		t.Fatalf("failed to normalize: %v", err)
	}
	if norm != "482-910-334" {
		t.Fatalf("unexpected norm: %s", norm)
	}

	_, err = NormalizeID("123")
	if err == nil {
		t.Fatal("expected error on short ID")
	}
}
