package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
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
	flightServiceURL string
	logger           = log.New(os.Stdout, "", 0)

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
	flightServiceURL = getEnv("FLIGHT_SERVICE_URL", "http://flight:8081")
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

type SearchResult struct {
	ID             string `json:"id"`
	FlightNumber   string `json:"flightNumber"`
	Origin         string `json:"origin"`
	Destination    string `json:"destination"`
	DepartureTime  string `json:"departureTime"`
	ArrivalTime    string `json:"arrivalTime"`
	Duration       int    `json:"duration"`
	AvailableSeats int    `json:"availableSeats"`
	Status         string `json:"status"`
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
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

func main() {
	otelCtx, otelCancel := context.WithCancel(context.Background())
	defer otelCancel()
	if otelShutdown, err := initOTEL(otelCtx, "search"); err != nil {
		logJSON("WARN", "search-service", fmt.Sprintf("OTEL init failed (continuing without traces): %v", err), "", "", nil)
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

	r.Use(otelgin.Middleware("search"))

	r.Use(func(c *gin.Context) {
		requestID := c.GetHeader("X-Request-ID")
		if requestID == "" {
			requestID = generateRequestID()
		}
		c.Set("request_id", requestID)
		c.Header("X-Request-ID", requestID)
		c.Next()
	})

	r.Use(metricsMiddleware("search"))

	r.GET("/healthz", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"status": "ok"}) })
	r.GET("/healthz/startup", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"status": "starting"}) })
	r.GET("/healthz/live", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"status": "alive"}) })
	r.GET("/healthz/ready", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"status": "ready"}) })
	r.GET("/readyz", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"status": "ok"}) })

	r.GET("/metrics", gin.WrapH(prometheusHandler()))

	r.GET("/api/search", func(c *gin.Context) {
		traceID, _ := c.Get("request_id")
		ctx := c.Request.Context()
		origin := c.Query("origin")
		destination := c.Query("destination")
		date := c.Query("date")

		searchURL := fmt.Sprintf("%s/api/flights?origin=%s&destination=%s&date=%s",
			flightServiceURL, origin, destination, date)

		req, _ := http.NewRequestWithContext(ctx, "GET", searchURL, nil)
		req.Header.Set("X-Request-ID", traceID.(string))
		// Inject W3C traceparent so the flight service span becomes a child
		otel.GetTextMapPropagator().Inject(ctx, propagation.HeaderCarrier(req.Header))

		client := &http.Client{Timeout: 10 * time.Second}
		resp, err := client.Do(req)
		if err != nil {
			logJSON("ERROR", "search-service", fmt.Sprintf("Flight service call failed: %v", err), traceID.(string), "", nil)
			c.JSON(http.StatusBadGateway, gin.H{"error": "Flight service unavailable"})
			return
		}
		defer resp.Body.Close()

		body, _ := io.ReadAll(resp.Body)
		var result map[string]interface{}
		json.Unmarshal(body, &result)

		flightsRaw, ok := result["flights"].([]interface{})
		if !ok {
			c.JSON(http.StatusOK, gin.H{"results": []SearchResult{}, "total": 0, "page": 1, "limit": 20})
			return
		}

		results := []SearchResult{}
		for _, f := range flightsRaw {
			fm := f.(map[string]interface{})
			depStr, _ := fm["departureTime"].(string)
			arrStr, _ := fm["arrivalTime"].(string)
			dep, _ := time.Parse(time.RFC3339, depStr)
			arr, _ := time.Parse(time.RFC3339, arrStr)
			duration := int(arr.Sub(dep).Minutes())
			avail, _ := fm["availableSeats"].(float64)
			results = append(results, SearchResult{
				ID:             fm["id"].(string),
				FlightNumber:   fm["flightNumber"].(string),
				Origin:         fm["origin"].(string),
				Destination:    fm["destination"].(string),
				DepartureTime:  depStr,
				ArrivalTime:    arrStr,
				Duration:       duration,
				AvailableSeats: int(avail),
				Status:         fm["status"].(string),
			})
		}
		logJSON("INFO", "search-service", "Search completed", traceID.(string), "", map[string]interface{}{"count": len(results)})
		c.JSON(http.StatusOK, gin.H{"results": results, "total": len(results), "page": 1, "limit": 20})
	})

	port := getEnv("PORT", "8083")
	srv := &http.Server{Addr: ":" + port, Handler: r}

	go func() {
		logJSON("INFO", "search-service", fmt.Sprintf("Starting on :%s", port), "", "", nil)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logJSON("ERROR", "search-service", fmt.Sprintf("Server error: %v", err), "", "", nil)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
	<-quit
	logJSON("INFO", "search-service", "Received SIGTERM, shutting down gracefully", "", "", nil)

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		logJSON("ERROR", "search-service", fmt.Sprintf("Shutdown error: %v", err), "", "", nil)
	}
	logJSON("INFO", "search-service", "Server stopped", "", "", nil)
}
