from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
import os

DATABASE_URL = os.getenv("DATABASE_URL")
DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")

if DATABASE_URL and DB_USER and DB_PASSWORD:
    # Splice credentials into URL: postgresql://user:pass@host:port/dbname
    # Strip whitespace (newlines) that might come from secret decoding
    DB_USER = DB_USER.strip()
    DB_PASSWORD = DB_PASSWORD.strip()
    
    scheme, rest = DATABASE_URL.split("://", 1)
    DATABASE_URL = f"{scheme}://{DB_USER}:{DB_PASSWORD}@{rest}"

if not DATABASE_URL:
    # Fallback for local testing if needed, though robust code should probably fail or handle differently
    DATABASE_URL = "postgresql://postgres:postgres@postgres:5432/apollo11"

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
