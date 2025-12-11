package main

import (
	"encoding/json"
	"time"

	"github.com/google/uuid"
)

// GroceryItem represents a grocery item in the database
type GroceryItem struct {
	ID                string `json:"id" db:"id"`
	Name              string `json:"name" db:"name"`
	Category          string `json:"category" db:"category"`
	IsNeeded          bool   `json:"isNeeded" db:"is_needed"`
	IsShoppingChecked bool   `json:"isShoppingChecked" db:"is_shopping_checked"`
}

// NewGroceryItem creates a new grocery item with a generated UUID
func NewGroceryItem(name, category string, isNeeded, isShoppingChecked bool) *GroceryItem {
	return &GroceryItem{
		ID:                uuid.New().String(),
		Name:              name,
		Category:          category,
		IsNeeded:          isNeeded,
		IsShoppingChecked: isShoppingChecked,
	}
}

// MealPlan represents a meal plan for a specific date
type MealPlan struct {
	ID              string    `json:"id" db:"id"`
	Date            time.Time `json:"date" db:"date"`
	MealDescription string    `json:"mealDescription" db:"meal_description"`
}

// MarshalJSON customizes JSON serialization to format date as YYYY-MM-DD
func (m MealPlan) MarshalJSON() ([]byte, error) {
	type Alias MealPlan
	return json.Marshal(&struct {
		Date string `json:"date"`
		*Alias
	}{
		Date:  m.Date.Format("2006-01-02"),
		Alias: (*Alias)(&m),
	})
}

// NewMealPlan creates a new meal plan with a generated UUID
func NewMealPlan(date time.Time, mealDescription string) *MealPlan {
	return &MealPlan{
		ID:              uuid.New().String(),
		Date:            date,
		MealDescription: mealDescription,
	}
}

// Receipt represents a receipt in the database
type Receipt struct {
	ID          string    `json:"id" db:"id"`
	Date        time.Time `json:"date" db:"date"`
	TotalAmount float64   `json:"totalAmount" db:"total_amount"`
	PurchasedBy string    `json:"purchasedBy" db:"purchased_by"`
	Items       string    `json:"-" db:"items"` // JSON string in database
	ItemsList   []string  `json:"items" db:"-"` // For JSON serialization
	Notes       *string   `json:"notes" db:"notes"`
}

// MarshalJSON customizes JSON serialization for Receipt
func (r Receipt) MarshalJSON() ([]byte, error) {
	type Alias Receipt

	// Parse items from JSON string
	var items []string
	if r.Items != "" {
		json.Unmarshal([]byte(r.Items), &items)
	}
	if items == nil {
		items = []string{}
	}

	return json.Marshal(&struct {
		Date  string   `json:"date"`
		Items []string `json:"items"`
		*Alias
	}{
		Date:  r.Date.Format("2006-01-02"),
		Items: items,
		Alias: (*Alias)(&r),
	})
}

// NewReceipt creates a new receipt with a generated UUID
func NewReceipt(date time.Time, totalAmount float64, purchasedBy string, items []string, notes *string) *Receipt {
	itemsJSON, _ := json.Marshal(items)
	return &Receipt{
		ID:          uuid.New().String(),
		Date:        date,
		TotalAmount: totalAmount,
		PurchasedBy: purchasedBy,
		Items:       string(itemsJSON),
		ItemsList:   items,
		Notes:       notes,
	}
}

// SetItems sets the items for a receipt (converts slice to JSON string)
func (r *Receipt) SetItems(items []string) error {
	itemsJSON, err := json.Marshal(items)
	if err != nil {
		return err
	}
	r.Items = string(itemsJSON)
	r.ItemsList = items
	return nil
}

// GetItems returns the items as a slice (parses JSON string)
func (r *Receipt) GetItems() ([]string, error) {
	var items []string
	if r.Items == "" {
		return items, nil
	}
	err := json.Unmarshal([]byte(r.Items), &items)
	return items, err
}
