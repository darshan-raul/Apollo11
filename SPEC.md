# Apollo11 Library Management System - API Specification

## Overview
6 microservices for a library management system:
- **frontend** (Go, port 3000) - serves static HTML, calls other services
- **auth** (Python/FastAPI, port 8080) - PostgreSQL, JWT authentication
- **catalog** (Go, port 8081) - PostgreSQL + Redis, books/authors management
- **circulation** (Go, port 8082) - PostgreSQL, borrow/return/reserve
- **notification** (Go, port 8083) - Redis queue, email/SMS notifications
- **fines** (Go, port 8084) - SQLite, fine calculation

---

## Authentication Service (auth:8080)

### Database: PostgreSQL (db=auth, port=5432)

#### Tables

**users**
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PRIMARY KEY |
| email | VARCHAR(255) | UNIQUE NOT NULL |
| password_hash | VARCHAR(255) | NOT NULL |
| full_name | VARCHAR(255) | NOT NULL |
| role | VARCHAR(50) | NOT NULL DEFAULT 'patron' |
| created_at | TIMESTAMP | NOT NULL DEFAULT NOW() |
| updated_at | TIMESTAMP | NOT NULL DEFAULT NOW() |

### Endpoints

#### POST /register
Register a new user.
- **Auth**: None
- **Request Body**:
```json
{
  "email": "string",
  "password": "string",
  "full_name": "string"
}
```
- **Response 201**:
```json
{
  "id": "uuid",
  "email": "string",
  "full_name": "string",
  "role": "patron"
}
```
- **Errors**: 400 (validation), 409 (email exists)

#### POST /login
Authenticate and receive JWT token.
- **Auth**: None
- **Request Body**:
```json
{
  "email": "string",
  "password": "string"
}
```
- **Response 200**:
```json
{
  "access_token": "string",
  "token_type": "Bearer",
  "expires_in": 3600
}
```
- **Errors**: 401 (invalid credentials)

#### GET /me
Get current user info.
- **Auth**: Bearer token required
- **Response 200**:
```json
{
  "id": "uuid",
  "email": "string",
  "full_name": "string",
  "role": "string"
}
```
- **Errors**: 401 (unauthorized)

### JWT Claims Structure
```json
{
  "sub": "user_id (UUID)",
  "email": "string",
  "role": "string",
  "exp": "unix_timestamp",
  "iat": "unix_timestamp"
}
```
JWT secret stored in `JWT_SECRET` environment variable.

---

## Catalog Service (catalog:8081)

### Database: PostgreSQL (db=catalog, port=5433)

#### Tables

**authors**
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PRIMARY KEY |
| name | VARCHAR(255) | NOT NULL |
| bio | TEXT | |
| created_at | TIMESTAMP | DEFAULT NOW() |

**books**
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PRIMARY KEY |
| isbn | VARCHAR(20) | UNIQUE NOT NULL |
| title | VARCHAR(255) | NOT NULL |
| author_id | UUID | FOREIGN KEY -> authors(id) |
| genre | VARCHAR(100) | |
| copies_total | INTEGER | NOT NULL DEFAULT 1 |
| copies_available | INTEGER | NOT NULL DEFAULT 1 |
| created_at | TIMESTAMP | DEFAULT NOW() |

### Redis (port=6379)
- Key patterns for caching:
  - `catalog:book:{book_id}` - TTL 5min
  - `catalog:author:{author_id}` - TTL 5min
  - `catalog:search:{query_hash}` - TTL 1min

### Endpoints

#### GET /health
Health check.
- **Auth**: None
- **Response 200**: `{"status": "ok"}`

#### GET /books
List all books.
- **Auth**: Optional
- **Query Params**: `?search=`, `?genre=`, `?author_id=`, `?page=1`, `?limit=20`
- **Response 200**:
```json
{
  "books": [{"id": "uuid", "isbn": "string", "title": "string", "author": {}, "genre": "string", "copies_available": 1}],
  "total": 100,
  "page": 1,
  "limit": 20
}
```

