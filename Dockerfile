FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /rssh-server ./cmd/rssh-server

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /rssh-server /usr/local/bin/rssh-server
EXPOSE 8443
ENTRYPOINT ["/usr/local/bin/rssh-server"]
CMD ["--addr", ":8443"]
