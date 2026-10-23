package repository

import (
	"context"

	"proptech-backend/internal/models"
)

// History returns every purchase / renewal of the broker, newest first.
func (r *BrokerSubscriptionRepository) History(ctx context.Context, brokerID string) ([]models.SubscriptionReceipt, error) {
	rows, err := r.db.Query(ctx, `
		SELECT h.id::text,
		       'SB-' || to_char(h.created_at, 'YYMMDD') || '-' || upper(left(h.id::text, 6)),
		       h.plan_type, h.amount::float8, h.starts_at, h.expires_at, h.created_at,
		       h.payment_ref,
		       COALESCE(po.payment_method, ''), COALESCE(po.cf_payment_id, '')
		FROM broker_subscription_history h
		LEFT JOIN payment_orders po ON po.order_id = h.payment_ref
		WHERE h.broker_id = $1
		ORDER BY h.created_at DESC`, brokerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []models.SubscriptionReceipt{}
	for rows.Next() {
		var x models.SubscriptionReceipt
		if err := rows.Scan(&x.ID, &x.ReceiptNo, &x.PlanType, &x.Amount, &x.StartsAt, &x.ExpiresAt,
			&x.PaidAt, &x.PaymentRef, &x.PaymentMethod, &x.TransactionID); err != nil {
			return nil, err
		}
		if p, ok := models.FindPlan(x.PlanType); ok {
			x.PlanName = p.Name
		} else {
			x.PlanName = x.PlanType
		}
		out = append(out, x)
	}
	return out, rows.Err()
}