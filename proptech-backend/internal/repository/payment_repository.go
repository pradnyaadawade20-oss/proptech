package repository

import (
	"context"
	"errors"
	"fmt"
	"math"
	"time"

	"proptech-backend/internal/models"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PaymentRepository struct {
	db *pgxpool.Pool
}

func NewPaymentRepository(db *pgxpool.Pool) *PaymentRepository {
	return &PaymentRepository{db: db}
}

func isUniqueViolation(err error) bool {
	var pe *pgconn.PgError
	return errors.As(err, &pe) && pe.Code == "23505"
}

var ErrOpenOrderExists = errors.New("an open payment order already exists")

// ---------------------------------------------------------------------------
// Owner bank
// ---------------------------------------------------------------------------

type BankRow struct {
	models.OwnerBank
	OwnerID      string
	VendorID     string
	AccountEnc   string
}

func (r *PaymentRepository) GetBank(ctx context.Context, ownerID string) (*BankRow, error) {
	var b BankRow
	err := r.db.QueryRow(ctx, `
		SELECT owner_id, vendor_id, account_holder, account_number, account_last4, ifsc,
		       status, status_detail, updated_at
		FROM owner_bank_accounts WHERE owner_id = $1`, ownerID).
		Scan(&b.OwnerID, &b.VendorID, &b.AccountHolder, &b.AccountEnc, &b.AccountLast4, &b.IFSC,
			&b.Status, &b.StatusDetail, &b.UpdatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &b, nil
}

func (r *PaymentRepository) SaveBank(ctx context.Context, ownerID, vendorID, holder, encNumber, last4, ifsc, status, detail string) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO owner_bank_accounts (owner_id, vendor_id, account_holder, account_number, account_last4, ifsc, status, status_detail)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		ON CONFLICT (owner_id) DO UPDATE SET
			account_holder = EXCLUDED.account_holder, account_number = EXCLUDED.account_number,
			account_last4 = EXCLUDED.account_last4, ifsc = EXCLUDED.ifsc,
			status = EXCLUDED.status, status_detail = EXCLUDED.status_detail, updated_at = now()`,
		ownerID, vendorID, holder, encNumber, last4, ifsc, status, detail)
	return err
}

func (r *PaymentRepository) SetBankStatus(ctx context.Context, ownerID, status, detail string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE owner_bank_accounts SET status = $2, status_detail = $3, updated_at = now() WHERE owner_id = $1`,
		ownerID, status, detail)
	return err
}

// UserContact is what Cashfree needs as "customer / vendor details".
type UserContact struct {
	Name, Email, Phone string
}

func (r *PaymentRepository) GetUserContact(ctx context.Context, userID string) (UserContact, error) {
	var u UserContact
	err := r.db.QueryRow(ctx, `SELECT name, COALESCE(email, ''), COALESCE(phone, '') FROM users WHERE id = $1`, userID).
		Scan(&u.Name, &u.Email, &u.Phone)
	return u, err
}

// ---------------------------------------------------------------------------
// Orders
// ---------------------------------------------------------------------------

type NewOrder struct {
	OrderID       string
	Kind          string // rent | deposit
	LeaseID       string
	RentPaymentID string // "" for deposit
	PayerID       string
	OwnerID       string
	VendorID      string
	Amount        float64
	RentAmount    float64
	LateDays      int
	LateFee       float64
	PlatformFee   float64
	OwnerAmount   float64
	ExpiresAt     time.Time
}

const orderSelect = `
	SELECT o.id, o.order_id, o.kind, o.lease_id, o.rent_payment_id, o.payer_id, o.owner_id,
	       COALESCE(pu.name, ''), COALESCE(p.title, ''),
	       COALESCE(to_char(rp.due_date, 'FMMonth YYYY'), ''),
	       o.vendor_id, o.amount, o.rent_amount, o.late_days, o.late_fee, o.platform_fee, o.owner_amount,
	       o.status, o.payment_session_id, o.cf_payment_id, o.payment_method, o.attempts, o.failure_reason,
	       o.last_failed_at, o.expires_at, o.paid_at,
	       o.settlement_status, o.settlement_utr, o.settlement_amount, o.settled_at, o.created_at
	FROM payment_orders o
	JOIN leases l ON l.id = o.lease_id
	JOIN properties p ON p.id = l.property_id
	LEFT JOIN users pu ON pu.id = o.payer_id
	LEFT JOIN rent_payments rp ON rp.id = o.rent_payment_id
`

