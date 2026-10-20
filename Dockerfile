# Multi-stage production build for rssh-server
FROM golang:1.24-alpine AS builder

WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /build/rssh-server ./cmd/rssh-server

# Hardened minimal runtime image
FROM alpine:3.21

RUN apk --no-cache add ca-certificates tzdata \
    && addgroup -g 10001 -S rssh \
    && adduser -u 10001 -S rssh -G rssh

WORKDIR /home/rssh
COPY --from=builder /build/rssh-server /usr/local/bin/rssh-server

USER rssh:rssh
EXPOSE 8443

ENTRYPOINT ["/usr/local/bin/rssh-server"]
CMD ["--addr", ":8443"]
