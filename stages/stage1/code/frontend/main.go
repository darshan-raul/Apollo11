// Package main - Apollo11 Frontend Service
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

var (
	authURL        = getEnv("AUTH_SERVICE_URL", "http://auth:8080")
	catalogURL     = getEnv("CATALOG_SERVICE_URL", "http://catalog:8081")
	circulationURL = getEnv("CIRCULATION_SERVICE_URL", "http://circulation:8082")
	finesURL       = getEnv("FINES_SERVICE_URL", "http://fines:8084")
)

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

type healthResult struct {
	Service string `json:"service"`
	Status  string `json:"status"`
}

func healthCheck(serviceName, url string) healthResult {
	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get(url + "/health")
	if err != nil {
		return healthResult{serviceName, "DOWN"}
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return healthResult{serviceName, "DOWN"}
	}
	return healthResult{serviceName, "UP"}
}

func main() {
	r := gin.Default()

	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	r.GET("/", func(c *gin.Context) {
		c.Data(http.StatusOK, "text/html; charset=utf-8", []byte(htmlPage))
	})

	r.GET("/health/all", func(c *gin.Context) {
		services := []healthResult{
			healthCheck("frontend", "http://localhost:3000"),
			healthCheck("auth", authURL+"/health"),
			healthCheck("catalog", catalogURL+"/health"),
			healthCheck("circulation", circulationURL+"/health"),
			healthCheck("fines", finesURL+"/health"),
		}
		c.JSON(http.StatusOK, gin.H{"services": services})
	})

	r.GET("/api/books", func(c *gin.Context) {
		resp, err := http.Get(catalogURL + "/books")
		if err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "catalog unavailable"})
			return
		}
		defer resp.Body.Close()
		var result map[string]interface{}
		if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "parse error"})
			return
		}
		c.JSON(resp.StatusCode, result)
	})

	r.GET("/api/books/:id", func(c *gin.Context) {
		resp, err := http.Get(catalogURL + "/books/" + c.Param("id"))
		if err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "catalog unavailable"})
			return
		}
		defer resp.Body.Close()
		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		c.JSON(resp.StatusCode, result)
	})

	r.GET("/api/authors", func(c *gin.Context) {
		resp, err := http.Get(catalogURL + "/authors")
		if err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "catalog unavailable"})
			return
		}
		defer resp.Body.Close()
		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		c.JSON(resp.StatusCode, result)
	})

	r.GET("/api/loans", func(c *gin.Context) {
		token := extractToken(c)
		if token == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "no token"})
			return
		}
		req, _ := http.NewRequest("GET", circulationURL+"/loans", nil)
		req.Header.Set("Authorization", "Bearer "+token)
		client := &http.Client{Timeout: 5 * time.Second}
		resp, err := client.Do(req)
		if err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "circulation unavailable"})
			return
		}
		defer resp.Body.Close()
		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		c.JSON(resp.StatusCode, result)
	})

	r.POST("/api/loans", func(c *gin.Context) {
		token := extractToken(c)
		if token == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "no token"})
			return
		}
		var body map[string]interface{}
		if err := c.ShouldBindJSON(&body); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
			return
		}
		jsonBody, _ := json.Marshal(body)
		req, _ := http.NewRequest("POST", circulationURL+"/loans", strings.NewReader(string(jsonBody)))
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("Content-Type", "application/json")
		client := &http.Client{Timeout: 5 * time.Second}
		resp, err := client.Do(req)
		if err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "circulation unavailable"})
			return
		}
		defer resp.Body.Close()
		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		c.JSON(resp.StatusCode, result)
	})

	r.POST("/api/loans/:id/return", func(c *gin.Context) {
		token := extractToken(c)
		if token == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "no token"})
			return
		}
		req, _ := http.NewRequest("POST", circulationURL+"/loans/"+c.Param("id")+"/return", nil)
		req.Header.Set("Authorization", "Bearer "+token)
		client := &http.Client{Timeout: 5 * time.Second}
		resp, err := client.Do(req)
		if err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "circulation unavailable"})
			return
		}
		defer resp.Body.Close()
		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		c.JSON(resp.StatusCode, result)
	})

	r.GET("/api/fines", func(c *gin.Context) {
		token := extractToken(c)
		if token == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "no token"})
			return
		}
		req, _ := http.NewRequest("GET", finesURL+"/fines", nil)
		req.Header.Set("Authorization", "Bearer "+token)
		client := &http.Client{Timeout: 5 * time.Second}
		resp, err := client.Do(req)
		if err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "fines unavailable"})
			return
		}
		defer resp.Body.Close()
		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		c.JSON(resp.StatusCode, result)
	})

	log.Printf("Frontend starting on :3000")
	r.Run(":3000")
}

