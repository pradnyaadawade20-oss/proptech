
// Package kyc holds the Aadhaar-KYC provider abstraction used by the KYC
// endpoints. Real UIDAI access needs a licensed AUA/KUA, so in practice this is
// a partner API (Digio, Signzy, Setu, DigiLocker, ...). Implement Provider for
// the partner you pick and register it in FromEnv; nothing else changes.
package kyc

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"strings"
)

// ErrInvalidOTP is returned by Provider.VerifyOTP for a wrong/expired code.
var ErrInvalidOTP = errors.New("invalid OTP")

type Provider interface {
	Name() string
	// SendOTP asks the provider to send an OTP to the phone linked with the
	// Aadhaar and returns the provider's transaction/reference id.
	SendOTP(ctx context.Context, aadhaar string) (refID string, err error)
	// VerifyOTP checks the code for a transaction. Wrong code -> ErrInvalidOTP.
	VerifyOTP(ctx context.Context, refID, otp string) error
}

// MockProvider is for development/testing only: no OTP is sent and the code
// is always 123456. FromEnv refuses to build it when APP_ENV=production.
type MockProvider struct{}

const mockOTP = "123456"

func (MockProvider) Name() string { return "mock" }

func (MockProvider) SendOTP(_ context.Context, _ string) (string, error) {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return "mock-" + hex.EncodeToString(b), nil
}

func (MockProvider) VerifyOTP(_ context.Context, _, otp string) error {
	if otp != mockOTP {
		return ErrInvalidOTP
	}
	return nil
}

// Hasher makes the keyed hash stored in user_kyc.aadhaar_hash.
type Hasher struct{ key []byte }

func (h Hasher) Hash(aadhaar string) string {
	m := hmac.New(sha256.New, h.key)
	m.Write([]byte(aadhaar))
	return hex.EncodeToString(m.Sum(nil))
}

// FromEnv builds the provider + hasher from environment variables:
//
//	KYC_PROVIDER     "mock" (default outside production). Add real names in the switch below.
//	KYC_HASH_SECRET  secret key for the Aadhaar hash; REQUIRED in production.
func FromEnv(appEnv string) (Provider, Hasher, error) {
	prod := appEnv == "production"

	secret := strings.TrimSpace(os.Getenv("KYC_HASH_SECRET"))
	if secret == "" {
		if prod {
			return nil, Hasher{}, errors.New("KYC_HASH_SECRET must be set when APP_ENV=production")
		}
		secret = "dev-only-kyc-hash-secret"
	}

	name := strings.ToLower(strings.TrimSpace(os.Getenv("KYC_PROVIDER")))
	switch name {
	case "", "mock":
		if prod {
			return nil, Hasher{}, errors.New("KYC_PROVIDER=mock is not allowed when APP_ENV=production")
		}
		return MockProvider{}, Hasher{key: []byte(secret)}, nil
	default:
		return nil, Hasher{}, fmt.Errorf("unknown KYC_PROVIDER %q (implement kyc.Provider and add it to FromEnv)", name)
	}
}

// NormalizeAadhaar strips spaces/hyphens and checks the shape of the number.
// strict=true also enforces the Verhoeff checksum every real Aadhaar carries
// (kept off for the mock provider so any 12 digits work in dev).
func NormalizeAadhaar(raw string, strict bool) (string, bool) {
	var b strings.Builder
	for _, r := range raw {
		switch {
		case r >= '0' && r <= '9':
			b.WriteRune(r)
		case r == ' ' || r == '-':
		default:
			return "", false
		}
	}
	s := b.String()
	if len(s) != 12 {
		return "", false
	}
	if strict && (s[0] < '2' || !verhoeffValid(s)) {
		return "", false
	}
	return s, true
}

var verhoeffD = [10][10]int{
	{0, 1, 2, 3, 4, 5, 6, 7, 8, 9},
	{1, 2, 3, 4, 0, 6, 7, 8, 9, 5},
	{2, 3, 4, 0, 1, 7, 8, 9, 5, 6},
	{3, 4, 0, 1, 2, 8, 9, 5, 6, 7},
	{4, 0, 1, 2, 3, 9, 5, 6, 7, 8},
	{5, 9, 8, 7, 6, 0, 4, 3, 2, 1},
	{6, 5, 9, 8, 7, 1, 0, 4, 3, 2},
	{7, 6, 5, 9, 8, 2, 1, 0, 4, 3},
	{8, 7, 6, 5, 9, 3, 2, 1, 0, 4},
	{9, 8, 7, 6, 5, 4, 3, 2, 1, 0},
}

var verhoeffP = [8][10]int{
	{0, 1, 2, 3, 4, 5, 6, 7, 8, 9},
	{1, 5, 7, 6, 2, 8, 3, 0, 9, 4},
	{5, 8, 0, 3, 7, 9, 6, 1, 4, 2},
	{8, 9, 1, 6, 0, 4, 3, 5, 2, 7},
	{9, 4, 5, 3, 1, 2, 6, 8, 7, 0},
	{4, 2, 8, 6, 5, 7, 3, 9, 0, 1},
	{2, 7, 9, 3, 8, 0, 6, 4, 1, 5},
	{7, 0, 4, 6, 9, 1, 3, 2, 5, 8},
}

func verhoeffValid(digits string) bool {
	c := 0
	n := len(digits)
	for i := 0; i < n; i++ {
		c = verhoeffD[c][verhoeffP[i%8][int(digits[n-1-i]-'0')]]
	}
	return c == 0
}