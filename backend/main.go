package main

import (
    "database/sql"
    "log"
    "net/http"

    "github.com/gin-gonic/gin"
    _ "github.com/lib/pq"
   // "github.com/rs/cors"

)

type Fact struct {
    ID   int    `json:"id"`
    Text string `json:"text"`
}

var db *sql.DB

func main() {
    var err error
    db, err = sql.Open("postgres", "user=apollo password=tothemoon dbname=apollo11 sslmode=disable")
    if err != nil {
        log.Fatal(err)
    }

    defer db.Close()

    r := gin.Default()

    // // Use cors middleware
    // config := cors.New(cors.Options{
    //     AllowedOrigins: []string{"http://localhost:3000"},
    //     AllowedMethods: []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
    //     AllowedHeaders: []string{"*"},
    // })
    // r.Use(func(c *gin.Context) {
    //     config.Handler(r).ServeHTTP(c.Writer, c.Request)
    // })


    r.GET("/facts", getFacts)
    r.POST("/facts", createFact)

    if err := r.Run(":8080"); err != nil {
        log.Fatal(err)
    }
}

func getFacts(c *gin.Context) {
    rows, err := db.Query("SELECT id, text FROM facts")
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }
    defer rows.Close()

    var facts []Fact
    for rows.Next() {
        var fact Fact
        if err := rows.Scan(&fact.ID, &fact.Text); err != nil {
            c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
            return
        }
        facts = append(facts, fact)
    }

    c.JSON(http.StatusOK, facts)
}

func createFact(c *gin.Context) {
    var newFact Fact
    if err := c.ShouldBindJSON(&newFact); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    _, err := db.Exec("INSERT INTO facts (text) VALUES ($1)", newFact.Text)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    c.JSON(http.StatusOK, gin.H{"message": "Fact added successfully"})
}
