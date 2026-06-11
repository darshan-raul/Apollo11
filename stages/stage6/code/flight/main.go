package main

import (
	"context"
	"database/sql"
	"encoding/hex"
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
	_ "github.com/lib/pq"
	"github.com/google/uuid"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.24.0"
	"go.opentelemetry.io/otel/trace"
)

var (
	db        *sql.DB
	jwtSecret string
	logger    = log.New(os.Stdout, "", 0)

	// Prometheus metrics
	httpRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{Name: "http_requests_total", Help: "Total HTTP requests by service, method, path, status."},
		[]string{"service", "method", "path", "status"},
	)
	httpRequestDurationMs = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{Name: "http_request_duration_ms", Help: "HTTP request latency (ms).", Buckets: prometheus.DefBuckets},
		[]string{"service", "method", "path"},
	)
)

func init() {
	jwtSecret = getEnv("JWT_SECRET", "apollo-airlines-dev-secret")
}

func logJSON(level, service, message, traceID, spanID string, extra ...map[string]interface{}) {
	if traceID == "" {
		span := trace.SpanFromContext(context.Background())
		if span.SpanContext().IsValid() {
			traceID = span.SpanContext().TraceID().String()
			if spanID == "" {
				spanID = span.SpanContext().SpanID().String()
			}
		}
	}
	entry := map[string]interface{}{
		"timestamp": time.Now().UTC().Format(time.RFC3339),
		"level":     level,
		"service":   service,
		"trace_id":  traceID,
		"span_id":   spanID,
		"message":   message,
	}
	if len(extra) > 0 && extra[0] != nil {
		for k, v := range extra[0] {
			entry[k] = v
		}
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

func initOTEL(ctx context.Context, serviceName string) (func(context.Context) error, error) {
	endpoint := getEnv("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector:4317")
	res, err := resource.New(ctx,
		resource.WithAttributes(semconv.ServiceName(serviceName)),
	)
	if err != nil {
		return nil, err
	}
	traceExporter, err := otlptracegrpc.New(ctx,
		otlptracegrpc.WithEndpoint(endpoint),
		otlptracegrpc.WithInsecure(),
	)
	if err != nil {
		return nil, err
	}
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(traceExporter),
		sdktrace.WithResource(res),
		sdktrace.WithSampler(sdktrace.AlwaysSample()),
	)
	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{}, propagation.Baggage{},
	))

	metricExporter, err := otlpmetricgrpc.New(ctx,
		otlpmetricgrpc.WithEndpoint(endpoint),
		otlpmetricgrpc.WithInsecure(),
	)
	if err != nil {
		return nil, err
	}
	mp := metric.NewMeterProvider(
		metric.WithReader(metric.NewPeriodicReader(metricExporter, metric.WithInterval(15*time.Second))),
		metric.WithResource(res),
	)
	otel.SetMeterProvider(mp)

	shutdown := func(ctx context.Context) error {
		var firstErr error
		if err := tp.Shutdown(ctx); err != nil {
			firstErr = err
		}
		if err := mp.Shutdown(ctx); err != nil && firstErr == nil {
			firstErr = err
		}
		return firstErr
	}
	return shutdown, nil
}

func prometheusHandler() http.Handler {
	reg := prometheus.NewRegistry()
	reg.MustRegister(httpRequestsTotal, httpRequestDurationMs)
	return promhttp.HandlerFor(reg, promhttp.HandlerOpts{Registry: reg})
}

func metricsMiddleware(service string) gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		c.Next()
		path := c.FullPath()
		if path == "" {
			path = "unknown"
		}
		status := fmt.Sprintf("%d", c.Writer.Status())
		httpRequestsTotal.WithLabelValues(service, c.Request.Method, path, status).Inc()
		httpRequestDurationMs.WithLabelValues(service, c.Request.Method, path).Observe(float64(time.Since(start).Milliseconds()))
	}
}

func injectTraceparent(ctx context.Context, req *http.Request) {
	otel.GetTextMapPropagator().Inject(ctx, propagation.HeaderCarrier(req.Header))
	_ = hex.EncodeToString // satisfy unused import
}

