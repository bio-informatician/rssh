.PHONY: all build test clean docker-build run install-service

BINARY_NAME := rssh-server
BUILD_DIR := bin

all: test build

build:
	@mkdir -p $(BUILD_DIR)
	go build -ldflags="-s -w" -o $(BUILD_DIR)/$(BINARY_NAME) ./cmd/rssh-server

test:
	go test -v -race -count=1 ./...

run: build
	./$(BUILD_DIR)/$(BINARY_NAME) --addr :8443

docker-build:
	docker build -t rssh-server:latest .

install-service: build
	@echo "Installing rssh-server to /usr/local/bin..."
	sudo cp $(BUILD_DIR)/$(BINARY_NAME) /usr/local/bin/
	sudo id -u rssh &>/dev/null || sudo useradd --system --no-create-home --shell /bin/false rssh
	sudo cp systemd/rssh-server.service /etc/systemd/system/
	sudo systemctl daemon-reload
	sudo systemctl enable --now rssh-server
	@echo "Service installed and started. Check status: sudo systemctl status rssh-server"

clean:
	rm -rf $(BUILD_DIR)
