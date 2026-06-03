// Package main - Apollo11 Fines Service
package main

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	_ "github.com/mattn/go-sqlite3"
)

// Config holds service configuration
type Config struct {
	DBPath      string
	Port        string
	JWT_SECRET  string
}

// Models

type Fine struct {
	ID        string  `json:"id"`
	PatronID  string  `json:"patron_id,omitempty"`
	LoanID    string  `json:"loan_id"`
	Amount    float64 `json:"amount"`
	Reason    string  `json:"reason"`
	Paid      bool    `json:"paid"`
	CreatedAt string `json:"created_at,omitempty"`
	PaidAt    string `json:"paid_at,omitempty"`
}

// Request/Response types

type FinesResponse struct {
	Fines       []Fine  `json:"fines"`
	TotalUnpaid float64 `json:"total_unpaid"`
}

type PayFineResponse struct {
	ID     string `json:"id"`
	Paid   bool   `json:"paid"`
	PaidAt string `json:"paid_at"`
}

type ErrorResponse struct {
	Error string `json:"error"`
}

// JWT Claims

type Claims struct {
	Sub   string `json:"sub"`
	Email string `json:"email"`
	Role  string `json:"role"`
	jwt.RegisteredClaims
}

// Global references
var (
	db         *sql.DB
	jwtSecret []byte
)

// initDB initializes the SQLite database
func initDB(dbPath string) (*sql.DB, error) {
	db, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	// Create fines table if not exists
	schema := `
	CREATE TABLE IF NOT EXISTS fines (
		id TEXT PRIMARY KEY,
		patron_id TEXT NOT NULL,
		loan_id TEXT NOT NULL,
		amount REAL NOT NULL,
		reason TEXT NOT NULL,
		paid INTEGER DEFAULT 0,
		created_at TEXT,
		paid_at TEXT
	);
	CREATE INDEX IF NOT EXISTS idx_fines_patron_id ON fines(patron_id);
	`
	_, err = db.Exec(schema)
	if err != nil {
		return nil, fmt.Errorf("failed to create schema: %w", err)
	}

	log.Println("Connected to SQLite")
	return db, nil
}

// Helper: extractBearerToken extracts JWT from Authorization header
func extractBearerToken(c *gin.Context) string {
	auth := c.GetHeader("Authorization")
	if !strings.HasPrefix(auth, "Bearer ") {
		return ""
	}
	return strings.TrimPrefix(auth, "Bearer ")
}

// Helper: validateToken validates JWT and returns claims
func validateToken(tokenString string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return jwtSecret, nil
	})
	if err != nil {
		return nil, err
	}

	if claims, ok := token.Claims.(*Claims); ok && token.Valid {
		return claims, nil
	}
	return nil, fmt.Errorf("invalid token")
}

// Helper: requireAuth middleware requires valid JWT
func requireAuth() gin.HandlerFunc {
	return func(c *gin.Context) {
		tokenString := extractBearerToken(c)
		if tokenString == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, ErrorResponse{Error: "missing authorization token"})
			return
		}

		claims, err := validateToken(tokenString)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, ErrorResponse{Error: "invalid token"})
			return
		}

		c.Set("user_id", claims.Sub)
		c.Set("user_role", claims.Role)
		c.Next()
	}
}

// --- Handlers ---

func healthHandler(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

// GET /fines - Get current user's fines
func listFinesHandler(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, ErrorResponse{Error: "user not authenticated"})
		return
	}
	patronID := userID.(string)

	rows, err := db.Query(`
		SELECT id, patron_id, loan_id, amount, reason, paid, created_at, paid_at
		FROM fines
		WHERE patron_id = ?
		ORDER BY created_at DESC
	`, patronID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: "failed to fetch fines"})
		return
	}
	defer rows.Close()

	fines := []Fine{}
	var totalUnpaid float64

	for rows.Next() {
		var f Fine
		var patronID, loanID, reason, createdAt, paidAt string
		var amount float64
		var paid int

		err := rows.Scan(&f.ID, &patronID, &loanID, &amount, &reason, &paid, &createdAt, &paidAt)
		if err != nil {
			continue
		}

		f.PatronID = patronID
		f.LoanID = loanID
		f.Amount = amount
		f.Reason = reason
		f.Paid = paid == 1
		f.CreatedAt = createdAt
		f.PaidAt = paidAt

		if !f.Paid {
			totalUnpaid += amount
		}

		fines = append(fines, f)
	}

	c.JSON(http.StatusOK, FinesResponse{
		Fines:       fines,
		TotalUnpaid: totalUnpaid,
	})
}

// POST /fines/:id/pay - Mark fine as paid
func payFineHandler(c *gin.Context) {
	fineID := c.Param("id")

	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, ErrorResponse{Error: "user not authenticated"})
		return
	}
	patronID := userID.(string)

	// Check fine exists and belongs to user
	var existingPatronID string
	var paid int
	err := db.QueryRow("SELECT patron_id, paid FROM fines WHERE id = ?", fineID).Scan(&existingPatronID, &paid)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, ErrorResponse{Error: "fine not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: "failed to fetch fine"})
		return
	}

	if existingPatronID != patronID {
		c.JSON(http.StatusNotFound, ErrorResponse{Error: "fine not found"})
		return
	}

	if paid == 1 {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: "fine already paid"})
		return
	}

	// Mark as paid
	paidAt := time.Now().UTC().Format(time.RFC3339)
	_, err = db.Exec("UPDATE fines SET paid = 1, paid_at = ? WHERE id = ?", paidAt, fineID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: "failed to mark fine as paid"})
		return
	}

	c.JSON(http.StatusOK, PayFineResponse{
		ID:     fineID,
		Paid:   true,
		PaidAt: paidAt,
	})
}

// main entry point
func main() {
	// Configuration
	cfg := Config{
		DBPath:      getEnv("FINES_DB_PATH", "/data/fines.db"),
		Port:        getEnv("PORT", "8084"),
		JWT_SECRET:  getEnv("JWT_SECRET", "default-secret-change-me"),
	}

	jwtSecret = []byte(cfg.JWT_SECRET)

	// Initialize database
	var err error
	db, err = initDB(cfg.DBPath)
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer db.Close()

	// Setup Gin router
	router := gin.Default()

	// Routes
	router.GET("/health", healthHandler)

	// Protected routes
	fines := router.Group("/fines")
	fines.Use(requireAuth())
	{
		fines.GET("", listFinesHandler)
		fines.POST("/:id/pay", payFineHandler)
	}

	// Start server
	addr := fmt.Sprintf(":%s", cfg.Port)
	log.Printf("Starting Fines Service on %s", addr)
	if err := router.Run(addr); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

// Helper: getEnv returns environment variable or default
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
