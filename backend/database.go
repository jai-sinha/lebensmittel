package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var db *pgxpool.Pool

// InitDB initializes the database connection pool
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

	// Test the connection
	err = pool.Ping(context.Background())
	if err != nil {
		return fmt.Errorf("failed to ping database: %w", err)
	}

	db = pool
	log.Println("Database connection established")
	return nil
}

// CloseDB closes the database connection pool
func CloseDB() {
	if db != nil {
		db.Close()
	}
}

// Grocery Item CRUD operations

// GetAllGroceryItems retrieves all grocery items from the database
func GetAllGroceryItems(ctx context.Context) ([]GroceryItem, error) {
	query := `SELECT id, name, category, is_needed, is_shopping_checked, group_id, user_id FROM grocery_items ORDER BY name`
	rows, err := db.Query(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("failed to query grocery items: %w", err)
	}
	defer rows.Close()

	var items []GroceryItem
	for rows.Next() {
		var item GroceryItem
		err := rows.Scan(&item.ID, &item.Name, &item.Category, &item.IsNeeded, &item.IsShoppingChecked, &item.GroupID, &item.UserID)
		if err != nil {
			return nil, fmt.Errorf("failed to scan grocery item: %w", err)
		}
		items = append(items, item)
	}

	return items, rows.Err()
}

// CreateGroceryItem creates a new grocery item in the database
func CreateGroceryItem(ctx context.Context, item *GroceryItem) error {
	query := `INSERT INTO grocery_items (id, name, category, is_needed, is_shopping_checked, group_id, user_id)
			  VALUES ($1, $2, $3, $4, $5, $6, $7)`
	_, err := db.Exec(ctx, query, item.ID, item.Name, item.Category, item.IsNeeded, item.IsShoppingChecked, item.GroupID, item.UserID)
	if err != nil {
		return fmt.Errorf("failed to create grocery item: %w", err)
	}
	return nil
}

// UpdateGroceryItem updates an existing grocery item in the database
func UpdateGroceryItem(ctx context.Context, itemID string, updates map[string]any) (*GroceryItem, error) {
	// Build dynamic update query
	setParts := []string{}
	args := []any{itemID}
	argCount := 2

	for field, value := range updates {
		var dbField string
		switch field {
		case "name":
			dbField = "name"
		case "category":
			dbField = "category"
		case "isNeeded":
			dbField = "is_needed"
		case "isShoppingChecked":
			dbField = "is_shopping_checked"
		default:
			continue
		}
		setParts = append(setParts, fmt.Sprintf("%s = $%d", dbField, argCount))
		args = append(args, value)
		argCount++
	}

	if len(setParts) == 0 {
		return nil, fmt.Errorf("no valid fields to update")
	}

	query := fmt.Sprintf("UPDATE grocery_items SET %s WHERE id = $1", joinStrings(setParts, ", "))
	_, err := db.Exec(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to update grocery item: %w", err)
	}

	return GetGroceryItemByID(ctx, itemID)
}

// GetGroceryItemByID retrieves a grocery item by ID
func GetGroceryItemByID(ctx context.Context, itemID string) (*GroceryItem, error) {
	query := `SELECT id, name, category, is_needed, is_shopping_checked, group_id, user_id FROM grocery_items WHERE id = $1`
	var item GroceryItem
	err := db.QueryRow(ctx, query, itemID).Scan(&item.ID, &item.Name, &item.Category, &item.IsNeeded, &item.IsShoppingChecked, &item.GroupID, &item.UserID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, fmt.Errorf("failed to get grocery item: %w", err)
	}
	return &item, nil
}

// DeleteGroceryItem deletes a grocery item from the database
func DeleteGroceryItem(ctx context.Context, itemID string) error {
	query := `DELETE FROM grocery_items WHERE id = $1`
	result, err := db.Exec(ctx, query, itemID)
	if err != nil {
		return fmt.Errorf("failed to delete grocery item: %w", err)
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("grocery item not found")
	}
	return nil
}

// Meal Plan CRUD operations

