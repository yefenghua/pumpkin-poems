package auth

import (
	"strings"
	"testing"
	"time"
)

func TestNormalizeAccountID(t *testing.T) {
	good := map[string]string{" Mama.Lee ": "mama.lee", "a_b-c9": "a_b-c9", "1234": "1234", strings.Repeat("x", 32): strings.Repeat("x", 32)}
	for in, want := range good {
		if got, err := NormalizeAccountID(in); err != nil || got != want {
			t.Errorf("NormalizeAccountID(%q) = %q, %v; want %q", in, got, err, want)
		}
	}
	for _, in := range []string{"", "abc", ".abc", "-abcd", "ab cd", "媽媽1234", "a@b.com", strings.Repeat("x", 33)} {
		if _, err := NormalizeAccountID(in); err == nil {
			t.Errorf("NormalizeAccountID(%q) accepted", in)
		}
	}
}

func TestValidatePassword(t *testing.T) {
	if err := ValidatePassword("correct horse", "mama"); err != nil {
		t.Fatal(err)
	}
	if err := ValidatePassword("秋夜月光照窗前", "mama"); err == nil { // 7 runes but 21 bytes
		t.Fatal("rune count, not byte count, must be used")
	}
	if err := ValidatePassword("秋夜月光照窗前明", "mama"); err != nil { // 8 runes
		t.Fatal(err)
	}
	for _, p := range []string{"", "short7!", strings.Repeat("p", 129), "MamaLee1", "\xff\xfe12345678"} {
		if err := ValidatePassword(p, "mamalee1"); err == nil {
			t.Errorf("ValidatePassword(%q) accepted", p)
		}
	}
}

func TestHashAndVerify(t *testing.T) {
	h1, h2 := HashPassword("secret-pw"), HashPassword("secret-pw")
	if h1 == h2 {
		t.Fatal("hashes must use random salts")
	}
	if !strings.HasPrefix(h1, "$argon2id$v=19$m=19456,t=2,p=1$") {
		t.Fatalf("hash format: %s", h1)
	}
	if !VerifyPassword(h1, "secret-pw") || !VerifyPassword(h2, "secret-pw") {
		t.Fatal("correct password rejected")
	}
	if VerifyPassword(h1, "secret-pX") || VerifyPassword(h1, "") {
		t.Fatal("wrong password accepted")
	}
	for _, bad := range []string{"", "plain", "$argon2i$v=19$m=1,t=1,p=1$AAAA$AAAA", "$argon2id$v=19$m=0,t=2,p=1$AAAA$AAAA",
		"$argon2id$v=19$m=19456,t=2,p=1$!!$AAAA", "$argon2id$v=19$m=19456,t=2,p=1$AAAA$"} {
		if VerifyPassword(bad, "secret-pw") {
			t.Errorf("malformed hash %q verified", bad)
		}
	}
	if !VerifyPassword(DummyHash, "not-a-real-password") {
		t.Fatal("dummy hash broken")
	}
}

func TestLoginLimiter(t *testing.T) {
	now := time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC)
	l := NewLoginLimiter()
	l.MaxFailures, l.Window = 3, time.Minute
	l.Now = func() time.Time { return now }

	for i := 0; i < 3; i++ {
		if ok, _ := l.Allow("mama"); !ok {
			t.Fatalf("attempt %d refused", i)
		}
		l.Fail("mama")
		now = now.Add(10 * time.Second)
	}
	ok, wait := l.Allow("mama")
	if ok || wait != 30*time.Second {
		t.Fatalf("after 3 failures: allow=%v wait=%v", ok, wait)
	}
	if ok, _ := l.Allow("papa"); !ok {
		t.Fatal("other account affected")
	}
	now = now.Add(31 * time.Second) // oldest failure leaves the window
	if ok, _ := l.Allow("mama"); !ok {
		t.Fatal("window did not slide")
	}
	l.Fail("mama")
	if ok, _ := l.Allow("mama"); ok {
		t.Fatal("should be locked again")
	}
	l.Reset("mama")
	if ok, _ := l.Allow("mama"); !ok {
		t.Fatal("reset did not clear failures")
	}
	now = now.Add(2 * time.Minute)
	l.Allow("zzz") // triggers gc
	if len(l.failures) != 0 {
		t.Fatalf("gc left %d entries", len(l.failures))
	}
}