#### GET /books/{id}
Get book by ID.
- **Auth**: Optional
- **Response 200**: `{"id": "uuid", "isbn": "string", "title": "string", "author": {}, "genre": "string", "copies_available": 1}`
- **Errors**: 404

#### POST /books
Create a book (admin only).
- **Auth**: Bearer token, role=admin
- **Request Body**:
```json
{
  "isbn": "string",
  "title": "string",
  "author_id": "uuid",
  "genre": "string",
  "copies_total": 1
}
```
- **Response 201**: Book object
- **Errors**: 400, 401, 403, 409 (isbn exists)

#### GET /authors
List authors.
- **Auth**: Optional
- **Query Params**: `?search=`, `?page=1`, `?limit=20`
- **Response 200**: Paginated author list

#### GET /authors/{id}
Get author by ID.
- **Auth**: Optional
- **Response 200**: Author object
- **Errors**: 404

#### POST /authors
Create author (admin only).
- **Auth**: Bearer token, role=admin
- **Request Body**:
```json
{
  "name": "string",
  "bio": "string"
}
```
- **Response 201**: Author object

---

## Circulation Service (circulation:8082)

### Database: PostgreSQL (db=circulation, port=5434)

#### Tables

**patrons**
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PRIMARY KEY |
| user_id | UUID | FOREIGN KEY -> auth.users(id), UNIQUE |
| card_number | VARCHAR(20) | UNIQUE NOT NULL |
| created_at | TIMESTAMP | DEFAULT NOW() |

**loans**
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PRIMARY KEY |
| patron_id | UUID | FOREIGN KEY -> patrons(id) |
| book_id | UUID | FOREIGN KEY -> catalog.books(id) |
| borrowed_at | TIMESTAMP | NOT NULL DEFAULT NOW() |
| due_date | TIMESTAMP | NOT NULL |
| returned_at | TIMESTAMP | |
| status | VARCHAR(20) | NOT NULL DEFAULT 'active' |

**reservations**
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PRIMARY KEY |
| patron_id | UUID | FOREIGN KEY -> patrons(id) |
| book_id | UUID | FOREIGN KEY -> catalog.books(id) |
| reserved_at | TIMESTAMP | DEFAULT NOW() |
| expires_at | TIMESTAMP | NOT NULL |
| status | VARCHAR(20) | DEFAULT 'active' |

### Endpoints

#### GET /health
Health check.
- **Auth**: None
- **Response 200**: `{"status": "ok"}`

#### POST /loans
Borrow a book.
- **Auth**: Bearer token required
- **Request Body**:
```json
{
  "book_id": "uuid"
}
```
- **Response 201**:
```json
{
  "id": "uuid",
  "book_id": "uuid",
  "borrowed_at": "timestamp",
  "due_date": "timestamp",
  "status": "active"
}
```
- **Errors**: 400, 401, 404 (book not found), 409 (no copies available)

#### POST /loans/{id}/return
Return a book.
- **Auth**: Bearer token required
- **Response 200**:
```json
{
  "id": "uuid",
  "returned_at": "timestamp",
  "status": "returned"
}
```
- **Errors**: 400, 401, 404

#### GET /loans
List current user's loans.
- **Auth**: Bearer token required
- **Query Params**: `?status=active|returned|all`
- **Response 200**: Array of loan objects

#### POST /reservations
Reserve a book.
- **Auth**: Bearer token required
- **Request Body**:
```json
{
  "book_id": "uuid"
}
```
- **Response 201**: Reservation object

#### GET /reservations
List current user's reservations.
- **Auth**: Bearer token required
- **Response 200**: Array of reservation objects

#### DELETE /reservations/{id}
Cancel reservation.
- **Auth**: Bearer token required
- **Response 204**

---

## Notification Service (notification:8083)