func scanOrder(row interface{ Scan(dest ...any) error }) (*models.PaymentOrder, error) {
	var o models.PaymentOrder
	err := row.Scan(&o.ID, &o.OrderID, &o.Kind, &o.LeaseID, &o.RentPaymentID, &o.PayerID, &o.OwnerID,
		&o.PayerName, &o.PropertyTitle, &o.PeriodLabel,
		&o.VendorID, &o.Amount, &o.RentAmount, &o.LateDays, &o.LateFee, &o.PlatformFee, &o.OwnerAmount,
		&o.Status, &o.PaymentSessionID, &o.CFPaymentID, &o.PaymentMethod, &o.Attempts, &o.FailureReason,
		&o.LastFailedAt, &o.ExpiresAt, &o.PaidAt,
		&o.SettlementStatus, &o.SettlementUTR, &o.SettlementAmount, &o.SettledAt, &o.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &o, nil
}

func (r *PaymentRepository) GetOrder(ctx context.Context, orderID string) (*models.PaymentOrder, error) {
	o, err := scanOrder(r.db.QueryRow(ctx, orderSelect+` WHERE o.order_id = $1`, orderID))
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrLeaseNotFound
		}
		return nil, err
	}
	return o, nil
}

// FindOpenOrder returns the order still waiting for payment for this rent month / deposit (nil if none).
func (r *PaymentRepository) FindOpenOrder(ctx context.Context, kind, leaseID, rentPaymentID string) (*models.PaymentOrder, error) {
	var row pgx.Row
	if kind == "rent" {
		row = r.db.QueryRow(ctx, orderSelect+` WHERE o.status = 'created' AND o.rent_payment_id = $1`, rentPaymentID)
	} else {
		row = r.db.QueryRow(ctx, orderSelect+` WHERE o.status = 'created' AND o.kind = 'deposit' AND o.lease_id = $1`, leaseID)
	}
	o, err := scanOrder(row)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return o, nil
}

