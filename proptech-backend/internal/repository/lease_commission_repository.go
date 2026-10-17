package repository

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// CommissionAgreement is the agreement between a broker (agent) and a tenant about the broker's commission.
// Flow: broker creates + signs ("sent") -> tenant signs ("signed") -> after the rental agreement is
// completed the tenant pays it through Cashfree (pay_status "paid").
type CommissionAgreement struct {
	ID              string     `json:"id"`
	AgreementNumber string     `json:"agreement_number"`
	PropertyID      string     `json:"property_id"`
	PropertyTitle   string     `json:"property_title"`
	AgentID         string     `json:"agent_id"`
	AgentName       string     `json:"agent_name"`
	TenantID        string     `json:"tenant_id"`
	TenantName      string     `json:"tenant_name"`
	Amount          float64    `json:"amount"`
	Note            string     `json:"note"`
	Status          string     `json:"status"` // sent | signed | declined | cancelled
	AgentSignType   string     `json:"-"`
	AgentSignData   string     `json:"-"`
	AgentSignedAt   *time.Time `json:"agent_signed_at,omitempty"`
	TenantSignType  string     `json:"-"`
	TenantSignData  string     `json:"-"`
	TenantSignedAt  *time.Time `json:"tenant_signed_at,omitempty"`
	PayStatus       string     `json:"pay_status"` // unpaid | paid
	PaymentMethod   string     `json:"payment_method"`
	Reference       string     `json:"reference"`
	ReceiptNo       string     `json:"receipt_no"`
	PaidAt          *time.Time `json:"paid_at,omitempty"`
	CreatedAt       time.Time  `json:"created_at"`
	LeaseID         string     `json:"lease_id"` // "" until the rental agreement is completed
	Role            string     `json:"role"`     // set per request: agent | tenant
}

const commissionAgreementSelect = `
	SELECT ca.id::text, ca.agreement_number, ca.property_id::text, COALESCE(p.title, ''),
	       ca.agent_id::text, COALESCE(ag.name, ''), ca.tenant_id::text, COALESCE(t.name, ''),
	       ca.amount, ca.note, ca.status,
	       ca.agent_sign_type, ca.agent_sign_data, ca.agent_signed_at,
	       ca.tenant_sign_type, ca.tenant_sign_data, ca.tenant_signed_at,
	       ca.pay_status, ca.payment_method, ca.reference, ca.receipt_no, ca.paid_at, ca.created_at,
	       COALESCE((SELECT l.id::text FROM leases l JOIN agreements a ON a.id = l.agreement_id
	                 WHERE a.property_id = ca.property_id AND a.tenant_id = ca.tenant_id
	                 ORDER BY l.created_at DESC LIMIT 1), '')
	FROM commission_agreements ca
	JOIN properties p ON p.id = ca.property_id
	JOIN users ag ON ag.id = ca.agent_id
	JOIN users t ON t.id = ca.tenant_id
`

func scanCommissionAgreement(row interface{ Scan(dest ...any) error }) (*CommissionAgreement, error) {
	var c CommissionAgreement
	if err := row.Scan(&c.ID, &c.AgreementNumber, &c.PropertyID, &c.PropertyTitle,
		&c.AgentID, &c.AgentName, &c.TenantID, &c.TenantName,
		&c.Amount, &c.Note, &c.Status,
		&c.AgentSignType, &c.AgentSignData, &c.AgentSignedAt,
		&c.TenantSignType, &c.TenantSignData, &c.TenantSignedAt,
		&c.PayStatus, &c.PaymentMethod, &c.Reference, &c.ReceiptNo, &c.PaidAt, &c.CreatedAt,
		&c.LeaseID); err != nil {
		return nil, err
	}
	return &c, nil
}

// PropertyPoster tells who posted the property and how ("broker" | "owner").
func (r *LeaseRepository) PropertyPoster(ctx context.Context, propertyID string) (ownerID, postedBy string, err error) {
	err = r.db.QueryRow(ctx, `SELECT COALESCE(owner_id::text, ''), COALESCE(posted_by, 'owner') FROM properties WHERE id = $1`,
		propertyID).Scan(&ownerID, &postedBy)
	if errors.Is(err, pgx.ErrNoRows) {
		err = ErrLeaseNotFound
	}
	return
}

// UserByEmail finds a PropTech account by email (case-insensitive).
func (r *LeaseRepository) UserByEmail(ctx context.Context, email string) (id, name string, err error) {
	err = r.db.QueryRow(ctx, `SELECT id::text, COALESCE(name, '') FROM users WHERE lower(email) = lower($1) LIMIT 1`,
		strings.TrimSpace(email)).Scan(&id, &name)
	if errors.Is(err, pgx.ErrNoRows) {
		err = ErrLeaseNotFound
	}
	return
}