// GetAllMealPlans retrieves all meal plans from the database ordered by date
func GetAllMealPlans(ctx context.Context) ([]MealPlan, error) {
	query := `SELECT id, date, meal_description, group_id, user_id FROM meal_plans ORDER BY date`
	rows, err := db.Query(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("failed to query meal plans: %w", err)
	}
	defer rows.Close()

	var meals []MealPlan
	for rows.Next() {
		var meal MealPlan
		err := rows.Scan(&meal.ID, &meal.Date, &meal.MealDescription, &meal.GroupID, &meal.UserID)
		if err != nil {
			return nil, fmt.Errorf("failed to scan meal plan: %w", err)
		}
		meals = append(meals, meal)
	}

	return meals, rows.Err()
}

// CreateMealPlan creates a new meal plan (removes any existing meal for the date first)
func CreateMealPlan(ctx context.Context, meal *MealPlan) error {
	tx, err := db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	// Delete any existing meal for this date
	_, err = tx.Exec(ctx, "DELETE FROM meal_plans WHERE date = $1", meal.Date)
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

// UpdateMealPlan updates an existing meal plan
func UpdateMealPlan(ctx context.Context, mealID string, updates map[string]any) (*MealPlan, error) {
	setParts := []string{}
	args := []any{mealID}
	argCount := 2

	for field, value := range updates {
		var dbField string
		switch field {
		case "date":
			dbField = "date"
		case "mealDescription":
			dbField = "meal_description"
		default:
			continue
		}
		setParts = append(setParts, fmt.Sprintf("%s = $%d", dbField, argCount))
		args = append(args, value)
		argCount++
	}

	if len(setParts) == 0 {
		return nil, fmt.Errorf("no valid fields to update")
	}

	query := fmt.Sprintf("UPDATE meal_plans SET %s WHERE id = $1", joinStrings(setParts, ", "))
	_, err := db.Exec(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to update meal plan: %w", err)
	}

	return GetMealPlanByID(ctx, mealID)
}

// GetMealPlanByID retrieves a meal plan by ID
func GetMealPlanByID(ctx context.Context, mealID string) (*MealPlan, error) {
	query := `SELECT id, date, meal_description, group_id, user_id FROM meal_plans WHERE id = $1`
	var meal MealPlan
	err := db.QueryRow(ctx, query, mealID).Scan(&meal.ID, &meal.Date, &meal.MealDescription, &meal.GroupID, &meal.UserID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, fmt.Errorf("failed to get meal plan: %w", err)
	}
	return &meal, nil
}

// DeleteMealPlan deletes a meal plan from the database
func DeleteMealPlan(ctx context.Context, mealID string) error {
	query := `DELETE FROM meal_plans WHERE id = $1`
	result, err := db.Exec(ctx, query, mealID)
	if err != nil {
		return fmt.Errorf("failed to delete meal plan: %w", err)
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("meal plan not found")
	}
	return nil
}

// Receipt CRUD operations

// GetAllReceipts retrieves all receipts from the database ordered by date descending
func GetAllReceipts(ctx context.Context) ([]Receipt, error) {
	query := `SELECT id, date, total_amount, purchased_by, items, notes, group_id, user_id FROM receipts ORDER BY date DESC`
	rows, err := db.Query(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("failed to query receipts: %w", err)
	}
	defer rows.Close()

	var receipts []Receipt
	for rows.Next() {
		var receipt Receipt
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

// CreateReceipt creates a new receipt and updates grocery items
func CreateReceipt(ctx context.Context, receipt *Receipt) error {
	tx, err := db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	// Get items that are needed and checked for the receipt
	itemsQuery := `SELECT name FROM grocery_items WHERE is_needed = true AND is_shopping_checked = true`
	rows, err := tx.Query(ctx, itemsQuery)
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
	receipt.SetItems(itemNames)

	// Update grocery items - set is_needed and is_shopping_checked to false
	if len(itemNames) > 0 {
		updateQuery := `UPDATE grocery_items SET is_needed = false, is_shopping_checked = false
						WHERE is_needed = true AND is_shopping_checked = true`
		_, err = tx.Exec(ctx, updateQuery)
		if err != nil {
			return fmt.Errorf("failed to update grocery items: %w", err)
		}
	}

	// Insert the receipt
	receiptQuery := `INSERT INTO receipts (id, date, total_amount, purchased_by, items, notes, group_id, user_id)
					 VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`
	_, err = tx.Exec(ctx, receiptQuery, receipt.ID, receipt.Date, receipt.TotalAmount,
		receipt.PurchasedBy, receipt.Items, receipt.Notes, receipt.GroupID, receipt.UserID)
	if err != nil {
		return fmt.Errorf("failed to create receipt: %w", err)
	}

	return tx.Commit(ctx)
}

// UpdateReceipt updates an existing receipt
func UpdateReceipt(ctx context.Context, receiptID string, updates map[string]any) (*Receipt, error) {
	setParts := []string{}
	args := []any{receiptID}
	argCount := 2

	for field, value := range updates {
		var dbField string
		switch field {
		case "date":
			dbField = "date"
		case "totalAmount":
			dbField = "total_amount"
		case "purchasedBy":
			dbField = "purchased_by"
		case "items":
			dbField = "items"
			// Convert items slice to JSON string
			if items, ok := value.([]string); ok {
				jsonItems, _ := json.Marshal(items)
				value = string(jsonItems)
			}
		case "notes":
			dbField = "notes"
		default:
			continue
		}
		setParts = append(setParts, fmt.Sprintf("%s = $%d", dbField, argCount))
		args = append(args, value)
		argCount++
	}

	if len(setParts) == 0 {
		return nil, fmt.Errorf("no valid fields to update")
	}

	query := fmt.Sprintf("UPDATE receipts SET %s WHERE id = $1", joinStrings(setParts, ", "))
	_, err := db.Exec(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to update receipt: %w", err)
	}

	return GetReceiptByID(ctx, receiptID)
}

// GetReceiptByID retrieves a receipt by ID
func GetReceiptByID(ctx context.Context, receiptID string) (*Receipt, error) {
	query := `SELECT id, date, total_amount, purchased_by, items, notes, group_id, user_id FROM receipts WHERE id = $1`
	var receipt Receipt
	var notes *string
	err := db.QueryRow(ctx, query, receiptID).Scan(&receipt.ID, &receipt.Date, &receipt.TotalAmount,
		&receipt.PurchasedBy, &receipt.Items, &notes, &receipt.GroupID, &receipt.UserID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, fmt.Errorf("failed to get receipt: %w", err)
	}
	receipt.Notes = notes
	return &receipt, nil
}

// DeleteReceipt deletes a receipt from the database
func DeleteReceipt(ctx context.Context, receiptID string) error {
	query := `DELETE FROM receipts WHERE id = $1`
	result, err := db.Exec(ctx, query, receiptID)
	if err != nil {
		return fmt.Errorf("failed to delete receipt: %w", err)
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("receipt not found")
	}
	return nil
}

// Group CRUD operations

// CreateGroup creates a new group
func CreateGroup(ctx context.Context, group *Group) error {
	query := `INSERT INTO groups (id, name) VALUES ($1, $2)`
	_, err := db.Exec(ctx, query, group.ID, group.Name)
	if err != nil {
		return fmt.Errorf("failed to create group: %w", err)
	}
	return nil
}

// GetGroupByID retrieves a group by ID
func GetGroupByID(ctx context.Context, groupID string) (*Group, error) {
	query := `SELECT id, name FROM groups WHERE id = $1`
	var group Group
	err := db.QueryRow(ctx, query, groupID).Scan(&group.ID, &group.Name)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, fmt.Errorf("failed to get group: %w", err)
	}
	return &group, nil
}

// UpdateGroup updates an existing group
func UpdateGroup(ctx context.Context, groupID string, updates map[string]any) (*Group, error) {
	setParts := []string{}
	args := []any{groupID}
	argCount := 2

	for field, value := range updates {
		var dbField string
		switch field {
		case "name":
			dbField = "name"
		default:
			continue
		}
		setParts = append(setParts, fmt.Sprintf("%s = $%d", dbField, argCount))
		args = append(args, value)
		argCount++
	}

	if len(setParts) == 0 {
		return nil, fmt.Errorf("no valid fields to update")
	}

	query := fmt.Sprintf("UPDATE groups SET %s WHERE id = $1", joinStrings(setParts, ", "))
	_, err := db.Exec(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to update group: %w", err)
	}

	return GetGroupByID(ctx, groupID)
}

// DeleteGroup deletes a group from the database
func DeleteGroup(ctx context.Context, groupID string) error {
	query := `DELETE FROM groups WHERE id = $1`
	result, err := db.Exec(ctx, query, groupID)
	if err != nil {
		return fmt.Errorf("failed to delete group: %w", err)
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("group not found")
	}
	return nil
}

// User CRUD operations

// CreateUser creates a new user
func CreateUser(ctx context.Context, user *User) error {
	query := `INSERT INTO users (id, username, password_hash, display_name)
			  VALUES ($1, $2, $3, $4)`
	_, err := db.Exec(ctx, query, user.ID, user.Username, user.PasswordHash, user.DisplayName)
	if err != nil {
		return fmt.Errorf("failed to create user: %w", err)
	}
	return nil
}

// GetUserByUsername retrieves a user by username
func GetUserByUsername(ctx context.Context, username string) (*User, error) {
	query := `SELECT id, username, password_hash, display_name FROM users WHERE username = $1`
	var user User
	err := db.QueryRow(ctx, query, username).Scan(&user.ID, &user.Username, &user.PasswordHash, &user.DisplayName)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, fmt.Errorf("failed to get user by username: %w", err)
	}
	return &user, nil
}

// GetUserByID retrieves a user by ID
func GetUserByID(ctx context.Context, userID string) (*User, error) {
	query := `SELECT id, username, password_hash, display_name FROM users WHERE id = $1`
	var user User
	err := db.QueryRow(ctx, query, userID).Scan(&user.ID, &user.Username, &user.PasswordHash, &user.DisplayName)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, fmt.Errorf("failed to get user: %w", err)
	}
	return &user, nil
}

