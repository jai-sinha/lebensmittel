package database

import (
	"context"
	"fmt"
	"strings"

	"github.com/lebensmittel/backend/models"
)

// reconcile response type
type Changes struct {
	// IsFull means this is a full snapshot
	IsFull     bool                 `json:"isFull"`
	NextSeq    int64                `json:"nextSeq"`
	Grocery    []models.GroceryItem `json:"grocery"`
	Meal       []models.MealPlan    `json:"meal"`
	Receipt    []models.Receipt     `json:"receipt"`
	DeletedIDs IDsByType            `json:"deletedIds"`
}

// group entity ids by entity type
type IDsByType struct {
	Grocery []string `json:"grocery"`
	Meal    []string `json:"meal"`
	Receipt []string `json:"receipt"`
}

func (ids *IDsByType) add(entityType, id string) error {
	switch entityType {
	case entityGrocery:
		ids.Grocery = append(ids.Grocery, id)
	case entityMeal:
		ids.Meal = append(ids.Meal, id)
	case entityReceipt:
		ids.Receipt = append(ids.Receipt, id)
	default:
		return fmt.Errorf("unknown entity type %q", entityType)
	}
	return nil
}

func GetGroupChanges(ctx context.Context, groupID string, afterSeq *int64) (Changes, error) {
	// make sure active changes can't race a read by getting the read bounds first
	nextSeq, oldest, err := ledgerBounds(ctx, groupID)
	if err != nil {
		return Changes{}, err
	}

	if afterSeq == nil || oldest == nil || *afterSeq < *oldest {
		return fullChanges(ctx, groupID, nextSeq)
	}
	return deltaChanges(ctx, groupID, *afterSeq, nextSeq)
}

// full fetches
func fullChanges(ctx context.Context, groupID string, nextSeq int64) (Changes, error) {
	out := emptyChanges(true, nextSeq)
	var err error
	if out.Grocery, err = GetAllGroceryItems(ctx, groupID); err != nil {
		return Changes{}, err
	}
	if out.Meal, err = GetAllMealPlans(ctx, groupID); err != nil {
		return Changes{}, err
	}
	if out.Receipt, err = GetAllReceipts(ctx, groupID); err != nil {
		return Changes{}, err
	}
	return out, nil
}

func deltaChanges(ctx context.Context, groupID string, afterSeq, nextSeq int64) (Changes, error) {
	records, err := ledgerRows(ctx, groupID, afterSeq, nextSeq)
	if err != nil {
		return Changes{}, err
	}

	out := emptyChanges(false, nextSeq)
	var wanted IDsByType
	for _, rec := range collapseChanges(records) {
		// a deleted id skips resolving
		ids := &out.DeletedIDs
		if rec.changeType != changeDelete {
			ids = &wanted
		}
		// very important toLower normalization here
		if err := ids.add(rec.entityType, strings.ToLower(rec.entityID)); err != nil {
			return Changes{}, err
		}
	}

	// resolve each item by its id, getting its latest state and collapsing any changes in the delta
	grocery, err := fetchGroceryByIDs(ctx, groupID, wanted.Grocery)
	if err != nil {
		return Changes{}, err
	}
	meals, err := fetchMealPlansByIDs(ctx, groupID, wanted.Meal)
	if err != nil {
		return Changes{}, err
	}
	receipts, err := fetchReceiptsByIDs(ctx, groupID, wanted.Receipt)
	if err != nil {
		return Changes{}, err
	}

	// any changes to items that then get deleted just get sent as deletions
	resolve(wanted.Grocery, grocery, &out.DeletedIDs.Grocery, &out.Grocery)
	resolve(wanted.Meal, meals, &out.DeletedIDs.Meal, &out.Meal)
	resolve(wanted.Receipt, receipts, &out.DeletedIDs.Receipt, &out.Receipt)
	return out, nil
}

func resolve[T any](wanted []string, found map[string]T, deleted *[]string, upserts *[]T) {
	for _, id := range wanted {
		if row, ok := found[id]; ok {
			*upserts = append(*upserts, row)
		} else {
			*deleted = append(*deleted, id)
		}
	}
}

