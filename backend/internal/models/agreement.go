package models

import "time"

// Status flow:
// requested -> draft_ready -> awaiting_signatures -> signed_by_owner
// -> signed_by_tenant -> completed | rejected | cancelled
type Agreement struct {
	ID               string     `json:"id"`
	PropertyID       string     `json:"property_id"`
	PropertyTitle    string     `json:"property_title"`
	PropertyImageURL string     `json:"property_image_url"`
	OwnerID          string     `json:"owner_id"`
	OwnerName        string     `json:"owner_name"`
	TenantID         string     `json:"tenant_id"`
	TenantName       string     `json:"tenant_name"`

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

type UpdateAgreementStatusRequest struct {
	Status string `json:"status" binding:"required,oneof=requested draft_ready awaiting_signatures signed_by_owner signed_by_tenant completed rejected cancelled"`
}