// UpdateUser updates an existing user
func UpdateUser(ctx context.Context, userID string, updates map[string]any) (*User, error) {
	setParts := []string{}
	args := []any{userID}
	argCount := 2

	for field, value := range updates {
		var dbField string
		switch field {
		case "username":
			dbField = "username"
		case "displayName":
			dbField = "display_name"
		default:
			continue
		}
		setParts = append(setParts, fmt.Sprintf("%s = $%d", dbField, argCount))
		args = append(args, value)
		argCount++
	}

	if len(setParts) == 0 {
		return nil, fmt.Errorf("no valid fields to update")
	}

	query := fmt.Sprintf("UPDATE users SET %s WHERE id = $1", joinStrings(setParts, ", "))
	_, err := db.Exec(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to update user: %w", err)
	}

	return GetUserByID(ctx, userID)
}

// DeleteUser deletes a user from the database
func DeleteUser(ctx context.Context, userID string) error {
	query := `DELETE FROM users WHERE id = $1`
	result, err := db.Exec(ctx, query, userID)
	if err != nil {
		return fmt.Errorf("failed to delete user: %w", err)
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("user not found")
	}
	return nil
}

// AddUserToGroup adds a user to a group
func AddUserToGroup(ctx context.Context, userID, groupID string) error {
	query := `INSERT INTO user_groups (user_id, group_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`
	_, err := db.Exec(ctx, query, userID, groupID)
	if err != nil {
		return fmt.Errorf("failed to add user to group: %w", err)
	}
	return nil
}

// GetUserGroups retrieves all groups for a user
func GetUserGroups(ctx context.Context, userID string) ([]Group, error) {
	query := `
		SELECT g.id, g.name
		FROM groups g
		JOIN user_groups ug ON g.id = ug.group_id
		WHERE ug.user_id = $1
	`
	rows, err := db.Query(ctx, query, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to query user groups: %w", err)
	}
	defer rows.Close()

	var groups []Group
	for rows.Next() {
		var group Group
		if err := rows.Scan(&group.ID, &group.Name); err != nil {
			return nil, fmt.Errorf("failed to scan group: %w", err)
		}
		groups = append(groups, group)
	}
	return groups, rows.Err()
}

// Helper function to join strings
func joinStrings(strs []string, sep string) string {
	if len(strs) == 0 {
		return ""
	}
	if len(strs) == 1 {
		return strs[0]
	}

	result := strs[0]
	for _, str := range strs[1:] {
		result += sep + str
	}
	return result
}
