package repository

import (
	"context"

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
// the first time they're asked for it — matches BrokerDashboardScreen
// always showing a plan card even for a brand-new broker. ListingsUsed is
// derived live from their properties, not stored, so it stays accurate.
func (r *BrokerSubscriptionRepository) GetByBrokerID(ctx context.Context, brokerID string) (*models.BrokerSubscription, error) {
	var s models.BrokerSubscription
	err := r.db.QueryRow(ctx, `
		SELECT id, broker_id, plan_name, listings_limit, created_at
		FROM broker_subscriptions
		WHERE broker_id = $1
	`, brokerID).Scan(&s.ID, &s.BrokerID, &s.PlanName, &s.ListingsLimit, &s.CreatedAt)

	if err == pgx.ErrNoRows {
		err = r.db.QueryRow(ctx, `
			INSERT INTO broker_subscriptions (broker_id)
			VALUES ($1)
			RETURNING id, broker_id, plan_name, listings_limit, created_at
		`, brokerID).Scan(&s.ID, &s.BrokerID, &s.PlanName, &s.ListingsLimit, &s.CreatedAt)
	}
	if err != nil {
		return nil, err
	}

	err = r.db.QueryRow(ctx, `
		SELECT COUNT(*) FROM properties WHERE owner_id = $1
	`, brokerID).Scan(&s.ListingsUsed)
	if err != nil {
		return nil, err
	}

	return &s, nil
}