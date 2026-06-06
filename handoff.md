# Apollo11 - Handoff Notes (Session: 2026-06-06)

## Goal
Fix broken Go services (flight, booking) in launchpad — admin portal couldn't reach them. All 10 services should be up and responding.

---

## What Was Done

###1. Backend Admin Endpoints

#### Identity Service (`stages/launchpad/code/identity/main.py`)
- **Added `GET /api/admin/users`** (lines ~310-334)
  - Protected by `verify_jwt` + ADMIN role check
  - Returns all users with: id, email, firstName, lastName, loyaltyTier, role, isActive, createdAt
  - Uses `RealDictCursor` for dict-style row access
  - **Status: WORKING**

#### Booking Service (`stages/launchpad/code/booking/main.go`)
- **Added `GET /api/admin/bookings`**
  - Protected by `adminRequired()` middleware
  - Returns all bookings with user email (calls identity `/api/admin/users` to build userMap)
  - Returns: id, bookingReference, flightId, userId, userEmail, seatNumber, status, createdAt
  - **Status: WORKING**

#### Flight Service (`stages/launchpad/code/flight/main.go`)
- **Status: WORKING**

---

### 2. Frontend Admin Panel

#### New Components
- **`src/components/ProtectedRoute.jsx`** - Wraps protected routes, redirects to `/dashboard` if role doesn't match `requiredRole`
- **`src/components/AdminStatCard.jsx`** - Stat card with icon, iconBg, iconColor, label, value (supports AnimatedNumber), delay for staggered animation

#### New Admin Pages (`src/pages/admin/`)
- **`AdminDashboard.jsx`** - Stats grid (flights/users/bookings count via parallel axios calls), quick action cards (Manage Flights, All Bookings), recent bookings table
- **`AdminFlights.jsx`** - Table of all flights with flight number, route, departure, arrival, capacity, available seats, status, edit/delete buttons, "+ New Flight" button
- **`AdminFlightForm.jsx`** - Create/edit flight form (flightNumber, origin, destination, departureTime, arrivalTime, totalCapacity, status for edit). Fetches existing flight via `GET /api/flights/:id` when editing
- **`AdminBookings.jsx`** - Table of all bookings with reference, user email, flight ID, seat, status, date, cancel action

#### App.jsx Changes
- Added imports for AdminDashboard, AdminFlights, AdminFlightForm, AdminBookings, ProtectedRoute
- Added `decodeJWT()` helper to parse JWT token and extract user info (id, email, role, tier)
- Changed `token` state to `user` state (stores decoded JWT payload)
- Navbar now receives `user` prop instead of `token`
- Admin nav item visible when `user.role === 'ADMIN'` (both desktop and mobile menus)
- All protected routes wrapped with `ProtectedRoute user={user}`
- New routes:
  - `/admin` → AdminDashboard
  - `/admin/flights` → AdminFlights
  - `/admin/flights/new` → AdminFlightForm
  - `/admin/flights/:id` → AdminFlightForm
  - `/admin/bookings` → AdminBookings

---

### 3. Infrastructure Fixes

#### Flight Service `init.sql` UUIDs Fixed
- `AA102` had invalid UUID `aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaabbb` (35 chars) → `aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaabb` (36 chars)
- `AA201` had invalid UUID `bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb` (35 chars) → `bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb` (36 chars)
- `AA301` had invalid UUID `cccccccc-cccc-cccc-cccc-cccccccccc` (34 chars) → `cccccccc-cccc-cccc-cccc-cccccccccccc` (36 chars)

#### `init.sql` Mount Locations Fixed (docker-compose.yml)
The `init.sql` files were incorrectly mounted on the **app services** (Python/Go) instead of the **database services** (PostgreSQL). PostgreSQL only runs init scripts on first boot when mounted on the database container.
- Removed `init.sql` volume mounts from `flight` and `booking` app services
- Added `init.sql` volume mounts to `flight-db` and `booking-db` services

#### Identity Service init.sql Email Fixed
- Admin user email was `'  '` (whitespace) → `admin@apolloairlines.com`
- Rebuilt identity-db volume to re-run init scripts

---

### 4. Critical Bug Fixes (Session 2026-06-06 Afternoon)

#### Bug1: Go Services Completely Silent — `initDB()` Infinite Retry Loop
**Symptom:** Flight (8081) and booking (8082) services not responding — `curl localhost:8081/healthz` returned empty reply. No error logs.

