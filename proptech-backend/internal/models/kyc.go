package models

import "time"

const (
	KYCNotStarted = "not_started"
	KYCPending    = "pending"
	KYCVerified   = "verified"
	KYCRejected   = "rejected"
)

// KYC is what the API returns. The full Aadhaar number is never in here.
type KYC struct {
	Status        string     `json:"status"` // not_started | pending | verified | rejected
	MaskedAadhaar string     `json:"masked_aadhaar,omitempty"`
	VerifiedAt    *time.Time `json:"verified_at,omitempty"`

	OTPSentAt *time.Time `json:"-"`
}

type KYCSendOTPRequest struct {
	Aadhaar string `json:"aadhaar" binding:"required"`
	Consent bool   `json:"consent"`
}

type KYCVerifyOTPRequest struct {
	OTP string `json:"otp" binding:"required,len=6"`
}