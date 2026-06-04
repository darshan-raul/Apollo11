# Apollo Airlines — Application Specification v1.1

## Purpose

A cloud-native airline reservation platform designed specifically for teaching:

- Docker
- Kubernetes (networking, storage, security, scheduling)
- Observability (Prometheus, Grafana, Jaeger/Tempo)
- OpenTelemetry
- Service Mesh (Istio / Linkerd)
- GitOps (ArgoCD / Flux)
- Multi-Cluster Operations (EKS / GKE / AKS)

The application is simple enough for beginners at Stage 1 but complex enough to demonstrate real-world cloud-native operational challenges by Stage 11.

---

## Changelog from v1.0

| Area | Change | Reason |
|---|---|---|
| Flight Service | Added internal seat management API | Booking Service must not write directly to Flight DB |
| Booking Service | Clarified JWT validation is local | Calling Identity per request is architecturally wrong; breaks tracing |
| Search Service | Added response contract + Redis evolution path | Load test and canary stages need a stable target interface |
| Notification Service | Expanded event enum + clarified async path | Kafka stage must feel earned, not bolted on |
| All Services | Added cross-cutting standards section | Health probes, metrics, and logging must exist from Stage 1 |
| New | Added seed data specification | Learners need working data from the first `docker compose up` |

---

## Service Inventory

| Service | Role | Stateful | Database |
|---|---|---|---|
| Identity | Auth + passenger management | Yes | PostgreSQL |
| Flight | Flight inventory + seat management | Yes | PostgreSQL |
| Booking | Reservations (flagship service) | Yes | PostgreSQL |
| Search | Optimised flight search | No | None (Redis in later stages) |
| Notification | Event fan-out | No | None |
| Frontend | React SPA | No | None |

---

## Cross-Cutting Standards

Every service must implement the following from Stage 1 onward. These are not added later — they exist in the codebase from the beginning. K8s stages configure them, not create them.

### Health Endpoints

```http
GET /healthz
```

Liveness probe. Returns `200 OK` if the process is alive.

```http
GET /readyz
```

Readiness probe. Returns `200 OK` only when all dependencies (DB connections, downstream service reachability) are healthy. Returns `503` otherwise.

---

### Metrics Endpoint

```http
GET /metrics
```

Prometheus-compatible metrics. Exposed on every service from day one.

Minimum required metrics:

```text
http_requests_total          (counter)
http_request_duration_ms     (histogram)
db_connections_active        (gauge, stateful services only)
```

---

### Logging Standard

All services emit structured JSON logs.

```json
{
  "timestamp": "2025-01-15T10:23:00Z",
  "level": "INFO",
  "service": "booking-service",
  "trace_id": "abc123",
  "span_id": "def456",
  "message": "Booking created",
  "booking_reference": "AA-2025-XK9"
}
```

`trace_id` and `span_id` are present from Stage 1. They will carry no value until OpenTelemetry is wired in at Stage 8, but the field must exist so that no code changes are required at that stage.

---

### Request ID Propagation

Every inbound HTTP request must be assigned a `X-Request-ID` header if one is not already present. This header is forwarded to all downstream calls.

---

## Identity Service

### Purpose

Unified authentication and passenger management. The single source of truth for all user identity, credentials, and profile data.

No other service owns or stores user data.

### Database

PostgreSQL

---

### Tables

#### users

```sql
CREATE TABLE users (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email            VARCHAR(255) UNIQUE NOT NULL,
    password_hash    VARCHAR(255) NOT NULL,
    first_name       VARCHAR(100),
    last_name        VARCHAR(100),
    passport_number  VARCHAR(50),
    loyalty_tier     VARCHAR(20) DEFAULT 'STANDARD',
    role             VARCHAR(20) DEFAULT 'PASSENGER',
    is_active        BOOLEAN DEFAULT TRUE,
    created_at       TIMESTAMP DEFAULT NOW(),
    updated_at       TIMESTAMP DEFAULT NOW()
);
```

---

### Roles

```text
PASSENGER    — default role, can search and book flights
ADMIN        — can create and update flights, view all bookings
```

### Loyalty Tiers

```text
STANDARD
SILVER
GOLD
PLATINUM
```

Tier is set manually by admin for now. No automatic upgrade logic. Exists to make the user profile feel real and to give OTEL traces meaningful attributes.

---

### JWT Specification

