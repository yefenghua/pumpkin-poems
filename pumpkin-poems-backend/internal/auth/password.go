// Package auth handles parent credentials (account ID + password) and issues
// opaque access tokens.
package auth

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"
	"unicode/utf8"

	"golang.org/x/crypto/argon2"
)

// Account ID rules: 4–32 characters of a–z, 0–9, '.', '_' or '-', starting
// with a letter or digit. IDs are case-insensitive and stored lower case.
const (
	MinAccountIDLen = 4
	MaxAccountIDLen = 32
	MinPasswordLen  = 8
	MaxPasswordLen  = 128
)

var (
	ErrInvalidAccountID = errors.New("account id must be 4-32 characters: letters, digits, '.', '_' or '-'")
	ErrWeakPassword     = fmt.Errorf("password must be %d-%d characters and differ from the account id", MinPasswordLen, MaxPasswordLen)
)

// NormalizeAccountID trims and lower-cases an account ID and reports whether
// the result is acceptable.
func NormalizeAccountID(raw string) (string, error) {
	id := strings.ToLower(strings.TrimSpace(raw))
	n := len(id)
	if n < MinAccountIDLen || n > MaxAccountIDLen {
		return "", ErrInvalidAccountID
	}
	for i := 0; i < n; i++ {
		c := id[i]
		switch {
		case c >= 'a' && c <= 'z', c >= '0' && c <= '9':
		case (c == '.' || c == '_' || c == '-') && i > 0:
		default:
			return "", ErrInvalidAccountID
		}
	}
	return id, nil
}

// ValidatePassword enforces length only (NIST SP 800-63B: no composition
// rules) and refuses a password equal to the account ID.
func ValidatePassword(password, accountID string) error {
	if !utf8.ValidString(password) {
		return ErrWeakPassword
	}
	n := utf8.RuneCountInString(password)
	if n < MinPasswordLen || n > MaxPasswordLen || strings.EqualFold(password, accountID) {
		return ErrWeakPassword
	}
	return nil
}

// Argon2id parameters (OWASP 2023 recommendation: 19 MiB, 2 iterations, 1 lane).
const (
	argonTime    = 2
	argonMemory  = 19 * 1024
	argonThreads = 1
	argonKeyLen  = 32
	argonSaltLen = 16
)

// HashPassword returns a PHC-formatted Argon2id hash:
// $argon2id$v=19$m=19456,t=2,p=1$<salt>$<hash>. The parameters travel with
// the hash so they can be raised later without invalidating old passwords.
func HashPassword(password string) string {
	var salt [argonSaltLen]byte
	if _, err := rand.Read(salt[:]); err != nil {
		panic(err)
	}
	key := argon2.IDKey([]byte(password), salt[:], argonTime, argonMemory, argonThreads, argonKeyLen)
	enc := base64.RawStdEncoding
	return fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s", argon2.Version, argonMemory, argonTime, argonThreads,
		enc.EncodeToString(salt[:]), enc.EncodeToString(key))
}

// VerifyPassword reports whether password matches the stored PHC hash. A
// malformed hash never matches.
func VerifyPassword(encoded, password string) bool {
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 || parts[0] != "" || parts[1] != "argon2id" {
		return false
	}
	var version int
	if _, err := fmt.Sscanf(parts[2], "v=%d", &version); err != nil || version != argon2.Version {
		return false
	}
	var mem, iter uint32
	var par uint8
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &mem, &iter, &par); err != nil || mem == 0 || iter == 0 || par == 0 {
		return false
	}
	enc := base64.RawStdEncoding
	salt, err := enc.DecodeString(parts[4])
	if err != nil {
		return false
	}
	want, err := enc.DecodeString(parts[5])
	if err != nil || len(want) == 0 {
		return false
	}
	got := argon2.IDKey([]byte(password), salt, iter, mem, par, uint32(len(want)))
	return subtle.ConstantTimeCompare(got, want) == 1
}

// DummyHash is verified against when the account does not exist, so a login
// attempt takes the same time whether or not the account ID is taken.
var DummyHash = HashPassword("not-a-real-password")
