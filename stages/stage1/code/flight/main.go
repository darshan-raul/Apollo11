package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	_ "github.com/lib/pq"
	"github.com/google/uuid"
)

var (
	db        *sql.DB
	jwtSecret string
	logger    = log.New(os.Stdout, "", 0)
)

func init() {
	jwtSecret = getEnv("JWT_SECRET", "apollo-airlines-dev-secret")
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

type Flight struct {
	ID             string `json:"id"`
	FlightNumber   string `json:"flightNumber"`
	Origin         string `json:"origin"`
	Destination    string `json:"destination"`
	DepartureTime  string `json:"departureTime"`
	ArrivalTime    string `json:"arrivalTime"`
	AvailableSeats int    `json:"availableSeats"`
	Status         string `json:"status"`
}

type CreateFlightRequest struct {
	FlightNumber  string `json:"flightNumber"`
	Origin        string `json:"origin"`
	Destination   string `json:"destination"`
	DepartureTime string `json:"departureTime"`
	ArrivalTime   string `json:"arrivalTime"`
	TotalCapacity int    `json:"totalCapacity"`
}

type UpdateSeatsRequest struct {
	Delta int `json:"delta"`
}

func getEnv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func initDB() {
	dbURL := getEnv("DATABASE_URL", "postgresql://postgres:postgres@flight-db:5432/flight")
	var err error
	db, err = sql.Open("postgres", dbURL)
	if err != nil {
		logJSON("ERROR", "flight-service", fmt.Sprintf("Failed to open DB: %v", err), "", "", nil)
	}
	for {
		err = db.Ping()
		if err == nil {
			break
		}
		time.Sleep(1 * time.Second)
	}
	logJSON("INFO", "flight-service", "Connected to flight DB", "", "", nil)
}

func generateRequestID() string {
	return uuid.New().String()
}

func main() {
	initDB()
	defer db.Close()

	r := gin.Default()

	r.Use(func(c *gin.Context) {
		requestID := c.GetHeader("X-Request-ID")
		if requestID == "" {
			requestID = generateRequestID()
		}
		c.Set("request_id", requestID)
		c.Header("X-Request-ID", requestID)
		c.Next()
	})

	r.GET("/healthz", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
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
		db.QueryRow("SELECT count(*) FROM pg_stat_activity WHERE datname = 'flight'").Scan(&activeConns)
		c.JSON(http.StatusOK, gin.H{
			"service":                  "flight",
			"http_requests_total":      0,
			"http_request_duration_ms": 0,
			"db_connections_active":    activeConns,
		})
	})

	r.GET("/api/flights", func(c *gin.Context) {
		requestID, _ := c.Get("request_id")
		traceID := requestID.(string)

		origin := c.Query("origin")
		destination := c.Query("destination")
		date := c.Query("date")

		query := `SELECT id, flight_number, origin, destination, departure_time, arrival_time, available_seats, status FROM flights WHERE 1=1`
		args := []interface{}{}
		argIdx := 1

		if origin != "" {
			query += fmt.Sprintf(" AND origin = $%d", argIdx)
			args = append(args, origin)
			argIdx++
		}
		if destination != "" {
			query += fmt.Sprintf(" AND destination = $%d", argIdx)
			args = append(args, destination)
			argIdx++
		}
		if date != "" {
			query += fmt.Sprintf(" AND DATE(departure_time) = $%d", argIdx)
			args = append(args, date)
		}

		query += " ORDER BY departure_time"

		rows, err := db.Query(query, args...)
		if err != nil {
			logJSON("ERROR", "flight-service", fmt.Sprintf("Query failed: %v", err), traceID, "", nil)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Query failed"})
			return
		}
		defer rows.Close()

		flights := []Flight{}
		for rows.Next() {
			var f Flight
			var depTime, arrTime time.Time
			err := rows.Scan(&f.ID, &f.FlightNumber, &f.Origin, &f.Destination, &depTime, &arrTime, &f.AvailableSeats, &f.Status)
			if err != nil {
				continue
			}
			f.DepartureTime = depTime.Format(time.RFC3339)
			f.ArrivalTime = arrTime.Format(time.RFC3339)
			flights = append(flights, f)
		}
		logJSON("INFO", "flight-service", "Flight search", traceID, "", map[string]interface{}{"count": len(flights)})
		c.JSON(http.StatusOK, gin.H{"flights": flights})
	})

	r.GET("/api/flights/:id", func(c *gin.Context) {
		requestID, _ := c.Get("request_id")
		traceID := requestID.(string)
		id := c.Param("id")

		var f Flight
		var depTime, arrTime time.Time
		err := db.QueryRow(
			`SELECT id, flight_number, origin, destination, departure_time, arrival_time, available_seats, status FROM flights WHERE id = $1`,
			id,
		).Scan(&f.ID, &f.FlightNumber, &f.Origin, &f.Destination, &depTime, &arrTime, &f.AvailableSeats, &f.Status)
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "Flight not found"})
			return
		}
		if err != nil {
			logJSON("ERROR", "flight-service", fmt.Sprintf("DB error: %v", err), traceID, "", nil)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "DB error"})
			return
		}
		f.DepartureTime = depTime.Format(time.RFC3339)
		f.ArrivalTime = arrTime.Format(time.RFC3339)
		c.JSON(http.StatusOK, f)
	})

	r.POST("/api/flights", authRequired("ADMIN"), func(c *gin.Context) {
		requestID, _ := c.Get("request_id")
		traceID := requestID.(string)
		var req CreateFlightRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request"})
			return
		}
		depTime, _ := time.Parse(time.RFC3339, req.DepartureTime)
		if depTime.IsZero() {
			depTime, _ = time.Parse("2006-01-02T15:04:05Z", req.DepartureTime)
		}
		arrTime, _ := time.Parse(time.RFC3339, req.ArrivalTime)
		if arrTime.IsZero() {
			arrTime, _ = time.Parse("2006-01-02T15:04:05Z", req.ArrivalTime)
		}
		var f Flight
		err := db.QueryRow(
			`INSERT INTO flights (flight_number, origin, destination, departure_time, arrival_time, total_capacity, available_seats, status)
			 VALUES ($1, $2, $3, $4, $5, $6, $6, 'SCHEDULED')
			 RETURNING id, flight_number, origin, destination, departure_time, arrival_time, available_seats, status`,
			req.FlightNumber, req.Origin, req.Destination, depTime, arrTime, req.TotalCapacity,
		).Scan(&f.ID, &f.FlightNumber, &f.Origin, &f.Destination, &depTime, &arrTime, &f.AvailableSeats, &f.Status)
		if err != nil {
			logJSON("ERROR", "flight-service", fmt.Sprintf("Create flight failed: %v", err), traceID, "", nil)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create flight"})
			return
		}
		f.DepartureTime = depTime.Format(time.RFC3339)
		f.ArrivalTime = arrTime.Format(time.RFC3339)
		logJSON("INFO", "flight-service", "Flight created", traceID, "", map[string]interface{}{"flight": f.FlightNumber})
		c.JSON(http.StatusCreated, f)
	})

	r.PUT("/api/flights/:id", authRequired("ADMIN"), func(c *gin.Context) {
		requestID, _ := c.Get("request_id")
		traceID := requestID.(string)
		id := c.Param("id")
		var updates map[string]interface{}
		if err := c.ShouldBindJSON(&updates); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request"})
			return
		}
		setParts := []string{}
		args := []interface{}{}
		argIdx := 1
		validFields := map[string]bool{"status": true, "departureTime": true, "arrivalTime": true}
		for k, v := range updates {
			if validFields[k] {
				setParts = append(setParts, fmt.Sprintf("%s = $%d", k, argIdx))
				args = append(args, v)
				argIdx++
			}
		}
		if len(setParts) == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "No valid fields to update"})
			return
		}
		args = append(args, id)
		var f Flight
		var depTime, arrTime time.Time
		err := db.QueryRow(
			fmt.Sprintf(`UPDATE flights SET %s, updated_at = NOW() WHERE id = $%d RETURNING id, flight_number, origin, destination, departure_time, arrival_time, available_seats, status`,
				strings.Join(setParts, ", "), argIdx),
			args...,
		).Scan(&f.ID, &f.FlightNumber, &f.Origin, &f.Destination, &depTime, &arrTime, &f.AvailableSeats, &f.Status)
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "Flight not found"})
			return
		}
		if err != nil {
			logJSON("ERROR", "flight-service", fmt.Sprintf("Update flight failed: %v", err), traceID, "", nil)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Update failed"})
			return
		}
		f.DepartureTime = depTime.Format(time.RFC3339)
		f.ArrivalTime = arrTime.Format(time.RFC3339)
		c.JSON(http.StatusOK, f)
	})

	r.PATCH("/api/flights/:id/seats", authRequired("ADMIN"), func(c *gin.Context) {
		requestID, _ := c.Get("request_id")
		traceID := requestID.(string)
		id := c.Param("id")
		var req UpdateSeatsRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request"})
			return
		}
		var currentSeats int
		err := db.QueryRow("SELECT available_seats FROM flights WHERE id = $1", id).Scan(&currentSeats)
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "Flight not found"})
			return
		}
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "DB error"})
			return
		}
		if req.Delta == -1 && currentSeats <= 0 {
			c.JSON(http.StatusConflict, gin.H{"error": "No seats available"})
			return
		}
		var f Flight
		var depTime, arrTime time.Time
		err = db.QueryRow(
			`UPDATE flights SET available_seats = available_seats + $1, updated_at = NOW() WHERE id = $2
			 RETURNING id, flight_number, origin, destination, departure_time, arrival_time, available_seats, status`,
			req.Delta, id,
		).Scan(&f.ID, &f.FlightNumber, &f.Origin, &f.Destination, &depTime, &arrTime, &f.AvailableSeats, &f.Status)
		if err != nil {
			logJSON("ERROR", "flight-service", fmt.Sprintf("Seat update failed: %v", err), traceID, "", nil)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Update failed"})
			return
		}
		f.DepartureTime = depTime.Format(time.RFC3339)
		f.ArrivalTime = arrTime.Format(time.RFC3339)
		logJSON("INFO", "flight-service", "Seats updated", traceID, "", map[string]interface{}{"flight": f.FlightNumber, "delta": req.Delta})
		c.JSON(http.StatusOK, f)
	})

	port := getEnv("PORT", "8081")
	log.Printf("Flight service starting on :%s", port)
	r.Run(":" + port)
}

func authRequired(requiredRole string) gin.HandlerFunc {
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
		role, _ := claims["role"].(string)
		if requiredRole != "" && role != requiredRole {
			c.JSON(http.StatusForbidden, gin.H{"error": "Insufficient permissions"})
			c.Abort()
			return
		}
		c.Set("role", role)
		c.Set("user_id", claims["sub"])
		c.Next()
	}
}