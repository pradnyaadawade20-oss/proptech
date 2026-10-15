package repository

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

// Commission is the agent's fee for one agreement, agreed before signing and paid by the tenant after.
type Commission struct {
	ID            string     `json:"id"`
	AgreementID   string     `json:"agreement_id"`
	AgentID       string     `json:"agent_id"`
	TenantID      string     `json:"tenant_id"`
	Amount        float64    `json:"amount"`
	Note          string     `json:"note"`
	Status        string     `json:"status"` // requested (tenant has not accepted) | accepted | paid
	PaymentMethod string     `json:"payment_method"`
	Reference     string     `json:"reference"`
	ReceiptNo     string     `json:"receipt_no"`
	PaidAt        *time.Time `json:"paid_at,omitempty"`
}

const commissionCols = `id, agreement_id, agent_id, tenant_id, amount, note, status,
	payment_method, reference, receipt_no, paid_at`

func scanCommission(row interface{ Scan(dest ...any) error }) (*Commission, error) {
	var c Commission
	if err := row.Scan(&c.ID, &c.AgreementID, &c.AgentID, &c.TenantID, &c.Amount, &c.Note, &c.Status,
		&c.PaymentMethod, &c.Reference, &c.ReceiptNo, &c.PaidAt); err != nil {
		return nil, err
	}
	return &c, nil
}

// AgreementParties: who the agent and tenant of an agreement are ("" agent = no broker).
func (r *LeaseRepository) AgreementParties(ctx context.Context, agreementID string) (agentID, tenantID, status string, err error) {
	err = r.db.QueryRow(ctx, `
		SELECT COALESCE(agent_id::text, ''), tenant_id::text, status
		FROM agreements WHERE id = $1`, agreementID).Scan(&agentID, &tenantID, &status)
	if errors.Is(err, pgx.ErrNoRows) {
		err = ErrLeaseNotFound
	}
	return
}

// LeaseIDForAgreement is "" until both parties have signed (the lease is created then).
func (r *LeaseRepository) LeaseIDForAgreement(ctx context.Context, agreementID string) (string, error) {
	var id string
	err := r.db.QueryRow(ctx, `SELECT id::text FROM leases WHERE agreement_id = $1`, agreementID).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", nil
	}
	return id, err
}

// GetCommission returns nil (and no error) when the agent has not proposed one yet.
func (r *LeaseRepository) GetCommission(ctx context.Context, agreementID string) (*Commission, error) {
	c, err := scanCommission(r.db.QueryRow(ctx, `SELECT `+commissionCols+` FROM lease_commissions WHERE agreement_id = $1`, agreementID))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	return c, err
}

// SetCommission lets the agent propose / change the amount. Locked once the tenant accepted it.
func (r *LeaseRepository) SetCommission(ctx context.Context, agreementID, agentID, tenantID string, amount float64, note string) (*Commission, error) {
	c, err := scanCommission(r.db.QueryRow(ctx, `
		INSERT INTO lease_commissions (agreement_id, agent_id, tenant_id, amount, note)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (agreement_id) DO UPDATE
		   SET amount = EXCLUDED.amount, note = EXCLUDED.note, updated_at = now()
		 WHERE lease_commissions.status = 'requested'
		RETURNING `+commissionCols, agreementID, agentID, tenantID, amount, note))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, badState("the tenant has already accepted this commission, so it can no longer be changed")
	}
	return c, err
}

// AcceptCommission: tenant agrees to the proposed amount (locks it).
func (r *LeaseRepository) AcceptCommission(ctx context.Context, agreementID, tenantID string) (*Commission, error) {
	c, err := scanCommission(r.db.QueryRow(ctx, `
		UPDATE lease_commissions SET status = 'accepted', accepted_at = now(), updated_at = now()
		WHERE agreement_id = $1 AND tenant_id = $2 AND status = 'requested'
		RETURNING `+commissionCols, agreementID, tenantID))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, badState("there is no commission waiting for your approval")
	}
	return c, err
}

// DeclineCommission: tenant says no; the proposal is removed so the agent can propose again.
func (r *LeaseRepository) DeclineCommission(ctx context.Context, agreementID, tenantID string) error {
	tag, err := r.db.Exec(ctx, `
		DELETE FROM lease_commissions
		WHERE agreement_id = $1 AND tenant_id = $2 AND status = 'requested'`, agreementID, tenantID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return badState("there is no commission waiting for your approval")
	}
	return nil
}

// AgentAgreementRow = one agreement of this agent with its commission (if any).
type AgentAgreementRow struct {
	AgreementID     string     `json:"agreement_id"`
	LeaseID         string     `json:"lease_id"`
	PropertyTitle   string     `json:"property_title"`
	TenantName      string     `json:"tenant_name"`
	AgreementStatus string     `json:"agreement_status"`
	Amount          float64    `json:"amount"`
	Note            string     `json:"note"`
	Status          string     `json:"status"` // "" (not proposed) | requested | accepted | paid
	PaymentMethod   string     `json:"payment_method"`
	Reference       string     `json:"reference"`
	ReceiptNo       string     `json:"receipt_no"`
	PaidAt          *time.Time `json:"paid_at,omitempty"`
}

func (r *LeaseRepository) ListAgentAgreements(ctx context.Context, agentID string) ([]AgentAgreementRow, error) {
	rows, err := r.db.Query(ctx, `
		SELECT a.id::text, COALESCE(l.id::text, ''), COALESCE(p.title, ''), COALESCE(t.name, ''), a.status,
		       COALESCE(c.amount, 0), COALESCE(c.note, ''), COALESCE(c.status, ''),
		       COALESCE(c.payment_method, ''), COALESCE(c.reference, ''), COALESCE(c.receipt_no, ''), c.paid_at
		FROM agreements a
		JOIN properties p ON p.id = a.property_id
		JOIN users t ON t.id = a.tenant_id
		LEFT JOIN leases l ON l.agreement_id = a.id
		LEFT JOIN lease_commissions c ON c.agreement_id = a.id
		WHERE a.agent_id = $1 AND a.status NOT IN ('rejected', 'cancelled', 'expired')
		ORDER BY a.created_at DESC`, agentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []AgentAgreementRow{}
	for rows.Next() {
		var x AgentAgreementRow
		if err := rows.Scan(&x.AgreementID, &x.LeaseID, &x.PropertyTitle, &x.TenantName, &x.AgreementStatus,
			&x.Amount, &x.Note, &x.Status, &x.PaymentMethod, &x.Reference, &x.ReceiptNo, &x.PaidAt); err != nil {
			return nil, err
		}
		out = append(out, x)
	}
	return out, rows.Err()
}