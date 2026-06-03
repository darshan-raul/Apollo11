-- Catalog Service: PostgreSQL init script
-- Runs automatically on first startup via docker-entrypoint-initdb.d

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS authors (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    bio TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS books (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    isbn VARCHAR(20) UNIQUE NOT NULL,
    title VARCHAR(255) NOT NULL,
    author_id UUID REFERENCES authors(id) ON DELETE SET NULL,
    genre VARCHAR(100),
    copies_total INTEGER NOT NULL DEFAULT 1,
    copies_available INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_books_author_id ON books(author_id);
CREATE INDEX IF NOT EXISTS idx_books_isbn ON books(isbn);
CREATE INDEX IF NOT EXISTS idx_books_genre ON books(genre);

-- Seed data: classic library books
INSERT INTO authors (id, name, bio) VALUES
    ('a0000000-0000-0000-0000-000000000001', 'George Orwell', 'English novelist and essayist, journalist and critic.'),
    ('a0000000-0000-0000-0000-000000000002', 'Harper Lee', 'American novelist known for To Kill a Mockingbird.'),
    ('a0000000-0000-0000-0000-000000000003', 'Gabriel Garcia Marquez', 'Colombian novelist, short-story writer, and journalist.')
ON CONFLICT DO NOTHING;

INSERT INTO books (isbn, title, author_id, genre, copies_total, copies_available) VALUES
    ('978-0-14-028329-7', '1984', 'a0000000-0000-0000-0000-000000000001', 'Dystopian Fiction', 3, 3),
    ('978-0-06-112008-4', 'To Kill a Mockingbird', 'a0000000-0000-0000-0000-000000000002', 'Southern Gothic', 2, 2),
    ('978-0-06-088328-7', 'One Hundred Years of Solitude', 'a0000000-0000-0000-0000-000000000003', 'Magical Realism', 2, 2)
ON CONFLICT DO NOTHING;