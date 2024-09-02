// main_test.go
package main

import (
    "bytes"
    "database/sql"
    "net/http"
    "net/http/httptest"
    "testing"

    "github.com/gin-gonic/gin"
    _ "github.com/lib/pq"
    "github.com/stretchr/testify/assert"
)

func setupRouter() *gin.Engine {
    gin.SetMode(gin.TestMode)
    r := gin.Default()
    r.GET("/facts", getFacts)
    r.POST("/facts", createFact)
    return r
}

func TestGetFacts(t *testing.T) {
    db, _ = sql.Open("postgres", "user=apollo dbname=apollo11 sslmode=disable")
    defer db.Close()

    // Setup router
    r := setupRouter()

    // Create a request to send to the router
    req, _ := http.NewRequest("GET", "/facts", nil)

    // Create a ResponseRecorder to record the response
    w := httptest.NewRecorder()

    // Perform the request
    r.ServeHTTP(w, req)

    // Check if status code is 200
    assert.Equal(t, http.StatusOK, w.Code)

    // Check if the response is a valid JSON array
    assert.Contains(t, w.Body.String(), "[")
    assert.Contains(t, w.Body.String(), "]")
}

func TestCreateFact(t *testing.T) {
    db, _ = sql.Open("postgres", "user=apollo dbname=apollo11 sslmode=disable")
    defer db.Close()

    r := setupRouter()

    // Create a new fact
    jsonBody := []byte(`{"text": "This is a test fact."}`)
    req, _ := http.NewRequest("POST", "/facts", bytes.NewBuffer(jsonBody))
    req.Header.Set("Content-Type", "application/json")

    w := httptest.NewRecorder()
    r.ServeHTTP(w, req)

    // Check if status code is 200
    assert.Equal(t, http.StatusOK, w.Code)

    // Check if the response contains a success message
    assert.Contains(t, w.Body.String(), "Fact added successfully")
}
