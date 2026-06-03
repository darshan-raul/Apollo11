-- Circulation Service: PostgreSQL init script
-- Runs automatically on first startup via docker-entrypoint-initdb.d

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Patrons are derived from auth.users but stored here for library-specific data
CREATE TABLE IF NOT EXISTS patrons (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL UNIQUE,  -- references auth.users(id)
    card_number VARCHAR(20) UNIQUE NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS loans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patron_id UUID NOT NULL REFERENCES patrons(id) ON DELETE CASCADE,
    book_id UUID NOT NULL,  -- book ID from catalog service
    borrowed_at TIMESTAMP NOT NULL DEFAULT NOW(),
    due_date TIMESTAMP NOT NULL,
    returned_at TIMESTAMP,
    status VARCHAR(20) NOT NULL DEFAULT 'active'
);

CREATE TABLE IF NOT EXISTS reservations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patron_id UUID NOT NULL REFERENCES patrons(id) ON DELETE CASCADE,
    book_id UUID NOT NULL,
    reserved_at TIMESTAMP NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMP NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'active'
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_loans_patron_id ON loans(patron_id);
CREATE INDEX IF NOT EXISTS idx_loans_book_id ON loans(book_id);
CREATE INDEX IF NOT EXISTS idx_loans_status ON loans(status);
CREATE INDEX IF NOT EXISTS idx_reservations_patron_id ON reservations(patron_id);
CREATE INDEX IF NOT EXISTS idx_reservations_book_id ON reservations(book_id);
CREATE INDEX IF NOT EXISTS idx_reservations_status ON reservations(status);