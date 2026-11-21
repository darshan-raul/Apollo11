package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/redis/go-redis/v9"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
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
	// Stage 7: default cache TTL for search results. 5 minutes matches the AGENTS.md
	// spec — long enough to absorb traffic spikes, short enough that stale
	// flight availability data is bounded. Overridable via CACHE_TTL_SECONDS.
	defaultCacheTTLSeconds = 300
	cacheTTLSeconds        = defaultCacheTTLSeconds
	redisReconnectCooldown = 5 * time.Second
)

var (
	flightServiceURL string
	logger           = log.New(os.Stdout, "", 0)

	// redisClient may be nil if Redis lost the startup race. redisMu guards
	// bounded lazy reconnection with cooldown from readiness probes and live requests.
	redisClient   *redis.Client
	lastRedisFail time.Time
	redisMu       sync.Mutex

	httpRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{Name: "http_requests_total", Help: "Total HTTP requests by service, method, path, status."},
		[]string{"service", "method", "path", "status"},
	)
	httpRequestDurationMs = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{Name: "http_request_duration_ms", Help: "HTTP request latency (ms).", Buckets: []float64{1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000}},
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

func traceAndSpanFromContext(ctx context.Context) (string, string) {
	if ctx == nil {
		return "", ""
	}
	sc := trace.SpanFromContext(ctx).SpanContext()
	if !sc.IsValid() {
		return "", ""
	}
	return sc.TraceID().String(), sc.SpanID().String()
}

func logJSON(level, service, message, traceID, spanID string, extra ...map[string]interface{}) {
	entry := map[string]interface{}{
		"timestamp":  time.Now().UTC().Format(time.RFC3339),
		"level":      level,
		"service":    service,
		"request_id": "",
		"trace_id":   traceID,
		"span_id":    spanID,
		"message":    message,
	}
	for _, m := range extra {
		for k, v := range m {
			entry[k] = v
		}
	}
	b, _ := json.Marshal(entry)
	logger.Println(string(b))
}

func logContext(ctx context.Context, requestID, level, service, message string, extra ...map[string]interface{}) {
	traceID, spanID := traceAndSpanFromContext(ctx)
	entry := map[string]interface{}{
		"timestamp":  time.Now().UTC().Format(time.RFC3339),
		"level":      level,
		"service":    service,
		"request_id": requestID,
		"trace_id":   traceID,
		"span_id":    spanID,
		"message":    message,
	}
	for _, m := range extra {
		for k, v := range m {
			entry[k] = v
		}
	}
	b, _ := json.Marshal(entry)
	logger.Println(string(b))
}

type flightItem struct {
	ID             string `json:"id"`
	FlightNumber   string `json:"flightNumber"`
	Origin         string `json:"origin"`
	Destination    string `json:"destination"`
	DepartureTime  string `json:"departureTime"`
	ArrivalTime    string `json:"arrivalTime"`
	AvailableSeats int    `json:"availableSeats"`
	Status         string `json:"status"`
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

func getCacheTTL() time.Duration {
	raw := strings.TrimSpace(os.Getenv("CACHE_TTL_SECONDS"))
	if raw == "" {
		return time.Duration(defaultCacheTTLSeconds) * time.Second
	}
	secs, err := strconv.Atoi(raw)
	if err != nil || secs <= 0 {
		logJSON("WARN", "search-service", fmt.Sprintf("Invalid CACHE_TTL_SECONDS=%q, using default %ds", raw, defaultCacheTTLSeconds), "", "", nil)
		return time.Duration(defaultCacheTTLSeconds) * time.Second
	}
	return time.Duration(secs) * time.Second
}

func resetRedisClient() {
	redisMu.Lock()
	defer redisMu.Unlock()
	if redisClient != nil {
		_ = redisClient.Close()
		redisClient = nil
	}
	lastRedisFail = time.Time{}
}

// getRedisClient establishes the Redis client with a bounded timeout and
// reconnect cooldown. Network I/O runs outside redisMu so concurrent requests do
// not serialize behind a Redis timeout.
func getRedisClient(parent context.Context, timeout time.Duration) (*redis.Client, error) {
	if getEnv("CACHE_ENABLED", "true") == "false" {
		return nil, nil
	}
	redisURL := getEnv("REDIS_URL", "redis://redis:6379")
	opt, err := redis.ParseURL(redisURL)
	if err != nil {
		return nil, fmt.Errorf("parse REDIS_URL: %w", err)
	}

	redisMu.Lock()
	if redisClient != nil {
		client := redisClient
		redisMu.Unlock()
		return client, nil
	}
	if !lastRedisFail.IsZero() && time.Since(lastRedisFail) < redisReconnectCooldown {
		redisMu.Unlock()
		return nil, fmt.Errorf("redis reconnect cooling down")
	}
	redisMu.Unlock()

	candidate := redis.NewClient(opt)
	ctx, cancel := context.WithTimeout(parent, timeout)
	defer cancel()
	if _, err := candidate.Ping(ctx).Result(); err != nil {
		_ = candidate.Close()
		redisMu.Lock()
		lastRedisFail = time.Now()
		redisMu.Unlock()
		return nil, fmt.Errorf("ping redis: %w", err)
	}

	redisMu.Lock()
	if redisClient != nil {
		existing := redisClient
		redisMu.Unlock()
		_ = candidate.Close()
		return existing, nil
	}
	redisClient = candidate
	lastRedisFail = time.Time{}
	redisMu.Unlock()

	logJSON("INFO", "search-service", "Connected to Redis", "", "", nil)
	return candidate, nil
}

func initRedis() error {
	_, err := getRedisClient(context.Background(), 10*time.Second)
	return err
}

func generateRequestID() string {
	return uuid.New().String()
}

func traceIDFromContext(ctx context.Context) string {
	spanContext := trace.SpanFromContext(ctx).SpanContext()
	if !spanContext.IsValid() {
		return ""
	}
	return spanContext.TraceID().String()
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
	reg.MustRegister(
		httpRequestsTotal,
		httpRequestDurationMs,
		cacheHitsTotal,
		cacheMissesTotal,
		collectors.NewGoCollector(),
		collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}),
	)
	return promhttp.HandlerFor(reg, promhttp.HandlerOpts{Registry: reg})
}

