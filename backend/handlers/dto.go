package handlers

import (
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/lebensmittel/backend/models"
)

type CreateGroceryItemRequest struct {
	ID                uuid.UUID `json:"id" binding:"required"`
	Name              string    `json:"name" binding:"required"`
	Category          string    `json:"category" binding:"required"`
	IsNeeded          *bool     `json:"isNeeded"`
	IsShoppingChecked *bool     `json:"isShoppingChecked"`
}

func (r CreateGroceryItemRequest) toModel(groupID string) models.GroceryItem {
	isNeeded := true
	if r.IsNeeded != nil {
		isNeeded = *r.IsNeeded
	}
	isShoppingChecked := false
	if r.IsShoppingChecked != nil {
		isShoppingChecked = *r.IsShoppingChecked
	}

	return models.GroceryItem{
		ID:                r.ID,
		Name:              r.Name,
		Category:          r.Category,
		IsNeeded:          isNeeded,
		IsShoppingChecked: isShoppingChecked,
		GroupID:           groupID,
	}
}

type CreateMealPlanRequest struct {
	ID              uuid.UUID `json:"id" binding:"required"`
	Date            string    `json:"date" binding:"required"`
	MealDescription string    `json:"mealDescription" binding:"required"`
}

func (r CreateMealPlanRequest) toModel(groupID string) (models.MealPlan, error) {
	date, err := parseDate(r.Date)
	if err != nil {
		return models.MealPlan{}, err
	}
	return models.MealPlan{
		ID:              r.ID,
		Date:            date,
		MealDescription: r.MealDescription,
		GroupID:         groupID,
	}, nil
}

type CreateReceiptRequest struct {
	ID          uuid.UUID `json:"id" binding:"required"`
	Date        string    `json:"date" binding:"required"`
	TotalAmount *float64  `json:"totalAmount" binding:"required"`
	PurchasedBy string    `json:"purchasedBy" binding:"required"`
	Notes       *string   `json:"notes"`
	Items       []string  `json:"items"`
}

func (r CreateReceiptRequest) toModel(groupID string) (models.Receipt, error) {
	date, err := parseDate(r.Date)
	if err != nil {
		return models.Receipt{}, err
	}

	return models.Receipt{
		ID:          r.ID,
		Date:        date,
		TotalAmount: *r.TotalAmount,
		PurchasedBy: r.PurchasedBy,
		ItemsList:   r.Items,
		Notes:       r.Notes,
		GroupID:     groupID,
	}, nil
}

func parseDate(value string) (time.Time, error) {
	date, err := time.Parse("2006-01-02", value)
	if err != nil {
		return time.Time{}, errors.New("Invalid date format. Use YYYY-MM-DD")
	}
	return date, nil
}
