package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

// --- Configuration ---
var (
	DB_URL    = os.Getenv("DATABASE_URL")
	REDIS_URL = os.Getenv("REDIS_URL")
)

// --- Global Instances ---
var (
	db  *gorm.DB
	rdb *redis.Client
)

// --- Models ---
type User struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	Username  string    `gorm:"uniqueIndex" json:"username"`
	Password  string    `json:"-"` // In real app, hash this
	CreatedAt time.Time `json:"created_at"`
}

type Stage struct {
	ID          uint   `gorm:"primaryKey" json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
}

type StageProgress struct {
	ID          uint      `gorm:"primaryKey" json:"id"`
	UserID      uint      `gorm:"index" json:"user_id"`
	StageID     uint      `gorm:"index" json:"stage_id"`
	Status      string    `json:"status"` // locked, available, in_progress, completed, failed
	Attempts    int       `json:"attempts"`
	CompletedAt time.Time `json:"completed_at"`
}

type SimulationLog struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	UserID    uint      `json:"user_id"`
	StageID   uint      `json:"stage_id"`
	Result    string    `json:"result"` // success, failure
	Message   string    `json:"message"`
	Data      string    `json:"data"` // JSON string of telemetry
	Timestamp time.Time `json:"timestamp"`
}

// --- Database Setup ---
func initDB() {
	var err error
	if DB_URL == "" {
		DB_URL = "postgres://apollo11:apollo11@postgres:5432/apollo11?sslmode=disable"
	}

	db, err = gorm.Open(postgres.Open(DB_URL), &gorm.Config{})
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	// Auto Migrate
	err = db.AutoMigrate(&User{}, &Stage{}, &StageProgress{}, &SimulationLog{})
	if err != nil {
		log.Fatalf("Failed to migrate database: %v", err)
	}

	// Seed Stages if empty
	var count int64
	db.Model(&Stage{}).Count(&count)
	if count == 0 {
		stages := []Stage{
			{ID: 1, Name: "Physical Fitness Assessment", Description: "Test cardiovascular endurance and strength."},
			{ID: 2, Name: "Mental Health Screening", Description: "Psychological evaluation for stress resilience."},
			{ID: 3, Name: "Technical Knowledge Test", Description: "Exam on spacecraft systems and orbital mechanics."},
			{ID: 4, Name: "Emergency Procedures Training", Description: "Simulation of crisis scenarios."},
			{ID: 5, Name: "Space Suit Operations", Description: "EVA suit pressure management and mobility."},
			{ID: 6, Name: "Zero Gravity Simulation", Description: "Adaptation to weightlessness in parabolic flight."},
			{ID: 7, Name: "Mission Planning", Description: "Calculating orbital trajectories and fuel usage."},
			{ID: 8, Name: "Communication Protocols", Description: "Radio discipline and ground control comms."},
			{ID: 9, Name: "Equipment Familiarization", Description: "Hands-on training with onboard tools."},
			{ID: 10, Name: "Mission Simulation", Description: "Full dress rehearsal of the mission profile."},
			{ID: 11, Name: "Final Certification", Description: "Final review and "Go/No-Go" decision."},
		}
		db.Create(&stages)
	}
}

// --- Redis Setup ---
func initRedis() {
	if REDIS_URL == "" {
		REDIS_URL = "redis://redis:6379/0"
	}
	opt, err := redis.ParseURL(REDIS_URL)
	if err != nil {
		log.Fatalf("Failed to parse Redis URL: %v", err)
	}

	rdb = redis.NewClient(opt)
}

// --- Redis Subscriber ---
func subscribeToSimulationResults() {
	ctx := context.Background()
	pubsub := rdb.Subscribe(ctx, "simulation_responses")
	defer pubsub.Close()

	ch := pubsub.Channel()

	for msg := range ch {
		var result struct {
			UserID    uint            `json:"user_id"`
			StageID   uint            `json:"stage_id"`
			Result    string          `json:"result"`
			Message   string          `json:"message"`
			Data      json.RawMessage `json:"simulation_data"`
			Timestamp time.Time       `json:"timestamp"`
		}

		if err := json.Unmarshal([]byte(msg.Payload), &result); err != nil {
			log.Printf("Error unmarshalling simulation response: %v", err)
			continue
		}

		log.Printf("Received simulation result for User %d, Stage %d: %s", result.UserID, result.StageID, result.Result)

		// Update StageProgress
		var progress StageProgress
		if err := db.Where("user_id = ? AND stage_id = ?", result.UserID, result.StageID).First(&progress).Error; err != nil {
			log.Printf("Progress not found for user %d stage %d", result.UserID, result.StageID)
			continue
		}

		if result.Result == "success" {
			progress.Status = "completed"
			progress.CompletedAt = time.Now()

			// Unlock next stage
			var nextStage Stage
			if err := db.Where("id = ?", result.StageID+1).First(&nextStage).Error; err == nil {
				// Check if next progress exists
				var nextProgress StageProgress
				if err := db.Where("user_id = ? AND stage_id = ?", result.UserID, nextStage.ID).First(&nextProgress).Error; err != nil {
					// Create if not exists (should handle by create user trigger, but safe fallback)
					db.Create(&StageProgress{UserID: result.UserID, StageID: nextStage.ID, Status: "available"})
				} else {
					if nextProgress.Status == "locked" {
						nextProgress.Status = "available"
						db.Save(&nextProgress)
					}
				}
			}
		} else {
			progress.Status = "failed"
		}
		db.Save(&progress)

		// Log Simulation
		dataBytes, _ := json.Marshal(result.Data)
		simLog := SimulationLog{
			UserID:    result.UserID,
			StageID:   result.StageID,
			Result:    result.Result,
			Message:   result.Message,
			Data:      string(dataBytes),
			Timestamp: time.Now(),
		}
		db.Create(&simLog)
	}
}

// --- Handlers ---

// Register User
func register(c *gin.Context) {
	var input struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := c.BindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user := User{Username: input.Username, Password: input.Password, CreatedAt: time.Now()}
	if err := db.Create(&user).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create user"})
		return
	}

	// Initialize Stage Progress
	var stages []Stage
	db.Find(&stages)
	for _, s := range stages {
		status := "locked"
		if s.ID == 1 {
			status = "available"
		}
		db.Create(&StageProgress{UserID: user.ID, StageID: s.ID, Status: status})
	}

	c.JSON(http.StatusOK, user)
}

// Login (Simple)
func login(c *gin.Context) {
	var input struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := c.BindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var user User
	if err := db.Where("username = ? AND password = ?", input.Username, input.Password).First(&user).Error; err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid credentials"})
		return
	}

	c.JSON(http.StatusOK, user)
}

// Get Stages
func getStages(c *gin.Context) {
	var stages []Stage
	db.Order("id asc").Find(&stages)
	c.JSON(http.StatusOK, stages)
}

// Get User Progress
func getUserProgress(c *gin.Context) {
	userID := c.Param("user_id")
	var progress []StageProgress
	db.Where("user_id = ?", userID).Order("stage_id asc").Find(&progress)
	c.JSON(http.StatusOK, progress)
}

// Start Simulation
func startSimulation(c *gin.Context) {
	var input struct {
		UserID  uint `json:"user_id"`
		StageID uint `json:"stage_id"`
	}
	if err := c.BindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Verify progress
	var progress StageProgress
	if err := db.Where("user_id = ? AND stage_id = ?", input.UserID, input.StageID).First(&progress).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Stage not found for user"})
		return
	}

	if progress.Status == "locked" {
		c.JSON(http.StatusForbidden, gin.H{"error": "Stage is locked"})
		return
	}

	// Update to in_progress
	progress.Status = "in_progress"
	progress.Attempts++
	db.Save(&progress)

	// Publish to Redis
	payload := map[string]interface{}{
		"user_id":        input.UserID,
		"stage_id":       input.StageID,
		"attempt_number": progress.Attempts,
	}
	data, _ := json.Marshal(payload)
	rdb.Publish(context.Background(), "simulation_requests", data)

	c.JSON(http.StatusOK, gin.H{"status": "in_progress", "message": "Simulation started"})
}

func main() {
	initDB()
	initRedis()

	// Start Redis Subscriber in goroutine
	go subscribeToSimulationResults()

	r := gin.Default()

	// CORS (Simple for dev)
	r.Use(func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	})

	api := r.Group("/api")
	{
		api.POST("/register", register)
		api.POST("/login", login)
		api.GET("/stages", getStages)
		api.GET("/user/:user_id/progress", getUserProgress)
		api.POST("/simulation/start", startSimulation)
	}

	r.Run(":8080")
}
