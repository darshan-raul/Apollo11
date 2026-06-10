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
	"github.com/redis/go-redis/v9"
)

var (
	redisClient *redis.Client
	logger      = log.New(os.Stdout, "", 0)
	ctx         = context.Background()
)

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

func main() {
	initRedis()
	defer redisClient.Close()

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

	// Stage 4: split /healthz into startup/live/ready probes. Notification's
	// readiness probe checks Redis (its sole downstream dependency).
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

	r.GET("/metrics", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"service":                  "notification",
			"http_requests_total":       0,
			"http_request_duration_ms": 0,
			"db_connections_active":     0,
		})
	})

	r.POST("/api/notify", func(c *gin.Context) {
		requestID, _ := c.Get("request_id")
		traceID := requestID.(string)

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
			logJSON("ERROR", "notification-service", fmt.Sprintf("Failed to push to queue: %v", err), traceID, "", nil)
		}

		logJSON("INFO", "notification-service", fmt.Sprintf("Event queued: %s", req.Type), traceID, "", map[string]interface{}{
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