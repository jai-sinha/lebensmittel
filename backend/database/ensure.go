package database

import (
	"context"
	"fmt"
	"log"
)

// delete this file once changes are live

// create the change-ledger table and index
func EnsureSchema() error {
	statements := []string{
		`CREATE TABLE IF NOT EXISTS group_change_log (
			seq BIGSERIAL PRIMARY KEY,
			group_id TEXT NOT NULL,
			entity_type TEXT NOT NULL,
			entity_id  TEXT NOT NULL,   -- no FK: hard-deletes keep only the id
			change_type TEXT NOT NULL,
			changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
		)`,
		`CREATE INDEX IF NOT EXISTS group_change_log_group_seq ON group_change_log(group_id, seq)`,
	}
	for _, statement := range statements {
		if _, err := db.Exec(context.Background(), statement); err != nil {
			return fmt.Errorf("failed to ensure schema: %w", err)
		}
	}
	log.Println("Schema ensured")
	return nil
}

// schedule a nightly pg_cron job that prunes ledger rows older than 30 days
func EnsurePruneJob() {
	if _, err := db.Exec(context.Background(), "CREATE EXTENSION IF NOT EXISTS pg_cron"); err != nil {
		log.Printf("pg_cron unavailable, skipping ledger prune job: %v", err)
		return
	}
	if _, err := db.Exec(context.Background(), `SELECT cron.schedule(
		'prune_group_change_log', '0 3 * * *',
		$$DELETE FROM group_change_log WHERE changed_at < now() - interval '30 days'$$
	)`); err != nil {
		// workaround for dev
		log.Printf("failed to schedule ledger prune job: %v", err)
	}
}