```text
Algorithm:  HS256
Expiry:     24 hours
Claims:
  sub       — user UUID
  email     — user email
  role      — PASSENGER | ADMIN
  tier      — loyalty tier
  iat       — issued at
  exp       — expiry
```

The JWT signing secret is an environment variable: `JWT_SECRET`.

All other services validate the JWT **locally** by verifying the signature using `JWT_SECRET`. They do not call Identity Service for JWT validation.

---

### APIs

#### Register

```http
POST /api/users/register
```

Request

```json
{
  "email": "john@example.com",
  "password": "secret123",
  "firstName": "John",
  "lastName": "Doe",
  "passportNumber": "AB123456"
}
```

Response `201`

```json
{
  "id": "uuid",
  "email": "john@example.com",
  "firstName": "John",
  "lastName": "Doe",
  "loyaltyTier": "STANDARD",
  "role": "PASSENGER"
}
```

---

#### Login

```http
POST /api/users/login
```

Request

```json
{
  "email": "john@example.com",
  "password": "secret123"
}
```

Response `200`

```json
{
  "token": "jwt-token",
  "expiresAt": "2025-01-16T10:00:00Z"
}
```

---

#### Get Profile

```http
GET /api/users/me
Authorization: Bearer <token>
```

Response `200`

```json
{
  "id": "uuid",
  "email": "john@example.com",
  "firstName": "John",
  "lastName": "Doe",
  "passportNumber": "AB123456",
  "loyaltyTier": "STANDARD",
  "role": "PASSENGER"
}
```

---

#### Update Profile

```http
PUT /api/users/me
Authorization: Bearer <token>
```

Request (all fields optional)

```json
{
  "firstName": "Johnny",
  "lastName": "Doe",
  "passportNumber": "AB999999"
}
```

---

#### Get User by ID (Internal)

```http
GET /api/users/{id}
Authorization: Bearer <token>
```

Used by Booking Service to confirm a user account is active before creating a booking. Returns `404` if not found, `403` if `is_active = false`.

Admin role required, or the token subject must match the requested `id`.

---

## Flight Service

### Purpose

Owns and manages all flight inventory. The single source of truth for flight schedules, routes, and seat availability.

Seat availability is updated exclusively through Flight Service APIs. No other service writes to the flights table directly.

### Database

PostgreSQL

---

### Tables

#### airports

```sql
CREATE TABLE airports (
    id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code     VARCHAR(5) UNIQUE NOT NULL,
    name     VARCHAR(100),
    city     VARCHAR(100),
    country  VARCHAR(100)
);
```

#### flights

```sql
CREATE TABLE flights (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    flight_number    VARCHAR(20) UNIQUE NOT NULL,
    origin           VARCHAR(5) REFERENCES airports(code),
    destination      VARCHAR(5) REFERENCES airports(code),
    departure_time   TIMESTAMP NOT NULL,
    arrival_time     TIMESTAMP NOT NULL,
    total_capacity   INT NOT NULL,
    available_seats  INT NOT NULL,
    status           VARCHAR(20) DEFAULT 'SCHEDULED',
    created_at       TIMESTAMP DEFAULT NOW(),
    updated_at       TIMESTAMP DEFAULT NOW()
);
```

---

### Flight Status

```text
SCHEDULED   — default state
BOARDING    — gate open, boarding in progress
DELAYED     — departure pushed
DEPARTED    — aircraft airborne
ARRIVED     — flight completed
CANCELLED   — flight will not operate
```

Status is updated by admin via `PUT /api/flights/{id}`.

---

### APIs

#### Search Flights

```http
GET /api/flights
```

Query parameters

```text
origin        — IATA airport code (required)
destination   — IATA airport code (required)
date          — YYYY-MM-DD (required)
```

Response `200`

```json
{
  "flights": [
    {
      "id": "uuid",
      "flightNumber": "AA101",
      "origin": "BOM",
      "destination": "SIN",
      "departureTime": "2025-06-01T08:00:00Z",
      "arrivalTime": "2025-06-01T14:30:00Z",
      "availableSeats": 42,
      "status": "SCHEDULED"
    }
  ]
}
```

---

#### Get Flight

```http
GET /api/flights/{id}
```

Returns single flight object.

---

#### Create Flight (Admin)

```http
POST /api/flights
Authorization: Bearer <token>  (role: ADMIN)
```

Request

```json
{
  "flightNumber": "AA101",
  "origin": "BOM",
  "destination": "SIN",
  "departureTime": "2025-06-01T08:00:00Z",
  "arrivalTime": "2025-06-01T14:30:00Z",
  "totalCapacity": 180
}
```

