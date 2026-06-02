// Package main - Apollo11 Circulation Service
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
	"github.com/google/uuid"
	_ "github.com/lib/pq"
)

var db *sql.DB

func main() {
	databaseURL := os.Getenv("DATABASE_URL")
	jwtSecret := os.Getenv("JWT_SECRET")

	if databaseURL == "" {
		log.Fatal("DATABASE_URL environment variable is required")
	}
	if jwtSecret == "" {
		log.Fatal("JWT_SECRET environment variable is required")
	}

	var err error
	db, err = sql.Open("postgres", databaseURL)
	if err != nil {
		log.Fatalf("Failed to open database connection: %v", err)
	}
	defer db.Close()

	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)

	if err := db.Ping(); err != nil {
		log.Fatalf("Failed to ping database: %v", err)
	}

	log.Println("Connected to PostgreSQL database")

	r := gin.Default()

	r.GET("/health", healthHandler)
	r.POST("/loans", authMiddleware(jwtSecret), createLoanHandler)
	r.GET("/loans", authMiddleware(jwtSecret), listLoansHandler)
	r.POST("/loans/:id/return", authMiddleware(jwtSecret), returnLoanHandler)
	r.POST("/reservations", authMiddleware(jwtSecret), createReservationHandler)
	r.GET("/reservations", authMiddleware(jwtSecret), listReservationsHandler)
	r.DELETE("/reservations/:id", authMiddleware(jwtSecret), cancelReservationHandler)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8082"
	}

	log.Printf("Circulation starting on :%s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

// healthHandler returns service health status
func healthHandler(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

// JWTClaims represents the JWT token claims
type JWTClaims struct {
	jwt.RegisteredClaims
}

// authMiddleware validates JWT token from Authorization header
func authMiddleware(jwtSecret string) gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Authorization header required"})
			c.Abort()
			return
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid authorization format"})
			c.Abort()
			return
		}

		tokenString := parts[1]

		token, err := jwt.ParseWithClaims(tokenString, &JWTClaims{}, func(token *jwt.Token) (interface{}, error) {
			if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
			}
			return []byte(jwtSecret), nil
		})

		if err != nil || !token.Valid {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid or expired token"})
			c.Abort()
			return
		}

		claims, ok := token.Claims.(*JWTClaims)
		if !ok {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid token claims"})
			c.Abort()
			return
		}

		userID := claims.Subject
		if userID == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Token missing subject claim"})
			c.Abort()
			return
		}

		c.Set("user_id", userID)
		c.Next()
	}
}

// getOrCreatePatron retrieves or creates a patron record for the given user_id
func getOrCreatePatron(userID string) (* PatronRecord, error) {
	patron := &PatronRecord{}

	// Try to find existing patron
	err := db.QueryRow(`
		SELECT id, user_id, card_number, created_at 
		FROM patrons 
		WHERE user_id = $1
	`, userID).Scan(&patron.ID, &patron.UserID, &patron.CardNumber, &patron.CreatedAt)

	if err == nil {
		return patron, nil
	}
	if err != sql.ErrNoRows {
		return nil, fmt.Errorf("query error: %w", err)
	}

	// Create new patron - auto-generate card number
	patronID := uuid.New().String()
	cardNumber := fmt.Sprintf("CIR-%s", strings.ReplaceAll(patronID[:8], "-", ""))

	_, err = db.Exec(`
		INSERT INTO patrons (id, user_id, card_number)
		VALUES ($1, $2, $3)
	`, patronID, userID, cardNumber)

	if err != nil {
		return nil, fmt.Errorf("failed to create patron: %w", err)
	}

	patron.ID = patronID
	patron.UserID = userID
	patron.CardNumber = cardNumber
	patron.CreatedAt = time.Now()

	return patron, nil
}

// PatronRecord holds patron data from the database
type PatronRecord struct {
	ID         string
	UserID     string
	CardNumber string
	CreatedAt  time.Time
}

