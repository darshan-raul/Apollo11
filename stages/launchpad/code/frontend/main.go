// Package main - Apollo11 Frontend Service
package main

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
)

func cors() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	}
}

func main() {
	r := gin.Default()
	r.Use(cors())

	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	r.GET("/", func(c *gin.Context) {
		html := `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Apollo11 Library</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        h1 { color: #333; }
        .card { background: white; padding: 20px; margin: 10px 0; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        button { background: #007bff; color: white; border: none; padding: 10px 20px; border-radius: 4px; cursor: pointer; }
        button:hover { background: #0056b3; }
    </style>
</head>
<body>
    <h1>Apollo11 Library Management</h1>
    <div class="card">
        <h2>Welcome to the Library</h2>
        <p>This is the Apollo11 K8s learning bootstrap project.</p>
        <p>Services: frontend, auth, catalog, circulation, notification, fines</p>
    </div>
    <div class="card">
        <h3>API Health</h3>
        <button onclick="checkHealth()">Check All Services</button>
        <pre id="health-output"></pre>
    </div>
    <script>
        async function checkHealth() {
            const services = [
                { name: 'frontend', url: 'http://localhost:3000/health' },
                { name: 'auth', url: 'http://localhost:8080/health' },
                { name: 'catalog', url: 'http://localhost:8081/health' },
                { name: 'circulation', url: 'http://localhost:8082/health' },
                { name: 'notification', url: 'http://localhost:8083/health' },
                { name: 'fines', url: 'http://localhost:8084/health' }
            ];
            let output = '';
            for (const s of services) {
                try {
                    const r = await fetch(s.url);
                    const d = await r.json();
                    output += s.name + ': ' + d.status + '\n';
                } catch(e) {
                    output += s.name + ': DOWN\n';
                }
            }
            document.getElementById('health-output').textContent = output;
        }
    </script>
</body>
</html>`
		c.Data(http.StatusOK, "text/html; charset=utf-8", []byte(html))
	})

	log.Println("Frontend starting on :3000")
	r.Run(":3000")
}