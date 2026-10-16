package repository

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"proptech-backend/internal/models"
)

type BrokerSubscriptionRepository struct {
	db *pgxpool.Pool
}

func NewBrokerSubscriptionRepository(db *pgxpool.Pool) *BrokerSubscriptionRepository {
	return &BrokerSubscriptionRepository{db: db}
}

// GetByBrokerID returns the broker's plan, creating a default Free Plan row
// the first time. ListingsUsed is counted live (listings posted as broker),
// and IsActive / CanAddListing are computed from expires_at, so an expired
// plan automatically falls back to the free limit.
func (r *BrokerSubscriptionRepository) GetByBrokerID(ctx context.Context, brokerID string) (*models.BrokerSubscription, error) {
	const sel = `
		SELECT id, broker_id, plan_name, listings_limit, plan_type, started_at, expires_at, created_at
		FROM broker_subscriptions
		WHERE broker_id = $1`

	var s models.BrokerSubscription
	scan := func(row pgx.Row) error {
		return row.Scan(&s.ID, &s.BrokerID, &s.PlanName, &s.ListingsLimit, &s.PlanType, &s.StartedAt, &s.ExpiresAt, &s.CreatedAt)
	}

	err := scan(r.db.QueryRow(ctx, sel, brokerID))
	if err == pgx.ErrNoRows {
		if _, err = r.db.Exec(ctx, `
			INSERT INTO broker_subscriptions (broker_id) VALUES ($1)
			ON CONFLICT (broker_id) DO NOTHING`, brokerID); err != nil {
			return nil, err
		}
		err = scan(r.db.QueryRow(ctx, sel, brokerID))
	}
	if err != nil {
		return nil, err
	}

	if err = r.db.QueryRow(ctx, `
		SELECT COUNT(*) FROM properties
		WHERE owner_id = $1 AND COALESCE(posted_by, 'owner') = 'broker'
	`, brokerID).Scan(&s.ListingsUsed); err != nil {
		return nil, err
	}

	paid := s.PlanType != models.PlanFree
	s.IsActive = paid && s.ExpiresAt != nil && s.ExpiresAt.After(time.Now())
	s.Expired = paid && !s.IsActive
	s.Unlimited = s.IsActive
	if !s.IsActive {
		s.PlanName = "Free Plan"
		if s.ListingsLimit <= 0 {
			s.ListingsLimit = models.FreeListingLimit
		}
	}
	s.CanAddListing = s.Unlimited || s.ListingsUsed < s.ListingsLimit
	return &s, nil
}

// Subscribe activates (or renews) a paid plan. If the broker still has time
// left on a plan, the new period is added after the current expiry.
func (r *BrokerSubscriptionRepository) Subscribe(ctx context.Context, brokerID string, plan models.SubscriptionPlan, paymentRef string) (*models.BrokerSubscription, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	if _, err = tx.Exec(ctx, `
		INSERT INTO broker_subscriptions (broker_id) VALUES ($1)
		ON CONFLICT (broker_id) DO NOTHING`, brokerID); err != nil {
		return nil, err
	}

	var current *time.Time
	if err = tx.QueryRow(ctx, `
		SELECT expires_at FROM broker_subscriptions WHERE broker_id = $1 FOR UPDATE`, brokerID).Scan(&current); err != nil {
		return nil, err
	}

	start := time.Now()
	if current != nil && current.After(start) {
		start = *current
	}
	expires := start.AddDate(0, plan.Months, 0)

	if _, err = tx.Exec(ctx, `
		UPDATE broker_subscriptions
		SET plan_type = $2, plan_name = $3, started_at = NOW(), expires_at = $4
		WHERE broker_id = $1`, brokerID, plan.ID, plan.Name, expires); err != nil {
		return nil, err
	}

	if _, err = tx.Exec(ctx, `
		INSERT INTO broker_subscription_history (broker_id, plan_type, amount, starts_at, expires_at, payment_ref)
		VALUES ($1, $2, $3, $4, $5, $6)`, brokerID, plan.ID, plan.Price, start, expires, paymentRef); err != nil {
		return nil, err
	}

	if err = tx.Commit(ctx); err != nil {
		return nil, err
	}
	return r.GetByBrokerID(ctx, brokerID)
}