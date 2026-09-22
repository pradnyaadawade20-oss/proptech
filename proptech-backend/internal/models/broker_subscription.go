package models

import "time"

// BrokerSubscription backs the "Free Plan / 3 of 3 listings used / Upgrade"
// card on BrokerDashboardScreen. ListingsUsed is derived (count of the
// broker's properties), not stored — see BrokerSubscriptionRepository.
type BrokerSubscription struct {
	ID            string    `json:"id"`
	BrokerID      string    `json:"broker_id"`
	PlanName      string    `json:"plan_name"`
	ListingsUsed  int       `json:"listings_used"`
	ListingsLimit int       `json:"listings_limit"`
	CreatedAt     time.Time `json:"created_at"`
}