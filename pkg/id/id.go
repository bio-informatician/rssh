// Copyright (C) 2026 Rakhssh Contributors - AGPLv3
package id

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"fmt"
	"math/big"
	"net"
	"os"
	"regexp"
	"strings"
)

var idRegex = regexp.MustCompile(`^\d{3}-\d{3}-\d{3}$`)

// FormatID formats a 9-digit string into XXX-XXX-XXX
func FormatID(raw string) string {
	digits := ""
	for _, r := range raw {
		if r >= '0' && r <= '9' {
			digits += string(r)
		}
	}
	if len(digits) != 9 {
		return raw
	}
	return fmt.Sprintf("%s-%s-%s", digits[0:3], digits[3:6], digits[6:9])
}

// CleanID strips hyphens and spaces to leave only digits
func CleanID(formatted string) string {
	digits := ""
	for _, r := range formatted {
		if r >= '0' && r <= '9' {
			digits += string(r)
		}
	}
	return digits
}

// ValidateID checks if the given ID conforms to 9 digits (formatted or unformatted)
func ValidateID(idStr string) bool {
	clean := CleanID(idStr)
	return len(clean) == 9
}

// GenerateRandomID creates a secure 9-digit ID formatted as XXX-XXX-XXX
func GenerateRandomID() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1000000000))
	if err != nil {
		return "", fmt.Errorf("failed to generate random id: %w", err)
	}
	return fmt.Sprintf("%03d-%03d-%03d", n.Int64()/1000000, (n.Int64()/1000)%1000, n.Int64()%1000), nil
}

// GeneratePersistentID generates a deterministic 9-digit ID based on hardware/environment
func GeneratePersistentID() string {
	h := sha256.New()

	// Try reading /etc/machine-id
	if machineID, err := os.ReadFile("/etc/machine-id"); err == nil {
		h.Write(machineID)
	}

	// Read hostname
	if hostname, err := os.Hostname(); err == nil {
		h.Write([]byte(hostname))
	}

	// Read first non-loopback MAC address
	if ifaces, err := net.Interfaces(); err == nil {
		for _, iface := range ifaces {
			if iface.Flags&net.FlagLoopback == 0 && len(iface.HardwareAddr) > 0 {
				h.Write(iface.HardwareAddr)
				break
			}
		}
	}

	sum := h.Sum(nil)
	val := binary.BigEndian.Uint64(sum[:8]) % 1000000000
	return fmt.Sprintf("%03d-%03d-%03d", val/1000000, (val/1000)%1000, val%1000)
}

// GeneratePIN creates a cryptographically secure random numeric PIN of specified length (default 4 digits)
func GeneratePIN(digits int) (string, error) {
	if digits < 4 {
		digits = 4
	}
	if digits > 8 {
		digits = 8
	}

	limit := int64(1)
	for i := 0; i < digits; i++ {
		limit *= 10
	}

	n, err := rand.Int(rand.Reader, big.NewInt(limit))
	if err != nil {
		return "", fmt.Errorf("failed to generate random pin: %w", err)
	}

	format := fmt.Sprintf("%%0%dd", digits)
	return fmt.Sprintf(format, n.Int64()), nil
}

// NormalizeID returns a standardized XXX-XXX-XXX format
func NormalizeID(input string) (string, error) {
	cleaned := CleanID(strings.TrimSpace(input))
	if len(cleaned) != 9 {
		return "", fmt.Errorf("invalid ID: must be exactly 9 digits, got %d", len(cleaned))
	}
	return FormatID(cleaned), nil
}