// SupersedeOpen retires the open order(s) of a target and returns their Cashfree order ids,
// so the caller can terminate them at Cashfree.
func (r *PaymentRepository) SupersedeOpen(ctx context.Context, kind, leaseID, rentPaymentID string) ([]string, error) {
	var rows pgx.Rows
	var err error
	if kind == "rent" {
		rows, err = r.db.Query(ctx, `
			UPDATE payment_orders SET status = 'superseded', updated_at = now()
			WHERE status = 'created' AND rent_payment_id = $1 RETURNING order_id`, rentPaymentID)
	} else {
		rows, err = r.db.Query(ctx, `
			UPDATE payment_orders SET status = 'superseded', updated_at = now()
			WHERE status = 'created' AND kind = 'deposit' AND lease_id = $1 RETURNING order_id`, leaseID)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

func (r *PaymentRepository) InsertOrder(ctx context.Context, n NewOrder) error {
	var rentID any
	if n.RentPaymentID != "" {
		rentID = n.RentPaymentID
	}
	_, err := r.db.Exec(ctx, `
		INSERT INTO payment_orders (order_id, kind, lease_id, rent_payment_id, payer_id, owner_id, vendor_id,
		                            amount, rent_amount, late_days, late_fee, platform_fee, owner_amount, expires_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)`,
		n.OrderID, n.Kind, n.LeaseID, rentID, n.PayerID, n.OwnerID, n.VendorID,
		n.Amount, n.RentAmount, n.LateDays, n.LateFee, n.PlatformFee, n.OwnerAmount, n.ExpiresAt)
	if isUniqueViolation(err) {
		return ErrOpenOrderExists
	}
	return err
}

func (r *PaymentRepository) AttachCashfree(ctx context.Context, orderID, cfOrderID, sessionID string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE payment_orders SET cf_order_id = $2, payment_session_id = $3, updated_at = now()
		WHERE order_id = $1`, orderID, cfOrderID, sessionID)
	return err
}

// DropOrder removes an order row whose Cashfree order could not be created.
func (r *PaymentRepository) DropOrder(ctx context.Context, orderID string) {
	_, _ = r.db.Exec(ctx, `DELETE FROM payment_orders WHERE order_id = $1 AND status = 'created' AND payment_session_id = ''`, orderID)
}

func (r *PaymentRepository) ListLeaseOrders(ctx context.Context, leaseID string) ([]models.PaymentOrder, error) {
	return r.listOrders(ctx, orderSelect+` WHERE o.lease_id = $1 ORDER BY o.created_at DESC LIMIT 100`, leaseID)
}

func (r *PaymentRepository) ListOwnerOrders(ctx context.Context, ownerID string) ([]models.PaymentOrder, error) {
	return r.listOrders(ctx, orderSelect+` WHERE o.owner_id = $1 AND o.status IN ('paid', 'duplicate') ORDER BY o.paid_at DESC NULLS LAST LIMIT 200`, ownerID)
}

func (r *PaymentRepository) listOrders(ctx context.Context, q string, arg any) ([]models.PaymentOrder, error) {
	rows, err := r.db.Query(ctx, q, arg)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []models.PaymentOrder{}
	for rows.Next() {
		o, err := scanOrder(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *o)
	}
	return out, rows.Err()
}

func (r *PaymentRepository) OwnerTotals(ctx context.Context, ownerID string) (models.SettlementTotals, error) {
	var t models.SettlementTotals
	err := r.db.QueryRow(ctx, `
		SELECT COALESCE(SUM(owner_amount), 0),
		       COALESCE(SUM(owner_amount) FILTER (WHERE settlement_status = 'settled'), 0),
		       COALESCE(SUM(owner_amount) FILTER (WHERE settlement_status <> 'settled'), 0),
		       COALESCE(SUM(platform_fee), 0)
		FROM payment_orders WHERE owner_id = $1 AND status = 'paid'`, ownerID).
		Scan(&t.CollectedTotal, &t.SettledTotal, &t.PendingTotal, &t.PlatformFees)
	return t, err
}

// ---------------------------------------------------------------------------
// Applying a gateway result (shared by webhook + polling) — idempotent
// ---------------------------------------------------------------------------

const (
	OutcomeApplied        = "applied"
	OutcomeAlready        = "already_paid"
	OutcomeDuplicate      = "duplicate_payment"
	OutcomeAmountMismatch = "amount_mismatch"
	OutcomeNotFound       = "order_not_found"
)

const depositReceiptSQL = `'DP-' || to_char(now() AT TIME ZONE 'Asia/Kolkata', 'YYMM') || '-' || upper(substr(id::text, 1, 6))`

// ApplySuccess marks the order paid and updates the rent row / deposit in ONE transaction.
// Calling it twice for the same payment is safe.
func (r *PaymentRepository) ApplySuccess(ctx context.Context, orderID, cfPaymentID, group string, paidAmount float64) (string, *models.PaymentOrder, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return "", nil, err
	}
	defer tx.Rollback(ctx)

	var id, kind, leaseID, status string
	var rentID *string
	var amount, lateFee float64
	var lateDays int
	err = tx.QueryRow(ctx, `
		SELECT id, kind, lease_id, rent_payment_id, status, amount, late_fee, late_days
		FROM payment_orders WHERE order_id = $1 FOR UPDATE`, orderID).
		Scan(&id, &kind, &leaseID, &rentID, &status, &amount, &lateFee, &lateDays)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return OutcomeNotFound, nil, nil
		}
		return "", nil, err
	}
	if status == "paid" || status == "duplicate" {
		o, gerr := r.GetOrder(ctx, orderID)
		return OutcomeAlready, o, gerr
	}
	if math.Abs(paidAmount-amount) > 0.01 {
		_, err = tx.Exec(ctx, `
			UPDATE payment_orders SET failure_reason = $2, updated_at = now() WHERE id = $1`,
			id, fmt.Sprintf("amount mismatch: paid %.2f, expected %.2f - needs manual review", paidAmount, amount))
		if err == nil {
			err = tx.Commit(ctx)
		}
		return OutcomeAmountMismatch, nil, err
	}

	applied := false
	method := "online_" + group
	if group == "" {
		method = "online"
	}
	if kind == "rent" && rentID != nil {
		var rpStatus string
		if err := tx.QueryRow(ctx, `SELECT status FROM rent_payments WHERE id = $1 FOR UPDATE`, *rentID).Scan(&rpStatus); err != nil {
			return "", nil, err
		}
		if rpStatus != "paid" {
			_, err = tx.Exec(ctx, `
				UPDATE rent_payments
				SET status = 'paid', paid_at = now(), submitted_at = COALESCE(submitted_at, now()),
				    payment_method = $2, reference = $3, late_days = $4, late_fee = $5,
				    reject_reason = NULL, receipt_no = `+receiptNoSQL+`
				WHERE id = $1`, *rentID, method, cfPaymentID, lateDays, lateFee)
			if err != nil {
				return "", nil, err
			}
			applied = true
		}
	} else {
		var dStatus string
		err := tx.QueryRow(ctx, `SELECT status FROM lease_deposits WHERE lease_id = $1 FOR UPDATE`, leaseID).Scan(&dStatus)
		if err != nil {
			return "", nil, err
		}
		if dStatus == "pending" || dStatus == "submitted" {
			_, err = tx.Exec(ctx, `
				UPDATE lease_deposits
				SET status = 'held', received_at = now(), payment_method = $2, reference = $3,
				    receipt_no = `+depositReceiptSQL+`, updated_at = now()
				WHERE lease_id = $1`, leaseID, method, cfPaymentID)
			if err != nil {
				return "", nil, err
			}
			applied = true
		}
	}

	if applied {
		_, err = tx.Exec(ctx, `
			UPDATE payment_orders SET status = 'paid', cf_payment_id = $2, payment_method = $3,
			       paid_at = now(), failure_reason = '', updated_at = now() WHERE id = $1`, id, cfPaymentID, group)
		if err == nil {
			_, err = tx.Exec(ctx, `
				INSERT INTO lease_events (lease_id, actor_id, event, detail)
				VALUES ($1, 'system', $2, $3)`, leaseID, kind+"_paid_online",
				fmt.Sprintf("Rs. %.2f paid online (%s), ref %s", amount, group, cfPaymentID))
		}
	} else {
		// Money arrived but the rent/deposit was already settled another way -> flag for refund.
		_, err = tx.Exec(ctx, `
			UPDATE payment_orders SET status = 'duplicate', cf_payment_id = $2, payment_method = $3,
			       paid_at = now(), failure_reason = 'paid twice - refund needed', updated_at = now() WHERE id = $1`,
			id, cfPaymentID, group)
		if err == nil {
			_, err = tx.Exec(ctx, `
				INSERT INTO lease_events (lease_id, actor_id, event, detail)
				VALUES ($1, 'system', 'duplicate_payment', $2)`, leaseID,
				fmt.Sprintf("Rs. %.2f received online but the %s was already paid. Refund needed (ref %s)", amount, kind, cfPaymentID))
		}
	}
	if err != nil {
		return "", nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return "", nil, err
	}
	o, gerr := r.GetOrder(ctx, orderID)
	if applied {
		return OutcomeApplied, o, gerr
	}
	return OutcomeDuplicate, o, gerr
}

// RecordFailure remembers why the latest attempt failed. The order stays open: the user can retry.
func (r *PaymentRepository) RecordFailure(ctx context.Context, orderID string, attempts int, reason string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE payment_orders
		SET attempts = GREATEST(attempts, $2), failure_reason = $3, last_failed_at = now(), updated_at = now()
		WHERE order_id = $1 AND status = 'created'`, orderID, attempts, reason)
	return err
}

// CloseOrder moves an unpaid order to expired / cancelled.
func (r *PaymentRepository) CloseOrder(ctx context.Context, orderID, status string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE payment_orders SET status = $2, updated_at = now() WHERE order_id = $1 AND status = 'created'`, orderID, status)
	return err
}

// StaleOpenOrders: open orders old enough that a webhook should have arrived by now.
func (r *PaymentRepository) StaleOpenOrders(ctx context.Context, limit int) ([]string, error) {
	rows, err := r.db.Query(ctx, `
		SELECT order_id FROM payment_orders
		WHERE status = 'created' AND payment_session_id <> '' AND created_at < now() - interval '3 minutes'
		ORDER BY created_at LIMIT $1`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

// ---------------------------------------------------------------------------
// Settlement tracking
// ---------------------------------------------------------------------------

func (r *PaymentRepository) SettlementCandidates(ctx context.Context, limit int) ([]string, error) {
	rows, err := r.db.Query(ctx, `
		SELECT order_id FROM payment_orders
		WHERE status = 'paid' AND settlement_status = 'pending' AND paid_at < now() - interval '1 hour'
		  AND (settlement_checked_at IS NULL OR settlement_checked_at < now() - interval '6 hours')
		ORDER BY paid_at LIMIT $1`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

func (r *PaymentRepository) TouchSettlementChecked(ctx context.Context, orderID string) {
	_, _ = r.db.Exec(ctx, `UPDATE payment_orders SET settlement_checked_at = now() WHERE order_id = $1`, orderID)
}

func (r *PaymentRepository) SetSettled(ctx context.Context, orderID, settlementID, utr string, amount float64, at *time.Time) error {
	_, err := r.db.Exec(ctx, `
		UPDATE payment_orders
		SET settlement_status = 'settled', settlement_id = $2, settlement_utr = $3, settlement_amount = $4,
		    settled_at = COALESCE($5, now()), settlement_checked_at = now(), updated_at = now()
		WHERE order_id = $1 AND status = 'paid'`, orderID, settlementID, utr, amount, at)
	return err
}

func (r *PaymentRepository) SetSettlementFailed(ctx context.Context, orderID string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE payment_orders SET settlement_status = 'failed', settlement_checked_at = now(), updated_at = now()
		WHERE order_id = $1 AND status = 'paid' AND settlement_status <> 'settled'`, orderID)
	return err
}