`available_seats` is set to `totalCapacity` on creation.

---

#### Update Flight (Admin)

```http
PUT /api/flights/{id}
Authorization: Bearer <token>  (role: ADMIN)
```

Can update: `status`, `departureTime`, `arrivalTime`. Cannot directly update `available_seats` via this endpoint.

---

#### Update Seat Availability (Internal)

```http
PATCH /api/flights/{id}/seats
Authorization: Bearer <token>  (role: ADMIN or service-to-service)
```

Request

```json
{
  "delta": -1
}
```

`delta` is `-1` when a booking is confirmed (consume a seat), `+1` when a booking is cancelled (restore a seat).

Returns `409 Conflict` if `delta = -1` and `available_seats = 0`.

This is the only way seat availability changes. Booking Service calls this endpoint — it does not write to the flights table.

---

## Booking Service

### Purpose

Manages flight reservations. The most operationally complex service in the platform and the primary vehicle for teaching distributed systems concepts.

Booking Service is the flagship service for:

- OpenTelemetry distributed tracing
- Service mesh traffic management
- Load testing
- Chaos/fault injection

### Database

PostgreSQL

---

### Tables

#### bookings

```sql
CREATE TABLE bookings (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_reference VARCHAR(20) UNIQUE NOT NULL,
    user_id           UUID NOT NULL,
    flight_id         UUID NOT NULL,
    seat_number       VARCHAR(10),
    status            VARCHAR(20) DEFAULT 'CONFIRMED',
    created_at        TIMESTAMP DEFAULT NOW(),
    updated_at        TIMESTAMP DEFAULT NOW()
);
```

`booking_reference` format: `AA-{YEAR}-{6 random alphanumeric uppercase}`. Example: `AA-2025-XK9P2M`.

---

### Booking Status

```text
CONFIRMED    — booking is active
CANCELLED    — booking cancelled by passenger or admin
```

---

### Dependencies and Call Model

```text
Identity Service   — verify user account is active (HTTP GET)
Flight Service     — check seat availability + update seats (HTTP GET + PATCH)
Notification Svc   — fire booking event (HTTP POST, synchronous in early stages)
```

**JWT validation is always local** — Booking Service verifies the token signature using the shared `JWT_SECRET`. It never calls Identity Service to validate a token. The call to Identity Service is only to confirm `is_active = true` on the user account.

---

### APIs

#### Create Booking

```http
POST /api/bookings
Authorization: Bearer <token>
```

Request

```json
{
  "flightId": "uuid"
}
```

Response `201`

```json
{
  "id": "uuid",
  "bookingReference": "AA-2025-XK9P2M",
  "flightId": "uuid",
  "userId": "uuid",
  "status": "CONFIRMED",
  "createdAt": "2025-01-15T10:23:00Z"
}
```

---

##### Create Booking — Execution Steps

This is the trace that students will see in Jaeger/Tempo at Stage 8.

```text
1. Validate JWT locally (verify signature, check expiry)
2. Extract user_id from JWT claims
3. Call Identity Service: GET /api/users/{user_id}
   → Abort with 403 if user not found or is_active = false
4. Call Flight Service: GET /api/flights/{flightId}
   → Abort with 404 if flight not found
   → Abort with 422 if flight status is CANCELLED or DEPARTED
5. Call Flight Service: PATCH /api/flights/{flightId}/seats { "delta": -1 }
   → Abort with 409 if no seats available
6. Generate booking_reference
7. Write booking record to Booking DB
8. Call Notification Service: POST /api/notify
9. Return 201 with booking object
```

Each step is a distinct span in the OTEL trace. Steps 3, 5, and 8 cross service boundaries and produce child spans in the downstream service.

---

#### Get Booking

```http
GET /api/bookings/{id}
Authorization: Bearer <token>
```

Passengers can only retrieve their own bookings. Admins can retrieve any booking.

---

#### My Bookings

```http
GET /api/bookings
Authorization: Bearer <token>
```

Returns all bookings for the authenticated user ordered by `created_at DESC`.

---

#### Cancel Booking

```http
DELETE /api/bookings/{id}
Authorization: Bearer <token>
```

##### Cancel Booking — Execution Steps

