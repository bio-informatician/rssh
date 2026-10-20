// Copyright (C) 2026 Rakhssh Contributors - AGPLv3
package crypto

import (
	"crypto/elliptic"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"

	"golang.org/x/crypto/hkdf"
)

// NIST P-256 curve parameters and verifiably generated blinding generators M and N.
var (
	p256Curve = elliptic.P256()

	// M and N points derived via nothing-up-my-sleeve SHA-256 hash-to-curve seeds.
	mPointX, _ = new(big.Int).SetString("272cfa2098dad3348ba30fe77960bcfb3015c69ba4d2b6812ddb1d0108689255", 16)
	mPointY, _ = new(big.Int).SetString("3886e555b7f54009718e4e2f1c93cda0317bc8f21445e618e15e9b3d98b1932d", 16)
	nPointX, _ = new(big.Int).SetString("4beb92420ff8c27a74c89ead35fd6ed3fe4fd565e214d32fcf430f483aa278c5", 16)
	nPointY, _ = new(big.Int).SetString("b768812270ad4db8910df150f374a9a5ba2c47d459eb3cfd9e51a205fffbaff8", 16)
)

// PAKEHost manages the host side of a 100% novel SPAKE2 exchange on NIST P-256
type PAKEHost struct {
	privHost *big.Int
	pin      string
}

// SessionKeys contains directional keys and verification tokens
type SessionKeys struct {
	HostToClientKey []byte
	ClientToHostKey []byte
	VerificationKey []byte
}

// PAKEMsg represents the wire frame exchanged during PAKE
type PAKEMsg struct {
	Point []byte `json:"point"`
}

// DeriveKeys derives directional AEAD keys and an auth token from the shared PAKE key
func DeriveKeys(sharedKey []byte) (*SessionKeys, error) {
	if len(sharedKey) == 0 {
		return nil, errors.New("empty shared key")
	}

	h2c := make([]byte, 32)
	c2h := make([]byte, 32)
	vfy := make([]byte, 32)

	// Derive Host -> Client key
	h2cReader := hkdf.New(sha256.New, sharedKey, nil, []byte("rssh_host_to_client_v1"))
	if _, err := io.ReadFull(h2cReader, h2c); err != nil {
		return nil, fmt.Errorf("failed to derive h2c key: %w", err)
	}

	// Derive Client -> Host key
	c2hReader := hkdf.New(sha256.New, sharedKey, nil, []byte("rssh_client_to_host_v1"))
	if _, err := io.ReadFull(c2hReader, c2h); err != nil {
		return nil, fmt.Errorf("failed to derive c2h key: %w", err)
	}

	// Derive Verification key
	vfyReader := hkdf.New(sha256.New, sharedKey, nil, []byte("rssh_verification_v1"))
	if _, err := io.ReadFull(vfyReader, vfy); err != nil {
		return nil, fmt.Errorf("failed to derive verification key: %w", err)
	}

	return &SessionKeys{
		HostToClientKey: h2c,
		ClientToHostKey: c2h,
		VerificationKey: vfy,
	}, nil
}

// ComputeAuthTag creates an HMAC authentication tag using the verification key
func ComputeAuthTag(verificationKey []byte, message []byte) []byte {
	mac := hmac.New(sha256.New, verificationKey)
	mac.Write(message)
	return mac.Sum(nil)
}

// VerifyAuthTag validates an HMAC authentication tag
func VerifyAuthTag(verificationKey []byte, message []byte, expectedTag []byte) bool {
	actual := ComputeAuthTag(verificationKey, message)
	return hmac.Equal(actual, expectedTag)
}

func derivePinScalar(pin string) []byte {
	params := p256Curve.Params()
	r := hkdf.New(sha256.New, []byte(pin), nil, []byte("rssh-spake2-pin-scalar-v1"))
	buf := make([]byte, 32)
	_, _ = io.ReadFull(r, buf)
	w := new(big.Int).SetBytes(buf)
	w.Mod(w, params.N)
	if w.Sign() == 0 {
		w.SetInt64(1)
	}
	return w.Bytes()
}

func negPoint(x, y *big.Int) (*big.Int, *big.Int) {
	negY := new(big.Int).Sub(p256Curve.Params().P, y)
	negY.Mod(negY, p256Curve.Params().P)
	return x, negY
}

// validatePAKEMsg validates and parses an incoming PAKE curve point.
func validatePAKEMsg(msg []byte) (*big.Int, *big.Int, error) {
	if len(msg) == 0 {
		return nil, nil, errors.New("empty PAKE message")
	}
	var m PAKEMsg
	if err := json.Unmarshal(msg, &m); err != nil {
		return nil, nil, fmt.Errorf("PAKE message is not valid JSON: %w", err)
	}
	if len(m.Point) == 0 {
		return nil, nil, errors.New("missing PAKE curve point")
	}
	x, y := elliptic.Unmarshal(p256Curve, m.Point)
	if x == nil || y == nil || !p256Curve.IsOnCurve(x, y) {
		return nil, nil, errors.New("invalid or off-curve PAKE point")
	}
	return x, y, nil
}