func main() {
	initDB()
	defer db.Close()

	otelCtx, otelCancel := context.WithCancel(context.Background())
	defer otelCancel()
	if otelShutdown, err := initOTEL(otelCtx, "flight"); err != nil {
		logJSON("WARN", "flight-service", fmt.Sprintf("OTEL init failed (continuing without traces): %v", err), "", "", nil)
	} else {
		defer func() {
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			_ = otelShutdown(ctx)
		}()
	}

	r := gin.Default()

	r.Use(func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Request-ID, traceparent")
		c.Header("Access-Control-Expose-Headers", "X-Request-ID")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	})

	r.Use(otelgin.Middleware("flight"))

	r.Use(func(c *gin.Context) {
		requestID := c.GetHeader("X-Request-ID")
		if requestID == "" {
			requestID = generateRequestID()
		}
		c.Set("request_id", requestID)
		c.Header("X-Request-ID", requestID)
		c.Next()
	})

	r.Use(metricsMiddleware("flight"))

	// Probes
	r.GET("/healthz", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"status": "ok"}) })
	r.GET("/healthz/startup", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"status": "starting"}) })
	r.GET("/healthz/live", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"status": "alive"}) })
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

	// Real Prometheus metrics
	r.GET("/metrics", gin.WrapH(prometheusHandler()))

	r.GET("/api/flights", func(c *gin.Context) {
		traceID, _ := c.Get("request_id")
		ctx := c.Request.Context()
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

		rows, err := db.QueryContext(ctx, query, args...)
		if err != nil {
			logJSON("ERROR", "flight-service", fmt.Sprintf("Query failed: %v", err), traceID.(string), "", nil)
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
		logJSON("INFO", "flight-service", "Flight search", traceID.(string), "", map[string]interface{}{"count": len(flights)})
		c.JSON(http.StatusOK, gin.H{"flights": flights})
	})

	r.GET("/api/flights/:id", func(c *gin.Context) {
		traceID, _ := c.Get("request_id")
		ctx := c.Request.Context()
		id := c.Param("id")

		var f Flight
		var depTime, arrTime time.Time
		err := db.QueryRowContext(ctx,
			`SELECT id, flight_number, origin, destination, departure_time, arrival_time, available_seats, status FROM flights WHERE id = $1`,
			id,
		).Scan(&f.ID, &f.FlightNumber, &f.Origin, &f.Destination, &depTime, &arrTime, &f.AvailableSeats, &f.Status)
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "Flight not found"})
			return
		}
		if err != nil {
			logJSON("ERROR", "flight-service", fmt.Sprintf("DB error: %v", err), traceID.(string), "", nil)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "DB error"})
			return
		}
		f.DepartureTime = depTime.Format(time.RFC3339)
		f.ArrivalTime = arrTime.Format(time.RFC3339)
		c.JSON(http.StatusOK, f)
	})

	r.POST("/api/flights", authRequired("ADMIN"), func(c *gin.Context) {
		traceID, _ := c.Get("request_id")
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
			logJSON("ERROR", "flight-service", fmt.Sprintf("Create flight failed: %v", err), traceID.(string), "", nil)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create flight"})
			return
		}
		f.DepartureTime = depTime.Format(time.RFC3339)
		f.ArrivalTime = arrTime.Format(time.RFC3339)
		logJSON("INFO", "flight-service", "Flight created", traceID.(string), "", map[string]interface{}{"flight": f.FlightNumber})
		c.JSON(http.StatusCreated, f)
	})

	r.PUT("/api/flights/:id", authRequired("ADMIN"), func(c *gin.Context) {
		traceID, _ := c.Get("request_id")
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
			logJSON("ERROR", "flight-service", fmt.Sprintf("Update flight failed: %v", err), traceID.(string), "", nil)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Update failed"})
			return
		}
		f.DepartureTime = depTime.Format(time.RFC3339)
		f.ArrivalTime = arrTime.Format(time.RFC3339)
		c.JSON(http.StatusOK, f)
	})

	r.PATCH("/api/flights/:id/seats", authRequired("ADMIN"), func(c *gin.Context) {
		traceID, _ := c.Get("request_id")
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
			logJSON("ERROR", "flight-service", fmt.Sprintf("Seat update failed: %v", err), traceID.(string), "", nil)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Update failed"})
			return
		}
		f.DepartureTime = depTime.Format(time.RFC3339)
		f.ArrivalTime = arrTime.Format(time.RFC3339)
		logJSON("INFO", "flight-service", "Seats updated", traceID.(string), "", map[string]interface{}{"flight": f.FlightNumber, "delta": req.Delta})
		c.JSON(http.StatusOK, f)
	})

	port := getEnv("PORT", "8081")
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