func (r *LeaseRepository) CreateCommissionAgreement(ctx context.Context, propertyID, agentID, tenantID string,
	amount float64, note, signType, signData string) (*CommissionAgreement, error) {
	var id string
	err := r.db.QueryRow(ctx, `
		INSERT INTO commission_agreements
		  (agreement_number, property_id, agent_id, tenant_id, amount, note, status,
		   agent_sign_type, agent_sign_data, agent_signed_at)
		VALUES ('CA-' || to_char(now(), 'YYMMDD') || '-' || upper(substr(md5(random()::text), 1, 6)),
		        $1, $2, $3, $4, $5, 'sent', $6, $7, now())
		RETURNING id::text`,
		propertyID, agentID, tenantID, amount, note, signType, signData).Scan(&id)
	if err != nil {
		if strings.Contains(err.Error(), "uq_commission_active") {
			return nil, badState("a commission agreement for this tenant and property already exists")
		}
		return nil, err
	}
	return r.GetCommissionAgreement(ctx, id)
}

func (r *LeaseRepository) GetCommissionAgreement(ctx context.Context, id string) (*CommissionAgreement, error) {
	c, err := scanCommissionAgreement(r.db.QueryRow(ctx, commissionAgreementSelect+` WHERE ca.id = $1`, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrLeaseNotFound
	}
	return c, err
}

// ListCommissionAgreements = everything where the user is the agent or the tenant, newest first.
func (r *LeaseRepository) ListCommissionAgreements(ctx context.Context, userID string) ([]CommissionAgreement, error) {
	rows, err := r.db.Query(ctx, commissionAgreementSelect+`
		WHERE ca.agent_id = $1 OR ca.tenant_id = $1
		ORDER BY ca.created_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []CommissionAgreement{}
	for rows.Next() {
		c, err := scanCommissionAgreement(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *c)
	}
	return out, rows.Err()
}

// SignCommissionAgreement: the tenant signs. Only works while the agreement is "sent".
func (r *LeaseRepository) SignCommissionAgreement(ctx context.Context, id, tenantID, signType, signData string) (*CommissionAgreement, error) {
	tag, err := r.db.Exec(ctx, `
		UPDATE commission_agreements
		SET status = 'signed', tenant_sign_type = $3, tenant_sign_data = $4, tenant_signed_at = now(), updated_at = now()
		WHERE id = $1 AND tenant_id = $2 AND status = 'sent'`, id, tenantID, signType, signData)
	if err != nil {
		return nil, err
	}
	if tag.RowsAffected() == 0 {
		return nil, badState("this commission agreement is no longer waiting for your signature")
	}
	return r.GetCommissionAgreement(ctx, id)
}

// DeclineCommissionAgreement: the tenant says no (the broker can send a new one).
func (r *LeaseRepository) DeclineCommissionAgreement(ctx context.Context, id, tenantID string) error {
	tag, err := r.db.Exec(ctx, `
		UPDATE commission_agreements SET status = 'declined', updated_at = now()
		WHERE id = $1 AND tenant_id = $2 AND status = 'sent'`, id, tenantID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return badState("this commission agreement is no longer waiting for your answer")
	}
	return nil
}

// CancelCommissionAgreement: the broker withdraws it before the tenant signs.
func (r *LeaseRepository) CancelCommissionAgreement(ctx context.Context, id, agentID string) error {
	tag, err := r.db.Exec(ctx, `
		UPDATE commission_agreements SET status = 'cancelled', updated_at = now()
		WHERE id = $1 AND agent_id = $2 AND status = 'sent'`, id, agentID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return badState("only an agreement the tenant has not signed yet can be cancelled")
	}
	return nil
}

// CommissionAgreementForLease: the signed commission agreement belonging to this lease (property + tenant).
func (r *LeaseRepository) CommissionAgreementForLease(ctx context.Context, leaseID string) (*CommissionAgreement, error) {
	c, err := scanCommissionAgreement(r.db.QueryRow(ctx, commissionAgreementSelect+`
		WHERE ca.status = 'signed' AND EXISTS (
		  SELECT 1 FROM leases l JOIN agreements a ON a.id = l.agreement_id
		  WHERE l.id = $1 AND a.property_id = ca.property_id AND a.tenant_id = ca.tenant_id)
		ORDER BY ca.created_at DESC LIMIT 1`, leaseID))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	return c, err
}