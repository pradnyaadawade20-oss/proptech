package repository

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"proptech-backend/internal/models"
)

// maxPageSize caps ?limit= so one request can't pull the whole table.
const maxPageSize = 100

// distanceExpr is the Haversine distance (km) from ($lat,$lng) to a row.
func distanceExpr(latPH, lngPH string) string {
	return fmt.Sprintf(
		"(6371 * acos(LEAST(1, GREATEST(-1, cos(radians(%[1]s::float8)) * cos(radians(latitude)) * cos(radians(longitude) - radians(%[2]s::float8)) + sin(radians(%[1]s::float8)) * sin(radians(latitude))))))",
		latPH, lngPH)
}

func lowerAll(in []string) []string {
	out := make([]string, 0, len(in))
	for _, s := range in {
		if s = strings.ToLower(strings.TrimSpace(s)); s != "" {
			out = append(out, s)
		}
	}
	return out
}

// BuildPropertySearch turns a filter into a WHERE clause ("" or "WHERE ..."),
// its positional args, and an ORDER BY clause. Pure function (no DB) so it is
// easy to unit-test. Every user value goes through a $n placeholder.
func BuildPropertySearch(f models.PropertyFilter) (where string, args []any, orderBy string) {
	var conds []string
	add := func(v any) string {
		args = append(args, v)
		return "$" + strconv.Itoa(len(args))
	}

	if q := strings.TrimSpace(f.Query); q != "" {
		ph := add("%" + q + "%")
		conds = append(conds, "(title || ' ' || location || ' ' || city || ' ' || locality || ' ' || society) ILIKE "+ph)
	}
	if v := strings.TrimSpace(f.Location); v != "" {
		ph := add("%" + v + "%")
		conds = append(conds, fmt.Sprintf("(location ILIKE %[1]s OR city ILIKE %[1]s OR locality ILIKE %[1]s)", ph))
	}
	if v := strings.TrimSpace(f.City); v != "" {
		conds = append(conds, "LOWER(city) = "+add(strings.ToLower(v)))
	}
	if v := strings.TrimSpace(f.Locality); v != "" {
		conds = append(conds, "locality ILIKE "+add("%"+v+"%"))
	}
	if b := lowerAll(f.BHK); len(b) > 0 {
		conds = append(conds, "LOWER(bhk) = ANY("+add(b)+"::text[])")
	}
	if fu := lowerAll(f.Furnishing); len(fu) > 0 {
		conds = append(conds, "LOWER(furnishing) = ANY("+add(fu)+"::text[])")
	}
	if v := strings.TrimSpace(f.Category); v != "" {
		conds = append(conds, "LOWER(category) = "+add(strings.ToLower(v)))
	}
	if v := strings.TrimSpace(f.ListingStatus); v != "" {
		conds = append(conds, "listing_status = "+add(strings.ToLower(v)))
	}
	if v := strings.TrimSpace(f.PostedBy); v != "" {
		conds = append(conds, "posted_by = "+add(strings.ToLower(v)))
	}
	if f.MinPrice != nil {
		conds = append(conds, "price >= "+add(*f.MinPrice))
	}
	if f.MaxPrice != nil {
		conds = append(conds, "price <= "+add(*f.MaxPrice))
	}
	if f.MinArea != nil {
		conds = append(conds, "area_sqft >= "+add(*f.MinArea))
	}
	if f.MaxArea != nil {
		conds = append(conds, "area_sqft <= "+add(*f.MaxArea))
	}
	if f.MinBathrooms != nil {
		conds = append(conds, "bathrooms >= "+add(*f.MinBathrooms))
	}
	if f.VerifiedOnly {
		conds = append(conds, "is_verified = TRUE")
	}
	if len(f.Amenities) > 0 {
		conds = append(conds, "amenities @> "+add(f.Amenities)+"::text[]")
	}

	// Map viewport (bounding box).
	if f.MinLat != nil && f.MaxLat != nil && f.MinLng != nil && f.MaxLng != nil {
		conds = append(conds, "latitude BETWEEN "+add(*f.MinLat)+" AND "+add(*f.MaxLat))
		conds = append(conds, "longitude BETWEEN "+add(*f.MinLng)+" AND "+add(*f.MaxLng))
	}

	// "Near me": radius around a point. Rows without coordinates are skipped.
	hasGeo := f.Lat != nil && f.Lng != nil
	var dist string
	if hasGeo {
		latPH, lngPH := add(*f.Lat), add(*f.Lng)
		dist = distanceExpr(latPH, lngPH)
		conds = append(conds, "(latitude <> 0 OR longitude <> 0)")
		if f.RadiusKm != nil && *f.RadiusKm > 0 {
			conds = append(conds, dist+" <= "+add(*f.RadiusKm))
		}
	}

	if len(conds) > 0 {
		where = "WHERE " + strings.Join(conds, " AND ")
	}

	switch f.Sort {
	case "price_asc", "price_low":
		orderBy = "ORDER BY price ASC, id"
	case "price_desc", "price_high":
		orderBy = "ORDER BY price DESC, id"
	case "rating":
		orderBy = "ORDER BY rating DESC, review_count DESC, id"
	case "area_large":
		orderBy = "ORDER BY area_sqft DESC, id"
	case "distance":
		if hasGeo {
			orderBy = "ORDER BY " + dist + " ASC, id"
		} else {
			orderBy = "ORDER BY created_at DESC, id"
		}
	default: // "", "newest"
		orderBy = "ORDER BY created_at DESC, id"
	}
	return where, args, orderBy
}

// Search returns one page of matching properties plus the total match count.
// f.Limit <= 0 means "no paging" (legacy behaviour: return everything).
func (r *PropertyRepository) Search(ctx context.Context, f models.PropertyFilter) ([]models.Property, int, error) {
	where, args, orderBy := BuildPropertySearch(f)

	var total int
	if err := r.db.QueryRow(ctx, "SELECT COUNT(*) FROM properties "+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	query := "SELECT " + propertyColumns + " FROM properties " + where + " " + orderBy
	if f.Limit > 0 {
		limit := f.Limit
		if limit > maxPageSize {
			limit = maxPageSize
		}
		page := f.Page
		if page < 1 {
			page = 1
		}
		args = append(args, limit, (page-1)*limit)
		query += fmt.Sprintf(" LIMIT $%d OFFSET $%d", len(args)-1, len(args))
	}

	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	properties := []models.Property{} // [] not null in JSON
	for rows.Next() {
		var p models.Property
		if err := rows.Scan(propertyDests(&p)...); err != nil {
			return nil, 0, err
		}
		properties = append(properties, p)
	}
	return properties, total, rows.Err()
}