func extractToken(c *gin.Context) string {
	auth := c.GetHeader("Authorization")
	if strings.HasPrefix(auth, "Bearer ") {
		return strings.TrimPrefix(auth, "Bearer ")
	}
	cookie, err := c.Cookie("token")
	if err == nil {
		return cookie
	}
	return ""
}

const htmlPage = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Apollo11 Library</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0f172a; color: #e2e8f0; min-height: 100vh; }
        .container { max-width: 900px; margin: 0 auto; padding: 2rem; }
        h1 { color: #38bdf8; margin-bottom: 0.5rem; }
        .subtitle { color: #94a3b8; margin-bottom: 2rem; }
        .card { background: #1e293b; border-radius: 12px; padding: 1.5rem; margin-bottom: 1rem; border: 1px solid #334155; }
        .card h2 { color: #38bdf8; font-size: 1.1rem; margin-bottom: 1rem; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 1rem; }
        .service-item { display: flex; justify-content: space-between; align-items: center; padding: 0.75rem 0; border-bottom: 1px solid #334155; }
        .service-item:last-child { border-bottom: none; }
        .status-dot { width: 10px; height: 10px; border-radius: 50%; display: inline-block; margin-right: 8px; }
        .up { background: #22c55e; } .down { background: #ef4444; }
        .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; margin-top: 1rem; }
        .info-item { background: #0f172a; padding: 1rem; border-radius: 8px; }
        .info-label { color: #94a3b8; font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.05em; }
        .info-value { color: #38bdf8; font-size: 1.5rem; font-weight: 600; }
        .badge { background: #38bdf8; color: #0f172a; padding: 0.25rem 0.75rem; border-radius: 999px; font-size: 0.75rem; font-weight: 600; }
        .footer { text-align: center; color: #475569; font-size: 0.875rem; margin-top: 3rem; padding-top: 2rem; border-top: 1px solid #1e293b; }
        button { background: #38bdf8; color: #0f172a; border: none; padding: 0.75rem 1.5rem; border-radius: 8px; font-weight: 600; cursor: pointer; margin-top: 1rem; }
        button:hover { background: #0ea5e9; }
        pre { background: #0f172a; padding: 1rem; border-radius: 8px; overflow-x: auto; font-size: 0.875rem; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Apollo11 Library</h1>
        <p class="subtitle">Kubernetes Learning Bootstrap — 11 Stage Curriculum</p>

        <div class="card">
            <h2>Services</h2>
            <div class="service-item"><span><span class="status-dot up"></span>Frontend (Go)</span><span class="badge">:3000</span></div>
            <div class="service-item"><span><span class="status-dot up"></span>Auth (Python)</span><span class="badge">:8080</span></div>
            <div class="service-item"><span><span class="status-dot up"></span>Catalog (Go)</span><span class="badge">:8081</span></div>
            <div class="service-item"><span><span class="status-dot up"></span>Circulation (Go)</span><span class="badge">:8082</span></div>
            <div class="service-item"><span><span class="status-dot up"></span>Notification (Go)</span><span class="badge">:8083</span></div>
            <div class="service-item"><span><span class="status-dot up"></span>Fines (Go)</span><span class="badge">:8084</span></div>
        </div>

        <div class="info-grid">
            <div class="info-item"><div class="info-label">Namespace</div><div class="info-value">apollo11</div></div>
            <div class="info-item"><div class="info-label">Services</div><div class="info-value">11</div></div>
            <div class="info-item"><div class="info-label">Stage</div><div class="info-value">1</div></div>
            <div class="info-item"><div class="info-label">Platform</div><div class="info-value">k8s</div></div>
        </div>

        <div class="footer">
            Apollo11 — Learn Kubernetes the right way
        </div>
    </div>
</body>
</html>`