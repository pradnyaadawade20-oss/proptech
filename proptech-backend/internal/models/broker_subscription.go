package models

import "time"

const (
	PlanFree    = "free"
	PlanMonthly = "monthly"
	PlanYearly  = "yearly"

	// FreeListingLimit: a broker can post this many listings for free.
	FreeListingLimit = 3
)

// SubscriptionPlan is a purchasable plan. Change prices here.
type SubscriptionPlan struct {
	ID     string `json:"id"` // monthly | yearly
	Name   string `json:"name"`
	Price  int    `json:"price"`  // INR
	Months int    `json:"months"` // validity
}

var SubscriptionPlans = []SubscriptionPlan{
	{ID: PlanMonthly, Name: "Pro Monthly", Price: 499, Months: 1},
	{ID: PlanYearly, Name: "Pro Yearly", Price: 4999, Months: 12},
}

func FindPlan(id string) (SubscriptionPlan, bool) {
	for _, p := range SubscriptionPlans {
		if p.ID == id {
			return p, true
		}
	}
	return SubscriptionPlan{}, false
}

// BrokerSubscription backs the plan card on BrokerDashboardScreen and the
// subscription screen. ListingsUsed / IsActive / CanAddListing are derived,
// not stored — see BrokerSubscriptionRepository.
type BrokerSubscription struct {
	ID            string     `json:"id"`
	BrokerID      string     `json:"broker_id"`
	PlanName      string     `json:"plan_name"`
	PlanType      string     `json:"plan_type"` // free | monthly | yearly
	ListingsUsed  int        `json:"listings_used"`
	ListingsLimit int        `json:"listings_limit"` // free limit (ignored when Unlimited)
	Unlimited     bool       `json:"unlimited"`
	IsActive      bool       `json:"is_active"` // paid plan and not expired
	Expired       bool       `json:"expired"`   // had a paid plan that lapsed
	CanAddListing bool       `json:"can_add_listing"`
	StartedAt     *time.Time `json:"started_at"`
	ExpiresAt     *time.Time `json:"expires_at"`
	CreatedAt     time.Time  `json:"created_at"`
}