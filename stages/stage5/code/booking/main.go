package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	_ "github.com/lib/pq"
	"github.com/google/uuid"
)

var (
	db                 *sql.DB
	jwtSecret          string
	flightServiceURL   string
	identityServiceURL string
	notificationSvcURL string
	logger             = log.New(os.Stdout, "", 0)
)

func init() {
	jwtSecret = getEnv("JWT_SECRET", "apollo-airlines-dev-secret")
	flightServiceURL = getEnv("FLIGHT_SERVICE_URL", "http://flight:8081")
	identityServiceURL = getEnv("IDENTITY_SERVICE_URL", "http://identity:8080")
	notificationSvcURL = getEnv("NOTIFICATION_SERVICE_URL", "http://notification:8084")
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func addSSLMode(dsn string) string {
	if strings.Contains(dsn, "sslmode=") {
		return dsn
	}
	return dsn + "?sslmode=disable"
}

func logJSON(level, service, message, traceID, spanID string, extra ...map[string]interface{}) {
	entry := map[string]interface{}{
		"timestamp": time.Now().UTC().Format(time.RFC3339),
		"level":     level,
		"service":   service,
		"trace_id":  traceID,
		"span_id":   spanID,
		"message":   message,
	}
	for k, v := range extra[0] {
		entry[k] = v
	}
	b, _ := json.Marshal(entry)
	logger.Println(string(b))
}

type Booking struct {
	ID               string `json:"id"`
	BookingReference string `json:"bookingReference"`
	FlightID         string `json:"flightId"`
	UserID           string `json:"userId"`
	SeatNumber       string `json:"seatNumber,omitempty"`
	Status           string `json:"status"`
	CreatedAt        string `json:"createdAt"`
	UserEmail        string `json:"userEmail,omitempty"`
}

type CreateBookingRequest struct {
	FlightID string `json:"flightId"`
}

func initDB() {
	dbURL := getEnv("DATABASE_URL", "postgresql://postgres:***@booking-db:5432/booking")
	var err error
	db, err = sql.Open("postgres", addSSLMode(dbURL))
	if err != nil {
		logJSON("ERROR", "booking-service", fmt.Sprintf("DB open failed: %v", err), "", "", nil)
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	for {
		err = db.PingContext(ctx)
		if err == nil {
			break
		}
		logJSON("ERROR", "booking-service", fmt.Sprintf("DB not ready (will retry): %v", err), "", "", nil)
		select {
		case <-ctx.Done():
			logJSON("ERROR", "booking-service", fmt.Sprintf("DB connection timeout: %v", ctx.Err()), "", "", nil)
			return
		case <-time.After(2 * time.Second):
		}
	}
	logJSON("INFO", "booking-service", "Connected to booking DB", "", "", nil)
}

func generateRequestID() string {
	return uuid.New().String()
}

func callService(url, method, body, traceID string) (int, []byte) {
	req, _ := http.NewRequest(method, url, bytes.NewBuffer([]byte(body)))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Request-ID", traceID)
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return 0, nil
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, respBody
}

func main() {
	initDB()
	defer db.Close()

	r := gin.Default()

	r.Use(func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Request-ID")
		c.Header("Access-Control-Expose-Headers", "X-Request-ID")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	})

	r.Use(func(c *gin.Context) {
		requestID := c.GetHeader("X-Request-ID")
		if requestID == "" {
			requestID = generateRequestID()
		}
		c.Set("request_id", requestID)
		c.Header("X-Request-ID", requestID)
		c.Next()
	})

	// Stage 4: split /healthz into startup/live/ready probes. The legacy
	// /healthz and /readyz paths are kept returning 200 for back-compat.
	r.GET("/healthz", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	r.GET("/healthz/startup", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "starting"})
	})

	r.GET("/healthz/live", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "alive"})
	})

	r.GET("/healthz/ready", func(c *gin.Context) {
		if err := db.Ping(); err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"status": "error", "detail": "DB not reachable"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"status": "ready"})
	})

	r.GET("/readyz", func(c *gin.Context) {
		if err := db.Ping(); err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"status": "error", "detail": "DB not reachable"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	r.GET("/metrics", func(c *gin.Context) {
		var activeConns int
		db.QueryRow("SELECT count(*) FROM pg_stat_activity WHERE datname = 'booking'").Scan(&activeConns)
		c.JSON(http.StatusOK, gin.H{
			"service":                  "booking",
			"http_requests_total":      0,
			"http_request_duration_ms": 0,
			"db_connections_active":    activeConns,
		})
	})

r.POST("/api/bookings", authRequired(), func(c *gin.Context) {
		requestID, _ := c.Get("request_id")
		traceID := requestID.(string)
		claimsVal, _ := c.Get("claims")
		claims := claimsVal.(jwt.MapClaims)
		userID := claims["sub"].(string)

		var req CreateBookingRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request"})
			return
		}

		statusCode, body := callService(
			fmt.Sprintf("%s/api/users/%s", identityServiceURL, userID),
			"GET", "", traceID,
		)
		if statusCode != 200 {
			logJSON("WARN", "booking-service", "User check failed", traceID, "", nil)
			if statusCode == 403 {
				c.JSON(http.StatusForbidden, gin.H{"error": "Account is inactive"})
				return
			}
			c.JSON(http.StatusBadGateway, gin.H{"error": "User verification failed"})
			return
		}

		statusCode, body = callService(
			fmt.Sprintf("%s/api/flights/%s", flightServiceURL, req.FlightID),
			"GET", "", traceID,
		)
		if statusCode != 200 {
			if statusCode == 404 {
				c.JSON(http.StatusNotFound, gin.H{"error": "Flight not found"})
				return
			}
			c.JSON(http.StatusBadGateway, gin.H{"error": "Flight service unavailable"})
			return
		}
		var flight map[string]interface{}
		json.Unmarshal(body, &flight)
		if flight["status"] == "CANCELLED" || flight["status"] == "DEPARTED" {
			c.JSON(http.StatusUnprocessableEntity, gin.H{"error": "Flight is not available for booking"})
			return
		}

		statusCode, body = callService(
			fmt.Sprintf("%s/api/flights/%s/seats", flightServiceURL, req.FlightID),
			"PATCH", `{"delta": -1}`, traceID,
		)
		if statusCode != 200 {
			c.JSON(http.StatusConflict, gin.H{"error": "No seats available"})
			return
		}

		ref := fmt.Sprintf("AA-%d-%s", time.Now().Year(), strings.ToUpper(uuid.New().String()[:6]))
		var bk Booking
		var createdAt time.Time
		err := db.QueryRow(
			`INSERT INTO bookings (booking_reference, user_id, flight_id, status)
			 VALUES ($1, $2, $3, 'CONFIRMED')
			 RETURNING id, booking_reference, user_id, flight_id, status, created_at`,
			ref, userID, req.FlightID,
		).Scan(&bk.ID, &bk.BookingReference, &bk.UserID, &bk.FlightID, &bk.Status, &createdAt)
		if err != nil {
			logJSON("ERROR", "booking-service", fmt.Sprintf("Booking insert failed: %v", err), traceID, "", nil)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create booking"})
			return
		}
		bk.CreatedAt = createdAt.Format(time.RFC3339)

		email, _ := claims["email"].(string)
		notifyBody, _ := json.Marshal(map[string]interface{}{
			"type":      "BOOKING_CONFIRMED",
			"recipient": email,
			"payload":   flight,
		})
		go callService(fmt.Sprintf("%s/api/notify", notificationSvcURL), "POST", string(notifyBody), traceID)

		logJSON("INFO", "booking-service", "Booking created", traceID, "", map[string]interface{}{"ref": bk.BookingReference})
		c.JSON(http.StatusCreated, bk)
	})

	r.GET("/api/bookings/:id", authRequired(), func(c *gin.Context) {
		_, _ = c.Get("request_id")
		claimsVal, _ := c.Get("claims")
		claims := claimsVal.(jwt.MapClaims)
		userID := claims["sub"].(string)
		role := claims["role"].(string)
		id := c.Param("id")

		var bk Booking
		var createdAt time.Time
		var seatNumber sql.NullString
		err := db.QueryRow(
			`SELECT id, booking_reference, user_id, flight_id, seat_number, status, created_at FROM bookings WHERE id = $1`,
			id,
		).Scan(&bk.ID, &bk.BookingReference, &bk.UserID, &bk.FlightID, &seatNumber, &bk.Status, &createdAt)
		bk.SeatNumber = seatNumber.String
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "Booking not found"})
			return
		}
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "DB error"})
			return
		}
		if role != "ADMIN" && bk.UserID != userID {
			c.JSON(http.StatusForbidden, gin.H{"error": "Not authorized"})
			return
		}
		bk.CreatedAt = createdAt.Format(time.RFC3339)
		c.JSON(http.StatusOK, bk)
	})

	r.GET("/api/bookings", authRequired(), func(c *gin.Context) {
		requestID, _ := c.Get("request_id")
		traceID := requestID.(string)
		claimsVal, _ := c.Get("claims")
		claims := claimsVal.(jwt.MapClaims)
		userID := claims["sub"].(string)

		rows, err := db.Query(
			`SELECT id, booking_reference, user_id, flight_id, seat_number, status, created_at FROM bookings WHERE user_id = $1 ORDER BY created_at DESC`,
			userID,
		)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Query failed"})
			return
		}
		defer rows.Close()

		bookings := []Booking{}
		for rows.Next() {
			var bk Booking
			var createdAt time.Time
			var seatNumber sql.NullString
			err := rows.Scan(&bk.ID, &bk.BookingReference, &bk.UserID, &bk.FlightID, &seatNumber, &bk.Status, &createdAt)
			if err != nil {
				continue
			}
			bk.SeatNumber = seatNumber.String
			bk.CreatedAt = createdAt.Format(time.RFC3339)
			bookings = append(bookings, bk)
		}
		logJSON("INFO", "booking-service", "My bookings", traceID, "", map[string]interface{}{"count": len(bookings)})
		c.JSON(http.StatusOK, gin.H{"bookings": bookings})
	})

	r.GET("/api/admin/bookings", adminRequired(), func(c *gin.Context) {
		requestID, _ := c.Get("request_id")
		traceID := requestID.(string)
		claimsVal, _ := c.Get("claims")
		claims := claimsVal.(jwt.MapClaims)
		role := claims["role"].(string)
		if role != "ADMIN" {
			c.JSON(http.StatusForbidden, gin.H{"error": "Admin access required"})
			return
		}

		rows, err := db.Query(
			`SELECT id, booking_reference, user_id, flight_id, seat_number, status, created_at FROM bookings ORDER BY created_at DESC`,
		)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Query failed"})
			return
		}
		defer rows.Close()

		bookings := []Booking{}
		for rows.Next() {
			var bk Booking
			var createdAt time.Time
			var seatNumber sql.NullString
			err := rows.Scan(&bk.ID, &bk.BookingReference, &bk.UserID, &bk.FlightID, &seatNumber, &bk.Status, &createdAt)
			if err != nil {
				continue
			}
			bk.SeatNumber = seatNumber.String
			bk.CreatedAt = createdAt.Format(time.RFC3339)
			bookings = append(bookings, bk)
		}

		userMap := map[string]string{}
		statusCode, body := callService(fmt.Sprintf("%s/api/admin/users", identityServiceURL), "GET", "", traceID)
		if statusCode == 200 {
			var result struct {
				Users []struct {
					ID    string `json:"id"`
					Email string `json:"email"`
				} `json:"users"`
			}
			if json.Unmarshal(body, &result) == nil {
				for _, u := range result.Users {
					userMap[u.ID] = u.Email
				}
			}
		}

		type AdminBooking struct {
			ID               string `json:"id"`
			BookingReference string `json:"bookingReference"`
			FlightID         string `json:"flightId"`
			UserID           string `json:"userId"`
			UserEmail        string `json:"userEmail"`
			SeatNumber       string `json:"seatNumber,omitempty"`
			Status           string `json:"status"`
			CreatedAt        string `json:"createdAt"`
		}
		ab := make([]AdminBooking, len(bookings))
		for i, b := range bookings {
			ab[i] = AdminBooking{
				ID:               b.ID,
				BookingReference: b.BookingReference,
				FlightID:         b.FlightID,
				UserID:           b.UserID,
				UserEmail:        userMap[b.UserID],
				SeatNumber:       b.SeatNumber,
				Status:           b.Status,
				CreatedAt:        b.CreatedAt,
			}
		}

		logJSON("INFO", "booking-service", "Admin fetched all bookings", traceID, "", map[string]interface{}{"count": len(ab)})
		c.JSON(http.StatusOK, gin.H{"bookings": ab})
	})

	r.DELETE("/api/bookings/:id", authRequired(), func(c *gin.Context) {
		requestID, _ := c.Get("request_id")
		traceID := requestID.(string)
		claimsVal, _ := c.Get("claims")
		claims := claimsVal.(jwt.MapClaims)
		userID := claims["sub"].(string)
		role := claims["role"].(string)
		id := c.Param("id")

		var bk Booking
		err := db.QueryRow(
			`SELECT id, booking_reference, user_id, flight_id, status FROM bookings WHERE id = $1`,
			id,
		).Scan(&bk.ID, &bk.BookingReference, &bk.UserID, &bk.FlightID, &bk.Status)
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "Booking not found"})
			return
		}
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "DB error"})
			return
		}
		if role != "ADMIN" && bk.UserID != userID {
			c.JSON(http.StatusForbidden, gin.H{"error": "Not authorized"})
			return
		}
		if bk.Status == "CANCELLED" {
			c.JSON(http.StatusUnprocessableEntity, gin.H{"error": "Booking already cancelled"})
			return
		}

		_, err = db.Exec(`UPDATE bookings SET status = 'CANCELLED', updated_at = NOW() WHERE id = $1`, id)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Cancel failed"})
			return
		}

		go callService(
			fmt.Sprintf("%s/api/flights/%s/seats", flightServiceURL, bk.FlightID),
			"PATCH", `{"delta": 1}`, traceID,
		)

		email, _ := claims["email"].(string)
		notifyBody, _ := json.Marshal(map[string]interface{}{
			"type":      "BOOKING_CANCELLED",
			"recipient": email,
			"payload":   map[string]string{"bookingReference": bk.BookingReference},
		})
		go callService(fmt.Sprintf("%s/api/notify", notificationSvcURL), "POST", string(notifyBody), traceID)

		logJSON("INFO", "booking-service", "Booking cancelled", traceID, "", map[string]interface{}{"id": id})
		c.JSON(http.StatusOK, gin.H{"message": "Booking cancelled"})
	})

	port := getEnv("PORT", "8082")

	srv := &http.Server{Addr: ":" + port, Handler: r}

	go func() {
		logJSON("INFO", "booking-service", fmt.Sprintf("Starting on :%s", port), "", "", nil)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logJSON("ERROR", "booking-service", fmt.Sprintf("Server error: %v", err), "", "", nil)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
	<-quit
	logJSON("INFO", "booking-service", "Received SIGTERM, shutting down gracefully", "", "", nil)

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		logJSON("ERROR", "booking-service", fmt.Sprintf("Shutdown error: %v", err), "", "", nil)
	}

	if err := db.Close(); err != nil {
		logJSON("ERROR", "booking-service", fmt.Sprintf("DB close error: %v", err), "", "", nil)
	}
	logJSON("INFO", "booking-service", "Server stopped", "", "", nil)
}