**Root Cause:** `initDB()` had an infinite retry loop:
```go
for {
    err = db.Ping()
    if err == nil { break }
    time.Sleep(1 * time.Second)
}
```
If the DB wasn't ready on first attempt, the loop blocked **forever** — the HTTP server never started, and no logs were written because logging wasn't initialized before `initDB()` ran.

**Fix:** Replaced with `context.WithTimeout(15s)` + `db.PingContext(ctx)` + error logging:
```go
ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
defer cancel()
for {
    err = db.PingContext(ctx)
    if err == nil { break }
    logJSON("ERROR", ..., fmt.Sprintf("DB not ready (will retry): %v", err), ...)
    select {
    case <-ctx.Done():
        logJSON("ERROR", ..., fmt.Sprintf("DB connection timeout: %v", ctx.Err()), ...)
        return
    case <-time.After(2 * time.Second):
    }
}
```

**Files:** `flight/main.go`, `booking/main.go`

---

#### Bug 2: PostgreSQL SSL Mode Error — `pq: SSL is not enabled on the server`
**Symptom:** Services started and logged routes correctly, but `GET /api/flights` returned `500` with error `pq: SSL is not enabled on the server`.

**Root Cause:** Go's `lib/pq` driver defaults to `sslmode=require`. PostgreSQL containers don't have SSL configured, so the driver tried TLS handshake and failed on every query.

**Fix:** Added `addSSLMode()` helper that appends `?sslmode=disable` if no `sslmode=` is present in the DSN:
```go
func addSSLMode(dsn string) string {
    if strings.Contains(dsn, "sslmode=") {
        return dsn
    }
    return dsn + "?sslmode=disable"
}
```
Called as `sql.Open("postgres", addSSLMode(dbURL))`.

**Files:** `flight/main.go`, `booking/main.go`

---

#### Bug 3: CORS Missing on Go Services
**Symptom:** Browser admin portal making cross-origin requests to flight/booking services — CORS preflight (OPTIONS) failed.

**Root Cause:** Only the Python `identity` service had CORS middleware. All4 Go services (flight, booking, search, notification) had none.

**Fix:** Added CORS middleware to all4 Go services:
```go
func corsMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        c.Header("Access-Control-Allow-Origin", "*")
        c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
        c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Authorization, X-Request-ID")
        c.Header("Access-Control-Expose-Headers", "X-Request-ID")
        if c.Request.Method == "OPTIONS" {
            c.AbortWithStatus(204)
            return
        }
        c.Next()
    }
}
```
Registered as `r.Use(corsMiddleware())` before the routes.

**Files:** `flight/main.go`, `booking/main.go`, `search/main.go`, `notification/main.go`

---

#### Bug 4: Booking Service — `sql.NullString` Crash on Nullable `seat_number`
**Symptom:** `GET /api/bookings` and `GET /api/admin/bookings` returned `500` when scanning rows with nullable `seat_number` into a `string` field.

**Root Cause:** 3 query handlers scanned `seat_number` (nullable VARCHAR) directly into a `string` variable. PostgreSQL NULL can't scan into a Go `string`.

**Fix:** Replaced direct `&bk.SeatNumber` scan with `sql.NullString`:
```go
var seatNumber sql.NullString
err := row.Scan(..., &seatNumber, ...)
if seatNumber.Valid {
    bk.SeatNumber = seatNumber.String
}
```

**Files:** `booking/main.go` (3 handlers: user bookings, admin bookings, single booking fetch)

---

#### Bug 5: Booking Service — Missing `UserEmail` Field
**Symptom:** Admin bookings endpoint couldn't populate `userEmail` because the `Booking` struct lacked the field.

**Fix:** Added `UserEmail string` field to `Booking` struct.

**Files:** `booking/main.go`

---

### 5. Frontend Multi-Stage Dockerfile Fix (All 11 Stages)
Previously fixed heredoc nginx config issue in all stage Dockerfiles (replaced broken `cat << EOF` heredoc with single-line echo).

---

## Files Modified