// LoanResponse represents a loan in API responses
type LoanResponse struct {
	ID         string    `json:"id"`
	BookID     string    `json:"book_id"`
	BorrowedAt time.Time `json:"borrowed_at"`
	DueDate    time.Time `json:"due_date"`
	ReturnedAt time.Time `json:"returned_at,omitempty"`
	Status     string    `json:"status"`
}

// createLoanHandler handles POST /loans - borrow a book
func createLoanHandler(c *gin.Context) {
	userID := c.GetString("user_id")

	var req struct {
		BookID string `json:"book_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "book_id is required"})
		return
	}

	// Get or create patron
	patron, err := getOrCreatePatron(userID)
	if err != nil {
		log.Printf("Error getting/creating patron: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get patron"})
		return
	}

	// Check if user already has this book on active loan
	var existingLoanID string
	err = db.QueryRow(`
		SELECT id FROM loans 
		WHERE patron_id = $1 AND book_id = $2 AND status = 'active'
	`, patron.ID, req.BookID).Scan(&existingLoanID)

	if err == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "You already have an active loan for this book"})
		return
	}
	if err != sql.ErrNoRows {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		return
	}

	// Create loan with due_date = now + 14 days
	loanID := uuid.New().String()
	dueDate := time.Now().Add(14 * 24 * time.Hour)
	borrowedAt := time.Now()

	_, err = db.Exec(`
		INSERT INTO loans (id, patron_id, book_id, borrowed_at, due_date, status)
		VALUES ($1, $2, $3, $4, $5, 'active')
	`, loanID, patron.ID, req.BookID, borrowedAt, dueDate)

	if err != nil {
		log.Printf("Error creating loan: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create loan"})
		return
	}

	c.JSON(http.StatusCreated, LoanResponse{
		ID:         loanID,
		BookID:     req.BookID,
		BorrowedAt: borrowedAt,
		DueDate:    dueDate,
		Status:     "active",
	})
}

// listLoansHandler handles GET /loans - list current user's loans
func listLoansHandler(c *gin.Context) {
	userID := c.GetString("user_id")
	status := c.Query("status")

	// Get patron
	patron, err := getOrCreatePatron(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get patron"})
		return
	}

	query := `
		SELECT id, book_id, borrowed_at, due_date, returned_at, status 
		FROM loans 
		WHERE patron_id = $1
	`
	args := []interface{}{patron.ID}

	if status == "active" {
		query += " AND status = 'active'"
	} else if status == "returned" {
		query += " AND status = 'returned'"
	}
	// "all" or empty: no additional filter

	query += " ORDER BY borrowed_at DESC"

	rows, err := db.Query(query, args...)
	if err != nil {
		log.Printf("Error listing loans: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to list loans"})
		return
	}
	defer rows.Close()

	loans := []LoanResponse{}
	for rows.Next() {
		var loan LoanResponse
		var returnedAt sql.NullTime
		if err := rows.Scan(&loan.ID, &loan.BookID, &loan.BorrowedAt, &loan.DueDate, &returnedAt, &loan.Status); err != nil {
			log.Printf("Error scanning loan row: %v", err)
			continue
		}
		if returnedAt.Valid {
			loan.ReturnedAt = returnedAt.Time
		}
		loans = append(loans, loan)
	}

	c.JSON(http.StatusOK, loans)
}

// returnLoanHandler handles POST /loans/:id/return
func returnLoanHandler(c *gin.Context) {
	userID := c.GetString("user_id")
	loanID := c.Param("id")

	// Get patron
	patron, err := getOrCreatePatron(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get patron"})
		return
	}

	// Verify loan belongs to user and is active
	var currentStatus string
	err = db.QueryRow(`
		SELECT status FROM loans 
		WHERE id = $1 AND patron_id = $2
	`, loanID, patron.ID).Scan(&currentStatus)

	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "Loan not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		return
	}

	if currentStatus == "returned" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Loan already returned"})
		return
	}

	// Update loan to returned
	returnedAt := time.Now()
	_, err = db.Exec(`
		UPDATE loans 
		SET returned_at = $1, status = 'returned' 
		WHERE id = $2
	`, returnedAt, loanID)

	if err != nil {
		log.Printf("Error returning loan: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to return loan"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"id":         loanID,
		"returned_at": returnedAt,
		"status":     "returned",
	})
}

// ReservationResponse represents a reservation in API responses
type ReservationResponse struct {
	ID         string    `json:"id"`
	BookID     string    `json:"book_id"`
	ReservedAt time.Time `json:"reserved_at"`
	ExpiresAt  time.Time `json:"expires_at"`
	Status     string    `json:"status"`
}

// createReservationHandler handles POST /reservations
func createReservationHandler(c *gin.Context) {
	userID := c.GetString("user_id")

	var req struct {
		BookID string `json:"book_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "book_id is required"})
		return
	}

	// Get or create patron
	patron, err := getOrCreatePatron(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get patron"})
		return
	}

	// Check for existing active reservation for this book
	var existingID string
	err = db.QueryRow(`
		SELECT id FROM reservations 
		WHERE patron_id = $1 AND book_id = $2 AND status = 'active'
	`, patron.ID, req.BookID).Scan(&existingID)

	if err == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "You already have an active reservation for this book"})
		return
	}
	if err != sql.ErrNoRows {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		return
	}

	// Create reservation with expires_at = now + 7 days
	reservationID := uuid.New().String()
	reservedAt := time.Now()
	expiresAt := reservedAt.Add(7 * 24 * time.Hour)

	_, err = db.Exec(`
		INSERT INTO reservations (id, patron_id, book_id, reserved_at, expires_at, status)
		VALUES ($1, $2, $3, $4, $5, 'active')
	`, reservationID, patron.ID, req.BookID, reservedAt, expiresAt)

	if err != nil {
		log.Printf("Error creating reservation: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create reservation"})
		return
	}

	c.JSON(http.StatusCreated, ReservationResponse{
		ID:         reservationID,
		BookID:     req.BookID,
		ReservedAt: reservedAt,
		ExpiresAt:  expiresAt,
		Status:     "active",
	})
}

