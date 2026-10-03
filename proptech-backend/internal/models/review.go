package models

import "time"

type Review struct {
	ID            string    `json:"id"`
	PropertyID    string    `json:"property_id"`
	UserID        string    `json:"user_id"`
	UserName      string    `json:"user_name"`
	UserAvatarURL string    `json:"user_avatar_url"`
	Rating        int       `json:"rating"` // 1-5
	Comment       string    `json:"comment"`
	CreatedAt     time.Time `json:"created_at"`
}

type CreateReviewRequest struct {
	Rating  int    `json:"rating" binding:"required,min=1,max=5"`
	Comment string `json:"comment"`
}
