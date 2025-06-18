CREATE TABLE IF NOT EXISTS bookings (
  id SERIAL PRIMARY KEY,
  movie_name TEXT,
  theatre_name TEXT,
  price TEXT
);