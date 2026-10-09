package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/lib/pq"
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

func addSSLMode(dsn string) string {
	if strings.Contains(dsn, "sslmode=") {
		return dsn
	}
	return dsn + "?sslmode=disable"
}

func initDB() {
	dbURL := getEnv("DATABASE_URL", "postgresql://postgres:***@flight-db:5432/flight")
	var err error
	db, err = sql.Open("postgres", addSSLMode(dbURL))
	if err != nil {
		logJSON("ERROR", "flight-service", fmt.Sprintf("Failed to open DB: %v", err), "", "", nil)
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	for {
		err = db.PingContext(ctx)
		if err == nil {
			break
		}
		logJSON("ERROR", "flight-service", fmt.Sprintf("DB not ready (will retry): %v", err), "", "", nil)
		select {
		case <-ctx.Done():
			logJSON("ERROR", "flight-service", fmt.Sprintf("DB connection timeout: %v", ctx.Err()), "", "", nil)
			return
		case <-time.After(2 * time.Second):
		}
	}
	logJSON("INFO", "flight-service", "Connected to flight DB", "", "", nil)
}

func generateRequestID() string {
	return uuid.New().String()
}

var flightTimeLayouts = []string{time.RFC3339, "2006-01-02T15:04:05", "2006-01-02T15:04"}

var validFlightStatuses = map[string]bool{
	"SCHEDULED": true, "BOARDING": true, "DELAYED": true,
	"DEPARTED": true, "ARRIVED": true, "CANCELLED": true,
}

// parseFlightTime accepts RFC3339 and the zone-less values sent by an HTML
// datetime-local input. Flight times are stored as UTC wall-clock timestamps.
func parseFlightTime(value string) (time.Time, error) {
	for _, layout := range flightTimeLayouts {
		if t, err := time.Parse(layout, value); err == nil {
			return t.UTC(), nil
		}
	}
	return time.Time{}, fmt.Errorf("unrecognised time %q", value)
}

func validFlightID(c *gin.Context) (string, bool) {
	id := c.Param("id")
	if _, err := uuid.Parse(id); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid flight ID"})
		return "", false
	}
	return id, true
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

	// Stage 4: split /healthz into three distinct probe paths. The legacy
	// /healthz and /readyz are kept returning 200 for backward compatibility
	// (smoke tests, external monitoring) but the kubelet probes target the
	// new /healthz/{startup,live,ready} paths.
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
		db.QueryRow("SELECT count(*) FROM pg_stat_activity WHERE datname = 'flight'").Scan(&activeConns)
		metrics := fmt.Sprintf(`# HELP http_requests_total Total HTTP requests observed by the service.
# TYPE http_requests_total counter
http_requests_total{service="flight"} 0
# HELP http_request_duration_ms Most recently observed request duration in milliseconds.
# TYPE http_request_duration_ms gauge
http_request_duration_ms{service="flight"} 0
# HELP db_connections_active Active database connections owned by the service.
# TYPE db_connections_active gauge
db_connections_active{service="flight"} %d
`, activeConns)
		c.Data(http.StatusOK, "text/plain; version=0.0.4; charset=utf-8", []byte(metrics))
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
			if _, err := time.Parse("2006-01-02", date); err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "date must be YYYY-MM-DD"})
				return
			}
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
		id, ok := validFlightID(c)
		if !ok {
			return
		}

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
		if req.FlightNumber == "" || req.Origin == "" || req.Destination == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "flightNumber, origin and destination are required"})
			return
		}
		if req.TotalCapacity <= 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "totalCapacity must be greater than zero"})
			return
		}
		depTime, depErr := parseFlightTime(req.DepartureTime)
		arrTime, arrErr := parseFlightTime(req.ArrivalTime)
		if depErr != nil || arrErr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "departureTime and arrivalTime must be valid timestamps"})
			return
		}
		if !arrTime.After(depTime) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "arrivalTime must be after departureTime"})
			return
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
			var pqErr *pq.Error
			if errors.As(err, &pqErr) {
				switch pqErr.Code {
				case "23503":
					c.JSON(http.StatusBadRequest, gin.H{"error": "Unknown origin or destination airport"})
					return
				case "23505":
					c.JSON(http.StatusConflict, gin.H{"error": "Flight already exists for that departure time"})
					return
				}
			}
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
		id, ok := validFlightID(c)
		if !ok {
			return
		}
		var updates map[string]interface{}
		if err := c.ShouldBindJSON(&updates); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request"})
			return
		}
		setParts := []string{}
		args := []interface{}{}
		argIdx := 1
		// JSON field -> column. Other fields in the payload are ignored.
		columns := []struct{ field, column string }{
			{"status", "status"},
			{"departureTime", "departure_time"},
			{"arrivalTime", "arrival_time"},
		}
		newTimes := map[string]time.Time{}
		for _, col := range columns {
			raw, present := updates[col.field]
			if !present {
				continue
			}
			text, isString := raw.(string)
			var value interface{} = text
			if col.field == "status" {
				if !isString || !validFlightStatuses[text] {
					c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid flight status"})
					return
				}
			} else {
				parsed, err := parseFlightTime(text)
				if !isString || err != nil {
					c.JSON(http.StatusBadRequest, gin.H{"error": col.field + " must be a valid timestamp"})
					return
				}
				value = parsed
				newTimes[col.field] = parsed
			}
			setParts = append(setParts, fmt.Sprintf("%s = $%d", col.column, argIdx))
			args = append(args, value)
			argIdx++
		}
		if len(setParts) == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "No valid fields to update"})
			return
		}
		if dep, ok := newTimes["departureTime"]; ok {
			if arr, ok := newTimes["arrivalTime"]; ok && !arr.After(dep) {
				c.JSON(http.StatusBadRequest, gin.H{"error": "arrivalTime must be after departureTime"})
				return
			}
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
			var pqErr *pq.Error
			if errors.As(err, &pqErr) && pqErr.Code == "23505" {
				c.JSON(http.StatusConflict, gin.H{"error": "Flight already exists for that departure time"})
				return
			}
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Update failed"})
			return
		}
		f.DepartureTime = depTime.Format(time.RFC3339)
		f.ArrivalTime = arrTime.Format(time.RFC3339)
		c.JSON(http.StatusOK, f)
	})

	r.PATCH("/api/flights/:id/seats", authRequired("SERVICE"), func(c *gin.Context) {
		requestID, _ := c.Get("request_id")
		traceID := requestID.(string)
		id, ok := validFlightID(c)
		if !ok {
			return
		}
		var req UpdateSeatsRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request"})
			return
		}
		if req.Delta == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "delta must not be zero"})
			return
		}
		// One statement checks and applies the change, so concurrent bookings
		// cannot drive the count below zero or above capacity.
		var f Flight
		var depTime, arrTime time.Time
		err := db.QueryRow(
			`UPDATE flights SET available_seats = available_seats + $1, updated_at = NOW()
			 WHERE id = $2 AND available_seats + $1 BETWEEN 0 AND total_capacity
			 RETURNING id, flight_number, origin, destination, departure_time, arrival_time, available_seats, status`,
			req.Delta, id,
		).Scan(&f.ID, &f.FlightNumber, &f.Origin, &f.Destination, &depTime, &arrTime, &f.AvailableSeats, &f.Status)
		if err == sql.ErrNoRows {
			var exists bool
			if err := db.QueryRow("SELECT EXISTS (SELECT 1 FROM flights WHERE id = $1)", id).Scan(&exists); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "DB error"})
				return
			}
			if !exists {
				c.JSON(http.StatusNotFound, gin.H{"error": "Flight not found"})
				return
			}
			if req.Delta < 0 {
				c.JSON(http.StatusConflict, gin.H{"error": "No seats available"})
				return
			}
			c.JSON(http.StatusConflict, gin.H{"error": "Seat count would exceed capacity"})
			return
		}
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

	// Stage 4: graceful shutdown. We start the HTTP server in a goroutine so
	// we can wait for SIGTERM in the main goroutine. On signal we call
	// srv.Shutdown(ctx) which stops accepting new connections, drains
	// in-flight requests up to the 30s timeout, then returns. After Shutdown
	// returns we close the DB pool. If Shutdown times out, srv.Shutdown
	// returns context.DeadlineExceeded and the kubelet will SIGKILL us.
	srv := &http.Server{Addr: fmt.Sprintf("0.0.0.0:%s", port), Handler: r}

	go func() {
		logJSON("INFO", "flight-service", fmt.Sprintf("Starting on :%s", port), "", "", nil)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logJSON("ERROR", "flight-service", fmt.Sprintf("Server error: %v", err), "", "", nil)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
	<-quit
	logJSON("INFO", "flight-service", "Received SIGTERM, shutting down gracefully", "", "", nil)

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		logJSON("ERROR", "flight-service", fmt.Sprintf("Shutdown error: %v", err), "", "", nil)
	}

	if err := db.Close(); err != nil {
		logJSON("ERROR", "flight-service", fmt.Sprintf("DB close error: %v", err), "", "", nil)
	}
	logJSON("INFO", "flight-service", "Server stopped", "", "", nil)
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
		}, jwt.WithValidMethods([]string{"HS256"}))
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
		roleAllowed := requiredRole == "" || role == requiredRole || (requiredRole == "SERVICE" && role == "ADMIN")
		if !roleAllowed {
			c.JSON(http.StatusForbidden, gin.H{"error": "Insufficient permissions"})
			c.Abort()
			return
		}
		c.Set("role", role)
		c.Set("user_id", claims["sub"])
		c.Next()
	}
}