func adminRequired() gin.HandlerFunc {
	return func(c *gin.Context) {
		auth := c.GetHeader("Authorization")
		if auth == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Missing authorization"})
			c.Abort()
			return
		}
		parts := strings.SplitN(auth, " ", 2)
		if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid authorization format"})
			c.Abort()
			return
		}
		tokenString := parts[1]
		token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
			return []byte(jwtSecret), nil
		})
		if err != nil || !token.Valid {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid or expired token"})
			c.Abort()
			return
		}
		claims, ok := token.Claims.(jwt.MapClaims)
		if !ok {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid token claims"})
			c.Abort()
			return
		}
		if claims["role"] != "ADMIN" {
			c.JSON(http.StatusForbidden, gin.H{"error": "Admin access required"})
			c.Abort()
			return
		}
		c.Set("claims", claims)
		c.Set("user_id", claims["sub"])
		c.Set("role", claims["role"])
		c.Next()
	}
}

func authRequired() gin.HandlerFunc {
	return func(c *gin.Context) {
		auth := c.GetHeader("Authorization")
		if auth == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Missing authorization"})
			c.Abort()
			return
		}
		parts := strings.SplitN(auth, " ", 2)
		if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid authorization format"})
			c.Abort()
			return
		}
		tokenString := parts[1]
		token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
			return []byte(jwtSecret), nil
		})
		if err != nil || !token.Valid {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid or expired token"})
			c.Abort()
			return
		}
		claims, ok := token.Claims.(jwt.MapClaims)
		if !ok {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid token claims"})
			c.Abort()
			return
		}
		c.Set("claims", claims)
		c.Set("user_id", claims["sub"])
		c.Set("role", claims["role"])
		c.Next()
	}
}