package repository

// Deposit refund through Cashfree: the paid deposit order and the refund's progress.

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
)

// PaidDepositOrder is the Cashfree order the tenant paid the deposit with, or nil (paid outside the app).
func (r *LeaseRepository) PaidDepositOrder(ctx context.Context, leaseID string) (*PaymentOrder, error) {
	o, err := scanOrder(r.db.QueryRow(ctx,
		orderSelect+` WHERE lease_id = $1 AND kind = 'deposit' AND status = 'paid' ORDER BY paid_at DESC NULLS LAST LIMIT 1`, leaseID))
	if errors.Is(err, ErrLeaseNotFound) {
		return nil, nil
	}
	return o, err
}

// OnlineRefund returns the stored Cashfree refund id and status of a deposit ("" when none yet).
func (r *LeaseRepository) OnlineRefund(ctx context.Context, leaseID string) (refundID, status string, err error) {
	err = r.db.QueryRow(ctx, `SELECT cf_refund_id, cf_refund_status FROM lease_deposits WHERE lease_id = $1`, leaseID).
		Scan(&refundID, &status)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", "", ErrLeaseNotFound
	}
	return
}

func (r *LeaseRepository) SaveOnlineRefund(ctx context.Context, leaseID, refundID, status string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE lease_deposits SET cf_refund_id = $2, cf_refund_status = $3, updated_at = now()
		WHERE lease_id = $1`, leaseID, refundID, status)
	return err
}