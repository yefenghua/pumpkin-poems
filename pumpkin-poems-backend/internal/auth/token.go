package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"time"
)

// TokenTTL is the lifetime of an access token.
const TokenTTL = 30 * 24 * time.Hour

// NewAccessToken returns a random opaque bearer token and the SHA-256 hash
// that is stored server side. The raw token is never persisted.
func NewAccessToken() (token string, hash []byte) {
	var b [32]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic(err)
	}
	token = base64.RawURLEncoding.EncodeToString(b[:])
	return token, HashToken(token)
}

func HashToken(token string) []byte {
	h := sha256.Sum256([]byte(token))
	return h[:]
}
