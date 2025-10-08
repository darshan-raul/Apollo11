package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/go-redis/redis/v8"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/joho/godotenv"
	_ "github.com/lib/pq"
)

// Configuration
type Config struct {
	DatabaseURL string
	RedisURL    string
	JWTSecret   string
	Port        string
}

// Database models
type User struct {
	ID       int    `json:"id" db:"id"`
	Username string `json:"username" db:"username"`
	Email    string `json:"email" db:"email"`
	FullName string `json:"full_name" db:"full_name"`
	IsActive bool   `json:"is_active" db:"is_active"`
}

type Stage struct {
	ID          int    `json:"id" db:"id"`
	Name        string `json:"name" db:"name"`
	Description string `json:"description" db:"description"`
	MaxAttempts int    `json:"max_attempts" db:"max_attempts"`
}

type StageProgress struct {
	ID               int       `json:"id" db:"id"`
	UserID           int       `json:"user_id" db:"user_id"`
	StageID          int       `json:"stage_id" db:"stage_id"`
	Status           string    `json:"status" db:"status"`
	Attempts         int       `json:"attempts" db:"attempts"`
	CompletedAt      *time.Time `json:"completed_at" db:"completed_at"`
	SimulationResult *string   `json:"simulation_result" db:"simulation_result"`
	SimulationData   *string   `json:"simulation_data" db:"simulation_data"`
}

type SimulationRequest struct {
	UserID          int                    `json:"user_id"`
	StageID         int                    `json:"stage_id"`
	AttemptNumber   int                    `json:"attempt_number"`
	SimulationData  map[string]interface{} `json:"simulation_data"`
}

type SimulationResponse struct {
	UserID          int                    `json:"user_id"`
	StageID         int                    `json:"stage_id"`
	AttemptNumber   int                    `json:"attempt_number"`
	Result          string                 `json:"result"`
	Message         string                 `json:"message"`
	SimulationData  map[string]interface{} `json:"simulation_data"`
	Timestamp       time.Time              `json:"timestamp"`
}

type UserStats struct {
	UserID          int     `json:"user_id"`
	Username        string  `json:"username"`
	FullName        string  `json:"full_name"`
	TotalStages     int     `json:"total_stages"`
	CompletedStages int     `json:"completed_stages"`
	CurrentStage    int     `json:"current_stage"`
	TotalAttempts   int     `json:"total_attempts"`
	SuccessRate     float64 `json:"success_rate"`
	LastActivity    *time.Time `json:"last_activity"`
}

type SystemStats struct {
	TotalUsers             int            `json:"total_users"`
	ActiveUsers            int            `json:"active_users"`
	TotalSimulations       int            `json:"total_simulations"`
	SuccessRate            float64        `json:"success_rate"`
	AverageCompletionTime  *float64       `json:"average_completion_time"`
	StageCompletionStats   map[int]int    `json:"stage_completion_stats"`
}

// Global variables
var (
	db    *sql.DB
	rdb   *redis.Client
	cfg   Config
)

// Initialize configuration
func initConfig() {
	godotenv.Load()
	
	cfg = Config{
		DatabaseURL: getEnv("DATABASE_URL", "postgres://apollo11:apollo11@postgres:5432/apollo11?sslmode=disable"),
		RedisURL:    getEnv("REDIS_URL", "redis://redis:6379"),
		JWTSecret:   getEnv("JWT_SECRET", "apollo11-secret-key"),
		Port:        getEnv("PORT", "8080"),
	}
}

// Get environment variable with default
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// Initialize database connection
func initDatabase() {
	var err error
	db, err = sql.Open("postgres", cfg.DatabaseURL)
	if err != nil {
		log.Fatal("Failed to connect to database:", err)
	}

	if err = db.Ping(); err != nil {
		log.Fatal("Failed to ping database:", err)
	}

	log.Println("Database connected successfully")
}

// Initialize Redis connection
func initRedis() {
	opt, err := redis.ParseURL(cfg.RedisURL)
	if err != nil {
		log.Fatal("Failed to parse Redis URL:", err)
	}

	rdb = redis.NewClient(opt)
	
	ctx := context.Background()
	if err := rdb.Ping(ctx).Err(); err != nil {
		log.Fatal("Failed to connect to Redis:", err)
	}

	log.Println("Redis connected successfully")
}

