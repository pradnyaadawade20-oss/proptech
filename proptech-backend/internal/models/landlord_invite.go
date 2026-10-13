package models

import "time"

// LandlordInvite is a broker's invitation to the real owner of a listing.
type LandlordInvite struct {
	ID               string     `json:"id"`
	PropertyID       string     `json:"property_id"`
	PropertyTitle    string     `json:"property_title"`
	BrokerID         string     `json:"broker_id"`
	BrokerName       string     `json:"broker_name"`
	Code             string     `json:"code,omitempty"` // only shown to the broker who created it
	LandlordName     string     `json:"landlord_name"`
	LandlordPhone    string     `json:"landlord_phone"`
	LandlordEmail    string     `json:"landlord_email"`
	LandlordUserID   string     `json:"landlord_user_id,omitempty"`
	LandlordUserName string     `json:"landlord_user_name,omitempty"` // real account name once accepted
	Status           string     `json:"status"`                       // pending | accepted | declined | cancelled | expired
	ExpiresAt        time.Time  `json:"expires_at"`
	CreatedAt        time.Time  `json:"created_at"`
	RespondedAt      *time.Time `json:"responded_at,omitempty"`
}

type CreateLandlordInviteRequest struct {
	Name  string `json:"name" binding:"required"`
	Phone string `json:"phone"`
	Email string `json:"email"`
}