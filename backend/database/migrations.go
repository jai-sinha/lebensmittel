package database

import (
	"context"
	"fmt"
	"log"

	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"
)

// RunMigrations executes database migrations
func RunMigrations(ctx context.Context) error {
	log.Println("Running migrations...")

	// 1. Create groups table
	if err := createGroupsTable(ctx); err != nil {
		return fmt.Errorf("failed to create groups table: %w", err)
	}

	// 2. Create users table
	if err := createUsersTable(ctx); err != nil {
		return fmt.Errorf("failed to create users table: %w", err)
	}

	// 3. Create user_groups table
	if err := createUserGroupsTable(ctx); err != nil {
		return fmt.Errorf("failed to create user_groups table: %w", err)
	}

	// 4. Create join_codes table
	if err := createJoinCodesTable(ctx); err != nil {
		return fmt.Errorf("failed to create join_codes table: %w", err)
	}

	// 5. Seed initial data if empty
	if err := seedInitialData(ctx); err != nil {
		return fmt.Errorf("failed to seed initial data: %w", err)
	}

	// 6. Migrate existing tables (add columns and backfill)
	if err := migrateExistingTables(ctx); err != nil {
		return fmt.Errorf("failed to migrate existing tables: %w", err)
	}

	log.Println("Migrations completed successfully")
	return nil
}

func createGroupsTable(ctx context.Context) error {
	query := `
	CREATE TABLE IF NOT EXISTS groups (
		id VARCHAR(36) PRIMARY KEY,
		name VARCHAR(255) NOT NULL
	);`
	_, err := db.Exec(ctx, query)
	return err
}

func createUsersTable(ctx context.Context) error {
	query := `
	CREATE TABLE IF NOT EXISTS users (
		id VARCHAR(36) PRIMARY KEY,
		username VARCHAR(255) NOT NULL UNIQUE,
		password_hash VARCHAR(255) NOT NULL,
		display_name VARCHAR(255) NOT NULL
	);`
	_, err := db.Exec(ctx, query)
	return err
}

func createUserGroupsTable(ctx context.Context) error {
	query := `
	CREATE TABLE IF NOT EXISTS user_groups (
		user_id VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		group_id VARCHAR(36) NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
		PRIMARY KEY (user_id, group_id)
	);`
	_, err := db.Exec(ctx, query)
	return err
}

func createJoinCodesTable(ctx context.Context) error {
	query := `
	CREATE TABLE IF NOT EXISTS join_codes (
		code VARCHAR(8) PRIMARY KEY,
		group_id VARCHAR(36) NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
		expires_at TIMESTAMP NOT NULL,
		created_by VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE
	);`
	_, err := db.Exec(ctx, query)
	return err
}

func seedInitialData(ctx context.Context) error {
	// Check if any groups exist
	var count int
	err := db.QueryRow(ctx, "SELECT COUNT(*) FROM groups").Scan(&count)
	if err != nil {
		return err
	}

	if count > 0 {
		log.Println("Data already exists, skipping seed")
		return nil
	}

	log.Println("Seeding initial data...")

	// Create initial group
	groupID := uuid.New().String()
	groupName := "Our Household"
	_, err = db.Exec(ctx, "INSERT INTO groups (id, name) VALUES ($1, $2)", groupID, groupName)
	if err != nil {
		return fmt.Errorf("failed to seed group: %w", err)
	}

	// Create initial users
	// Note: In a real app, passwords should be properly hashed.
	// For this migration, we'll use a simple default password "password"
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte("password"), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("failed to hash password: %w", err)
	}

	users := []struct {
		Username    string
		DisplayName string
	}{
		{"jsinha", "Jai"},
		{"hweppner", "Hanna"}, // Placeholder, user can update later
	}

	for _, u := range users {
		userID := uuid.New().String()
		_, err := db.Exec(ctx,
			"INSERT INTO users (id, username, password_hash, display_name) VALUES ($1, $2, $3, $4)",
			userID, u.Username, string(hashedPassword), u.DisplayName,
		)
		if err != nil {
			return fmt.Errorf("failed to seed user %s: %w", u.Username, err)
		}

		// Add to group
		_, err = db.Exec(ctx, "INSERT INTO user_groups (user_id, group_id) VALUES ($1, $2)", userID, groupID)
		if err != nil {
			return fmt.Errorf("failed to add user %s to group: %w", u.Username, err)
		}
	}

	log.Printf("Seeded group '%s' and %d users", groupName, len(users))
	return nil
}

