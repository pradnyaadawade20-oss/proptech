package repository

import "context"

// CommissionSigned says whether the tenant has signed the broker's commission agreement for this property.
// A tenant cannot request a rental agreement for a broker listing until this is true.
func (r *AgreementRepository) CommissionSigned(ctx context.Context, propertyID, tenantID string) (bool, error) {
	var ok bool
	err := r.db.QueryRow(ctx, `
		SELECT EXISTS (SELECT 1 FROM commission_agreements
		               WHERE property_id = $1 AND tenant_id = $2 AND status = 'signed')`,
		propertyID, tenantID).Scan(&ok)
	return ok, err
}