### Redis (port=6380)
- Queue key: `notifications:queue` (LIST)
- Notification format (JSON):
```json
{
  "id": "uuid",
  "type": "email|sms",
  "recipient": "string",
  "subject": "string",
  "body": "string",
  "created_at": "timestamp"
}
```

### Endpoints

#### GET /health
Health check.
- **Auth**: None
- **Response 200**: `{"status": "ok"}`

#### POST /notifications
Enqueue a notification (internal use).
- **Auth**: Bearer token, role=admin|system
- **Request Body**:
```json
{
  "type": "email|sms",
  "recipient": "string",
  "subject": "string",
  "body": "string"
}
```
- **Response 202**:
```json
{
  "id": "uuid",
  "queued": true
}
```

#### GET /notifications
Get queue depth (admin).
- **Auth**: Bearer token, role=admin
- **Response 200**:
```json
{
  "pending": 42
}
```

---

## Fines Service (fines:8084)

### Database: SQLite (/data/fines.db)

#### Tables

**fines**
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PRIMARY KEY |
| patron_id | UUID | NOT NULL |
| loan_id | UUID | NOT NULL |
| amount | DECIMAL(10,2) | NOT NULL |
| reason | VARCHAR(255) | NOT NULL |
| paid | BOOLEAN | DEFAULT FALSE |
| created_at | TIMESTAMP | DEFAULT NOW() |
| paid_at | TIMESTAMP | |

### Endpoints

#### GET /health
Health check.
- **Auth**: None
- **Response 200**: `{"status": "ok"}`

#### GET /fines
Get current user's fines.
- **Auth**: Bearer token required
- **Response 200**:
```json
{
  "fines": [
    {
      "id": "uuid",
      "loan_id": "uuid",
      "amount": 5.50,
      "reason": "Overdue by 3 days",
      "paid": false
    }
  ],
  "total_unpaid": 15.50
}
```

#### POST /fines/{id}/pay
Mark fine as paid.
- **Auth**: Bearer token required
- **Response 200**:
```json
{
  "id": "uuid",
  "paid": true,
  "paid_at": "timestamp"
}
```

---

## Frontend Service (frontend:3000)

### Endpoints

#### GET /
Serve index.html (library web UI).

#### GET /health
Health check.
- **Auth**: None
- **Response 200**: `{"status": "ok"}`

### Inter-service Calls
- `GET http://auth:8080/me` - Validate token, get user info
- `GET http://catalog:8081/books` - List books
- `POST http://circulation:8082/loans` - Borrow book
- `POST http://circulation:8082/loans/{id}/return` - Return book

---

## Inter-Service Communication

```yaml
frontend:
  calls:
    - auth (validate token)
    - catalog (browse books)
    - circulation (borrow/return)

auth:
  calls: None

catalog:
  calls: None (uses Redis for caching)

circulation:
  calls:
    - auth (verify patron exists)
    - catalog (check book availability)
    - notification (notify on reservation ready)
    - fines (create fine on overdue)

notification:
  calls: None (Redis queue only)

fines:
  calls: None

notification from circulation:
  - When reservation available
  - When book overdue
  - When fine issued
```

---

## Environment Variables

### auth
- `DATABASE_URL`: postgresql://user:pass@host:5432/auth
- `JWT_SECRET`: secret for signing JWTs
- `PORT`: 8080

### catalog
- `DATABASE_URL`: postgresql://user:pass@host:5433/catalog
- `REDIS_URL`: redis://host:6379
- `PORT`: 8081

### circulation
- `DATABASE_URL`: postgresql://user:pass@host:5434/circulation
- `AUTH_SERVICE_URL`: http://auth:8080
- `CATALOG_SERVICE_URL`: http://catalog:8081
- `NOTIFICATION_SERVICE_URL`: http://notification:8083
- `FINES_SERVICE_URL`: http://fines:8084
- `PORT`: 8082

### notification
- `REDIS_URL`: redis://host:6380
- `PORT`: 8083

### fines
- `DATABASE_PATH`: /data/fines.db
- `PORT`: 8084

### frontend
- `PORT`: 3000