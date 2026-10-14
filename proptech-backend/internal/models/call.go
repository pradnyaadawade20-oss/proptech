package models

import "time"

// Call is one audio call between the two sides of a lead (buyer <-> owner).
// status: ringing | active | ended | rejected | missed
type Call struct {
	ID          string     `json:"id"`
	LeadID      string     `json:"lead_id"`
	CallerID    string     `json:"caller_id"`
	CalleeID    string     `json:"callee_id"`
	Status      string     `json:"status"`
	CreatedAt   time.Time  `json:"created_at"`
	AnsweredAt  *time.Time `json:"answered_at,omitempty"`
	EndedAt     *time.Time `json:"ended_at,omitempty"`
	DurationSec int        `json:"duration_sec"`

	// Only filled by the history list.
	Direction string `json:"direction,omitempty"` // incoming | outgoing
	PeerName  string `json:"peer_name,omitempty"`
}

// FillDuration sets DurationSec from the answered/ended timestamps.
func (c *Call) FillDuration() {
	if c.AnsweredAt != nil && c.EndedAt != nil && c.EndedAt.After(*c.AnsweredAt) {
		c.DurationSec = int(c.EndedAt.Sub(*c.AnsweredAt).Seconds())
	}
}

type CreateCallRequest struct {
	LeadID string `json:"lead_id" binding:"required"`
}