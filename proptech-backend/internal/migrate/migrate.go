package migrate

import (
	"bytes"
	"context"
	"embed"
	"fmt"
	"log"
	"sort"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Run applies every *.sql file in files, in filename order, that hasn't
// already been recorded in the schema_migrations table. Safe to call on
// every startup: already-applied files are skipped.
func Run(ctx context.Context, pool *pgxpool.Pool, files embed.FS) error {
	if _, err := pool.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS schema_migrations (
			filename    TEXT PRIMARY KEY,
			applied_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)
	`); err != nil {
		return fmt.Errorf("create schema_migrations table: %w", err)
	}

	entries, err := files.ReadDir(".")
	if err != nil {
		return fmt.Errorf("read embedded migrations: %w", err)
	}

	var names []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".sql") {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)

	for _, name := range names {
		var already bool
		err := pool.QueryRow(ctx,
			`SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE filename = $1)`, name,
		).Scan(&already)
		if err != nil {
			return fmt.Errorf("check migration %s: %w", name, err)
		}
		if already {
			continue
		}

		sqlBytes, err := files.ReadFile(name)
		if err != nil {
			return fmt.Errorf("read migration %s: %w", name, err)
		}
		// Strip a leading UTF-8 BOM (EF BB BF) if present. Some files were
		// saved with one (e.g. by editors on Windows) and Postgres treats
		// it as a syntax error rather than whitespace.
		sqlBytes = bytes.TrimPrefix(sqlBytes, []byte{0xEF, 0xBB, 0xBF})

		tx, err := pool.Begin(ctx)
		if err != nil {
			return fmt.Errorf("begin tx for %s: %w", name, err)
		}

		if _, err := tx.Exec(ctx, string(sqlBytes)); err != nil {
			tx.Rollback(ctx)
			return fmt.Errorf("apply migration %s: %w", name, err)
		}

		if _, err := tx.Exec(ctx,
			`INSERT INTO schema_migrations (filename) VALUES ($1)`, name,
		); err != nil {
			tx.Rollback(ctx)
			return fmt.Errorf("record migration %s: %w", name, err)
		}

		if err := tx.Commit(ctx); err != nil {
			return fmt.Errorf("commit migration %s: %w", name, err)
		}

		log.Println("Applied migration:", name)
	}

	return nil
}
