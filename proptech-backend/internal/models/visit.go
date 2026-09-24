package models

import "time"

type Visit struct {
	ID               string    `json:"id"`
	PropertyID       string    `json:"property_id"`
	PropertyTitle    string    `json:"property_title"`
	PropertyImageURL string    `json:"property_image_url"`
	VisitorID        string    `json:"visitor_id"`
	VisitorName      string    `json:"visitor_name"`
	ScheduledAt      time.Time `json:"scheduled_at"`
	Status           string    `json:"status"`
	CreatedAt        time.Time `json:"created_at"`
}

type CreateVisitRequest struct {
	PropertyID  string    `json:"property_id" binding:"required"`
	VisitorID   string    `json:"visitor_id"` // ignored if sent — handler overwrites with the JWT user id
	ScheduledAt time.Time `json:"scheduled_at" binding:"required"`
}

type UpdateVisitStatusRequest struct {
	Status string `json:"status" binding:"required,oneof=pending confirmed completed cancelled"`
}
