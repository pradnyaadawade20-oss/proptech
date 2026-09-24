package models

import "time"

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