// ---------------------------------------------------------------------------
// Webhook log (idempotency)
// ---------------------------------------------------------------------------

// InsertWebhookEvent returns false when this exact event was already received.
func (r *PaymentRepository) InsertWebhookEvent(ctx context.Context, key, typ, orderID string, payload []byte) (bool, error) {
	tag, err := r.db.Exec(ctx, `
		INSERT INTO payment_webhook_events (event_key, event_type, order_id, payload)
		VALUES ($1, $2, $3, $4::jsonb) ON CONFLICT (event_key) DO NOTHING`, key, typ, orderID, string(payload))
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() == 1, nil
}

func (r *PaymentRepository) SetWebhookResult(ctx context.Context, key, result string) {
	_, _ = r.db.Exec(ctx, `UPDATE payment_webhook_events SET result = $2 WHERE event_key = $1`, key, result)
}

// ForgetWebhookEvent lets Cashfree's retry be processed again after a temporary failure of ours.
func (r *PaymentRepository) ForgetWebhookEvent(ctx context.Context, key string) {
	_, _ = r.db.Exec(ctx, `DELETE FROM payment_webhook_events WHERE event_key = $1`, key)
}

func (r *PaymentRepository) DepositReceiptNo(ctx context.Context, leaseID string) (string, error) {
	var s *string
	err := r.db.QueryRow(ctx, `SELECT receipt_no FROM lease_deposits WHERE lease_id = $1`, leaseID).Scan(&s)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", ErrLeaseNotFound
		}
		return "", err
	}
	if s == nil {
		return "", nil
	}
	return *s, nil
}

// BumpFailure counts one more failed attempt (used by the failed-payment webhook).
func (r *PaymentRepository) BumpFailure(ctx context.Context, orderID, reason string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE payment_orders
		SET attempts = attempts + 1, failure_reason = $2, last_failed_at = now(), updated_at = now()
		WHERE order_id = $1 AND status = 'created'`, orderID, reason)
	return err
}