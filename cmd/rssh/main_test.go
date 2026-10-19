package main

import (
	"bytes"
	"strings"
	"testing"
)

func TestRootCmdHelp(t *testing.T) {
	cmd := newRootCmd()
	var out bytes.Buffer
	cmd.SetOut(&out)
	cmd.SetArgs([]string{"--help"})

	err := cmd.Execute()
	if err != nil {
		t.Fatalf("expected no error for --help, got: %v", err)
	}

	helpOutput := out.String()
	expectedSubcommands := []string{
		"host",
		"connect",
		"proxy",
		"forward",
		"daemon",
		"block",
		"unblock",
		"blocked",
		"chat",
	}

	for _, sub := range expectedSubcommands {
		if !strings.Contains(helpOutput, sub) {
			t.Errorf("help output missing subcommand %q", sub)
		}
	}
}

func TestRootCmdFlags(t *testing.T) {
	cmd := newRootCmd()
	flags := []string{"server", "pin", "p2p-timeout", "debug"}
	for _, fl := range flags {
		if cmd.PersistentFlags().Lookup(fl) == nil {
			t.Errorf("missing persistent flag --%s", fl)
		}
	}
}

func TestSubcommandArgValidation(t *testing.T) {
	tests := []struct {
		name    string
		args    []string
		wantErr bool
	}{
		{"connect without arg", []string{"connect"}, true},
		{"proxy without arg", []string{"proxy"}, true},
		{"forward without arg", []string{"forward"}, true},
		{"block without arg", []string{"block"}, true},
		{"unblock without arg", []string{"unblock"}, true},
		{"chat with too many args", []string{"chat", "123-456-789", "extra-arg"}, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cmd := newRootCmd()
			cmd.SetArgs(tt.args)
			var buf bytes.Buffer
			cmd.SetOut(&buf)
			cmd.SetErr(&buf)
			err := cmd.Execute()
			if (err != nil) != tt.wantErr {
				t.Errorf("Execute(%v) error = %v, wantErr %v", tt.args, err, tt.wantErr)
			}
		})
	}
}

func TestSafeID(t *testing.T) {
	if got := safeID("1234567890"); got != "12345678" {
		t.Errorf("safeID(long) = %s, want 12345678", got)
	}
	if got := safeID("abc"); got != "abc" {
		t.Errorf("safeID(short) = %s, want abc", got)
	}
	if got := safeID(""); got != "" {
		t.Errorf("safeID(empty) = %s, want empty", got)
	}
}

func TestSanitizeForTerminal(t *testing.T) {
	input := "hello\x1b[31mworld\a\r\n\t!"
	got := sanitizeForTerminal(input)
	if strings.Contains(got, "\x1b") {
		t.Error("sanitized string must not contain escape bytes")
	}
	if strings.Contains(got, "\a") {
		t.Error("sanitized string must not contain bell byte")
	}
	if !strings.Contains(got, "hello") || !strings.Contains(got, "world") {
		t.Errorf("sanitized text corrupted: %q", got)
	}
}
