package migrations

import "embed"

// Files embeds all .sql migration files so they ship inside the compiled
// binary (Dockerfile only copies the built binary, not this folder).
//
//go:embed *.sql
var Files embed.FS