// ledgerRows reads the group's change records in the window (afterSeq, nextSeq].
func ledgerRows(ctx context.Context, groupID string, afterSeq, nextSeq int64) ([]changeRecord, error) {
	rows, err := db.Query(ctx,
		`SELECT seq, entity_type, entity_id, change_type FROM group_changelog
		 WHERE group_id = $1 AND seq > $2 AND seq <= $3 ORDER BY seq`,
		groupID, afterSeq, nextSeq)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	records := []changeRecord{}
	for rows.Next() {
		var rec changeRecord
		if err := rows.Scan(&rec.seq, &rec.entityType, &rec.entityID, &rec.changeType); err != nil {
			return nil, err
		}
		records = append(records, rec)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return records, nil
}

// resolve every item in the changelog, per item type

func fetchGroceryByIDs(ctx context.Context, groupID string, ids []string) (map[string]models.GroceryItem, error) {
	rows, err := db.Query(ctx,
		`SELECT id, name, category, is_needed, is_shopping_checked, group_id
		 FROM grocery_items WHERE group_id = $1 AND id = ANY($2::uuid[])`,
		groupID, ids)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	found := make(map[string]models.GroceryItem, len(ids))
	for rows.Next() {
		var item models.GroceryItem
		if err := rows.Scan(&item.ID, &item.Name, &item.Category, &item.IsNeeded, &item.IsShoppingChecked, &item.GroupID); err != nil {
			return nil, err
		}
		found[item.ID] = item
	}
	return found, rows.Err()
}

func fetchMealPlansByIDs(ctx context.Context, groupID string, ids []string) (map[string]models.MealPlan, error) {
	rows, err := db.Query(ctx,
		`SELECT id, date, meal_description, group_id
		 FROM meal_plans WHERE group_id = $1 AND id = ANY($2::uuid[])`,
		groupID, ids)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	found := make(map[string]models.MealPlan, len(ids))
	for rows.Next() {
		var meal models.MealPlan
		if err := rows.Scan(&meal.ID, &meal.Date, &meal.MealDescription, &meal.GroupID); err != nil {
			return nil, err
		}
		found[meal.ID] = meal
	}
	return found, rows.Err()
}

func fetchReceiptsByIDs(ctx context.Context, groupID string, ids []string) (map[string]models.Receipt, error) {
	rows, err := db.Query(ctx,
		`SELECT id, date, total_amount, purchased_by, items, notes, group_id
		 FROM receipts WHERE group_id = $1 AND id = ANY($2::uuid[])`,
		groupID, ids)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	found := make(map[string]models.Receipt, len(ids))
	for rows.Next() {
		var receipt models.Receipt
		if err := rows.Scan(&receipt.ID, &receipt.Date, &receipt.TotalAmount, &receipt.PurchasedBy, &receipt.Items, &receipt.Notes, &receipt.GroupID); err != nil {
			return nil, err
		}
		found[receipt.ID] = receipt
	}
	return found, rows.Err()
}

// send empty lists and not nulls!
func emptyChanges(isFull bool, nextSeq int64) Changes {
	return Changes{
		IsFull:  isFull,
		NextSeq: nextSeq,
		Grocery: []models.GroceryItem{},
		Meal:    []models.MealPlan{},
		Receipt: []models.Receipt{},
		DeletedIDs: IDsByType{
			Grocery: []string{},
			Meal:    []string{},
			Receipt: []string{},
		},
	}
}

// set bounds on each changelog read, so we don't race any concurrent changes
func ledgerBounds(ctx context.Context, groupID string) (nextSeq int64, oldest *int64, err error) {
	var newest *int64
	if err := db.QueryRow(ctx,
		`SELECT MAX(seq), MIN(seq) FROM group_changelog WHERE group_id = $1`, groupID,
	).Scan(&newest, &oldest); err != nil {
		return 0, nil, err
	}
	if newest == nil {
		return 0, nil, nil
	}
	return *newest, oldest, nil
}

// one row in the group change ledger
type changeRecord struct {
	seq        int64
	entityType string
	entityID   string
	changeType string
}

// reduce ledger rows to the latest change per entity, so we only resolve each item once
func collapseChanges(records []changeRecord) []changeRecord {
	latest := map[[2]string]changeRecord{}
	for _, rec := range records {
		latest[[2]string{rec.entityType, rec.entityID}] = rec
	}

	collapsed := make([]changeRecord, 0, len(latest))
	for _, rec := range records {
		key := [2]string{rec.entityType, rec.entityID}
		if latest[key] == rec {
			collapsed = append(collapsed, rec)
			delete(latest, key)
		}
	}
	return collapsed
}
