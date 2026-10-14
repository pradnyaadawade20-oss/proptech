package repository

import (
	"context"
	"errors"
	"math"
	"time"

	"github.com/jackc/pgx/v5"
)

// PaymentOrder is one Cashfree order (a rent month or the security deposit).
type PaymentOrder struct {
	ID               string     `json:"id"`
	OrderID          string     `json:"order_id"`
	Kind             string     `json:"kind"` // rent | deposit
	LeaseID          string     `json:"lease_id"`
	RentPaymentID    *string    `json:"rent_payment_id,omitempty"`
	PayerID          string     `json:"payer_id"`
	OwnerID          string     `json:"owner_id"`
	Amount           float64    `json:"amount"`
	RentAmount       float64    `json:"rent_amount"`
	LateDays         int        `json:"late_days"`
	LateFee          float64    `json:"late_fee"`
	Status           string     `json:"status"` // created | paid | expired | cancelled | superseded | duplicate
	CFOrderID        string     `json:"-"`
	PaymentSessionID string     `json:"-"`
	CFPaymentID      string     `json:"cf_payment_id,omitempty"`
	PaymentMethod    string     `json:"payment_method,omitempty"`
	FailureReason    string     `json:"failure_reason,omitempty"`
	ExpiresAt        time.Time  `json:"expires_at"`
	PaidAt           *time.Time `json:"paid_at,omitempty"`
}

const orderSelect = `
	SELECT id, order_id, kind, lease_id, rent_payment_id, payer_id, owner_id,
	       amount, rent_amount, late_days, late_fee, status, cf_order_id, payment_session_id,
	       cf_payment_id, payment_method, failure_reason, expires_at, paid_at
	FROM payment_orders
`

func scanOrder(row interface{ Scan(dest ...any) error }) (*PaymentOrder, error) {
	var o PaymentOrder
	err := row.Scan(&o.ID, &o.OrderID, &o.Kind, &o.LeaseID, &o.RentPaymentID, &o.PayerID, &o.OwnerID,
		&o.Amount, &o.RentAmount, &o.LateDays, &o.LateFee, &o.Status, &o.CFOrderID, &o.PaymentSessionID,
		&o.CFPaymentID, &o.PaymentMethod, &o.FailureReason, &o.ExpiresAt, &o.PaidAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrLeaseNotFound
		}
		return nil, err
	}
	return &o, nil
}

func (r *LeaseRepository) GetOrderByOrderID(ctx context.Context, orderID string) (*PaymentOrder, error) {
	return scanOrder(r.db.QueryRow(ctx, orderSelect+` WHERE order_id = $1`, orderID))
}

// OpenOrder returns the still-usable (created, not expired) order of a rent month / deposit, or nil.
func (r *LeaseRepository) OpenOrder(ctx context.Context, kind, targetID string) (*PaymentOrder, error) {
	q := orderSelect + ` WHERE status = 'created' AND expires_at > now() AND `
	if kind == "rent" {
		q += `kind = 'rent' AND rent_payment_id = $1`
	} else {
		q += `kind = 'deposit' AND lease_id = $1`
	}
	o, err := scanOrder(r.db.QueryRow(ctx, q+` ORDER BY created_at DESC LIMIT 1`, targetID))
	if errors.Is(err, ErrLeaseNotFound) {
		return nil, nil
	}
	return o, err
}

// SupersedeOpen retires every open order of the target so a fresh one can be created
// (e.g. the late fee changed). A superseded order that still gets paid is accepted by FinalizeOrder.
func (r *LeaseRepository) SupersedeOpen(ctx context.Context, kind, targetID string) error {
	var err error
	if kind == "rent" {
		_, err = r.db.Exec(ctx, `UPDATE payment_orders SET status = 'superseded', updated_at = now()
			WHERE status = 'created' AND kind = 'rent' AND rent_payment_id = $1`, targetID)
	} else {
		_, err = r.db.Exec(ctx, `UPDATE payment_orders SET status = 'superseded', updated_at = now()
			WHERE status = 'created' AND kind = 'deposit' AND lease_id = $1`, targetID)
	}
	return err
}

func (r *LeaseRepository) InsertOrder(ctx context.Context, o *PaymentOrder) error {
	return r.db.QueryRow(ctx, `
		INSERT INTO payment_orders
		  (order_id, kind, lease_id, rent_payment_id, payer_id, owner_id, amount, rent_amount,
		   late_days, late_fee, platform_fee, owner_amount, cf_order_id, payment_session_id, expires_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,0,$7,$11,$12,$13)
		RETURNING id`,
		o.OrderID, o.Kind, o.LeaseID, o.RentPaymentID, o.PayerID, o.OwnerID, o.Amount, o.RentAmount,
		o.LateDays, o.LateFee, o.CFOrderID, o.PaymentSessionID, o.ExpiresAt).Scan(&o.ID)
}

