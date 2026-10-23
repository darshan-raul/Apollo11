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
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

var (
	flightServiceURL string
	logger           = log.New(os.Stdout, "", 0)
)

func init() {
	flightServiceURL = getEnv("FLIGHT_SERVICE_URL", "http://flight:8081")
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

type SearchResult struct {
	ID            string `json:"id"`
	FlightNumber  string `json:"flightNumber"`
	Origin        string `json:"origin"`
	Destination   string `json:"destination"`
	DepartureTime string `json:"departureTime"`
	ArrivalTime   string `json:"arrivalTime"`
	Duration      int    `json:"duration"`
	AvailableSeats int   `json:"availableSeats"`
	Status        string `json:"status"`
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

func main() {
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

	// Stage 4: split /healthz into startup/live/ready probes. Search has no
	// persistent local state to check, so /readyz and /healthz/ready both
	// return 200 unconditionally. The legacy /healthz path is kept for
	// back-compat.
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
		c.JSON(http.StatusOK, gin.H{"status": "ready"})
	})

	r.GET("/readyz", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	r.GET("/metrics", func(c *gin.Context) {
		metrics := `# HELP http_requests_total Total HTTP requests observed by the service.
# TYPE http_requests_total counter
http_requests_total{service="search"} 0
# HELP http_request_duration_ms Most recently observed request duration in milliseconds.
# TYPE http_request_duration_ms gauge
http_request_duration_ms{service="search"} 0
# HELP db_connections_active Active database connections owned by the service.
# TYPE db_connections_active gauge
db_connections_active{service="search"} 0
`
		c.Data(http.StatusOK, "text/plain; version=0.0.4; charset=utf-8", []byte(metrics))
	})

	r.GET("/api/search", func(c *gin.Context) {
		requestID, _ := c.Get("request_id")
		traceID := requestID.(string)

		origin := c.Query("origin")
		destination := c.Query("destination")
		date := c.Query("date")

		if date != "" {
			if _, err := time.Parse("2006-01-02", date); err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "date must be YYYY-MM-DD"})
				return
			}
		}

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

		req, _ := http.NewRequest("GET", searchURL, nil)
		req.Header.Set("X-Request-ID", traceID)
		client := &http.Client{Timeout: 10 * time.Second}
		resp, err := client.Do(req)
		if err != nil {
			logJSON("ERROR", "search-service", fmt.Sprintf("Flight service call failed: %v", err), traceID, "", nil)
			c.JSON(http.StatusBadGateway, gin.H{"error": "Flight service unavailable"})
			return
		}
		defer resp.Body.Close()

		body, _ := io.ReadAll(resp.Body)
		var result map[string]interface{}
		decodeErr := json.Unmarshal(body, &result)

		// An upstream failure is not an empty result set.
		flightsRaw, ok := result["flights"].([]interface{})
		if resp.StatusCode != http.StatusOK || decodeErr != nil || !ok {
			logJSON("ERROR", "search-service", fmt.Sprintf("Flight service returned HTTP %d", resp.StatusCode), traceID, "", nil)
			c.JSON(http.StatusBadGateway, gin.H{"error": "Flight service unavailable"})
			return
		}

		results := []SearchResult{}
		for _, f := range flightsRaw {
			fm := f.(map[string]interface{})
			depStr := fm["departureTime"].(string)
			arrStr := fm["arrivalTime"].(string)
			dep, _ := time.Parse(time.RFC3339, depStr)
			arr, _ := time.Parse(time.RFC3339, arrStr)
			duration := int(arr.Sub(dep).Minutes())
			results = append(results, SearchResult{
				ID:            fm["id"].(string),
				FlightNumber:  fm["flightNumber"].(string),
				Origin:        fm["origin"].(string),
				Destination:   fm["destination"].(string),
				DepartureTime: depStr,
				ArrivalTime:   arrStr,
				Duration:      duration,
				AvailableSeats: int(fm["availableSeats"].(float64)),
				Status:        fm["status"].(string),
			})
		}
		logJSON("INFO", "search-service", "Search completed", traceID, "", map[string]interface{}{"count": len(results)})
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