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
	"github.com/redis/go-redis/v9"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.24.0"
	"go.opentelemetry.io/otel/trace"
)

const (
	// Stage 7: cache TTL for search results. 5 minutes matches the AGENTS.md
	// spec — long enough to absorb traffic spikes, short enough that stale
	// flight availability data is bounded.
	cacheTTLSeconds = 5 * 60
)

var (
	flightServiceURL string
	logger           = log.New(os.Stdout, "", 0)

	// redisClient may be nil if the initial Ping failed (degraded startup).
	// The /api/search handler treats this as a cache-miss-every-time case
	// (cache writes are no-ops, cache reads are misses) — search keeps
	// working, just without caching.
	redisClient *redis.Client

	httpRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{Name: "http_requests_total", Help: "Total HTTP requests by service, method, path, status."},
		[]string{"service", "method", "path", "status"},
	)
	httpRequestDurationMs = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{Name: "http_request_duration_ms", Help: "HTTP request latency (ms).", Buckets: prometheus.DefBuckets},
		[]string{"service", "method", "path"},
	)
	// Stage 7: cache observability. Promoted to the Prometheus registry so
	// Grafana can plot hit ratio and Redis can be tuned accordingly.
	cacheHitsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{Name: "cache_hits_total", Help: "Search cache hits."},
		[]string{"service"},
	)
	cacheMissesTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{Name: "cache_misses_total", Help: "Search cache misses."},
		[]string{"service"},
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

// initRedis establishes the Redis client with a bounded timeout. Unlike
// notification's old `for { Ping }` infinite loop (an anti-pattern
// flagged in AGENTS.md), this returns an error on failure and lets the
// caller proceed in degraded mode — search keeps working without cache.
func initRedis() error {
	redisURL := getEnv("REDIS_URL", "redis://redis:6379")
	opt, err := redis.ParseURL(redisURL)
	if err != nil {
		return fmt.Errorf("parse REDIS_URL: %w", err)
	}
	redisClient = redis.NewClient(opt)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if _, err := redisClient.Ping(ctx).Result(); err != nil {
		// Don't bail — close the broken client and leave redisClient=nil.
		// The /api/search handler will treat every request as a cache miss.
		_ = redisClient.Close()
		redisClient = nil
		return fmt.Errorf("ping redis: %w", err)
	}
	logJSON("INFO", "search-service", "Connected to Redis", "", "", nil)
	return nil
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
	reg.MustRegister(httpRequestsTotal, httpRequestDurationMs, cacheHitsTotal, cacheMissesTotal)
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

	// Stage 7: Redis init. Non-blocking with bounded timeout; degrades
	// gracefully if Redis is unreachable (cache disabled, not fatal).
	if err := initRedis(); err != nil {
		logJSON("WARN", "search-service",
			fmt.Sprintf("Redis init failed (running without cache): %v", err), "", "", nil)
	}
	defer func() {
		if redisClient != nil {
			_ = redisClient.Close()
		}
	}()

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
	r.GET("/healthz/ready", func(c *gin.Context) {
		// Stage 7: readiness = "I can serve real traffic". If Redis is
		// configured but unreachable, we are degraded (slower, no cache)
		// but not unready. Report the cache state in the body.
		cacheState := "disabled"
		if redisClient != nil {
			ctx, cancel := context.WithTimeout(c.Request.Context(), 1*time.Second)
			defer cancel()
			if err := redisClient.Ping(ctx).Err(); err != nil {
				cacheState = "unreachable"
			} else {
				cacheState = "ok"
			}
		}
		c.JSON(http.StatusOK, gin.H{"status": "ready", "cache": cacheState})
	})
	r.GET("/readyz", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"status": "ok"}) })

	r.GET("/metrics", gin.WrapH(prometheusHandler()))

	r.GET("/api/search", func(c *gin.Context) {
		traceID, _ := c.Get("request_id")
		ctx := c.Request.Context()
		origin := c.Query("origin")
		destination := c.Query("destination")
		date := c.Query("date")

		// Stage 7: cache key. Origin/destination/date are the natural
		// partition — same three values = identical result, and they
		// bound the keyspace (6 airports × 5 dates × 6 airports ≈ 180 keys).
		cacheKey := fmt.Sprintf("search:%s:%s:%s", origin, destination, date)
		tracer := otel.Tracer("search-service")

		// --- Cache GET -------------------------------------------------
		if redisClient != nil {
			_, cacheSpan := tracer.Start(ctx, "cache.get",
				trace.WithAttributes(attribute.String("cache.key", cacheKey)))
			cacheCtx, cancel := context.WithTimeout(ctx, 1*time.Second)
			cached, cerr := redisClient.Get(cacheCtx, cacheKey).Result()
			cancel()
			if cerr == nil {
				cacheSpan.SetAttributes(attribute.Bool("cache.hit", true))
				cacheSpan.End()
				cacheHitsTotal.WithLabelValues("search").Inc()
				c.Header("X-Cache", "HIT")
				c.Header("Content-Type", "application/json")
				c.String(http.StatusOK, cached)
				logJSON("INFO", "search-service", "Search served from cache",
					traceID.(string), "", map[string]interface{}{"cache_key": cacheKey})
				return
			}
			if !errors.Is(cerr, redis.Nil) {
				// Real error (not just "key not found"). Log + treat as miss
				// so a Redis blip doesn't break search.
				logJSON("WARN", "search-service",
					fmt.Sprintf("Redis GET failed (degrading to miss): %v", cerr),
					traceID.(string), "", nil)
			}
			cacheSpan.SetAttributes(attribute.Bool("cache.hit", false))
			cacheSpan.End()
		}
		cacheMissesTotal.WithLabelValues("search").Inc()

		// --- Cache MISS: call flight service --------------------------
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
		var results []SearchResult
		if ok {
			results = make([]SearchResult, 0, len(flightsRaw))
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
		} else {
			results = []SearchResult{}
		}

		payload := gin.H{"results": results, "total": len(results), "page": 1, "limit": 20}

		// --- Cache SET -------------------------------------------------
		// Best-effort: failure to SET does not fail the request.
		if redisClient != nil {
			payloadBytes, mErr := json.Marshal(payload)
			if mErr == nil {
				_, setSpan := tracer.Start(ctx, "cache.set",
					trace.WithAttributes(attribute.String("cache.key", cacheKey)))
				setCtx, cancel := context.WithTimeout(ctx, 1*time.Second)
				sErr := redisClient.Set(setCtx, cacheKey, payloadBytes, time.Duration(cacheTTLSeconds)*time.Second).Err()
				cancel()
				if sErr != nil {
					logJSON("WARN", "search-service",
						fmt.Sprintf("Redis SET failed (response still served): %v", sErr),
						traceID.(string), "", nil)
				}
				setSpan.End()
			}
		}

		c.Header("X-Cache", "MISS")
		logJSON("INFO", "search-service", "Search completed",
			traceID.(string), "", map[string]interface{}{"count": len(results), "cache_key": cacheKey})
		c.JSON(http.StatusOK, payload)
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
