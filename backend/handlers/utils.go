package handlers

import (
	"context"
	"fmt"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/lebensmittel/backend/database"
	"github.com/lebensmittel/backend/models"
)

// getActiveGroupID determines the group ID to use for the request.
// It checks the "X-Group-ID" header. If present, it verifies the user is a member.
// If absent, it defaults to the user's first group.
func getActiveGroupID(c *gin.Context) (string, error) {
	userID := c.GetString("userID")
	if userID == "" {
		return "", fmt.Errorf("unauthorized")
	}

	// Get all groups for the user
	userGroups, err := database.GetUserGroups(c.Request.Context(), userID)
	if err != nil {
		return "", fmt.Errorf("failed to get user groups: %w", err)
	}
	if len(userGroups) == 0 {
		return "", fmt.Errorf("user has no groups")
	}

	// Check for X-Group-ID header
	requestedGroupID := c.GetHeader("X-Group-ID")

	if requestedGroupID != "" {
		// Verify membership
		isMember := false
		for _, g := range userGroups {
			if g.ID == requestedGroupID {
				isMember = true
				break
			}
		}
		if !isMember {
			return "", fmt.Errorf("user is not a member of the requested group")
		}
		return requestedGroupID, nil
	}

	// Default to the first group
	return userGroups[0].ID, nil
}

// GenerateExampleData creates example grocery items, a receipt, and a meal plan for a new group.
func GenerateExampleData(ctx context.Context, userID, groupID string) error {
	user, err := database.GetUserByID(ctx, userID)
	if err != nil {
		return fmt.Errorf("failed to fetch user: %w", err)
	}
	if user == nil {
		return fmt.Errorf("user not found")
	}

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
		newItem := models.NewGroceryItem(item.Name, item.Category, false, false, groupID, userID)
		if err := database.CreateGroceryItem(ctx, newItem); err != nil {
			return fmt.Errorf("failed to create grocery item %s: %w", item.Name, err)
		}
	}

	now := time.Now()

	receiptItems := []string{
		"Milk", "Juice", "Eggs", "Turkey", "Cilantro", "Apple Cider Vinegar",
		"Pepperoni", "Shredded Mozzarella", "Parmesan", "Bacon", "Parsley",
		"Tomatoes", "Avocados",
	}
	notes := "Example receipt"
	receipt := models.NewReceipt(now, 42.67, user.DisplayName, receiptItems, &notes, groupID, userID)
	if err := database.CreateReceipt(ctx, receipt); err != nil {
		return fmt.Errorf("failed to create receipt: %w", err)
	}

	mealPlan := models.NewMealPlan(now, "Example Meal", groupID, userID)
	if err := database.CreateMealPlan(ctx, mealPlan); err != nil {
		return fmt.Errorf("failed to create meal plan: %w", err)
	}

	return nil
}