// listReservationsHandler handles GET /reservations
func listReservationsHandler(c *gin.Context) {
	userID := c.GetString("user_id")

	// Get patron
	patron, err := getOrCreatePatron(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get patron"})
		return
	}

	rows, err := db.Query(`
		SELECT id, book_id, reserved_at, expires_at, status 
		FROM reservations 
		WHERE patron_id = $1
		ORDER BY reserved_at DESC
	`, patron.ID)

	if err != nil {
		log.Printf("Error listing reservations: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to list reservations"})
		return
	}
	defer rows.Close()

	reservations := []ReservationResponse{}
	for rows.Next() {
		var res ReservationResponse
		if err := rows.Scan(&res.ID, &res.BookID, &res.ReservedAt, &res.ExpiresAt, &res.Status); err != nil {
			log.Printf("Error scanning reservation row: %v", err)
			continue
		}
		reservations = append(reservations, res)
	}

	c.JSON(http.StatusOK, reservations)
}

// cancelReservationHandler handles DELETE /reservations/:id
func cancelReservationHandler(c *gin.Context) {
	userID := c.GetString("user_id")
	reservationID := c.Param("id")

	// Get patron
	patron, err := getOrCreatePatron(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get patron"})
		return
	}

	// Verify reservation belongs to user
	var currentStatus string
	err = db.QueryRow(`
		SELECT status FROM reservations 
		WHERE id = $1 AND patron_id = $2
	`, reservationID, patron.ID).Scan(&currentStatus)

	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "Reservation not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		return
	}

	// Delete the reservation
	_, err = db.Exec(`DELETE FROM reservations WHERE id = $1`, reservationID)
	if err != nil {
		log.Printf("Error cancelling reservation: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to cancel reservation"})
		return
	}

	c.Status(http.StatusNoContent)
}