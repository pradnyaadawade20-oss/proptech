package repository

import (
	"context"

	"proptech-backend/internal/models"
)

// RecordView counts one view per viewer per day.
func (r *PropertyRepository) RecordView(ctx context.Context, propertyID, viewerKey string) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO property_views (property_id, viewer_key, view_date)
		VALUES ($1, $2, (now() AT TIME ZONE 'Asia/Kolkata')::date)
		ON CONFLICT (property_id, viewer_key, view_date) DO NOTHING`, propertyID, viewerKey)
	return err
}

// OwnerStats returns views / interested / saved / enquiries for every listing of the owner.
func (r *PropertyRepository) OwnerStats(ctx context.Context, ownerID string) ([]models.PropertyStat, error) {
	rows, err := r.db.Query(ctx, `
		SELECT p.id,
		       (SELECT COUNT(DISTINCT v.viewer_key) FROM property_views v WHERE v.property_id = p.id),
		       (SELECT COUNT(*) FROM (
		            SELECT f.user_id FROM favorites f WHERE f.property_id = p.id AND f.user_id IS NOT NULL
		            UNION
		            SELECT l.buyer_id FROM leads l WHERE l.property_id = p.id
		        ) u),
		       (SELECT COUNT(*) FROM favorites f WHERE f.property_id = p.id),
		       (SELECT COUNT(*) FROM leads l WHERE l.property_id = p.id)
		FROM properties p
		WHERE p.owner_id = $1`, ownerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []models.PropertyStat{}
	for rows.Next() {
		var s models.PropertyStat
		if err := rows.Scan(&s.PropertyID, &s.Views, &s.Interested, &s.Saved, &s.Enquiries); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}