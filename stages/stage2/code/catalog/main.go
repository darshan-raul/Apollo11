// Package main - Apollo11 Catalog Service
package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/go-redis/redis/v8"
	"github.com/golang-jwt/jwt/v5"
	_ "github.com/lib/pq"
)

// Config holds the service configuration
type Config struct {
	DATABASE_URL string
	REDIS_URL    string
	JWT_SECRET   string
}

// Global references
var (
	db          *sql.DB
	rdb          *redis.Client
	jwtSecret    []byte
	ctx          = context.Background()
)

// Models

type Author struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Bio       string    `json:"bio,omitempty"`
	CreatedAt time.Time `json:"created_at,omitempty"`
}

type Book struct {
	ID              string  `json:"id"`
	ISBN            string  `json:"isbn"`
	Title           string  `json:"title"`
	AuthorID        string  `json:"author_id,omitempty"`
	Author          *Author `json:"author,omitempty"`
	Genre           string  `json:"genre,omitempty"`
	CopiesTotal     int     `json:"copies_total,omitempty"`
	CopiesAvailable int     `json:"copies_available"`
}

// Request/Response types

type CreateBookRequest struct {
	ISBN        string `json:"isbn" binding:"required"`
	Title       string `json:"title" binding:"required"`
	AuthorID    string `json:"author_id" binding:"required"`
	Genre       string `json:"genre"`
	CopiesTotal int    `json:"copies_total"`
}

type CreateAuthorRequest struct {
	Name string `json:"name" binding:"required"`
	Bio  string `json:"bio"`
}

type PaginatedBooksResponse struct {
	Books []Book `json:"books"`
	Total int    `json:"total"`
	Page  int    `json:"page"`
	Limit int    `json:"limit"`
}

type PaginatedAuthorsResponse struct {
	Authors []Author `json:"authors"`
	Total   int      `json:"total"`
	Page    int      `json:"page"`
	Limit   int      `json:"limit"`
}

type ErrorResponse struct {
	Error string `json:"error"`
}

// JWT Claims

type Claims struct {
	Sub   string `json:"sub"`
	Email string `json:"email"`
	Role  string `json:"role"`
	jwt.RegisteredClaims
}

// initDB initializes the PostgreSQL connection
func initDB(databaseURL string) (*sql.DB, error) {
	db, err := sql.Open("postgres", databaseURL)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)

	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	log.Println("Connected to PostgreSQL")
	return db, nil
}

// initRedis initializes the Redis connection
func initRedis(redisURL string) (*redis.Client, error) {
	opt, err := redis.ParseURL(redisURL)
	if err != nil {
		return nil, fmt.Errorf("failed to parse redis URL: %w", err)
	}

	rdb := redis.NewClient(opt)
	if _, err := rdb.Ping(ctx).Result(); err != nil {
		return nil, fmt.Errorf("failed to ping redis: %w", err)
	}

	log.Println("Connected to Redis")
	return rdb, nil
}

// Helper: getPageParams extracts page and limit from query params
func getPageParams(c *gin.Context) (page, limit int) {
	page = 1
	limit = 20

	if p := c.Query("page"); p != "" {
		if parsed, err := strconv.Atoi(p); err == nil && parsed > 0 {
			page = parsed
		}
	}
	if l := c.Query("limit"); l != "" {
		if parsed, err := strconv.Atoi(l); err == nil && parsed > 0 && parsed <= 100 {
			limit = parsed
		}
	}
	return
}

// Helper: extractBearerToken extracts JWT from Authorization header
func extractBearerToken(c *gin.Context) string {
	auth := c.GetHeader("Authorization")
	if !strings.HasPrefix(auth, "Bearer ") {
		return ""
	}
	return strings.TrimPrefix(auth, "Bearer ")
}

// Helper: validateToken validates JWT and returns claims
func validateToken(tokenString string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return jwtSecret, nil
	})
	if err != nil {
		return nil, err
	}

	if claims, ok := token.Claims.(*Claims); ok && token.Valid {
		return claims, nil
	}
	return nil, fmt.Errorf("invalid token")
}

