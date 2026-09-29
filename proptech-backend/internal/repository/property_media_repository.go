package repository

import (
	"context"
	"fmt"

	"proptech-backend/internal/models"
)

// MediaRef is the lightweight (no bytes) description of one stored
// photo/video, used to build the URLs sent to the app.
type MediaRef struct {
	ID         string
	PropertyID string
	Kind       string // "image" | "video"
}

// SaveMedia stores one extra photo or the walkthrough video for a property
// and returns the new media id. A property has at most one video, so
// saving a new one replaces the old one.
func (r *PropertyRepository) SaveMedia(ctx context.Context, propertyID, kind, contentType string, data []byte) (string, error) {
	if kind == "video" {
		if _, err := r.db.Exec(ctx,
			`DELETE FROM property_media WHERE property_id = $1 AND kind = 'video'`, propertyID); err != nil {
			return "", err
		}
	}
	var id string
	err := r.db.QueryRow(ctx, `
		INSERT INTO property_media (property_id, kind, content_type, data)
		VALUES ($1, $2, $3, $4)
		RETURNING id
	`, propertyID, kind, contentType, data).Scan(&id)
	return id, err
}

// CountMedia returns how many media rows of the given kind a property has.
func (r *PropertyRepository) CountMedia(ctx context.Context, propertyID, kind string) (int, error) {
	var n int
	err := r.db.QueryRow(ctx,
		`SELECT COUNT(*) FROM property_media WHERE property_id = $1 AND kind = $2`,
		propertyID, kind).Scan(&n)
	return n, err
}

// GetMedia returns the raw bytes + content type of one stored photo/video.
func (r *PropertyRepository) GetMedia(ctx context.Context, propertyID, mediaID string) ([]byte, string, error) {
	var data []byte
	var contentType string
	err := r.db.QueryRow(ctx, `
		SELECT data, content_type FROM property_media
		WHERE id = $1 AND property_id = $2
	`, mediaID, propertyID).Scan(&data, &contentType)
	if err != nil {
		return nil, "", err
	}
	return data, contentType, nil
}

// ListMedia returns the media (without bytes) for the given properties,
// in upload order.
func (r *PropertyRepository) ListMedia(ctx context.Context, propertyIDs []string) ([]MediaRef, error) {
	if len(propertyIDs) == 0 {
		return nil, nil
	}
	rows, err := r.db.Query(ctx, `
		SELECT id, property_id, kind FROM property_media
		WHERE property_id::text = ANY($1)
		ORDER BY position
	`, propertyIDs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var refs []MediaRef
	for rows.Next() {
		var m MediaRef
		if err := rows.Scan(&m.ID, &m.PropertyID, &m.Kind); err != nil {
			return nil, err
		}
		refs = append(refs, m)
	}
	return refs, rows.Err()
}

// MediaURLs turns media refs into the app-facing fields: extra photo URLs
// and the video URL ("" when there's none).
func MediaURLs(refs []MediaRef, baseURL string) (images []string, video string) {
	images = []string{}
	for _, m := range refs {
		url := fmt.Sprintf("%s/api/properties/%s/media/%s", baseURL, m.PropertyID, m.ID)
		if m.Kind == "video" {
			video = url
		} else {
			images = append(images, url)
		}
	}
	return images, video
}

// AttachMedia fills AdditionalImageURLs / VideoTourURL on each property
// (best effort — a failure here just leaves the extras empty).
func (r *PropertyRepository) AttachMedia(ctx context.Context, props []models.Property, baseURL string) {
	if len(props) == 0 {
		return
	}
	ids := make([]string, 0, len(props))
	for _, p := range props {
		ids = append(ids, p.ID)
	}
	refs, err := r.ListMedia(ctx, ids)
	if err != nil {
		for i := range props {
			props[i].AdditionalImageURLs = []string{}
		}
		return
	}
	byProp := map[string][]MediaRef{}
	for _, m := range refs {
		byProp[m.PropertyID] = append(byProp[m.PropertyID], m)
	}
	for i := range props {
		images, video := MediaURLs(byProp[props[i].ID], baseURL)
		props[i].AdditionalImageURLs = images
		if video != "" {
			v := video
			props[i].VideoTourURL = &v
		}
	}
}