| File | Change |
|------|--------|
| `stages/launchpad/code/identity/main.py` | Added `GET /api/admin/users` endpoint |
| `stages/launchpad/code/identity/init.sql` | Fixed admin email (whitespace → `admin@apolloairlines.com`) |
| `stages/launchpad/code/booking/main.go` | Added `GET /api/admin/bookings` + `adminRequired()` middleware; added `addSSLMode()`; fixed `initDB()` timeout; fixed3x `sql.NullString` scans; added `UserEmail` field |
| `stages/launchpad/code/flight/main.go` | Added `addSSLMode()`; fixed `initDB()` timeout with `context.WithTimeout`; added CORS middleware |
| `stages/launchpad/code/flight/init.sql` | Fixed invalid UUIDs for AA102, AA201, AA301 |
| `stages/launchpad/code/search/main.go` | Added CORS middleware |
| `stages/launchpad/code/notification/main.go` | Added CORS middleware |
| `stages/launchpad/docker-compose.yml` | Fixed init.sql mount locations (moved from app services to db services) |
| `stages/launchpad/code/frontend/src/App.jsx` | Admin nav, protected routes, JWT decode |
| `stages/launchpad/code/frontend/src/components/ProtectedRoute.jsx` | New file |
| `stages/launchpad/code/frontend/src/components/AdminStatCard.jsx` | New file |
| `stages/launchpad/code/frontend/src/pages/admin/AdminDashboard.jsx` | New file |
| `stages/launchpad/code/frontend/src/pages/admin/AdminFlights.jsx` | New file |
| `stages/launchpad/code/frontend/src/pages/admin/AdminFlightForm.jsx` | New file |
| `stages/launchpad/code/frontend/src/pages/admin/AdminBookings.jsx` | New file |

---

## Admin Credentials
- **Email:** admin@apolloairlines.com
- **Password:** admin123
- **Role:** ADMIN
- **Loyalty Tier:** PLATINUM

## Passenger Credentials
- **Email:** passenger@apolloairlines.com
- **Password:** pass123
- **Role:** PASSENGER
- **Loyalty Tier:** STANDARD

---

## API Endpoints Reference

### Identity Service (Port 8080)
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/api/users/login` | No | Login, returns JWT |
| POST | `/api/users/register` | No | Register new user |
| GET | `/api/users/me` | Bearer | Get current user |
| GET | `/api/admin/users` | Bearer (ADMIN) | Get all users |

### Flight Service (Port 8081)
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/api/flights` | No | List flights |
| GET | `/api/flights/:id` | No | Get flight |
| POST | `/api/flights` | Bearer (ADMIN) | Create flight |
| PUT | `/api/flights/:id` | Bearer (ADMIN) | Update flight |
| PATCH | `/api/flights/:id/seats` | Bearer | Update seats |

### Booking Service (Port 8082)
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/api/bookings` | Bearer | List my bookings |
| POST | `/api/bookings` | Bearer | Create booking |
| DELETE | `/api/bookings/:id` | Bearer | Cancel booking |
| GET | `/api/admin/bookings` | Bearer (ADMIN) | List all bookings |

### Search Service (Port 8083)
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/api/search` | No | Search flights |

### Notification Service (Port 8084)
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/api/notify` | No | Send notification |

---

## Docker Compose Services Status

```
launchpad-frontend-1       WORKING  (port 3000)
launchpad-identity-1       WORKING  (port 8080)
launchpad-identity-db-1    HEALTHY
launchpad-flight-1         WORKING  (port 8081) ✅ FIXED
launchpad-flight-db-1      HEALTHY
launchpad-booking-1        WORKING  (port 8082) ✅ FIXED
launchpad-booking-db-1     HEALTHY
launchpad-search-1         WORKING  (port 8083) ✅ FIXED
launchpad-notification-1   WORKING  (port 8084) ✅ FIXED
launchpad-redis-1          HEALTHY
launchpad-dozzle-1         WORKING  (port 8085)
```

---

## Key Lessons Learned

1. **`initDB()` must have a timeout** — infinite retry loops that block the HTTP server startup are a silent killer. Always wrap with `context.WithTimeout`.

2. **Go `lib/pq` defaults to SSL** — always append `?sslmode=disable` for local development. PostgreSQL containers in dev typically don't have SSL configured.

3. **CORS is not automatic** — even if one service (Python/FastAPI) has it, Go services need their own CORS middleware.

4. **PostgreSQL NULL vs Go `string`** — nullable columns must use `sql.NullString` (or `*string` with manual NULL checking). Direct scan into `string` panics.

5. **Docker layer ENV corruption** — when debugging why env vars appear correct in `docker inspect` but the running process uses different values, rebuild images from scratch (`--no-cache`).
