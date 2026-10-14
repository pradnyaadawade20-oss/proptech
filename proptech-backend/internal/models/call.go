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

// CreateCallRequest identifies who to call. Send ONE of:
//   - lead_id                          (chat / leads screens)
//   - property_id                      (buyer on a listing: the lead is created if missing)
//   - property_id + peer_id            (owner calling a buyer who enquired on that listing)
type CreateCallRequest struct {
	LeadID     string `json:"lead_id"`
	PropertyID string `json:"property_id"`
	PeerID     string `json:"peer_id"`
}