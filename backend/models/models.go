package models

import (
	"encoding/json"
	"time"

	"github.com/google/uuid"
)

type GroceryItem struct {
	ID                uuid.UUID `json:"id" db:"id"`
	Name              string    `json:"name" db:"name"`
	Category          string    `json:"category" db:"category"`
	IsNeeded          bool      `json:"isNeeded" db:"is_needed"`
	IsShoppingChecked bool      `json:"isShoppingChecked" db:"is_shopping_checked"`
	GroupID           string    `json:"groupId" db:"group_id"`
}

type MealPlan struct {
	ID              uuid.UUID `json:"id" db:"id"`
	Date            time.Time `json:"date" db:"date"`
	MealDescription string    `json:"mealDescription" db:"meal_description"`
	GroupID         string    `json:"groupId" db:"group_id"`
}

// with custom JSON serialization to format date as YYYY-MM-DD
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

type Receipt struct {
	ID          uuid.UUID `json:"id" db:"id"`
	Date        time.Time `json:"date" db:"date"`
	TotalAmount float64   `json:"totalAmount" db:"total_amount"`
	PurchasedBy string    `json:"purchasedBy" db:"purchased_by"`
	Items       string    `json:"-" db:"items"` // JSON string in database
	ItemsList   []string  `json:"items" db:"-"` // For JSON serialization
	Notes       *string   `json:"notes" db:"notes"`
	GroupID     string    `json:"groupId" db:"group_id"`
}

func (r Receipt) MarshalJSON() ([]byte, error) {
	type Alias Receipt

	// parse items from JSON string
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

func (r *Receipt) SetItems(items []string) error {
	itemsJSON, err := json.Marshal(items)
	if err != nil {
		return err
	}
	r.Items = string(itemsJSON)
	r.ItemsList = items
	return nil
}

func (r *Receipt) GetItems() ([]string, error) {
	var items []string
	if r.Items == "" {
		return items, nil
	}
	err := json.Unmarshal([]byte(r.Items), &items)
	return items, err
}

type Group struct {
	ID         string   `json:"id" db:"id"`
	Name       string   `json:"name" db:"name"`
	Categories []string `json:"categories" db:"categories"`
	Members    []string `json:"members" db:"members"`
}

func NewGroup(name string) *Group {
	return &Group{
		ID:         uuid.New().String(),
		Name:       name,
		Categories: []string{"Essentials", "Protein", "Veggies", "Carbs", "Household", "Other"},
		Members:    []string{"Default"},
	}
}