// Helper: requireAuth middleware validates JWT but does not require it for optional endpoints
func requireAuth() gin.HandlerFunc {
	return func(c *gin.Context) {
		tokenString := extractBearerToken(c)
		if tokenString == "" {
			c.Next()
			return
		}

		claims, err := validateToken(tokenString)
		if err != nil {
			c.Next()
			return
		}

		c.Set("user_id", claims.Sub)
		c.Set("user_role", claims.Role)
		c.Next()
	}
}

// Helper: requireAdmin middleware requires admin role
func requireAdmin() gin.HandlerFunc {
	return func(c *gin.Context) {
		tokenString := extractBearerToken(c)
		if tokenString == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, ErrorResponse{Error: "missing authorization token"})
			return
		}

		claims, err := validateToken(tokenString)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, ErrorResponse{Error: "invalid token"})
			return
		}

		if claims.Role != "admin" {
			c.AbortWithStatusJSON(http.StatusForbidden, ErrorResponse{Error: "admin role required"})
			return
		}

		c.Set("user_id", claims.Sub)
		c.Set("user_role", claims.Role)
		c.Next()
	}
}

// Redis caching helpers

func cacheGet(key string) (string, error) {
	val, err := rdb.Get(ctx, key).Result()
	if err == redis.Nil {
		return "", nil
	}
	return val, err
}

func cacheSet(key string, value interface{}, ttl time.Duration) error {
	data, err := json.Marshal(value)
	if err != nil {
		return err
	}
	return rdb.Set(ctx, key, data, ttl).Err()
}

// --- Handlers ---

func healthHandler(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

// GET /books
func listBooksHandler(c *gin.Context) {
	page, limit := getPageParams(c)
	offset := (page - 1) * limit

	search := c.Query("search")
	genre := c.Query("genre")
	authorID := c.Query("author_id")

	// Build query
	query := `SELECT id, isbn, title, author_id, genre, copies_total, copies_available FROM books WHERE 1=1`
	countQuery := `SELECT COUNT(*) FROM books WHERE 1=1`
	args := []interface{}{}
	argIdx := 1

	if search != "" {
		searchFilter := fmt.Sprintf(" AND (title ILIKE $%d OR isbn ILIKE $%d)", argIdx, argIdx)
		query += searchFilter
		countQuery += searchFilter
		args = append(args, "%"+search+"%")
		argIdx++
	}
	if genre != "" {
		genreFilter := fmt.Sprintf(" AND genre = $%d", argIdx)
		query += genreFilter
		countQuery += genreFilter
		args = append(args, genre)
		argIdx++
	}
	if authorID != "" {
		authorFilter := fmt.Sprintf(" AND author_id = $%d", argIdx)
		query += authorFilter
		countQuery += authorFilter
		args = append(args, authorID)
		argIdx++
	}

	// Get total count
	var total int
	err := db.QueryRow(countQuery, args...).Scan(&total)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: "failed to count books"})
		return
	}

	// Add pagination
	query += fmt.Sprintf(" ORDER BY created_at DESC LIMIT $%d OFFSET $%d", argIdx, argIdx+1)
	args = append(args, limit, offset)

	rows, err := db.Query(query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: "failed to fetch books"})
		return
	}
	defer rows.Close()

	books := []Book{}
	for rows.Next() {
		var b Book
		var authorID sql.NullString
		var genre sql.NullString
		var copiesTotal int
		err := rows.Scan(&b.ID, &b.ISBN, &b.Title, &authorID, &genre, &copiesTotal, &b.CopiesAvailable)
		if err != nil {
			continue
		}
		if authorID.Valid {
			b.AuthorID = authorID.String
			// Fetch author info
			author, _ := getAuthorByID(authorID.String)
			b.Author = author
		}
		if genre.Valid {
			b.Genre = genre.String
		}
		b.CopiesTotal = copiesTotal
		books = append(books, b)
	}

	c.JSON(http.StatusOK, PaginatedBooksResponse{
		Books: books,
		Total: total,
		Page:  page,
		Limit: limit,
	})
}

