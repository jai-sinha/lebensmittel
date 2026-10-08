package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/lebensmittel/backend/database"
	"github.com/lebensmittel/backend/models"
	"github.com/lebensmittel/backend/websocket"
)

func GetMealPlans(c *gin.Context) {
	gid := groupID(c)

	meals, err := database.GetAllMealPlans(c.Request.Context(), gid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if meals == nil { // ensure JSON never returns null
		meals = []models.MealPlan{}
	}

	c.JSON(http.StatusOK, gin.H{
		"mealPlans": meals,
		"count":     len(meals),
	})
}

func CreateMealPlan(c *gin.Context) {
	var data CreateMealPlanRequest
	if err := c.ShouldBindJSON(&data); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Date and mealDescription are required"})
		return
	}

	meal, err := data.toModel(groupID(c))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	created, isNew, err := database.CreateMealPlan(c.Request.Context(), &meal)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	createdOnce(c, created, isNew, groupID(c), "meal_plan_created")
}

func UpdateMealPlan(c *gin.Context) {
	mealID, _ := uuid.Parse(c.Param("meal_id"))

	var data map[string]any
	if err := c.ShouldBindJSON(&data); err != nil || len(data) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No data provided"})
		return
	}

	if dateStr, ok := data["date"].(string); ok {
		date, err := time.Parse("2006-01-02", dateStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid date format. Use YYYY-MM-DD"})
			return
		}
		data["date"] = date
	}

	gid := groupID(c)

	meal, err := database.UpdateMealPlan(c.Request.Context(), mealID, gid, data)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if meal == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Meal plan not found"})
		return
	}

	websocket.EmitEvent("meal_plan_updated", meal, meal.GroupID)

	c.JSON(http.StatusOK, meal)
}

func DeleteMealPlan(c *gin.Context) {
	mealID, _ := uuid.Parse(c.Param("meal_id"))

	gid := groupID(c)

	if err := database.DeleteMealPlan(c.Request.Context(), mealID, gid); err != nil {
		if err.Error() == "meal plan not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Meal plan not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}

	websocket.EmitEvent("meal_plan_deleted", gin.H{"id": mealID}, gid)

	c.JSON(http.StatusOK, gin.H{"message": "Meal plan deleted successfully"})
}
