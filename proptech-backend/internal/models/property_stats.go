package models

// PropertyStat is what an owner sees on each of their listings.
type PropertyStat struct {
	PropertyID string `json:"property_id"`
	Views      int    `json:"views"`      // different people who opened the listing
	Interested int    `json:"interested"` // different people who saved it or contacted the owner
	Saved      int    `json:"saved"`
	Enquiries  int    `json:"enquiries"`
}