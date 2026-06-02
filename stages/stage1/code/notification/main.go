// Package main - Apollo11 Notification Service
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/go-redis/redis/v8"
	"github.com/google/uuid"
)

// Notification represents a notification queued for delivery
type Notification struct {
	ID        string    `json:"id"`
	Type      string    `json:"type"` // email or sms
	Recipient string    `json:"recipient"`
	Subject   string    `json:"subject"`
	Body      string    `json:"body"`
	CreatedAt time.Time `json:"created_at"`
}

// NotificationRequest is the incoming request payload
type NotificationRequest struct {
	Type      string `json:"type" binding:"required,oneof=email sms"`
	Recipient string `json:"recipient" binding:"required"`
	Subject   string `json:"subject" binding:"required"`
	Body      string `json:"body" binding:"required"`
}

const (
	RedisQueueKey = "notifications:queue"
)

var redisClient *redis.Client

func main() {
	// Get Redis URL from environment
	redisURL := os.Getenv("REDIS_URL")
	if redisURL == "" {
		log.Fatal("REDIS_URL environment variable is required")
	}

	// Get port from environment, default to 8083
	port := os.Getenv("PORT")
	if port == "" {
		port = "8083"
	}

	// Parse Redis URL and create client
	opt, err := redis.ParseURL(redisURL)
	if err != nil {
		log.Fatalf("Failed to parse REDIS_URL: %v", err)
	}

	redisClient = redis.NewClient(opt)

	// Test Redis connection
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := redisClient.Ping(ctx).Err(); err != nil {
		log.Fatalf("Failed to connect to Redis: %v", err)
	}

	log.Printf("Connected to Redis at %s", redisURL)

	// Setup Gin router
	r := gin.Default()

	// Health check endpoint
	r.GET("/health", healthHandler)

	// Notification endpoints
	r.POST("/notifications", createNotificationHandler)
	r.GET("/notifications", getQueueDepthHandler)

	log.Printf("Notification service starting on :%s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

func healthHandler(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func createNotificationHandler(c *gin.Context) {
	var req NotificationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Invalid request body: " + err.Error(),
		})
		return
	}

	// Create notification with generated ID and timestamp
	notification := Notification{
		ID:        uuid.New().String(),
		Type:      req.Type,
		Recipient: req.Recipient,
		Subject:   req.Subject,
		Body:      req.Body,
		CreatedAt: time.Now().UTC(),
	}

	// Serialize to JSON
	data, err := json.Marshal(notification)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Failed to serialize notification",
		})
		return
	}

	// Push to Redis queue using LPUSH
	ctx := context.Background()
	if err := redisClient.LPush(ctx, RedisQueueKey, data).Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": fmt.Sprintf("Failed to enqueue notification: %v", err),
		})
		return
	}

	log.Printf("Enqueued notification %s (type=%s, recipient=%s)", notification.ID, notification.Type, notification.Recipient)

	c.JSON(http.StatusAccepted, gin.H{
		"id":     notification.ID,
		"queued": true,
	})
}

func getQueueDepthHandler(c *gin.Context) {
	ctx := context.Background()
	length, err := redisClient.LLen(ctx, RedisQueueKey).Result()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": fmt.Sprintf("Failed to get queue depth: %v", err),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"pending": length,
	})
}