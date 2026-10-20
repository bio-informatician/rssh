// Copyright (C) 2026 Rakhssh Contributors - AGPLv3
package sshserver

import (
	"bytes"
	"io"
	"net"
	"strings"
	"testing"
	"time"

	"github.com/pkg/sftp"
	gossh "golang.org/x/crypto/ssh"
)

func TestEmbeddedSSHServer(t *testing.T) {
	srv, err := NewServer()
	if err != nil {
		t.Fatalf("failed to create embedded ssh server: %v", err)
	}
	defer srv.Close()

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("failed to listen on loopback: %v", err)
	}
	defer ln.Close()

	clientPipeCh := make(chan net.Conn, 1)
	go func() {
		c, err := net.Dial("tcp", ln.Addr().String())
		if err == nil {
			clientPipeCh <- c
		}
	}()

	hostPipe, err := ln.Accept()
	if err != nil {
		t.Fatalf("failed to accept on loopback: %v", err)
	}
	defer hostPipe.Close()

	clientPipe := <-clientPipeCh
	defer clientPipe.Close()

	if err := srv.PushStream(hostPipe); err != nil {
		t.Fatalf("PushStream failed: %v", err)
	}

	// Connect SSH client over the pipe
	sshConfig := &gossh.ClientConfig{
		User:            "user",
		Auth:            []gossh.AuthMethod{gossh.Password("anything")},
		HostKeyCallback: gossh.InsecureIgnoreHostKey(),
		Timeout:         3 * time.Second,
	}

	cConn, chans, reqs, err := gossh.NewClientConn(clientPipe, "127.0.0.1:2222", sshConfig)
	if err != nil {
		t.Fatalf("NewClientConn failed: %v", err)
	}
	defer cConn.Close()

	client := gossh.NewClient(cConn, chans, reqs)
	defer client.Close()

	// 1. Test Command Execution (exec)
	session, err := client.NewSession()
	if err != nil {
		t.Fatalf("NewSession failed: %v", err)
	}
	defer session.Close()

	out, err := session.CombinedOutput("echo RSSH_SSH_EXEC_TEST")
	if err != nil {
		t.Fatalf("exec failed: %v, out: %s", err, out)
	}
	if !strings.Contains(string(out), "RSSH_SSH_EXEC_TEST") {
		t.Fatalf("expected output 'RSSH_SSH_EXEC_TEST', got '%s'", out)
	}

	// 2. Test SFTP Subsystem
	sftpClient, err := sftp.NewClient(client)
	if err != nil {
		t.Fatalf("SFTP client init failed: %v", err)
	}
	defer sftpClient.Close()

	cwd, err := sftpClient.Getwd()
	if err != nil {
		t.Fatalf("SFTP Getwd failed: %v", err)
	}
	if cwd == "" {
		t.Fatal("empty SFTP working directory")
	}

	// Test writing and reading file via SFTP in memory/scratch
	testFile := "sftp_test_marker.tmp"
	f, err := sftpClient.Create(testFile)
	if err != nil {
		t.Fatalf("SFTP create failed: %v", err)
	}
	testContent := []byte("sftp write test passed")
	_, _ = f.Write(testContent)
	_ = f.Close()
	defer sftpClient.Remove(testFile)

	rf, err := sftpClient.Open(testFile)
	if err != nil {
		t.Fatalf("SFTP Open failed: %v", err)
	}
	readBack, err := io.ReadAll(rf)
	_ = rf.Close()
	if err != nil {
		t.Fatalf("SFTP ReadAll failed: %v", err)
	}
	if !bytes.Equal(readBack, testContent) {
		t.Fatalf("SFTP readback mismatch: expected %s, got %s", testContent, readBack)
	}
}