// StartHostPAKE initializes the Host PAKE exchange and returns the blinded point message for the client
func StartHostPAKE(pin string) (*PAKEHost, []byte, error) {
	params := p256Curve.Params()
	priv, err := rand.Int(rand.Reader, params.N)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to generate host secret scalar: %w", err)
	}
	if priv.Sign() == 0 {
		priv.SetInt64(1)
	}

	wBytes := derivePinScalar(pin)

	// x*G
	xGx, xGy := p256Curve.ScalarBaseMult(priv.Bytes())
	// w*M
	wMx, wMy := p256Curve.ScalarMult(mPointX, mPointY, wBytes)
	// X = x*G + w*M
	Xx, Xy := p256Curve.Add(xGx, xGy, wMx, wMy)

	payload, err := json.Marshal(PAKEMsg{
		Point: elliptic.Marshal(p256Curve, Xx, Xy),
	})
	if err != nil {
		return nil, nil, fmt.Errorf("failed to marshal host PAKE message: %w", err)
	}

	return &PAKEHost{
		privHost: priv,
		pin:      pin,
	}, payload, nil
}

// RespondClientPAKE computes the client response point and derives session keys.
func RespondClientPAKE(pin string, hostMsg []byte) (clientMsg []byte, keys *SessionKeys, err error) {
	Xx, Xy, err := validatePAKEMsg(hostMsg)
	if err != nil {
		return nil, nil, fmt.Errorf("invalid host PAKE message: %w", err)
	}

	params := p256Curve.Params()
	priv, err := rand.Int(rand.Reader, params.N)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to generate client secret scalar: %w", err)
	}
	if priv.Sign() == 0 {
		priv.SetInt64(1)
	}

	wBytes := derivePinScalar(pin)

	// y*G
	yGx, yGy := p256Curve.ScalarBaseMult(priv.Bytes())
	// w*N
	wNx, wNy := p256Curve.ScalarMult(nPointX, nPointY, wBytes)
	// Y = y*G + w*N
	Yx, Yy := p256Curve.Add(yGx, yGy, wNx, wNy)

	// De-blind X: X - w*M = x*G
	wMx, wMy := p256Curve.ScalarMult(mPointX, mPointY, wBytes)
	negWMx, negWMy := negPoint(wMx, wMy)
	deblindXx, deblindXy := p256Curve.Add(Xx, Xy, negWMx, negWMy)

	// Shared secret point: y * (X - w*M) = y * x * G
	Kx, Ky := p256Curve.ScalarMult(deblindXx, deblindXy, priv.Bytes())
	sharedPoint := elliptic.Marshal(p256Curve, Kx, Ky)
	sharedSecret := sha256.Sum256(sharedPoint)

	keys, err = DeriveKeys(sharedSecret[:])
	if err != nil {
		return nil, nil, err
	}

	clientMsg, err = json.Marshal(PAKEMsg{
		Point: elliptic.Marshal(p256Curve, Yx, Yy),
	})
	if err != nil {
		return nil, nil, fmt.Errorf("failed to marshal client PAKE message: %w", err)
	}

	return clientMsg, keys, nil
}

// FinishHostPAKE finishes the host PAKE exchange with the client response and derives session keys.
func (h *PAKEHost) FinishHostPAKE(clientMsg []byte) (*SessionKeys, error) {
	Yx, Yy, err := validatePAKEMsg(clientMsg)
	if err != nil {
		return nil, fmt.Errorf("invalid client PAKE message: %w", err)
	}

	wBytes := derivePinScalar(h.pin)

	// De-blind Y: Y - w*N = y*G
	wNx, wNy := p256Curve.ScalarMult(nPointX, nPointY, wBytes)
	negWNx, negWNy := negPoint(wNx, wNy)
	deblindYx, deblindYy := p256Curve.Add(Yx, Yy, negWNx, negWNy)

	// Shared secret point: x * (Y - w*N) = x * y * G
	Kx, Ky := p256Curve.ScalarMult(deblindYx, deblindYy, h.privHost.Bytes())
	sharedPoint := elliptic.Marshal(p256Curve, Kx, Ky)
	sharedSecret := sha256.Sum256(sharedPoint)

	return DeriveKeys(sharedSecret[:])
}

// ConfirmationNonceLen is the length of the per-session key-confirmation nonce.
const ConfirmationNonceLen = 16

// BuildConfirmationTag generates the HMAC key-confirmation tag that proves both peers
// derived the same session key from the same PIN.
// The tag is: HMAC-SHA256(verificationKey, "rssh-confirm" || direction || nonce)
// direction must be either "host" or "client".
func BuildConfirmationTag(verificationKey []byte, direction string, nonce []byte) []byte {
	mac := hmac.New(sha256.New, verificationKey)
	mac.Write([]byte("rssh-confirm"))
	mac.Write([]byte(direction))
	mac.Write(nonce)
	return mac.Sum(nil)
}

// GenerateConfirmationNonce returns a fresh random nonce for key confirmation.
func GenerateConfirmationNonce() ([]byte, error) {
	b := make([]byte, ConfirmationNonceLen)
	if _, err := rand.Read(b); err != nil {
		return nil, err
	}
	return b, nil
}