// JWT middleware
func authMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		tokenString := c.GetHeader("Authorization")
		if tokenString == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Authorization header required"})
			c.Abort()
			return
		}

		if len(tokenString) < 7 || tokenString[:7] != "Bearer " {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid authorization format"})
			c.Abort()
			return
		}

		tokenString = tokenString[7:]
		token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
			return []byte(cfg.JWTSecret), nil
		})

		if err != nil || !token.Valid {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid token"})
			c.Abort()
			return
		}

		claims, ok := token.Claims.(jwt.MapClaims)
		if !ok {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid token claims"})
			c.Abort()
			return
		}

		userID, ok := claims["user_id"].(float64)
		if !ok {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID in token"})
			c.Abort()
			return
		}

		c.Set("user_id", int(userID))
		c.Next()
	}
}

// Start simulation endpoint
func startSimulation(c *gin.Context) {
	var req SimulationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate user exists
	var user User
	err := db.QueryRow("SELECT id, username, email, full_name, is_active FROM users WHERE id = $1", req.UserID).Scan(
		&user.ID, &user.Username, &user.Email, &user.FullName, &user.IsActive)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	// Get stage progress
	var progress StageProgress
	err = db.QueryRow(`
		SELECT id, user_id, stage_id, status, attempts, completed_at, simulation_result, simulation_data
		FROM stage_progress 
		WHERE user_id = $1 AND stage_id = $2
	`, req.UserID, req.StageID).Scan(
		&progress.ID, &progress.UserID, &progress.StageID, &progress.Status,
		&progress.Attempts, &progress.CompletedAt, &progress.SimulationResult, &progress.SimulationData)

	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Stage progress not found"})
		return
	}

	// Check if stage can be started
	if progress.Status != "available" && progress.Status != "failed" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Stage is not available for simulation"})
		return
	}

	// Update progress to in_progress
	_, err = db.Exec(`
		UPDATE stage_progress 
		SET status = 'in_progress', attempts = attempts + 1, updated_at = NOW()
		WHERE id = $1
	`, progress.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update stage progress"})
		return
	}

	// Generate simulation ID
	simulationID := uuid.New().String()

	// Publish simulation request to Redis
	simulationReq := SimulationRequest{
		UserID:         req.UserID,
		StageID:        req.StageID,
		AttemptNumber:  progress.Attempts + 1,
		SimulationData: req.SimulationData,
	}

	reqData, _ := json.Marshal(simulationReq)
	ctx := context.Background()
	err = rdb.Publish(ctx, "simulation_requests", string(reqData)).Err()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to publish simulation request"})
		return
	}

	// Store simulation ID for tracking
	rdb.Set(ctx, fmt.Sprintf("simulation:%s", simulationID), reqData, time.Hour)

	c.JSON(http.StatusOK, gin.H{
		"message":        "Simulation started",
		"simulation_id":  simulationID,
		"user_id":        req.UserID,
		"stage_id":       req.StageID,
		"attempt_number": progress.Attempts + 1,
	})
}

// Process simulation response
func processSimulationResponse(c *gin.Context) {
	var resp SimulationResponse
	if err := c.ShouldBindJSON(&resp); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Update stage progress based on simulation result
	var status string
	var completedAt *time.Time
	if resp.Result == "success" {
		status = "completed"
		now := time.Now()
		completedAt = &now
	} else {
		status = "failed"
	}

	// Get current progress
	var progress StageProgress
	err := db.QueryRow(`
		SELECT id, user_id, stage_id, status, attempts, completed_at, simulation_result, simulation_data
		FROM stage_progress 
		WHERE user_id = $1 AND stage_id = $2
	`, resp.UserID, resp.StageID).Scan(
		&progress.ID, &progress.UserID, &progress.StageID, &progress.Status,
		&progress.Attempts, &progress.CompletedAt, &progress.SimulationResult, &progress.SimulationData)

	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Stage progress not found"})
		return
	}

	// Update progress
	simulationDataJSON, _ := json.Marshal(resp.SimulationData)
	_, err = db.Exec(`
		UPDATE stage_progress 
		SET status = $1, completed_at = $2, simulation_result = $3, simulation_data = $4, updated_at = NOW()
		WHERE id = $5
	`, status, completedAt, resp.Result, string(simulationDataJSON), progress.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update stage progress"})
		return
	}

	// Log simulation
	_, err = db.Exec(`
		INSERT INTO simulation_logs (user_id, stage_id, attempt_number, result, message, simulation_data, timestamp)
		VALUES ($1, $2, $3, $4, $5, $6, NOW())
	`, resp.UserID, resp.StageID, resp.AttemptNumber, resp.Result, resp.Message, string(simulationDataJSON))
	if err != nil {
		log.Printf("Failed to log simulation: %v", err)
	}

	// If stage completed successfully, unlock next stage
	if resp.Result == "success" {
		unlockNextStage(resp.UserID, resp.StageID)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Simulation response processed"})
}