// GET /books/:id
func getBookHandler(c *gin.Context) {
	id := c.Param("id")

	// Try cache first
	cacheKey := "catalog:book:" + id
	cached, err := cacheGet(cacheKey)
	if err == nil && cached != "" {
		var book Book
		if json.Unmarshal([]byte(cached), &book) == nil {
			c.JSON(http.StatusOK, book)
			return
		}
	}

	// Query database
	var b Book
	var authorID sql.NullString
	var genre sql.NullString
	var copiesTotal int

	err = db.QueryRow(`
		SELECT id, isbn, title, author_id, genre, copies_total, copies_available 
		FROM books WHERE id = $1
	`, id).Scan(&b.ID, &b.ISBN, &b.Title, &authorID, &genre, &copiesTotal, &b.CopiesAvailable)

	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, ErrorResponse{Error: "book not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: "failed to fetch book"})
		return
	}

	if authorID.Valid {
		b.AuthorID = authorID.String
		author, _ := getAuthorByID(authorID.String)
		b.Author = author
	}
	if genre.Valid {
		b.Genre = genre.String
	}
	b.CopiesTotal = copiesTotal

	// Cache result
	cacheSet(cacheKey, b, 5*time.Minute)

	c.JSON(http.StatusOK, b)
}

// POST /books (admin only)
func createBookHandler(c *gin.Context) {
	var req CreateBookRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: "invalid request: " + err.Error()})
		return
	}

	// Validate author exists
	var authorExists bool
	err := db.QueryRow("SELECT EXISTS(SELECT 1 FROM authors WHERE id = $1)", req.AuthorID).Scan(&authorExists)
	if err != nil || !authorExists {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: "author not found"})
		return
	}

	copiesTotal := req.CopiesTotal
	if copiesTotal <= 0 {
		copiesTotal = 1
	}

	var bookID string
	err = db.QueryRow(`
		INSERT INTO books (isbn, title, author_id, genre, copies_total, copies_available)
		VALUES ($1, $2, $3, $4, $5, $5)
		ON CONFLICT (isbn) DO UPDATE SET title = EXCLUDED.title
		RETURNING id
	`, req.ISBN, req.Title, req.AuthorID, req.Genre, copiesTotal).Scan(&bookID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: "failed to create book"})
		return
	}

	// Fetch the created book
	var b Book
	var authorID sql.NullString
	var genre sql.NullString
	var copiesTotalDb int

	err = db.QueryRow(`
		SELECT id, isbn, title, author_id, genre, copies_total, copies_available 
		FROM books WHERE id = $1
	`, bookID).Scan(&b.ID, &b.ISBN, &b.Title, &authorID, &genre, &copiesTotalDb, &b.CopiesAvailable)

	if err != nil {
		c.JSON(http.StatusCreated, gin.H{"id": bookID})
		return
	}

	if authorID.Valid {
		b.AuthorID = authorID.String
		author, _ := getAuthorByID(authorID.String)
		b.Author = author
	}
	if genre.Valid {
		b.Genre = genre.String
	}
	b.CopiesTotal = copiesTotalDb

	c.JSON(http.StatusCreated, b)
}

// GET /authors
func listAuthorsHandler(c *gin.Context) {
	page, limit := getPageParams(c)
	offset := (page - 1) * limit

	search := c.Query("search")

	query := `SELECT id, name, bio, created_at FROM authors WHERE 1=1`
	countQuery := `SELECT COUNT(*) FROM authors WHERE 1=1`
	args := []interface{}{}
	argIdx := 1

	if search != "" {
		searchFilter := fmt.Sprintf(" AND name ILIKE $%d", argIdx)
		query += searchFilter
		countQuery += searchFilter
		args = append(args, "%"+search+"%")
		argIdx++
	}

	var total int
	err := db.QueryRow(countQuery, args...).Scan(&total)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: "failed to count authors"})
		return
	}

	query += fmt.Sprintf(" ORDER BY name ASC LIMIT $%d OFFSET $%d", argIdx, argIdx+1)
	args = append(args, limit, offset)

	rows, err := db.Query(query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: "failed to fetch authors"})
		return
	}
	defer rows.Close()

	authors := []Author{}
	for rows.Next() {
		var a Author
		var bio sql.NullString
		err := rows.Scan(&a.ID, &a.Name, &bio, &a.CreatedAt)
		if err != nil {
			continue
		}
		if bio.Valid {
			a.Bio = bio.String
		}
		authors = append(authors, a)
	}

	c.JSON(http.StatusOK, PaginatedAuthorsResponse{
		Authors: authors,
		Total:   total,
		Page:    page,
		Limit:   limit,
	})
}

