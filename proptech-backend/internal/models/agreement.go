package models

import "time"

// Status flow:
// requested -> draft_ready -> awaiting_signatures -> signed_by_owner
// -> signed_by_tenant -> completed | rejected | cancelled | expired
//
// User-facing mapping (spec 12.5):
//   Pending  = requested
//   Approved = draft_ready / awaiting_signatures (owner accepted + drafted)
//   Signed   = completed (signed_by_* = partially signed)
//   Rejected = rejected (owner), Cancelled = cancelled (either party)
//   Expired  = expired (set by the expiry job / deadline passed, never by a user)
type Agreement struct {
	ID               string `json:"id"`
	PropertyID       string `json:"property_id"`
	PropertyTitle    string `json:"property_title"`
	PropertyImageURL string `json:"property_image_url"`
	OwnerID          string `json:"owner_id"`
	OwnerName        string `json:"owner_name"`
	TenantID         string `json:"tenant_id"`
	TenantName       string `json:"tenant_name"`

	Status string `json:"status"`

	MonthlyRent     *float64 `json:"monthly_rent,omitempty"`
	SecurityDeposit *float64 `json:"security_deposit,omitempty"`
	StartDate       *string  `json:"start_date,omitempty"` // YYYY-MM-DD
	DurationMonths  *int     `json:"duration_months,omitempty"`
	Terms           *string  `json:"terms,omitempty"`

	OwnerSignatureType string     `json:"owner_signature_type,omitempty"`
	OwnerSignatureData string     `json:"owner_signature_data,omitempty"`
	OwnerSignedAt      *time.Time `json:"owner_signed_at,omitempty"`

	TenantSignatureType string     `json:"tenant_signature_type,omitempty"`
	TenantSignatureData string     `json:"tenant_signature_data,omitempty"`
	TenantSignedAt      *time.Time `json:"tenant_signed_at,omitempty"`

	FinalPDFURL string `json:"final_pdf_url,omitempty"`

	// Deadline for the next step; nil once the agreement reaches a final state.
	ExpiresAt *time.Time `json:"expires_at,omitempty"`
	// Why/who/when for rejected / cancelled / expired. StatusChangedBy is empty
	// when the system expired it.
	StatusReason    string     `json:"status_reason,omitempty"`
	StatusChangedBy string     `json:"status_changed_by,omitempty"`
	StatusChangedAt *time.Time `json:"status_changed_at,omitempty"`

	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// Step 1: tenant (or owner) raises a request for an agreement on a property.
type CreateAgreementRequest struct {
	PropertyID string `json:"property_id" binding:"required"`
	OwnerID    string `json:"owner_id" binding:"required"`
	TenantID   string `json:"tenant_id" binding:"required"`
}

// Step 2: owner (or backend) fills in the draft terms.
type UpdateDraftRequest struct {
	MonthlyRent     *float64 `json:"monthly_rent"`
	SecurityDeposit *float64 `json:"security_deposit"`
	StartDate       *string  `json:"start_date"`
	DurationMonths  *int     `json:"duration_months"`
	Terms           *string  `json:"terms" binding:"required"`
}

// Step 3: either party signs — via drawn signature (base64 PNG) or typed name.
type SignAgreementRequest struct {
	SignerRole    string `json:"signer_role" binding:"required,oneof=owner tenant"`
	SignatureType string `json:"signature_type" binding:"required,oneof=draw type"`
	SignatureData string `json:"signature_data" binding:"required"`
}

// Manual status changes: only these. "completed" is set ONLY by Sign (both
// signatures), signed_by_* only by Sign, draft_ready only by UpdateDraft.
// "expired" is deliberately NOT allowed here: only the expiry job sets it.
type UpdateAgreementStatusRequest struct {
	Status string `json:"status" binding:"required,oneof=awaiting_signatures rejected cancelled"`
	// Optional note shown to the other party (reject / cancel).
	Reason string `json:"reason" binding:"max=500"`
}

// How long a party has to take the next step before the agreement expires.
const AgreementExpiryDays = 7

// Allowed status transitions (manual + automatic).
var AgreementTransitions = map[string][]string{
	"requested":           {"draft_ready", "rejected", "cancelled", "expired"},
	"draft_ready":         {"draft_ready", "awaiting_signatures", "rejected", "cancelled", "expired"},
	"awaiting_signatures": {"signed_by_owner", "signed_by_tenant", "draft_ready", "rejected", "cancelled", "expired"},
	"signed_by_owner":     {"completed", "cancelled", "expired"},
	"signed_by_tenant":    {"completed", "cancelled", "expired"},
}

// AgreementIsFinal reports whether the status can no longer change.
func AgreementIsFinal(status string) bool {
	switch status {
	case "completed", "rejected", "cancelled", "expired":
		return true
	}
	return false
}

// PastDeadline is true when the agreement is still open but its deadline has
// passed (the hourly job just hasn't flipped it to "expired" yet).
func (a *Agreement) PastDeadline() bool {
	return !AgreementIsFinal(a.Status) && a.ExpiresAt != nil && a.ExpiresAt.Before(time.Now())
}

func AgreementCanMove(from, to string) bool {
	for _, t := range AgreementTransitions[from] {
		if t == to {
			return true
		}
	}
	return false
}

// OTP before e-sign.
type AgreementOTPSendRequest struct {
	SignerRole string `json:"signer_role" binding:"required,oneof=owner tenant"`
}

type AgreementOTPVerifyRequest struct {
	SignerRole string `json:"signer_role" binding:"required,oneof=owner tenant"`
	Code       string `json:"code" binding:"required,len=6"`
}