// Unlock next stage for user
func unlockNextStage(userID, currentStageID int) {
	nextStageID := currentStageID + 1
	if nextStageID > 11 { // Maximum 11 stages
		return
	}

	_, err := db.Exec(`
		UPDATE stage_progress 
		SET status = 'available', updated_at = NOW()
		WHERE user_id = $1 AND stage_id = $2 AND status = 'locked'
	`, userID, nextStageID)
	if err != nil {
		log.Printf("Failed to unlock next stage: %v", err)
	}
}

// Get user progress
func getUserProgress(c *gin.Context) {
	userID := c.GetInt("user_id")

	rows, err := db.Query(`
		SELECT sp.stage_id, s.name, s.description, sp.status, sp.attempts, sp.completed_at, sp.simulation_result
		FROM stage_progress sp
		JOIN stages s ON sp.stage_id = s.id
		WHERE sp.user_id = $1
		ORDER BY sp.stage_id
	`, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get user progress"})
		return
	}
	defer rows.Close()

	var progress []map[string]interface{}
	for rows.Next() {
		var stageID int
		var name, description, status string
		var attempts int
		var completedAt *time.Time
		var simulationResult *string

		err := rows.Scan(&stageID, &name, &description, &status, &attempts, &completedAt, &simulationResult)
		if err != nil {
			continue
		}

		stageData := map[string]interface{}{
			"stage_id": stageID,
			"name":     name,
			"description": description,
			"status":   status,
			"attempts": attempts,
		}

		if completedAt != nil {
			stageData["completed_at"] = completedAt.Format(time.RFC3339)
		}
		if simulationResult != nil {
			stageData["simulation_result"] = *simulationResult
		}

		progress = append(progress, stageData)
	}

	c.JSON(http.StatusOK, gin.H{
		"user_id": userID,
		"progress": progress,
	})
}

// Get user statistics
func getUserStats(c *gin.Context) {
	userID := c.GetInt("user_id")

	var stats UserStats
	err := db.QueryRow(`
		SELECT u.id, u.username, u.full_name,
		       COUNT(sp.stage_id) as total_stages,
		       COUNT(CASE WHEN sp.status = 'completed' THEN 1 END) as completed_stages,
		       COALESCE(MIN(CASE WHEN sp.status IN ('available', 'in_progress') THEN sp.stage_id END), 12) as current_stage,
		       SUM(sp.attempts) as total_attempts,
		       COALESCE(AVG(CASE WHEN sp.status = 'completed' THEN 1.0 ELSE 0.0 END), 0) as success_rate,
		       MAX(sp.updated_at) as last_activity
		FROM users u
		LEFT JOIN stage_progress sp ON u.id = sp.user_id
		WHERE u.id = $1
		GROUP BY u.id, u.username, u.full_name
	`, userID).Scan(
		&stats.UserID, &stats.Username, &stats.FullName,
		&stats.TotalStages, &stats.CompletedStages, &stats.CurrentStage,
		&stats.TotalAttempts, &stats.SuccessRate, &stats.LastActivity)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get user stats"})
		return
	}

	c.JSON(http.StatusOK, stats)
}