// MarkFailure records a failed attempt (the tenant can simply try again in the same session).
func (r *LeaseRepository) MarkFailure(ctx context.Context, orderID, reason string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE payment_orders
		SET attempts = attempts + 1, failure_reason = $2, last_failed_at = now(), updated_at = now()
		WHERE order_id = $1 AND status <> 'paid'`, orderID, reason)
	return err
}

func (r *LeaseRepository) ExpireOrder(ctx context.Context, orderID string) error {
	_, err := r.db.Exec(ctx, `UPDATE payment_orders SET status = 'expired', updated_at = now()
		WHERE order_id = $1 AND status = 'created'`, orderID)
	return err
}

// UserContact gives Cashfree the customer details it requires.
func (r *LeaseRepository) UserContact(ctx context.Context, userID string) (name, phone, email string, err error) {
	err = r.db.QueryRow(ctx, `SELECT COALESCE(name,''), COALESCE(phone,''), COALESCE(email,'')
		FROM users WHERE id = $1`, userID).Scan(&name, &phone, &email)
	return
}

// LogWebhook stores a webhook once. fresh=false means we already handled this exact event.
func (r *LeaseRepository) LogWebhook(ctx context.Context, key, typ, orderID string, payload []byte) (fresh bool, err error) {
	var id string
	err = r.db.QueryRow(ctx, `
		INSERT INTO payment_webhook_events (event_key, event_type, order_id, payload)
		VALUES ($1, $2, $3, $4::jsonb)
		ON CONFLICT (event_key) DO NOTHING
		RETURNING id`, key, typ, orderID, string(payload)).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		// Seen before: reprocess only if the earlier attempt did not finish.
		var result string
		if e := r.db.QueryRow(ctx, `SELECT result FROM payment_webhook_events WHERE event_key = $1`, key).Scan(&result); e != nil {
			return false, e
		}
		return result != "ok", nil
	}
	return err == nil, err
}

func (r *LeaseRepository) WebhookDone(ctx context.Context, key, result string) {
	_, _ = r.db.Exec(ctx, `UPDATE payment_webhook_events SET result = $2 WHERE event_key = $1`, key, result)
}

// FinalizeOrder marks the order paid and settles the rent month / deposit in ONE transaction.
// Safe to call many times (webhook retries + app polling): returns done=false when it was already paid.
// duplicate=true means the rent/deposit was already settled some other way - money must be refunded manually.
func (r *LeaseRepository) FinalizeOrder(ctx context.Context, orderID, cfPaymentID, method string, paidAmount float64) (o *PaymentOrder, done bool, duplicate bool, err error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, false, false, err
	}
	defer tx.Rollback(ctx)

	o, err = scanOrder(tx.QueryRow(ctx, orderSelect+` WHERE order_id = $1 FOR UPDATE`, orderID))
	if err != nil {
		return nil, false, false, err
	}
	if o.Status == "paid" || o.Status == "duplicate" {
		return o, false, o.Status == "duplicate", nil
	}
	if math.Abs(paidAmount-o.Amount) > 0.01 {
		return nil, false, false, badState("paid amount does not match the order amount")
	}

	settled := false
	if o.Kind == "rent" && o.RentPaymentID != nil {
		tag, e := tx.Exec(ctx, `
			UPDATE rent_payments
			SET status = 'paid', paid_at = now(), submitted_at = COALESCE(submitted_at, now()),
			    payment_method = $2, reference = $3, late_days = $4, late_fee = $5, reject_reason = NULL,
			    receipt_no = `+receiptNoSQL+`
			WHERE id = $1 AND status <> 'paid'`, *o.RentPaymentID, method, cfPaymentID, o.LateDays, o.LateFee)
		if e != nil {
			return nil, false, false, e
		}
		settled = tag.RowsAffected() > 0
	} else {
		tag, e := tx.Exec(ctx, `
			UPDATE lease_deposits
			SET status = 'held', received_at = now(), submitted_at = COALESCE(submitted_at, now()),
			    payment_method = $2, reference = $3, updated_at = now()
			WHERE lease_id = $1 AND status IN ('pending', 'submitted')`, o.LeaseID, method, cfPaymentID)
		if e != nil {
			return nil, false, false, e
		}
		settled = tag.RowsAffected() > 0
	}

	newStatus := "paid"
	if !settled {
		newStatus = "duplicate"
	}
	if _, err = tx.Exec(ctx, `
		UPDATE payment_orders
		SET status = $2, cf_payment_id = $3, payment_method = $4, paid_at = now(),
		    settlement_status = 'pending', failure_reason = '', updated_at = now()
		WHERE order_id = $1`, orderID, newStatus, cfPaymentID, method); err != nil {
		return nil, false, false, err
	}
	if err = tx.Commit(ctx); err != nil {
		return nil, false, false, err
	}
	o.Status, o.CFPaymentID, o.PaymentMethod = newStatus, cfPaymentID, method
	return o, true, !settled, nil
}

// ListOpenOrders = orders that may still get paid (used by the background sweeper).
// Looks back 3 hours so a payment made just before the 45 min expiry is still caught.
func (r *LeaseRepository) ListOpenOrders(ctx context.Context) ([]PaymentOrder, error) {
	rows, err := r.db.Query(ctx, orderSelect+` WHERE status IN ('created', 'superseded')
		AND created_at > now() - interval '3 hours' ORDER BY created_at LIMIT 50`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []PaymentOrder{}
	for rows.Next() {
		o, err := scanOrder(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *o)
	}
	return out, rows.Err()
}