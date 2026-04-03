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

	if err := database.InitDB(); err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer database.CloseDB()

	// Start background task to clean up expired join codes
	go func() {
		ticker := time.NewTicker(1 * time.Hour)
		defer ticker.Stop()
		for range ticker.C {
			if err := database.DeleteExpiredJoinCodes(context.Background()); err != nil {
				log.Printf("Failed to delete expired join codes: %v", err)
			}
		}
	}()

	websocket.InitWebSocketManager()

	gin.SetMode(gin.ReleaseMode)
	r := gin.Default()

	config := cors.DefaultConfig()
	config.AllowAllOrigins = true
	config.AllowMethods = []string{"GET", "POST", "PATCH", "DELETE", "OPTIONS"}
	config.AllowHeaders = []string{"Origin", "Content-Type", "Accept", "Authorization"}
	r.Use(cors.New(config))

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

	protected.GET("/grocery-items", handlers.GetGroceryItems)
	protected.POST("/grocery-items", handlers.CreateGroceryItem)
	protected.PATCH("/grocery-items/:item_id", handlers.UpdateGroceryItem)
	protected.DELETE("/grocery-items/:item_id", handlers.DeleteGroceryItem)

	protected.GET("/meal-plans", handlers.GetMealPlans)
	protected.POST("/meal-plans", handlers.CreateMealPlan)
	protected.PATCH("/meal-plans/:meal_id", handlers.UpdateMealPlan)
	protected.DELETE("/meal-plans/:meal_id", handlers.DeleteMealPlan)

	protected.GET("/receipts", handlers.GetReceipts)
	protected.POST("/receipts", handlers.CreateReceipt)
	protected.PATCH("/receipts/:receipt_id", handlers.UpdateReceipt)
	protected.DELETE("/receipts/:receipt_id", handlers.DeleteReceipt)

	protected.POST("/users", handlers.CreateUser)
	protected.GET("/users/:username", handlers.GetUser)
	protected.PATCH("/users/:user_id", handlers.UpdateUser)
	protected.DELETE("/users/:user_id", handlers.DeleteUser)
	protected.GET("/users/me/groups", handlers.GetUserGroups)
	protected.GET("/users/me/active-group", handlers.GetActiveGroup)

	protected.POST("/groups", handlers.CreateGroup)
	protected.GET("/groups/:group_id", handlers.GetGroup)
	protected.PATCH("/groups/:group_id", handlers.UpdateGroup)
	protected.DELETE("/groups/:group_id", handlers.DeleteGroup)
	protected.POST("/groups/:group_id/users", handlers.AddUserToGroup)
	protected.GET("/groups/:group_id/users", handlers.GetGroupUsers)
	protected.DELETE("/groups/:group_id/users/:user_id", handlers.RemoveUserFromGroup)
	protected.POST("/groups/:group_id/invite", handlers.GenerateJoinCode)
	protected.POST("/groups/join", handlers.JoinGroupWithCode)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8000"
	}

	log.Printf("Server starting on port %s", port)
	srv := &http.Server{
		Addr:    ":" + port,
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
