package database

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/lebensmittel/backend/models"
)

var db *pgxpool.Pool

func InitDB() error {
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		databaseURL = "postgres://jsinha:@localhost/lebensmittel"
	}

	config, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return fmt.Errorf("failed to parse database URL: %w", err)
	}

	pool, err := pgxpool.NewWithConfig(context.Background(), config)
	if err != nil {
		return fmt.Errorf("failed to create connection pool: %w", err)
	}

	err = pool.Ping(context.Background())
	if err != nil {
		return fmt.Errorf("failed to ping database: %w", err)
	}

	db = pool
	log.Println("Database connection established")
	return nil
}

func CloseDB() {
	if db != nil {
		db.Close()
	}
}

// GroceryItems

func GetAllGroceryItems(ctx context.Context, groupID string) ([]models.GroceryItem, error) {
	query := `SELECT id, name, category, is_needed, is_shopping_checked, group_id, user_id FROM grocery_items WHERE group_id = $1 ORDER BY name`
	rows, err := db.Query(ctx, query, groupID)
	if err != nil {
		return nil, fmt.Errorf("failed to query grocery items: %w", err)
	}
	defer rows.Close()

	items := []models.GroceryItem{}
	for rows.Next() {
		var item models.GroceryItem
		err := rows.Scan(&item.ID, &item.Name, &item.Category, &item.IsNeeded, &item.IsShoppingChecked, &item.GroupID, &item.UserID)
		if err != nil {
			return nil, fmt.Errorf("failed to scan grocery item: %w", err)
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func CreateGroceryItem(ctx context.Context, item *models.GroceryItem) error {
	query := `INSERT INTO grocery_items (id, name, category, is_needed, is_shopping_checked, group_id, user_id) VALUES ($1, $2, $3, $4, $5, $6, $7)`
	_, err := db.Exec(ctx, query, item.ID, item.Name, item.Category, item.IsNeeded, item.IsShoppingChecked, item.GroupID, item.UserID)
	return err
}

func UpdateGroceryItem(ctx context.Context, id string, updates map[string]any) (*models.GroceryItem, error) {
	setParts := []string{}
	args := []any{id}
	argID := 2

	for k, v := range updates {
		dbCol := k
		switch k {
		case "isNeeded":
			dbCol = "is_needed"
		case "isShoppingChecked":
			dbCol = "is_shopping_checked"
		}
		setParts = append(setParts, fmt.Sprintf("%s = $%d", dbCol, argID))
		args = append(args, v)
		argID++
	}

	if len(setParts) == 0 {
		return GetGroceryItemByID(ctx, id)
	}

	query := fmt.Sprintf("UPDATE grocery_items SET %s WHERE id = $1 RETURNING id, name, category, is_needed, is_shopping_checked, group_id, user_id", strings.Join(setParts, ", "))

	var item models.GroceryItem
	err := db.QueryRow(ctx, query, args...).Scan(&item.ID, &item.Name, &item.Category, &item.IsNeeded, &item.IsShoppingChecked, &item.GroupID, &item.UserID)
	if err != nil {
		return nil, err
	}
	return &item, nil
}

func GetGroceryItemByID(ctx context.Context, id string) (*models.GroceryItem, error) {
	query := `SELECT id, name, category, is_needed, is_shopping_checked, group_id, user_id FROM grocery_items WHERE id = $1`
	var item models.GroceryItem
	err := db.QueryRow(ctx, query, id).Scan(&item.ID, &item.Name, &item.Category, &item.IsNeeded, &item.IsShoppingChecked, &item.GroupID, &item.UserID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &item, nil
}

func DeleteGroceryItem(ctx context.Context, id string) error {
	_, err := db.Exec(ctx, "DELETE FROM grocery_items WHERE id = $1", id)
	return err
}

// MealPlans

func GetAllMealPlans(ctx context.Context, groupID string) ([]models.MealPlan, error) {
	query := `SELECT id, date, meal_description, group_id, user_id FROM meal_plans WHERE group_id = $1 ORDER BY date`
	rows, err := db.Query(ctx, query, groupID)
	if err != nil {
		return nil, fmt.Errorf("failed to query meal plans: %w", err)
	}
	defer rows.Close()

	meals := []models.MealPlan{}
	for rows.Next() {
		var meal models.MealPlan
		err := rows.Scan(&meal.ID, &meal.Date, &meal.MealDescription, &meal.GroupID, &meal.UserID)
		if err != nil {
			return nil, fmt.Errorf("failed to scan meal plan: %w", err)
		}
		meals = append(meals, meal)
	}
	return meals, rows.Err()
}

func CreateMealPlan(ctx context.Context, meal *models.MealPlan) error {
	tx, err := db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	// Delete any existing meal for this date
	_, err = tx.Exec(ctx, "DELETE FROM meal_plans WHERE date = $1 AND group_id = $2", meal.Date, meal.GroupID)
	if err != nil {
		return fmt.Errorf("failed to delete existing meal plan: %w", err)
	}

	// Insert new meal plan
	query := `INSERT INTO meal_plans (id, date, meal_description, group_id, user_id) VALUES ($1, $2, $3, $4, $5)`
	_, err = tx.Exec(ctx, query, meal.ID, meal.Date, meal.MealDescription, meal.GroupID, meal.UserID)
	if err != nil {
		return fmt.Errorf("failed to create meal plan: %w", err)
	}

	return tx.Commit(ctx)
}

func UpdateMealPlan(ctx context.Context, id string, updates map[string]any) (*models.MealPlan, error) {
	setParts := []string{}
	args := []any{id}
	argID := 2

	for k, v := range updates {
		dbCol := k
		switch k {
		case "mealDescription":
			dbCol = "meal_description"
		}
		setParts = append(setParts, fmt.Sprintf("%s = $%d", dbCol, argID))
		args = append(args, v)
		argID++
	}
	if len(setParts) == 0 {
		return GetMealPlanByID(ctx, id)
	}

	query := fmt.Sprintf("UPDATE meal_plans SET %s WHERE id = $1 RETURNING id, date, meal_description, group_id, user_id", strings.Join(setParts, ", "))
	var meal models.MealPlan
	err := db.QueryRow(ctx, query, args...).Scan(&meal.ID, &meal.Date, &meal.MealDescription, &meal.GroupID, &meal.UserID)
	if err != nil {
		return nil, err
	}
	return &meal, nil
}

func GetMealPlanByID(ctx context.Context, id string) (*models.MealPlan, error) {
	query := `SELECT id, date, meal_description, group_id, user_id FROM meal_plans WHERE id = $1`
	var meal models.MealPlan
	err := db.QueryRow(ctx, query, id).Scan(&meal.ID, &meal.Date, &meal.MealDescription, &meal.GroupID, &meal.UserID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &meal, nil
}

func DeleteMealPlan(ctx context.Context, id string) error {
	_, err := db.Exec(ctx, "DELETE FROM meal_plans WHERE id = $1", id)
	return err
}

// Receipts

func GetAllReceipts(ctx context.Context, groupID string) ([]models.Receipt, error) {
	query := `SELECT id, date, total_amount, purchased_by, items, notes, group_id, user_id FROM receipts WHERE group_id = $1 ORDER BY date DESC`
	rows, err := db.Query(ctx, query, groupID)
	if err != nil {
		return nil, fmt.Errorf("failed to query receipts: %w", err)
	}
	defer rows.Close()

	receipts := []models.Receipt{}
	for rows.Next() {
		var receipt models.Receipt
		var notes *string
		err := rows.Scan(&receipt.ID, &receipt.Date, &receipt.TotalAmount, &receipt.PurchasedBy, &receipt.Items, &notes, &receipt.GroupID, &receipt.UserID)
		if err != nil {
			return nil, fmt.Errorf("failed to scan receipt: %w", err)
		}
		receipt.Notes = notes
		receipts = append(receipts, receipt)
	}
	return receipts, rows.Err()
}

func CreateReceipt(ctx context.Context, receipt *models.Receipt) error {
	tx, err := db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	// Get items that are needed and checked for the receipt
	itemsQuery := `SELECT name FROM grocery_items WHERE is_needed = true AND is_shopping_checked = true AND group_id = $1`
	rows, err := tx.Query(ctx, itemsQuery, receipt.GroupID)
	if err != nil {
		return fmt.Errorf("failed to query grocery items for receipt: %w", err)
	}
	defer rows.Close()

	var itemNames []string
	for rows.Next() {
		var name string
		err := rows.Scan(&name)
		if err != nil {
			return fmt.Errorf("failed to scan grocery item name: %w", err)
		}
		itemNames = append(itemNames, name)
	}

	// Update the receipt with the items
	if len(itemNames) > 0 {
		receipt.SetItems(itemNames)

		// Update grocery items - set is_needed and is_shopping_checked to false
		updateQuery := `UPDATE grocery_items SET is_needed = false, is_shopping_checked = false
						WHERE is_needed = true AND is_shopping_checked = true AND group_id = $1`
		_, err = tx.Exec(ctx, updateQuery, receipt.GroupID)
		if err != nil {
			return fmt.Errorf("failed to update grocery items: %w", err)
		}
	} else if receipt.Items == "" && len(receipt.ItemsList) > 0 {
		receipt.SetItems(receipt.ItemsList)
	}

	query := `INSERT INTO receipts (id, date, total_amount, purchased_by, items, notes, group_id, user_id) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`
	_, err = tx.Exec(ctx, query, receipt.ID, receipt.Date, receipt.TotalAmount, receipt.PurchasedBy, receipt.Items, receipt.Notes, receipt.GroupID, receipt.UserID)
	if err != nil {
		return fmt.Errorf("failed to create receipt: %w", err)
	}

	return tx.Commit(ctx)
}

func UpdateReceipt(ctx context.Context, id string, updates map[string]any) (*models.Receipt, error) {
	setParts := []string{}
	args := []any{id}
	argID := 2

	for k, v := range updates {
		dbCol := k
		val := v
		switch k {
		case "totalAmount":
			dbCol = "total_amount"
		case "purchasedBy":
			dbCol = "purchased_by"
		case "items":
			// Convert items slice to JSON string
			if items, ok := v.([]string); ok {
				jsonItems, _ := json.Marshal(items)
				val = string(jsonItems)
			}
		}
		setParts = append(setParts, fmt.Sprintf("%s = $%d", dbCol, argID))
		args = append(args, val)
		argID++
	}
	if len(setParts) == 0 {
		return GetReceiptByID(ctx, id)
	}

	query := fmt.Sprintf("UPDATE receipts SET %s WHERE id = $1 RETURNING id, date, total_amount, purchased_by, items, notes, group_id, user_id", strings.Join(setParts, ", "))
	var receipt models.Receipt
	var notes *string
	err := db.QueryRow(ctx, query, args...).Scan(&receipt.ID, &receipt.Date, &receipt.TotalAmount, &receipt.PurchasedBy, &receipt.Items, &notes, &receipt.GroupID, &receipt.UserID)
	if err != nil {
		return nil, err
	}
	receipt.Notes = notes
	return &receipt, nil
}

func GetReceiptByID(ctx context.Context, id string) (*models.Receipt, error) {
	query := `SELECT id, date, total_amount, purchased_by, items, notes, group_id, user_id FROM receipts WHERE id = $1`
	var receipt models.Receipt
	var notes *string
	err := db.QueryRow(ctx, query, id).Scan(&receipt.ID, &receipt.Date, &receipt.TotalAmount, &receipt.PurchasedBy, &receipt.Items, &notes, &receipt.GroupID, &receipt.UserID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	receipt.Notes = notes
	return &receipt, nil
}

func DeleteReceipt(ctx context.Context, id string) error {
	_, err := db.Exec(ctx, "DELETE FROM receipts WHERE id = $1", id)
	return err
}

// Groups

func CreateGroup(ctx context.Context, group *models.Group) error {
	query := `INSERT INTO groups (id, name) VALUES ($1, $2)`
	_, err := db.Exec(ctx, query, group.ID, group.Name)
	return err
}

func GetGroupByID(ctx context.Context, id string) (*models.Group, error) {
	query := `SELECT id, name FROM groups WHERE id = $1`
	var group models.Group
	err := db.QueryRow(ctx, query, id).Scan(&group.ID, &group.Name)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &group, nil
}

func UpdateGroup(ctx context.Context, id string, updates map[string]any) (*models.Group, error) {
	setParts := []string{}
	args := []any{id}
	argID := 2

	for k, v := range updates {
		setParts = append(setParts, fmt.Sprintf("%s = $%d", k, argID))
		args = append(args, v)
		argID++
	}
	if len(setParts) == 0 {
		return GetGroupByID(ctx, id)
	}

	query := fmt.Sprintf("UPDATE groups SET %s WHERE id = $1 RETURNING id, name", strings.Join(setParts, ", "))
	var group models.Group
	err := db.QueryRow(ctx, query, args...).Scan(&group.ID, &group.Name)
	if err != nil {
		return nil, err
	}
	return &group, nil
}

func DeleteGroup(ctx context.Context, groupID string) error {
	tx, err := db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	queries := []string{
		`DELETE FROM grocery_items WHERE group_id = $1`,
		`DELETE FROM meal_plans WHERE group_id = $1`,
		`DELETE FROM receipts WHERE group_id = $1`,
		`DELETE FROM user_groups WHERE group_id = $1`,
		`DELETE FROM join_codes WHERE group_id = $1`,
		`DELETE FROM groups WHERE id = $1`,
	}

	for i, query := range queries {
		tag, err := tx.Exec(ctx, query, groupID)
		if err != nil {
			return fmt.Errorf("failed to execute query %d: %w", i, err)
		}
		// If the last query (deleting the group) affects no rows, return group not found
		if i == len(queries)-1 && tag.RowsAffected() == 0 {
			return fmt.Errorf("group not found")
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	return nil
}

// Users

func CreateUser(ctx context.Context, user *models.User) error {
	query := `INSERT INTO users (id, username, password_hash, display_name) VALUES ($1, $2, $3, $4)`
	_, err := db.Exec(ctx, query, user.ID, user.Username, user.PasswordHash, user.DisplayName)
	return err
}

func GetUserByUsername(ctx context.Context, username string) (*models.User, error) {
	query := `SELECT id, username, password_hash, display_name FROM users WHERE username = $1`
	var user models.User
	err := db.QueryRow(ctx, query, username).Scan(&user.ID, &user.Username, &user.PasswordHash, &user.DisplayName)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &user, nil
}

func GetUserByID(ctx context.Context, id string) (*models.User, error) {
	query := `SELECT id, username, password_hash, display_name FROM users WHERE id = $1`
	var user models.User
	err := db.QueryRow(ctx, query, id).Scan(&user.ID, &user.Username, &user.PasswordHash, &user.DisplayName)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &user, nil
}

func UpdateUser(ctx context.Context, id string, updates map[string]any) (*models.User, error) {
	setParts := []string{}
	args := []any{id}
	argID := 2

	for k, v := range updates {
		dbCol := k
		switch k {
		case "displayName":
			dbCol = "display_name"
		}
		setParts = append(setParts, fmt.Sprintf("%s = $%d", dbCol, argID))
		args = append(args, v)
		argID++
	}
	if len(setParts) == 0 {
		return GetUserByID(ctx, id)
	}

	query := fmt.Sprintf("UPDATE users SET %s WHERE id = $1 RETURNING id, username, password_hash, display_name", strings.Join(setParts, ", "))
	var user models.User
	err := db.QueryRow(ctx, query, args...).Scan(&user.ID, &user.Username, &user.PasswordHash, &user.DisplayName)
	if err != nil {
		return nil, err
	}
	return &user, nil
}

func DeleteUser(ctx context.Context, id string) error {
	_, err := db.Exec(ctx, "DELETE FROM users WHERE id = $1", id)
	return err
}

// Group Users

func AddUserToGroup(ctx context.Context, userID, groupID string) error {
	_, err := db.Exec(ctx, "INSERT INTO user_groups (user_id, group_id) VALUES ($1, $2)", userID, groupID)
	return err
}

func RemoveUserFromGroup(ctx context.Context, userID, groupID string) error {
	_, err := db.Exec(ctx, "DELETE FROM user_groups WHERE user_id = $1 AND group_id = $2", userID, groupID)
	return err
}

// GetUserGroups returns the groups for a given user.
func GetUserGroups(ctx context.Context, userID string) ([]models.Group, error) {
	query := `
        SELECT g.id, g.name
        FROM groups g
        JOIN user_groups ug ON g.id = ug.group_id
        WHERE ug.user_id = $1
    `
	rows, err := db.Query(ctx, query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	// Initialize slice to empty to ensure JSON serialization is [] not null
	groups := []models.Group{}
	for rows.Next() {
		var g models.Group
		if err := rows.Scan(&g.ID, &g.Name); err != nil {
			return nil, err
		}
		groups = append(groups, g)
	}
	return groups, rows.Err()
}

func GetGroupUsers(ctx context.Context, groupID string) ([]models.GroupUser, error) {
	query := `
		SELECT u.id, u.display_name
		FROM users u
		JOIN user_groups ug ON u.id = ug.user_id
		WHERE ug.group_id = $1
	`
	rows, err := db.Query(ctx, query, groupID)
	if err != nil {
		return nil, fmt.Errorf("failed to query group users: %w", err)
	}
	defer rows.Close()

	users := []models.GroupUser{}
	for rows.Next() {
		var user models.GroupUser
		if err := rows.Scan(&user.ID, &user.DisplayName); err != nil {
			return nil, fmt.Errorf("failed to scan user: %w", err)
		}
		users = append(users, user)
	}
	return users, rows.Err()
}

// Join Codes

func CreateJoinCode(ctx context.Context, code *models.JoinCode) error {
	query := `INSERT INTO join_codes (code, group_id, expires_at, created_by) VALUES ($1, $2, $3, $4)`
	_, err := db.Exec(ctx, query, code.Code, code.GroupID, code.ExpiresAt, code.CreatedBy)
	return err
}

func GetJoinCode(ctx context.Context, code string) (*models.JoinCode, error) {
	query := `
		SELECT code, group_id, expires_at, created_by
		FROM join_codes
		WHERE code = $1
	`
	var jc models.JoinCode
	err := db.QueryRow(ctx, query, code).Scan(&jc.Code, &jc.GroupID, &jc.ExpiresAt, &jc.CreatedBy)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, fmt.Errorf("failed to get join code: %w", err)
	}
	return &jc, nil
}

func DeleteJoinCode(ctx context.Context, code string) error {
	_, err := db.Exec(ctx, "DELETE FROM join_codes WHERE code = $1", code)
	return err
}
