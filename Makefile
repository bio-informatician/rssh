.PHONY: all build test clean cross-compile-linux release-linux install uninstall

BINARY_NAME := rssh
BUILD_DIR := bin
DIST_DIR := bin/dist
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "v0.1.0")
LDFLAGS := -s -w -X main.version=$(VERSION)

all: test build

build:
	@mkdir -p $(BUILD_DIR)
	go build -ldflags="$(LDFLAGS)" -o $(BUILD_DIR)/$(BINARY_NAME) ./cmd/rssh

test:
	go test -v -race -count=1 ./...

cross-compile-linux:
	@mkdir -p $(DIST_DIR)
	@echo "Building Linux amd64..."
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="$(LDFLAGS)" -o $(DIST_DIR)/$(BINARY_NAME)-linux-amd64 ./cmd/rssh
	@echo "Building Linux arm64..."
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -ldflags="$(LDFLAGS)" -o $(DIST_DIR)/$(BINARY_NAME)-linux-arm64 ./cmd/rssh

release-linux: test cross-compile-linux
	@echo "Generating SHA-256 checksums..."
	@cd $(DIST_DIR) && sha256sum $(BINARY_NAME)-linux-amd64 $(BINARY_NAME)-linux-arm64 > checksums.txt
	@echo "Release artifacts ready in $(DIST_DIR):"
	@ls -lh $(DIST_DIR)

install: build
	@mkdir -p $(HOME)/.local/bin
	cp $(BUILD_DIR)/$(BINARY_NAME) $(HOME)/.local/bin/
	@echo "Installed $(BINARY_NAME) to $(HOME)/.local/bin/"

uninstall:
	rm -f $(HOME)/.local/bin/$(BINARY_NAME)
	@echo "Removed $(BINARY_NAME) from $(HOME)/.local/bin/"

clean:
	rm -rf $(BUILD_DIR)
