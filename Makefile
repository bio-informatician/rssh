.PHONY: all build test clean cross-compile

BINARY_NAME=rssh
SERVER_NAME=rssh-server
BUILD_DIR=bin

all: build

build:
	@mkdir -p $(BUILD_DIR)
	go build -o $(BUILD_DIR)/$(BINARY_NAME) ./cmd/rssh
	go build -o $(BUILD_DIR)/$(SERVER_NAME) ./cmd/rssh-server

test:
	go test -v -count=1 ./...

cross-compile:
	@mkdir -p $(BUILD_DIR)/dist
	# Linux amd64
	GOOS=linux GOARCH=amd64 go build -o $(BUILD_DIR)/dist/$(BINARY_NAME)-linux-amd64 ./cmd/rssh
	GOOS=linux GOARCH=amd64 go build -o $(BUILD_DIR)/dist/$(SERVER_NAME)-linux-amd64 ./cmd/rssh-server
	# Linux arm64
	GOOS=linux GOARCH=arm64 go build -o $(BUILD_DIR)/dist/$(BINARY_NAME)-linux-arm64 ./cmd/rssh
	GOOS=linux GOARCH=arm64 go build -o $(BUILD_DIR)/dist/$(SERVER_NAME)-linux-arm64 ./cmd/rssh-server
	# macOS amd64
	GOOS=darwin GOARCH=amd64 go build -o $(BUILD_DIR)/dist/$(BINARY_NAME)-darwin-amd64 ./cmd/rssh
	# macOS arm64 (Apple Silicon)
	GOOS=darwin GOARCH=arm64 go build -o $(BUILD_DIR)/dist/$(BINARY_NAME)-darwin-arm64 ./cmd/rssh
	# Windows amd64
	GOOS=windows GOARCH=amd64 go build -o $(BUILD_DIR)/dist/$(BINARY_NAME)-windows-amd64.exe ./cmd/rssh

clean:
	rm -rf $(BUILD_DIR)
