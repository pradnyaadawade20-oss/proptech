package models

import "time"

// OwnerBank is what the API returns about an owner's payout account.
// The full account number is never sent back.
type OwnerBank struct {
	AccountHolder string    `json:"account_holder"`
	AccountLast4  string    `json:"account_last4"`
	IFSC          string    `json:"ifsc"`
	Status        string    `json:"status"` // pending | active | verification_failed | inactive
	StatusDetail  string    `json:"status_detail"`
	UpdatedAt     time.Time `json:"updated_at"`
}

type SaveBankRequest struct {
	AccountHolder        string `json:"account_holder" binding:"required"`
	AccountNumber        string `json:"account_number" binding:"required"`
	ConfirmAccountNumber string `json:"confirm_account_number" binding:"required"`
	IFSC                 string `json:"ifsc" binding:"required"`
	PAN                  string `json:"pan"` // required in production, sandbox falls back to a test PAN
}

// PaymentOrder is one Cashfree checkout attempt group (an "order") for a rent month or a deposit.
type PaymentOrder struct {
	ID               string  `json:"id"`
	OrderID          string  `json:"order_id"`
	Kind             string  `json:"kind"` // rent | deposit
	LeaseID          string  `json:"lease_id"`
	RentPaymentID    *string `json:"rent_payment_id,omitempty"`
	PayerID          string  `json:"payer_id"`
	OwnerID          string  `json:"owner_id"`
	PayerName        string  `json:"payer_name,omitempty"`
	PropertyTitle    string  `json:"property_title,omitempty"`
	PeriodLabel      string  `json:"period_label,omitempty"`
	VendorID         string  `json:"-"`
	Amount           float64 `json:"amount"`
	RentAmount       float64 `json:"rent_amount"`
	LateDays         int     `json:"late_days"`
	LateFee          float64 `json:"late_fee"`
	PlatformFee      float64 `json:"platform_fee"`
	OwnerAmount      float64 `json:"owner_amount"`
	Status           string  `json:"status"` // created | paid | expired | cancelled | superseded | duplicate
	PaymentSessionID string  `json:"-"`
	CFPaymentID      string  `json:"cf_payment_id,omitempty"`
	PaymentMethod    string  `json:"payment_method,omitempty"`
	Attempts         int     `json:"attempts"`
	FailureReason    string  `json:"failure_reason,omitempty"`
	LastFailedAt     *time.Time `json:"last_failed_at,omitempty"`
	ExpiresAt        time.Time  `json:"expires_at"`
	PaidAt           *time.Time `json:"paid_at,omitempty"`

	SettlementStatus string     `json:"settlement_status"` // pending | settled | failed
	SettlementUTR    string     `json:"settlement_utr,omitempty"`
	SettlementAmount *float64   `json:"settlement_amount,omitempty"`
	SettledAt        *time.Time `json:"settled_at,omitempty"`
	CreatedAt        time.Time  `json:"created_at"`
}

// CheckoutSession is the only thing the mobile app needs to open Cashfree checkout.
type CheckoutSession struct {
	OrderID          string    `json:"order_id"`
	PaymentSessionID string    `json:"payment_session_id"`
	Amount           float64   `json:"amount"`
	Environment      string    `json:"environment"` // SANDBOX | PRODUCTION
	ExpiresAt        time.Time `json:"expires_at"`
	Resumed          bool      `json:"resumed"`
}

type SettlementTotals struct {
	CollectedTotal float64 `json:"collected_total"`
	SettledTotal   float64 `json:"settled_total"`
	PendingTotal   float64 `json:"pending_total"`
	PlatformFees   float64 `json:"platform_fees"`
}