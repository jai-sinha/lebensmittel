package handlers

import (
	"fmt"
	"strings"
	"time"

	"github.com/lebensmittel/backend/database"
	"github.com/lebensmittel/backend/models"

	"github.com/gin-gonic/gin"
)

func getRequestedGroupID(c *gin.Context) (string, error) {
	groupID := strings.TrimSpace(c.GetHeader("X-Group-ID"))
	if groupID == "" {
		return "", fmt.Errorf("X-Group-ID header required")
	}
	return groupID, nil
}

// GenerateExampleData creates example grocery items, a receipt, and a meal plan for a new group.
func GenerateExampleData(c *gin.Context, groupID string) error {
	groceryItems := []struct {
		Name     string
		Category string
	}{
		{"Eggs", "Essentials"},
		{"Olive oil", "Other"},
		{"Chicken breasts", "Protein"},
		{"Red onion", "Veggies"},
		{"Coffee beans", "Other"},
		{"Tortillas", "Carbs"},
		{"Jasmine rice", "Carbs"},
		{"Beer", "Essentials"},
		{"Whitefish", "Protein"},
		{"Salmon", "Protein"},
		{"Frozen pizza", "Essentials"},
		{"Toilet paper", "Household"},
		{"Cabbage", "Veggies"},
		{"Dishwasher pods", "Household"},
		{"Tofu", "Protein"},
		{"Bananas", "Essentials"},
		{"Leafy greens", "Veggies"},
		{"Avocados", "Essentials"},
		{"Turkey", "Essentials"},
		{"Ground beef", "Protein"},
		{"Spaghetti", "Essentials"},
		{"Milk", "Essentials"},
		{"Limes", "Essentials"},
		{"Garlic", "Other"},
		{"Sliced bread", "Essentials"},
		{"Pickles", "Veggies"},
	}

	for _, item := range groceryItems {
		newItem := models.NewGroceryItem(item.Name, item.Category, false, false, groupID)
		if err := database.CreateGroceryItem(c, newItem); err != nil {
			return fmt.Errorf("failed to create grocery item %s: %w", item.Name, err)
		}
	}

	now := time.Now()

	receiptItems := []string{
		"Milk", "Juice", "Eggs", "Turkey", "Cilantro", "Apple Cider Vinegar",
		"Pepperoni", "Shredded Mozzarella", "Parmesan", "Bacon", "Parsley",
		"Tomatoes", "Avocados",
	}
	notes := "Example receipt, feel free to delete me!"
	receipt := models.NewReceipt(now, 42.67, "Default", receiptItems, &notes, groupID)
	if _, err := database.CreateReceipt(c, receipt); err != nil {
		return fmt.Errorf("failed to create receipt: %w", err)
	}

	mealPlan := models.NewMealPlan(now, "Example Meal", groupID)
	if err := database.CreateMealPlan(c, mealPlan); err != nil {
		return fmt.Errorf("failed to create meal plan: %w", err)
	}

	return nil
}