// getAuthorByID is a helper to fetch author by ID (used by other handlers)
func getAuthorByID(authorID string) (*Author, error) {
	if authorID == "" {
		return nil, nil
	}

	// Try cache first
	cacheKey := "catalog:author:" + authorID
	cached, err := cacheGet(cacheKey)
	if err == nil && cached != "" {
		var author Author
		if json.Unmarshal([]byte(cached), &author) == nil {
			return &author, nil
		}
	}

	var a Author
	var bio sql.NullString
	err = db.QueryRow(`
		SELECT id, name, bio, created_at FROM authors WHERE id = $1
	`, authorID).Scan(&a.ID, &a.Name, &bio, &a.CreatedAt)

	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	if bio.Valid {
		a.Bio = bio.String
	}

	// Cache result
	cacheSet(cacheKey, a, 5*time.Minute)

	return &a, nil
}

// GET /authors/:id
func getAuthorHandler(c *gin.Context) {
	id := c.Param("id")

	// Try cache first
	cacheKey := "catalog:author:" + id
	cached, err := cacheGet(cacheKey)
	if err == nil && cached != "" {
		var author Author
		if json.Unmarshal([]byte(cached), &author) == nil {
			c.JSON(http.StatusOK, author)
			return
		}
	}

	author, err := getAuthorByID(id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: "failed to fetch author"})
		return
	}
	if author == nil {
		c.JSON(http.StatusNotFound, ErrorResponse{Error: "author not found"})
		return
	}

	c.JSON(http.StatusOK, author)
}

// POST /authors (admin only)
func createAuthorHandler(c *gin.Context) {
	var req CreateAuthorRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: "invalid request: " + err.Error()})
		return
	}

	var authorID string
	err := db.QueryRow(`
		INSERT INTO authors (name, bio) VALUES ($1, $2) RETURNING id
	`, req.Name, req.Bio).Scan(&authorID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: "failed to create author"})
		return
	}

	author := Author{
		ID:   authorID,
		Name: req.Name,
		Bio:  req.Bio,
	}

	c.JSON(http.StatusCreated, author)
}

func main() {
	// Load configuration
	config := Config{
		DATABASE_URL: os.Getenv("DATABASE_URL"),
		REDIS_URL:    os.Getenv("REDIS_URL"),
		JWT_SECRET:   os.Getenv("JWT_SECRET"),
	}

	if config.DATABASE_URL == "" {
		log.Fatal("DATABASE_URL environment variable is required")
	}
	if config.REDIS_URL == "" {
		log.Fatal("REDIS_URL environment variable is required")
	}
	if config.JWT_SECRET == "" {
		log.Fatal("JWT_SECRET environment variable is required")
	}

	jwtSecret = []byte(config.JWT_SECRET)

	// Initialize database
	var err error
	db, err = initDB(config.DATABASE_URL)
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer db.Close()

	// Initialize Redis
	rdb, err = initRedis(config.REDIS_URL)
	if err != nil {
		log.Fatalf("Failed to initialize Redis: %v", err)
	}
	defer rdb.Close()

	// Setup Gin router
	r := gin.Default()

	// Health check (no auth)
	r.GET("/health", healthHandler)

	// Book routes (optional auth for some, admin for create)
	bookRoutes := r.Group("/books")
	bookRoutes.Use(requireAuth())
	{
		bookRoutes.GET("", listBooksHandler)
		bookRoutes.GET("/:id", getBookHandler)
		bookRoutes.POST("", requireAdmin(), createBookHandler)
	}

	// Author routes
	authorRoutes := r.Group("/authors")
	authorRoutes.Use(requireAuth())
	{
		authorRoutes.GET("", listAuthorsHandler)
		authorRoutes.GET("/:id", getAuthorHandler)
		authorRoutes.POST("", requireAdmin(), createAuthorHandler)
	}

	// Graceful shutdown
	port := os.Getenv("PORT")
	if port == "" {
		port = "8081"
	}

	log.Printf("Catalog starting on :%s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}