```text
1. Validate JWT locally
2. Fetch booking — abort 404 if not found
3. Verify booking belongs to token subject — abort 403 if not
4. Verify booking status is CONFIRMED — abort 422 if already CANCELLED
5. Update booking status to CANCELLED in Booking DB
6. Call Flight Service: PATCH /api/flights/{flightId}/seats { "delta": +1 }
7. Call Notification Service: POST /api/notify (BOOKING_CANCELLED)
8. Return 200
```

---

### Future: Async Notification (Stage 9+)

At Stage 9, Steps 8 (Create) and 7 (Cancel) are replaced:

```text
Booking Service  →  Kafka topic: booking.events  →  Notification Service
```

The Booking Service publishes an event and returns immediately. Notification Service becomes a Kafka consumer. No API contract changes in either service.

---

## Search Service

### Purpose

Provides an optimised, cacheable flight search endpoint that is intentionally decoupled from Flight Service.

Stateless. No database.

### Why It Is a Separate Service

Search Service is the primary teaching target for:

```text
Horizontal Pod Autoscaler (HPA)
Canary deployments
Load testing (k6 / Locust)
Service mesh traffic splitting
Response caching (Redis — Stage 7+)
```

These demonstrations would pollute Flight Service if combined. The separation is intentional and justified by real-world practice: high-traffic read paths are routinely extracted from transactional services.

---

### Dependencies

```text
Flight Service   — HTTP GET (read only)
Redis            — optional cache (Stage 7+)
```

---

### APIs

#### Search

```http
GET /api/search
```

Query parameters

```text
origin        — IATA code (required)
destination   — IATA code (required)
date          — YYYY-MM-DD (required)
sort          — price | duration | departure  (optional, default: departure)
page          — integer (optional, default: 1)
limit         — integer (optional, default: 20, max: 100)
```

Response `200`

```json
{
  "results": [
    {
      "id": "uuid",
      "flightNumber": "AA101",
      "origin": "BOM",
      "destination": "SIN",
      "departureTime": "2025-06-01T08:00:00Z",
      "arrivalTime": "2025-06-01T14:30:00Z",
      "duration": 390,
      "availableSeats": 42,
      "status": "SCHEDULED"
    }
  ],
  "total": 3,
  "page": 1,
  "limit": 20
}
```

`duration` is in minutes. Calculated by Search Service from departure and arrival times.

---

### Caching Behaviour (Stage 7+)

```text
Cache key:    search:{origin}:{destination}:{date}
TTL:          5 minutes
Cache miss:   call Flight Service, populate cache, return result
Cache hit:    return cached result (add X-Cache: HIT header)
```

This makes cache behaviour observable in load test results and service mesh dashboards.

---

## Notification Service

### Purpose

Receives booking and flight events and dispatches notifications. Currently logs only.

Stateless. No database.

---

### Event Types

```text
BOOKING_CONFIRMED    — passenger booked a flight
BOOKING_CANCELLED    — passenger cancelled a booking
FLIGHT_DELAYED       — flight departure pushed (admin triggered)
FLIGHT_CANCELLED     — flight cancelled (admin triggered)
FLIGHT_BOARDING      — flight now boarding (admin triggered)
```

FLIGHT_* events are for future use. Booking Service uses only `BOOKING_CONFIRMED` and `BOOKING_CANCELLED` today.

---

### APIs

#### Notify

```http
POST /api/notify
```

Request

```json
{
  "type": "BOOKING_CONFIRMED",
  "recipient": "john@example.com",
  "payload": {
    "bookingReference": "AA-2025-XK9P2M",
    "flightNumber": "AA101",
    "origin": "BOM",
    "destination": "SIN",
    "departureTime": "2025-06-01T08:00:00Z"
  }
}
```

Response `202 Accepted`

---

### Current Behaviour

```text
Log the event as structured JSON
Return 202
```

No email is sent. No external system is called.

---

### Stage 9+ Evolution

Notification Service becomes a Kafka consumer on topic `booking.events`.

The `/api/notify` HTTP endpoint is retained for backward compatibility and direct testing but is no longer the primary path.

No changes to the event schema. No changes to Booking Service's publish contract. The internal dispatch changes; the interface does not.

---

## Frontend

Technology: React

Keep intentionally simple. The frontend is not the subject of the course. It must be functional enough that learners feel they are working with a real application.

---

### Pages

| Route | Purpose |
|---|---|
| `/login` | Email + password login |
| `/register` | New user registration |
| `/dashboard` | Authenticated landing page, upcoming bookings summary |
| `/search` | Flight search form + results |
| `/flights/{id}` | Flight details + Book button |
| `/bookings` | My bookings list |
| `/bookings/{id}` | Single booking detail + Cancel button |