// Get system statistics
func getSystemStats(c *gin.Context) {
	var stats SystemStats
	stats.StageCompletionStats = make(map[int]int)

	// Get basic stats
	err := db.QueryRow(`
		SELECT 
			COUNT(DISTINCT u.id) as total_users,
			COUNT(DISTINCT CASE WHEN u.is_active THEN u.id END) as active_users,
			COUNT(sl.id) as total_simulations,
			COALESCE(AVG(CASE WHEN sl.result = 'success' THEN 1.0 ELSE 0.0 END), 0) as success_rate
		FROM users u
		LEFT JOIN simulation_logs sl ON u.id = sl.user_id
	`).Scan(&stats.TotalUsers, &stats.ActiveUsers, &stats.TotalSimulations, &stats.SuccessRate)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get system stats"})
		return
	}

	// Get stage completion stats
	rows, err := db.Query(`
		SELECT stage_id, COUNT(*) as completion_count
		FROM stage_progress
		WHERE status = 'completed'
		GROUP BY stage_id
		ORDER BY stage_id
	`)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var stageID, count int
			if err := rows.Scan(&stageID, &count); err == nil {
				stats.StageCompletionStats[stageID] = count
			}
		}
	}

	c.JSON(http.StatusOK, stats)
}

// Health check endpoint
func healthCheck(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":    "healthy",
		"timestamp": time.Now().Format(time.RFC3339),
		"service":   "apollo11-core-api",
	})
}

// Setup routes
func setupRoutes() *gin.Engine {
	r := gin.Default()

	// Health check
	r.GET("/health", healthCheck)

	// API routes
	api := r.Group("/api")
	{
		// Simulation endpoints
		api.POST("/simulation/start", startSimulation)
		api.POST("/simulation/response", processSimulationResponse)

		// Protected routes
		protected := api.Group("/")
		protected.Use(authMiddleware())
		{
			protected.GET("/user/progress", getUserProgress)
			protected.GET("/user/stats", getUserStats)
			protected.GET("/system/stats", getSystemStats)
		}
	}

	return r
}

// Listen for simulation responses from Redis
func listenForSimulationResponses() {
	ctx := context.Background()
	pubsub := rdb.Subscribe(ctx, "simulation_responses")
	defer pubsub.Close()

	for {
		msg, err := pubsub.ReceiveMessage(ctx)
		if err != nil {
			log.Printf("Error receiving message: %v", err)
			continue
		}

		var resp SimulationResponse
		if err := json.Unmarshal([]byte(msg.Payload), &resp); err != nil {
			log.Printf("Error unmarshaling simulation response: %v", err)
			continue
		}

		// Process the simulation response
		processSimulationResponseFromRedis(resp)
	}
}

// Process simulation response from Redis
func processSimulationResponseFromRedis(resp SimulationResponse) {
	// Update stage progress based on simulation result
	var status string
	var completedAt *time.Time
	if resp.Result == "success" {
		status = "completed"
		now := time.Now()
		completedAt = &now
	} else {
		status = "failed"
	}

	// Update progress
	simulationDataJSON, _ := json.Marshal(resp.SimulationData)
	_, err := db.Exec(`
		UPDATE stage_progress 
		SET status = $1, completed_at = $2, simulation_result = $3, simulation_data = $4, updated_at = NOW()
		WHERE user_id = $5 AND stage_id = $6
	`, status, completedAt, resp.Result, string(simulationDataJSON), resp.UserID, resp.StageID)
	if err != nil {
		log.Printf("Failed to update stage progress: %v", err)
		return
	}

	// Log simulation
	_, err = db.Exec(`
		INSERT INTO simulation_logs (user_id, stage_id, attempt_number, result, message, simulation_data, timestamp)
		VALUES ($1, $2, $3, $4, $5, $6, NOW())
	`, resp.UserID, resp.StageID, resp.AttemptNumber, resp.Result, resp.Message, string(simulationDataJSON))
	if err != nil {
		log.Printf("Failed to log simulation: %v", err)
	}

	// If stage completed successfully, unlock next stage
	if resp.Result == "success" {
		unlockNextStage(resp.UserID, resp.StageID)
	}

	log.Printf("Processed simulation response for user %d, stage %d: %s", resp.UserID, resp.StageID, resp.Result)
}

func main() {
	// Initialize configuration
	initConfig()

	// Initialize database
	initDatabase()
	defer db.Close()

	// Initialize Redis
	initRedis()
	defer rdb.Close()

	// Start listening for simulation responses in a goroutine
	go listenForSimulationResponses()

	// Setup and start HTTP server
	r := setupRoutes()
	
	log.Printf("Starting Apollo 11 Core API server on port %s", cfg.Port)
	if err := r.Run(":" + cfg.Port); err != nil {
		log.Fatal("Failed to start server:", err)
	}
}
