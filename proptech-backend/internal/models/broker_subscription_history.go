package models

import "time"

// SubscriptionReceipt is one purchase / renewal shown in the history list.
type SubscriptionReceipt struct {
	ID            string    `json:"id"`
	ReceiptNo     string    `json:"receipt_no"`
	PlanType      string    `json:"plan_type"`
	PlanName      string    `json:"plan_name"`
	Amount        float64   `json:"amount"`
	StartsAt      time.Time `json:"starts_at"`
	ExpiresAt     time.Time `json:"expires_at"`
	PaidAt        time.Time `json:"paid_at"`
	PaymentRef    string    `json:"payment_ref"`
	PaymentMethod string    `json:"payment_method"`
	TransactionID string    `json:"transaction_id"`
}