---

## Primary Workflows

### Workflow 1 — Register

```text
Frontend → Identity Service → Identity DB
```

---

### Workflow 2 — Login

```text
Frontend → Identity Service → Identity DB → JWT returned
```

---

### Workflow 3 — Search Flights

```text
Frontend → Search Service → Flight Service → Flight DB
```

In Stage 7+, Search Service checks Redis before calling Flight Service.

---

### Workflow 4 — View Flight

```text
Frontend → Flight Service → Flight DB
```

---

### Workflow 5 — Create Booking (Flagship Workflow)

```text
Frontend
    │
    ▼
Booking Service ──► Identity Service  (is user active?)
    │
    ├──────────────► Flight Service   (get flight details)
    │
    ├──────────────► Flight Service   (decrement seats)
    │
    ├──────────────► Booking DB       (write booking)
    │
    └──────────────► Notification Svc (BOOKING_CONFIRMED)
```

This workflow generates the distributed trace that students observe in Jaeger/Tempo at Stage 8. Every arrow is a span. Every service boundary is a new span parent.

---

### Workflow 6 — Cancel Booking

```text
Frontend
    │
    ▼
Booking Service ──► Booking DB       (mark CANCELLED)
    │
    ├──────────────► Flight Service   (restore seat)
    │
    └──────────────► Notification Svc (BOOKING_CANCELLED)
```

---

## Seed Data

The following data must be present after a fresh `docker compose up`. Learners should not have to create flights or airports manually at any stage.

### Airports

| Code | Name | City | Country |
|---|---|---|---|
| BOM | Chhatrapati Shivaji Maharaj International | Mumbai | India |
| DEL | Indira Gandhi International | New Delhi | India |
| SIN | Changi Airport | Singapore | Singapore |
| DXB | Dubai International | Dubai | UAE |
| LHR | Heathrow Airport | London | UK |
| JFK | John F. Kennedy International | New York | USA |

---

### Flights (sample — scheduled from today + 30 days)

| Flight | Route | Departure | Seats |
|---|---|---|---|
| AA101 | BOM → SIN | 08:00 | 180 |
| AA102 | SIN → BOM | 20:00 | 180 |
| AA201 | DEL → DXB | 09:30 | 220 |
| AA202 | DXB → DEL | 22:00 | 220 |
| AA301 | BOM → LHR | 01:00 | 300 |
| AA401 | DEL → JFK | 02:00 | 280 |

Seed script must use deterministic UUIDs so that foreign keys are stable across resets.

---

### Users

| Email | Password | Role |
|---|---|---|
| `admin@apolloairlines.com` | `admin123` | ADMIN |
| `passenger@apolloairlines.com` | `pass123` | PASSENGER |

Passwords are stored as bcrypt hashes in the seed. Plain text values are only in this spec for learner reference.

---

## Observability Design

The trace students will observe at Stage 8 for a Create Booking request:

```text
Booking Service (root span)
    │
    ├── Identity Service: GET /api/users/{id}
    │
    ├── Flight Service: GET /api/flights/{id}
    │
    ├── Flight Service: PATCH /api/flights/{id}/seats
    │
    ├── Booking DB: INSERT bookings
    │
    └── Notification Service: POST /api/notify
```

Total spans for a successful booking: 6 spans across 3 services + 1 DB span.

This single trace demonstrates:

- Cross-service context propagation
- Database query timing
- Downstream dependency latency
- Failure points for fault injection (Stage 10)

---

## Stage-to-Feature Mapping

| Stage | Primary Feature | Service(s) Involved |
|---|---|---|
| 1 | Docker Compose | All |
| 2 | Kubernetes basics (Pods, Deployments) | All |
| 3 | Services + Ingress + DNS | All |
| 4 | ConfigMaps + Secrets + Env | Identity, Booking |
| 5 | Persistent Volumes + StatefulSets | Identity DB, Flight DB, Booking DB |
| 6 | Health Probes + Resource Limits | All |
| 7 | HPA + Redis Cache | Search Service |
| 8 | OpenTelemetry + Jaeger | Booking → Identity → Flight → Notification |
| 9 | Kafka + Async Messaging | Booking → Notification |
| 10 | Service Mesh + Fault Injection | All |
| 11 | GitOps + Multi-cluster | All |
