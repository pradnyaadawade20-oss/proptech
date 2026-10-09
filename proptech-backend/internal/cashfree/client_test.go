package cashfree

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"testing"
)

func TestVerifyWebhook(t *testing.T) {
	cfg := &Config{SecretKey: "test_secret"}
	body := []byte(`{"type":"PAYMENT_SUCCESS_WEBHOOK","data":{"order":{"order_id":"pt_r_1"}}}`)
	ts := "1746426425612"

	mac := hmac.New(sha256.New, []byte("test_secret"))
	mac.Write([]byte(ts))
	mac.Write(body)
	sig := base64.StdEncoding.EncodeToString(mac.Sum(nil))

	if !cfg.VerifyWebhook(ts, body, sig) {
		t.Fatal("valid signature rejected")
	}
	if cfg.VerifyWebhook(ts, append(body, ' '), sig) {
		t.Fatal("tampered body accepted")
	}
	if cfg.VerifyWebhook("1746426425613", body, sig) {
		t.Fatal("wrong timestamp accepted")
	}
	if cfg.VerifyWebhook(ts, body, "") || cfg.VerifyWebhook("", body, sig) {
		t.Fatal("missing header accepted")
	}
	if (&Config{}).VerifyWebhook(ts, body, sig) {
		t.Fatal("accepted with no secret configured")
	}
}

func TestEncryptRoundTrip(t *testing.T) {
	cfg := ConfigFromEnv("jwt-secret-for-test")
	enc, err := cfg.Encrypt("026291800001191")
	if err != nil {
		t.Fatal(err)
	}
	if enc == "026291800001191" {
		t.Fatal("not encrypted")
	}
	got, err := cfg.Decrypt(enc)
	if err != nil || got != "026291800001191" {
		t.Fatalf("round trip failed: %q %v", got, err)
	}
}

func TestVendorState(t *testing.T) {
	cases := map[string]string{
		"ACTIVE": "active", "BANK_DETAILS_UNDER_VERIFICATION": "pending",
		"VERIFICATION_FAILED": "verification_failed", "INACTIVE": "inactive",
	}
	for in, want := range cases {
		if got := VendorState(in); got != want {
			t.Errorf("VendorState(%q) = %q, want %q", in, got, want)
		}
	}
}