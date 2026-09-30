package models

import "time"

type Favorite struct {
	ID         string    `json:"id"`
	UserID     string    `json:"user_id"`
	PropertyID string    `json:"property_id"`
	CreatedAt  time.Time `json:"created_at"`
}

type AddFavoriteRequest struct {
	UserID     string `json:"user_id"` // ignored if sent — handler overwrites with the JWT user id
	PropertyID string `json:"property_id" binding:"required"`
}