func metricsMiddleware(service string) gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		c.Next()
		path := c.FullPath()
		if path == "/metrics" {
			return
		}
		if path == "" {
			path = "unknown"
		}
		status := fmt.Sprintf("%d", c.Writer.Status())
		httpRequestsTotal.WithLabelValues(service, c.Request.Method, path, status).Inc()
		httpRequestDurationMs.WithLabelValues(service, c.Request.Method, path).Observe(float64(time.Since(start).Microseconds()) / 1000.0)
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
		redisMu.Lock()
		defer redisMu.Unlock()
		if redisClient != nil {
			_ = redisClient.Close()
		}
	}()

	r := newRouter()

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

func newRouter() *gin.Engine {
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
		client, connectErr := getRedisClient(c.Request.Context(), 1*time.Second)
		if client != nil {
			ctx, cancel := context.WithTimeout(c.Request.Context(), time.Second)
			if err := client.Ping(ctx).Err(); err != nil {
				cacheState = "unreachable"
			} else {
				cacheState = "ok"
			}
			cancel()
		} else if connectErr != nil {
			cacheState = "unreachable"
		}
		c.JSON(http.StatusOK, gin.H{"status": "ready", "cache": cacheState})
	})
	r.GET("/readyz", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"status": "ok"}) })

	r.GET("/metrics", gin.WrapH(prometheusHandler()))

	r.GET("/api/search", func(c *gin.Context) {
		requestID := c.GetString("request_id")
		ctx := c.Request.Context()
		origin := c.Query("origin")
		destination := c.Query("destination")
		date := c.Query("date")
		if date != "" {
			if _, err := time.Parse("2006-01-02", date); err != nil {
				logContext(ctx, requestID, "WARN", "search-service", "Invalid date parameter", map[string]interface{}{"date": date})
				c.JSON(http.StatusBadRequest, gin.H{"error": "date must be YYYY-MM-DD"})
				return
			}
		}

		// Stage 7: cache key. Origin/destination/date are the natural
		// partition — same three values = identical result, and they
		// bound the keyspace (6 airports × 5 dates × 6 airports ≈ 180 keys).
		cacheKey := fmt.Sprintf("search:%s:%s:%s", origin, destination, date)
		tracer := otel.Tracer("search-service")

		// --- Cache GET -------------------------------------------------
		cacheClient, _ := getRedisClient(ctx, time.Second)
		if cacheClient != nil {
			_, cacheSpan := tracer.Start(ctx, "cache.get",
				trace.WithAttributes(attribute.String("cache.key", cacheKey)))
			cacheCtx, cancel := context.WithTimeout(ctx, 1*time.Second)
			cached, cerr := cacheClient.Get(cacheCtx, cacheKey).Result()
			cancel()
			if cerr == nil {
				cacheSpan.SetAttributes(attribute.Bool("cache.hit", true))
				cacheSpan.End()
				cacheHitsTotal.WithLabelValues("search").Inc()
				c.Header("X-Cache", "HIT")
				c.Header("Content-Type", "application/json")
				c.String(http.StatusOK, cached)
				logContext(ctx, requestID, "INFO", "search-service", "Search served from cache", map[string]interface{}{"cache_key": cacheKey})
				return
			}
			if !errors.Is(cerr, redis.Nil) {
				// Real error (not just "key not found"). Record OTEL error + treat as miss
				// so a Redis blip doesn't break search.
				cacheSpan.RecordError(cerr)
				cacheSpan.SetStatus(codes.Error, cerr.Error())
				logContext(ctx, requestID, "WARN", "search-service", fmt.Sprintf("Redis GET failed (degrading to miss): %v", cerr))
			}
			cacheSpan.SetAttributes(attribute.Bool("cache.hit", false))
			cacheSpan.End()
		}
		cacheMissesTotal.WithLabelValues("search").Inc()

		// --- Cache MISS: call flight service --------------------------
		// Encode the values so a parameter cannot smuggle in another one.
		params := url.Values{}
		for key, value := range map[string]string{"origin": origin, "destination": destination, "date": date} {
			if value != "" {
				params.Set(key, value)
			}
		}
		searchURL := flightServiceURL + "/api/flights"
		if len(params) > 0 {
			searchURL += "?" + params.Encode()
		}

		clientCtx, clientSpan := tracer.Start(ctx,
			fmt.Sprintf("HTTP GET %s", searchURL),
			trace.WithSpanKind(trace.SpanKindClient),
		)
		req, err := http.NewRequestWithContext(clientCtx, "GET", searchURL, nil)
		if err != nil {
			clientSpan.RecordError(err)
			clientSpan.SetStatus(codes.Error, err.Error())
			clientSpan.End()
			logContext(ctx, requestID, "ERROR", "search-service", fmt.Sprintf("Failed to build request: %v", err))
			c.JSON(http.StatusBadGateway, gin.H{"error": "Flight service unavailable"})
			return
		}
		req.Header.Set("X-Request-ID", requestID)
		// Inject W3C traceparent so the flight service span becomes a child
		otel.GetTextMapPropagator().Inject(clientCtx, propagation.HeaderCarrier(req.Header))

		client := &http.Client{Timeout: 10 * time.Second}
		resp, err := client.Do(req)
		if err != nil {
			clientSpan.RecordError(err)
			clientSpan.SetStatus(codes.Error, err.Error())
			clientSpan.End()
			logContext(ctx, requestID, "ERROR", "search-service", fmt.Sprintf("Flight service call failed: %v", err))
			c.JSON(http.StatusBadGateway, gin.H{"error": "Flight service unavailable"})
			return
		}
		defer resp.Body.Close()

		clientSpan.SetAttributes(
			semconv.HTTPResponseStatusCode(resp.StatusCode),
			semconv.URLFull(searchURL),
		)
		body, readErr := io.ReadAll(resp.Body)
		if readErr != nil {
			clientSpan.RecordError(readErr)
			clientSpan.SetStatus(codes.Error, readErr.Error())
			clientSpan.End()
			logContext(ctx, requestID, "ERROR", "search-service", fmt.Sprintf("Failed to read flight response: %v", readErr))
			c.JSON(http.StatusBadGateway, gin.H{"error": "Flight service unavailable"})
			return
		}
		clientSpan.End()

		var flightResp struct {
			Flights []flightItem `json:"flights"`
		}
		decodeErr := json.Unmarshal(body, &flightResp)

		// An upstream failure is not an empty result set, and must not be
		// cached as one.
		if resp.StatusCode != http.StatusOK || decodeErr != nil || flightResp.Flights == nil {
			logContext(ctx, requestID, "ERROR", "search-service", fmt.Sprintf("Flight service returned HTTP %d", resp.StatusCode))
			c.JSON(http.StatusBadGateway, gin.H{"error": "Flight service unavailable"})
			return
		}
		results := make([]SearchResult, 0, len(flightResp.Flights))
		for _, fm := range flightResp.Flights {
			dep, depErr := time.Parse(time.RFC3339, fm.DepartureTime)
			arr, arrErr := time.Parse(time.RFC3339, fm.ArrivalTime)
			duration := 0
			if depErr == nil && arrErr == nil && arr.After(dep) {
				duration = int(arr.Sub(dep).Minutes())
			}
			results = append(results, SearchResult{
				ID:             fm.ID,
				FlightNumber:   fm.FlightNumber,
				Origin:         fm.Origin,
				Destination:    fm.Destination,
				DepartureTime:  fm.DepartureTime,
				ArrivalTime:    fm.ArrivalTime,
				Duration:       duration,
				AvailableSeats: fm.AvailableSeats,
				Status:         fm.Status,
			})
		}
		payload := gin.H{"results": results, "total": len(results), "page": 1, "limit": 20}

		// --- Cache SET -------------------------------------------------
		// Best-effort: failure to SET does not fail the request.
		if cacheClient != nil {
			payloadBytes, mErr := json.Marshal(payload)
			if mErr == nil {
				_, setSpan := tracer.Start(ctx, "cache.set",
					trace.WithAttributes(attribute.String("cache.key", cacheKey)))
				setCtx, cancel := context.WithTimeout(ctx, 1*time.Second)
				sErr := cacheClient.Set(setCtx, cacheKey, payloadBytes, getCacheTTL()).Err()
				cancel()
				if sErr != nil {
					setSpan.RecordError(sErr)
					setSpan.SetStatus(codes.Error, sErr.Error())
					logContext(ctx, requestID, "WARN", "search-service", fmt.Sprintf("Redis SET failed (response still served): %v", sErr))
				}
				setSpan.End()
			}
		}

		c.Header("X-Cache", "MISS")
		logContext(ctx, requestID, "INFO", "search-service", "Search completed", map[string]interface{}{"count": len(results), "cache_key": cacheKey})
		c.JSON(http.StatusOK, payload)
	})

	return r
}
