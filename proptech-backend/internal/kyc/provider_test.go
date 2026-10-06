package kyc

import "testing"

func TestNormalizeAadhaar(t *testing.T) {
	// 2363 is the textbook Verhoeff example; 234567890124 is a checksum-valid 12-digit number.
	if !verhoeffValid("2363") || verhoeffValid("2364") {
		t.Fatal("verhoeff tables are wrong")
	}
	if s, ok := NormalizeAadhaar("2345 6789 0124", true); !ok || s != "234567890124" {
		t.Fatalf("valid number rejected: %q %v", s, ok)
	}
	if _, ok := NormalizeAadhaar("2345 6789 0125", true); ok {
		t.Fatal("bad checksum accepted")
	}
	if _, ok := NormalizeAadhaar("1234 5678 9012", false); !ok {
		t.Fatal("mock mode should accept any 12 digits")
	}
	if _, ok := NormalizeAadhaar("12345", false); ok {
		t.Fatal("short number accepted")
	}
	if _, ok := NormalizeAadhaar("2345 6789 01ab", false); ok {
		t.Fatal("letters accepted")
	}
}