func migrateExistingTables(ctx context.Context) error {
	// Migrate users.group_id to user_groups if it exists
	var exists bool
	err := db.QueryRow(ctx, "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='group_id')").Scan(&exists)
	if err == nil && exists {
		log.Println("Migrating users.group_id to user_groups table...")
		_, err := db.Exec(ctx, `
			INSERT INTO user_groups (user_id, group_id)
			SELECT id, group_id FROM users WHERE group_id IS NOT NULL
			ON CONFLICT DO NOTHING
		`)
		if err != nil {
			return fmt.Errorf("failed to migrate user groups: %w", err)
		}

		// Drop the column
		_, err = db.Exec(ctx, "ALTER TABLE users DROP COLUMN group_id")
		if err != nil {
			return fmt.Errorf("failed to drop group_id from users: %w", err)
		}
	}

	// We need a default group ID and user ID for backfilling.
	// We'll try to find the ones created by seedInitialData.
	var groupID string
	err = db.QueryRow(ctx, "SELECT id FROM groups WHERE name = 'Our Household' LIMIT 1").Scan(&groupID)
	if err != nil {
		// Fallback to any group
		err = db.QueryRow(ctx, "SELECT id FROM groups LIMIT 1").Scan(&groupID)
		if err != nil {
			// If no groups exist, we can't backfill, but that might be okay if tables are empty
			log.Println("Warning: No groups found for backfilling")
		}
	}

	var userID string
	err = db.QueryRow(ctx, "SELECT id FROM users WHERE username = 'jsinha' LIMIT 1").Scan(&userID)
	if err != nil {
		// Fallback to any user
		err = db.QueryRow(ctx, "SELECT id FROM users LIMIT 1").Scan(&userID)
		if err != nil {
			log.Println("Warning: No users found for backfilling")
		}
	}

	if groupID != "" && userID != "" {
		tables := []string{"grocery_items", "meal_plans", "receipts"}

		for _, table := range tables {
			// Add group_id column
			if err := addColumnIfNotExists(ctx, table, "group_id", "VARCHAR(36)"); err != nil {
				return err
			}
			// Add user_id column
			if err := addColumnIfNotExists(ctx, table, "user_id", "VARCHAR(36)"); err != nil {
				return err
			}

			// Backfill group_id
			query := fmt.Sprintf("UPDATE %s SET group_id = $1 WHERE group_id IS NULL", table)
			if _, err := db.Exec(ctx, query, groupID); err != nil {
				return fmt.Errorf("failed to backfill group_id for %s: %w", table, err)
			}

			// Backfill user_id
			query = fmt.Sprintf("UPDATE %s SET user_id = $1 WHERE user_id IS NULL", table)
			if _, err := db.Exec(ctx, query, userID); err != nil {
				return fmt.Errorf("failed to backfill user_id for %s: %w", table, err)
			}
		}
	}

	return nil
}

func addColumnIfNotExists(ctx context.Context, table, column, colType string) error {
	query := fmt.Sprintf("ALTER TABLE %s ADD COLUMN IF NOT EXISTS %s %s", table, column, colType)
	_, err := db.Exec(ctx, query)
	if err != nil {
		return fmt.Errorf("failed to add column %s to %s: %w", column, table, err)
	}
	return nil
}
