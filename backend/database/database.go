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
	query := `SELECT id, name, category, is_needed, is_shopping_checked, group_id FROM grocery_items WHERE group_id = $1 ORDER BY name`
	rows, err := db.Query(ctx, query, groupID)
	if err != nil {
		return nil, fmt.Errorf("failed to query grocery items: %w", err)
	}
	defer rows.Close()

	items := []models.GroceryItem{}
	for rows.Next() {
		var item models.GroceryItem
		err := rows.Scan(&item.ID, &item.Name, &item.Category, &item.IsNeeded, &item.IsShoppingChecked, &item.GroupID)
		if err != nil {
			return nil, fmt.Errorf("failed to scan grocery item: %w", err)
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func CreateGroceryItem(ctx context.Context, item *models.GroceryItem) error {
	query := `INSERT INTO grocery_items (id, name, category, is_needed, is_shopping_checked, group_id) VALUES ($1, $2, $3, $4, $5, $6)`
	_, err := db.Exec(ctx, query, item.ID, item.Name, item.Category, item.IsNeeded, item.IsShoppingChecked, item.GroupID)
	return err
}

func UpdateGroceryItem(ctx context.Context, id, groupID string, updates map[string]any) (*models.GroceryItem, error) {
	setParts := []string{}
	args := []any{id, groupID}
	argID := 3

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
		return GetGroceryItemByID(ctx, id, groupID)
	}

	query := fmt.Sprintf("UPDATE grocery_items SET %s WHERE id = $1 AND group_id = $2 RETURNING id, name, category, is_needed, is_shopping_checked, group_id", strings.Join(setParts, ", "))

	var item models.GroceryItem
	err := db.QueryRow(ctx, query, args...).Scan(&item.ID, &item.Name, &item.Category, &item.IsNeeded, &item.IsShoppingChecked, &item.GroupID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &item, nil
}

func GetGroceryItemByID(ctx context.Context, id, groupID string) (*models.GroceryItem, error) {
	query := `SELECT id, name, category, is_needed, is_shopping_checked, group_id FROM grocery_items WHERE id = $1 AND group_id = $2`
	var item models.GroceryItem
	err := db.QueryRow(ctx, query, id, groupID).Scan(&item.ID, &item.Name, &item.Category, &item.IsNeeded, &item.IsShoppingChecked, &item.GroupID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &item, nil
}

func DeleteGroceryItem(ctx context.Context, id, groupID string) error {
	tag, err := db.Exec(ctx, "DELETE FROM grocery_items WHERE id = $1 AND group_id = $2", id, groupID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("grocery item not found")
	}
	return nil
}

// MealPlans

func GetAllMealPlans(ctx context.Context, groupID string) ([]models.MealPlan, error) {
	query := `SELECT id, date, meal_description, group_id FROM meal_plans WHERE group_id = $1 ORDER BY date`
	rows, err := db.Query(ctx, query, groupID)
	if err != nil {
		return nil, fmt.Errorf("failed to query meal plans: %w", err)
	}
	defer rows.Close()

	meals := []models.MealPlan{}
	for rows.Next() {
		var meal models.MealPlan
		err := rows.Scan(&meal.ID, &meal.Date, &meal.MealDescription, &meal.GroupID)
		if err != nil {
			return nil, fmt.Errorf("failed to scan meal plan: %w", err)
		}
		meals = append(meals, meal)
	}
	return meals, rows.Err()
}

func CreateMealPlan(ctx context.Context, meal *models.MealPlan) error {
	query := `INSERT INTO meal_plans (id, date, meal_description, group_id) VALUES ($1, $2, $3, $4)`
	_, err := db.Exec(ctx, query, meal.ID, meal.Date, meal.MealDescription, meal.GroupID)
	if err != nil {
		return fmt.Errorf("failed to create meal plan: %w", err)
	}
	return nil
}

func UpdateMealPlan(ctx context.Context, id, groupID string, updates map[string]any) (*models.MealPlan, error) {
	setParts := []string{}
	args := []any{id, groupID}
	argID := 3

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
		return GetMealPlanByID(ctx, id, groupID)
	}

	query := fmt.Sprintf("UPDATE meal_plans SET %s WHERE id = $1 AND group_id = $2 RETURNING id, date, meal_description, group_id", strings.Join(setParts, ", "))
	var meal models.MealPlan
	err := db.QueryRow(ctx, query, args...).Scan(&meal.ID, &meal.Date, &meal.MealDescription, &meal.GroupID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &meal, nil
}

func GetMealPlanByID(ctx context.Context, id, groupID string) (*models.MealPlan, error) {
	query := `SELECT id, date, meal_description, group_id FROM meal_plans WHERE id = $1 AND group_id = $2`
	var meal models.MealPlan
	err := db.QueryRow(ctx, query, id, groupID).Scan(&meal.ID, &meal.Date, &meal.MealDescription, &meal.GroupID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &meal, nil
}

func DeleteMealPlan(ctx context.Context, id, groupID string) error {
	tag, err := db.Exec(ctx, "DELETE FROM meal_plans WHERE id = $1 AND group_id = $2", id, groupID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("meal plan not found")
	}
	return nil
}

// Receipts

func GetAllReceipts(ctx context.Context, groupID string) ([]models.Receipt, error) {
	query := `SELECT id, date, total_amount, purchased_by, items, notes, group_id FROM receipts WHERE group_id = $1 ORDER BY date DESC`
	rows, err := db.Query(ctx, query, groupID)
	if err != nil {
		return nil, fmt.Errorf("failed to query receipts: %w", err)
	}
	defer rows.Close()

	receipts := []models.Receipt{}
	for rows.Next() {
		var receipt models.Receipt
		var notes *string
		err := rows.Scan(&receipt.ID, &receipt.Date, &receipt.TotalAmount, &receipt.PurchasedBy, &receipt.Items, &notes, &receipt.GroupID)
		if err != nil {
			return nil, fmt.Errorf("failed to scan receipt: %w", err)
		}
		receipt.Notes = notes
		receipts = append(receipts, receipt)
	}
	return receipts, rows.Err()
}

func CreateReceipt(ctx context.Context, receipt *models.Receipt) ([]models.GroceryItem, error) {
	tx, err := db.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	if len(receipt.ItemsList) == 0 {
		// No items provided, skip grocery item updates
		if err := receipt.SetItems(receipt.ItemsList); err != nil {
			return nil, fmt.Errorf("failed to set receipt items: %w", err)
		}

		query := `INSERT INTO receipts (id, date, total_amount, purchased_by, items, notes, group_id) VALUES ($1, $2, $3, $4, $5, $6, $7)`
		_, err = tx.Exec(ctx, query, receipt.ID, receipt.Date, receipt.TotalAmount, receipt.PurchasedBy, receipt.Items, receipt.Notes, receipt.GroupID)
		if err != nil {
			return nil, fmt.Errorf("failed to create receipt: %w", err)
		}

		if err := tx.Commit(ctx); err != nil {
			return nil, err
		}

		return []models.GroceryItem{}, nil
	}

	// Get items that are needed and checked for the receipt.
	itemsQuery := `SELECT id, name, category, is_needed, is_shopping_checked, group_id
		FROM grocery_items
		WHERE is_needed = true AND is_shopping_checked = true AND group_id = $1`
	rows, err := tx.Query(ctx, itemsQuery, receipt.GroupID)
	if err != nil {
		return nil, fmt.Errorf("failed to query grocery items for receipt: %w", err)
	}
	defer rows.Close()

	explicitItemSet := map[string]struct{}{}
	for _, name := range receipt.ItemsList {
		explicitItemSet[name] = struct{}{}
	}

	updatedItems := []models.GroceryItem{}
	for rows.Next() {
		var item models.GroceryItem
		err := rows.Scan(&item.ID, &item.Name, &item.Category, &item.IsNeeded, &item.IsShoppingChecked, &item.GroupID)
		if err != nil {
			return nil, fmt.Errorf("failed to scan grocery item for receipt: %w", err)
		}

		if _, ok := explicitItemSet[item.Name]; !ok {
			continue
		}

		item.IsNeeded = false
		item.IsShoppingChecked = false
		updatedItems = append(updatedItems, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("failed iterating grocery items for receipt: %w", err)
	}

	if err := receipt.SetItems(receipt.ItemsList); err != nil {
		return nil, fmt.Errorf("failed to set explicit receipt items: %w", err)
	}

	itemIDs := make([]string, 0, len(updatedItems))
	for _, item := range updatedItems {
		itemIDs = append(itemIDs, item.ID)
	}

	if len(itemIDs) > 0 {
		updateQuery := `UPDATE grocery_items SET is_needed = false, is_shopping_checked = false
						WHERE id = ANY($1) AND group_id = $2`
		_, err = tx.Exec(ctx, updateQuery, itemIDs, receipt.GroupID)
		if err != nil {
			return nil, fmt.Errorf("failed to update explicit grocery items: %w", err)
		}
	}

	query := `INSERT INTO receipts (id, date, total_amount, purchased_by, items, notes, group_id) VALUES ($1, $2, $3, $4, $5, $6, $7)`
	_, err = tx.Exec(ctx, query, receipt.ID, receipt.Date, receipt.TotalAmount, receipt.PurchasedBy, receipt.Items, receipt.Notes, receipt.GroupID)
	if err != nil {
		return nil, fmt.Errorf("failed to create receipt: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	return updatedItems, nil
}

func UpdateReceipt(ctx context.Context, id, groupID string, updates map[string]any) (*models.Receipt, error) {
	setParts := []string{}
	args := []any{id, groupID}
	argID := 3

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
		return GetReceiptByID(ctx, id, groupID)
	}

	query := fmt.Sprintf("UPDATE receipts SET %s WHERE id = $1 AND group_id = $2 RETURNING id, date, total_amount, purchased_by, items, notes, group_id", strings.Join(setParts, ", "))
	var receipt models.Receipt
	var notes *string
	err := db.QueryRow(ctx, query, args...).Scan(&receipt.ID, &receipt.Date, &receipt.TotalAmount, &receipt.PurchasedBy, &receipt.Items, &notes, &receipt.GroupID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	receipt.Notes = notes
	return &receipt, nil
}

func GetReceiptByID(ctx context.Context, id, groupID string) (*models.Receipt, error) {
	query := `SELECT id, date, total_amount, purchased_by, items, notes, group_id FROM receipts WHERE id = $1 AND group_id = $2`
	var receipt models.Receipt
	var notes *string
	err := db.QueryRow(ctx, query, id, groupID).Scan(&receipt.ID, &receipt.Date, &receipt.TotalAmount, &receipt.PurchasedBy, &receipt.Items, &notes, &receipt.GroupID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	receipt.Notes = notes
	return &receipt, nil
}

func DeleteReceipt(ctx context.Context, id, groupID string) error {
	tag, err := db.Exec(ctx, "DELETE FROM receipts WHERE id = $1 AND group_id = $2", id, groupID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("receipt not found")
	}
	return nil
}

// Groups

func CreateGroup(ctx context.Context, group *models.Group) error {
	query := `INSERT INTO groups (id, name, categories, members) VALUES ($1, $2, $3, $4)`
	_, err := db.Exec(ctx, query, group.ID, group.Name, group.Categories, group.Members)
	return err
}

func GetGroupByID(ctx context.Context, id string) (*models.Group, error) {
	query := `SELECT id, name, categories, members FROM groups WHERE id = $1`
	var group models.Group
	err := db.QueryRow(ctx, query, id).Scan(&group.ID, &group.Name, &group.Categories, &group.Members)
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

	for _, field := range []struct {
		key    string
		column string
	}{
		{key: "name", column: "name"},
		{key: "categories", column: "categories"},
		{key: "members", column: "members"},
	} {
		value, exists := updates[field.key]
		if !exists {
			continue
		}

		setParts = append(setParts, fmt.Sprintf("%s = $%d", field.column, argID))
		args = append(args, value)
		argID++
	}
	if len(setParts) == 0 {
		return GetGroupByID(ctx, id)
	}

	query := fmt.Sprintf(
		"UPDATE groups SET %s WHERE id = $1 RETURNING id, name, categories, members",
		strings.Join(setParts, ", "),
	)
	var group models.Group
	err := db.QueryRow(ctx, query, args...).Scan(&group.ID, &group.Name, &group.Categories, &group.Members)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
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

	// TODO: i think delete cascades automatically. can we remove this?
	queries := []string{
		`DELETE FROM grocery_items WHERE group_id = $1`,
		`DELETE FROM meal_plans WHERE group_id = $1`,
		`DELETE FROM receipts WHERE group_id = $1`,
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

// GetGroupsFromID is a temporary migration helper that reads legacy user-group
// memberships so old installs can recover their existing groups after auth removal.
func GetGroupsFromID(ctx context.Context, id string) ([]string, error) {
	query := `SELECT group_id FROM user_groups WHERE user_id = $1 ORDER BY group_id`
	rows, err := db.Query(ctx, query, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	groups := []string{}
	for rows.Next() {
		var groupID string
		if err := rows.Scan(&groupID); err != nil {
			return nil, err
		}
		groups = append(groups, groupID)
	}

	return groups, rows.Err()
}
