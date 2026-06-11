package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
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
	"github.com/redis/go-redis/v9"
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
	redisClient *redis.Client
	logger      = log.New(os.Stdout, "", 0)
	ctx         = context.Background()

	httpRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{Name: "http_requests_total", Help: "Total HTTP requests by service, method, path, status."},
		[]string{"service", "method", "path", "status"},
	)
	httpRequestDurationMs = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{Name: "http_request_duration_ms", Help: "HTTP request latency (ms).", Buckets: prometheus.DefBuckets},
		[]string{"service", "method", "path"},
	)
)

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

type NotifyRequest struct {
	Type      string                 `json:"type"`
	Recipient string                 `json:"recipient"`
	Payload   map[string]interface{} `json:"payload"`
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func initRedis() {
	redisURL := getEnv("REDIS_URL", "redis://redis:6379")
	opt, err := redis.ParseURL(redisURL)
	if err != nil {
		logJSON("ERROR", "notification-service", fmt.Sprintf("Redis URL parse failed: %v", err), "", "", nil)
	}
	redisClient = redis.NewClient(opt)
	for {
		_, err := redisClient.Ping(ctx).Result()
		if err == nil {
			break
		}
		time.Sleep(1 * time.Second)
	}
	logJSON("INFO", "notification-service", "Connected to Redis", "", "", nil)
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
	initRedis()
	defer redisClient.Close()

	otelCtx, otelCancel := context.WithCancel(context.Background())
	defer otelCancel()
	if otelShutdown, err := initOTEL(otelCtx, "notification"); err != nil {
		logJSON("WARN", "notification-service", fmt.Sprintf("OTEL init failed (continuing without traces): %v", err), "", "", nil)
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

	r.Use(otelgin.Middleware("notification"))

	r.Use(func(c *gin.Context) {
		requestID := c.GetHeader("X-Request-ID")
		if requestID == "" {
			requestID = generateRequestID()
		}
		c.Set("request_id", requestID)
		c.Header("X-Request-ID", requestID)
		c.Next()
	})

	r.Use(metricsMiddleware("notification"))

	r.GET("/healthz", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"status": "ok"}) })
	r.GET("/healthz/startup", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"status": "starting"}) })
	r.GET("/healthz/live", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"status": "alive"}) })
	r.GET("/healthz/ready", func(c *gin.Context) {
		if _, err := redisClient.Ping(ctx).Result(); err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"status": "error", "detail": "Redis not reachable"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"status": "ready"})
	})
	r.GET("/readyz", func(c *gin.Context) {
		_, err := redisClient.Ping(ctx).Result()
		if err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"status": "error", "detail": "Redis not reachable"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	r.GET("/metrics", gin.WrapH(prometheusHandler()))

	r.POST("/api/notify", func(c *gin.Context) {
		traceID, _ := c.Get("request_id")

		var req NotifyRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request"})
			return
		}

		eventJSON, _ := json.Marshal(map[string]interface{}{
			"id":         uuid.New().String(),
			"type":       req.Type,
			"recipient":   req.Recipient,
			"payload":     req.Payload,
			"trace_id":   traceID,
			"created_at":  time.Now().UTC().Format(time.RFC3339),
		})

		err := redisClient.LPush(ctx, "notifications:queue", string(eventJSON)).Err()
		if err != nil {
			logJSON("ERROR", "notification-service", fmt.Sprintf("Failed to push to queue: %v", err), traceID.(string), "", nil)
		}

		logJSON("INFO", "notification-service", fmt.Sprintf("Event queued: %s", req.Type), traceID.(string), "", map[string]interface{}{
			"type":      req.Type,
			"recipient": req.Recipient,
		})
		c.JSON(http.StatusAccepted, gin.H{"message": "Notification queued"})
	})

	r.GET("/api/notifications/pending", func(c *gin.Context) {
		count, _ := redisClient.LLen(ctx, "notifications:queue").Result()
		c.JSON(http.StatusOK, gin.H{"pending": count})
	})

	port := getEnv("PORT", "8084")
	srv := &http.Server{Addr: ":" + port, Handler: r}

	go func() {
		logJSON("INFO", "notification-service", fmt.Sprintf("Starting on :%s", port), "", "", nil)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logJSON("ERROR", "notification-service", fmt.Sprintf("Server error: %v", err), "", "", nil)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
	<-quit
	logJSON("INFO", "notification-service", "Received SIGTERM, shutting down gracefully", "", "", nil)

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		logJSON("ERROR", "notification-service", fmt.Sprintf("Shutdown error: %v", err), "", "", nil)
	}

	if err := redisClient.Close(); err != nil {
		logJSON("ERROR", "notification-service", fmt.Sprintf("Redis close error: %v", err), "", "", nil)
	}
	logJSON("INFO", "notification-service", "Server stopped", "", "", nil)
}
