package models

import (
	"fmt"
	"time"
)

type Property struct {
	ID            string    `json:"id"`
	OwnerID       *string   `json:"owner_id,omitempty"`
	Title         string    `json:"title"`
	ImageURL      string    `json:"image_url"`
	Price         float64   `json:"price"`
	PriceUnit     string    `json:"price_unit"`
	BHK           string    `json:"bhk"`
	Furnishing    string    `json:"furnishing"`
	Location      string    `json:"location"`
	IsVerified    bool      `json:"is_verified"`
	Rating        float64   `json:"rating"`
	ReviewCount   int       `json:"review_count"`
	Category      string    `json:"category"`
	Amenities     []string  `json:"amenities"`
	ListingStatus string    `json:"listing_status"`
	CreatedAt     time.Time `json:"created_at"`

	// Listing details (see 013_property_details.sql).
	Area               float64    `json:"area"` // sq ft
	Bathrooms          int        `json:"bathrooms"`
	Balconies          int        `json:"balconies"`
	FloorNumber        int        `json:"floor_number"`
	TotalFloors        int        `json:"total_floors"`
	City               string     `json:"city"`
	Locality           string     `json:"locality"`
	Society            string     `json:"society"`
	Pincode            string     `json:"pincode"`
	SecurityDeposit    float64    `json:"security_deposit"`
	MaintenanceCharges float64    `json:"maintenance_charges"`
	PreferredTenants   []string   `json:"preferred_tenants"`
	AvailableFrom      *time.Time `json:"available_from,omitempty"`
	Description        string     `json:"description"`
	PropertyAgeYears   int        `json:"property_age_years"` // -1 = unknown
	Facing             string     `json:"facing"`
	OwnershipType      string     `json:"ownership_type"`
	IsPriceNegotiable  bool       `json:"is_price_negotiable"`
	ContactPreference  string     `json:"contact_preference"` // call | chat | both
	PostedBy           string     `json:"posted_by"`           // owner | broker

	// Filled by PropertyRepository.AttachMedia (not columns on properties).
	AdditionalImageURLs []string `json:"additional_image_urls"`
	VideoTourURL        *string  `json:"video_tour_url,omitempty"`
}

type PropertyFilter struct {
	Location      string
	MinPrice      *float64
	MaxPrice      *float64
	BHK           string
	Furnishing    string
	Category      string
	ListingStatus string
	Sort          string // "price_asc" | "price_desc" | "rating" | "" (newest first)
}

// PropertyDetailsInput holds the optional listing-detail fields shared by
// the create and update requests.
type PropertyDetailsInput struct {
	Area               float64  `json:"area"`
	Bathrooms          int      `json:"bathrooms"`
	Balconies          int      `json:"balconies"`
	FloorNumber        int      `json:"floor_number"`
	TotalFloors        int      `json:"total_floors"`
	City               string   `json:"city"`
	Locality           string   `json:"locality"`
	Society            string   `json:"society"`
	Pincode            string   `json:"pincode"`
	SecurityDeposit    float64  `json:"security_deposit"`
	MaintenanceCharges float64  `json:"maintenance_charges"`
	PreferredTenants   []string `json:"preferred_tenants"`
	AvailableFrom      *string  `json:"available_from"` // "YYYY-MM-DD" or empty
	Description        string   `json:"description"`
	PropertyAgeYears   *int     `json:"property_age_years"` // nil = unknown
	Facing             string   `json:"facing"`
	OwnershipType      string   `json:"ownership_type"`
	IsPriceNegotiable  bool     `json:"is_price_negotiable"`
	ContactPreference  string   `json:"contact_preference"`
}

// ParsedAvailableFrom turns the "YYYY-MM-DD" string into a date (nil if empty).
func (d PropertyDetailsInput) ParsedAvailableFrom() (*time.Time, error) {
	if d.AvailableFrom == nil || *d.AvailableFrom == "" {
		return nil, nil
	}
	t, err := time.Parse("2006-01-02", *d.AvailableFrom)
	if err != nil {
		return nil, fmt.Errorf("available_from must be YYYY-MM-DD")
	}
	return &t, nil
}

// AgeOrUnknown returns the property age, or -1 when not provided.
func (d PropertyDetailsInput) AgeOrUnknown() int {
	if d.PropertyAgeYears == nil {
		return -1
	}
	return *d.PropertyAgeYears
}

// ContactPreferenceOrDefault falls back to "both" when empty/invalid.
func (d PropertyDetailsInput) ContactPreferenceOrDefault() string {
	switch d.ContactPreference {
	case "call", "chat", "both":
		return d.ContactPreference
	}
	return "both"
}

// TenantsOrEmpty avoids sending NULL for the TEXT[] column.
func (d PropertyDetailsInput) TenantsOrEmpty() []string {
	if d.PreferredTenants == nil {
		return []string{}
	}
	return d.PreferredTenants
}

type CreatePropertyRequest struct {
	OwnerID    string   `json:"owner_id"` // ignored if sent — handler overwrites with the JWT user id
	Title      string   `json:"title" binding:"required"`
	ImageURL   string   `json:"image_url"`
	Price      float64  `json:"price" binding:"required"`
	PriceUnit  string   `json:"price_unit"`
	BHK        string   `json:"bhk"`
	Furnishing string   `json:"furnishing"`
	Location   string   `json:"location" binding:"required"`
	Category   string   `json:"category"`
	Amenities  []string `json:"amenities"`
	PostedBy   string   `json:"posted_by"` // owner | broker (create only)

	PropertyDetailsInput
}

// PostedByOrDefault falls back to "owner" when empty/invalid.
func (r CreatePropertyRequest) PostedByOrDefault() string {
	if r.PostedBy == "broker" {
		return "broker"
	}
	return "owner"
}

type UpdatePropertyRequest struct {
	Title      string   `json:"title" binding:"required"`
	ImageURL   string   `json:"image_url"`
	Price      float64  `json:"price" binding:"required"`
	PriceUnit  string   `json:"price_unit"`
	BHK        string   `json:"bhk"`
	Furnishing string   `json:"furnishing"`
	Location   string   `json:"location" binding:"required"`
	Category   string   `json:"category"`
	Amenities  []string `json:"amenities"`

	PropertyDetailsInput
}

type UpdateListingStatusRequest struct {
	ListingStatus string `json:"listing_status" binding:"required,oneof=available rented sold"`
}

type DashboardStats struct {
	TotalProperties int `json:"total_properties"`
	Available       int `json:"available"`
	Rented          int `json:"rented"`
	Sold            int `json:"sold"`
	ActiveLeads     int `json:"active_leads"`
	VisitsThisWeek  int `json:"visits_this_week"`
}