package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/lebensmittel/backend/database"
	"github.com/lebensmittel/backend/handlers"
	"github.com/lebensmittel/backend/middleware"
	"github.com/lebensmittel/backend/websocket"
)

func main() {

	// Initialize database
	if err := database.InitDB(); err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer database.CloseDB()

	// Run database migrations
	if err := database.RunMigrations(context.Background()); err != nil {
		log.Fatalf("Failed to run migrations: %v", err)
	}

	// Initialize WebSocket manager
	websocket.InitWebSocketManager()

	// Create Gin router
	r := gin.Default()
	gin.SetMode(gin.ReleaseMode)

	// Configure CORS
	config := cors.DefaultConfig()
	config.AllowAllOrigins = true
	config.AllowMethods = []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"}
	config.AllowHeaders = []string{"Origin", "Content-Type", "Accept", "Authorization"}
	r.Use(cors.New(config))

	// API routes list for documentation
	apiRoutes := []map[string]any{
		{"route": "/", "methods": []string{"GET"}, "description": "Home route (API info)"},
		{"route": "/health", "methods": []string{"GET"}, "description": "Health check"},
		{"route": "/ws", "methods": []string{"GET"}, "description": "WebSocket connection"},
		{"route": "/api/grocery-items", "methods": []string{"GET"}, "description": "Get all grocery items"},
		{"route": "/api/grocery-items", "methods": []string{"POST"}, "description": "Create a grocery item"},
		{"route": "/api/grocery-items/:item_id", "methods": []string{"PUT"}, "description": "Update a grocery item"},
		{"route": "/api/grocery-items/:item_id", "methods": []string{"DELETE"}, "description": "Delete a grocery item"},
		{"route": "/api/meal-plans", "methods": []string{"GET"}, "description": "Get all meal plans"},
		{"route": "/api/meal-plans", "methods": []string{"POST"}, "description": "Create a meal plan"},
		{"route": "/api/meal-plans/:meal_id", "methods": []string{"PUT"}, "description": "Update a meal plan"},
		{"route": "/api/meal-plans/:meal_id", "methods": []string{"DELETE"}, "description": "Delete a meal plan"},
		{"route": "/api/receipts", "methods": []string{"GET"}, "description": "Get all receipts"},
		{"route": "/api/receipts", "methods": []string{"POST"}, "description": "Create a receipt"},
		{"route": "/api/receipts/:receipt_id", "methods": []string{"PUT"}, "description": "Update a receipt"},
		{"route": "/api/receipts/:receipt_id", "methods": []string{"DELETE"}, "description": "Delete a receipt"},
		{"route": "/api/register", "methods": []string{"POST"}, "description": "Register a new user"},
		{"route": "/api/login", "methods": []string{"POST"}, "description": "Login"},
		{"route": "/api/refresh", "methods": []string{"POST"}, "description": "Refresh access token"},
		{"route": "/api/users", "methods": []string{"POST"}, "description": "Create a user"},
		{"route": "/api/users/:username", "methods": []string{"GET"}, "description": "Get a user"},
		{"route": "/api/users/:user_id", "methods": []string{"PUT"}, "description": "Update a user"},
		{"route": "/api/users/:user_id", "methods": []string{"DELETE"}, "description": "Delete a user"},
		{"route": "/api/groups", "methods": []string{"POST"}, "description": "Create a group"},
		{"route": "/api/groups/:group_id", "methods": []string{"GET"}, "description": "Get a group"},
		{"route": "/api/groups/:group_id", "methods": []string{"PUT"}, "description": "Update a group"},
		{"route": "/api/groups/:group_id", "methods": []string{"DELETE"}, "description": "Delete a group"},
		{"route": "/api/groups/:group_id/users", "methods": []string{"POST"}, "description": "Add user to group"},
	}

	// Home route
	r.GET("/", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"message":   "Welcome to the Lebensmittel Backend API",
			"status":    "success",
			"version":   "2.0.0",
			"apiRoutes": apiRoutes,
		})
	})

	// Health check
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "healthy",
			"message": "Service is running",
		})
	})

	// WebSocket endpoint
	r.GET("/ws", websocket.HandleWebSocket)

	// API routes group
	api := r.Group("/api")

	// Public routes
	api.POST("/register", handlers.Register)
	api.POST("/login", handlers.Login)
	api.POST("/refresh", handlers.Refresh)

	// Protected routes
	protected := api.Group("/")
	protected.Use(middleware.AuthMiddleware())

	// Grocery Items routes
	protected.GET("/grocery-items", handlers.GetGroceryItems)
	protected.POST("/grocery-items", handlers.CreateGroceryItem)
	protected.PUT("/grocery-items/:item_id", handlers.UpdateGroceryItem)
	protected.DELETE("/grocery-items/:item_id", handlers.DeleteGroceryItem)

	// Meal Plans routes
	protected.GET("/meal-plans", handlers.GetMealPlans)
	protected.POST("/meal-plans", handlers.CreateMealPlan)
	protected.PUT("/meal-plans/:meal_id", handlers.UpdateMealPlan)
	protected.DELETE("/meal-plans/:meal_id", handlers.DeleteMealPlan)

	// Receipts routes
	protected.GET("/receipts", handlers.GetReceipts)
	protected.POST("/receipts", handlers.CreateReceipt)
	protected.PUT("/receipts/:receipt_id", handlers.UpdateReceipt)
	protected.DELETE("/receipts/:receipt_id", handlers.DeleteReceipt)

	// Users routes
	protected.POST("/users", handlers.CreateUser)
	protected.GET("/users/:username", handlers.GetUser)
	protected.PUT("/users/:user_id", handlers.UpdateUser)
	protected.DELETE("/users/:user_id", handlers.DeleteUser)

	// Groups routes
	protected.POST("/groups", handlers.CreateGroup)
	protected.GET("/groups/:group_id", handlers.GetGroup)
	protected.PUT("/groups/:group_id", handlers.UpdateGroup)
	protected.DELETE("/groups/:group_id", handlers.DeleteGroup)
	protected.POST("/groups/:group_id/users", handlers.AddUserToGroup)

	// Get port from environment or default to 8000
	port := os.Getenv("PORT")
	if port == "" {
		port = "8000"
	}

	log.Printf("Server starting on port %s", port)
	srv := &http.Server{
		Addr:    ":8000",
		Handler: r,
	}

	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("listen: %s\n", err)
		}
	}()

	// Wait for interrupt signal to gracefully shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Fatal("Server forced to shutdown:", err)
	}

	log.Println("Server exiting")
}
