package models

import "time"

// Lead = one buyer/tenant enquiry on one property (unique per property+buyer).
// Status flow (forward only): new -> contacted -> visited -> closed.
type Lead struct {
	ID               string    `json:"id"`
	PropertyID       string    `json:"property_id"`
	PropertyTitle    string    `json:"property_title"`
	PropertyImageURL string    `json:"property_image_url"`
	OwnerID          string    `json:"owner_id"`
	BuyerID          string    `json:"buyer_id"`
	Name             string    `json:"name"`
	Phone            string    `json:"phone"`
	Email            string    `json:"email"`
	Message          string    `json:"message"`
	Source           string    `json:"source"`
	Status           string    `json:"status"`
	CreatedAt        time.Time `json:"created_at"`
	UpdatedAt        time.Time `json:"updated_at"`
}

type CreateLeadRequest struct {
	PropertyID string `json:"property_id" binding:"required"`
	Name       string `json:"name"`
	Phone      string `json:"phone"`
	Message    string `json:"message"`
	Source     string `json:"source" binding:"omitempty,oneof=contact call chat visit"`
}

// Owner manages their own pipeline, so any status can be set manually.
// (Automatic moves from chat / visit / agreement are forward-only.)
type UpdateLeadStatusRequest struct {
	Status string `json:"status" binding:"required,oneof=new contacted visited closed"`
}

type LeadCounts struct {
	All       int `json:"all"`
	New       int `json:"new"`
	Contacted int `json:"contacted"`
	Visited   int `json:"visited"`
	Closed    int `json:"closed"`
}