package models

import "time"

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

// CreateLeadRequest: buyer taps "Contact Owner" / Call / Chat / Book visit.
type CreateLeadRequest struct {
	PropertyID string `json:"property_id" binding:"required"`
	Name       string `json:"name"`
	Phone      string `json:"phone"`
	Message    string `json:"message"`
	Source     string `json:"source"` // contact | call | chat | visit (default contact)
}

type UpdateLeadStatusRequest struct {
	Status string `json:"status" binding:"required,oneof=new contacted visited closed"`
}

// LeadCounts backs the tab badges on the Leads screen.
type LeadCounts struct {
	All       int `json:"all"`
	New       int `json:"new"`
	Contacted int `json:"contacted"`
	Visited   int `json:"visited"`
	Closed    int `json:"closed"`
}

// SourceOrDefault falls back to "contact" for empty/unknown values.
func (r CreateLeadRequest) SourceOrDefault() string {
	switch r.Source {
	case "contact", "call", "chat", "visit":
		return r.Source
	}
	return "contact"
}
