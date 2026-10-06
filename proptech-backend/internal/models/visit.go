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

	// Visitor's feedback after a completed visit (empty until given).
	FeedbackInterest string     `json:"feedback_interest"`
	FeedbackNote     string     `json:"feedback_note"`
	FeedbackAt       *time.Time `json:"feedback_at"`
}

type CreateVisitRequest struct {
	PropertyID  string    `json:"property_id" binding:"required"`
	VisitorID   string    `json:"visitor_id"` // ignored if sent — handler overwrites with the JWT user id
	ScheduledAt time.Time `json:"scheduled_at" binding:"required"`
}

type UpdateVisitStatusRequest struct {
	Status string `json:"status" binding:"required,oneof=pending confirmed completed cancelled"`
}

type VisitFeedbackRequest struct {
	Interest string `json:"interest" binding:"required,oneof=interested maybe not_interested"`
	Note     string `json:"note" binding:"max=500"`
}
