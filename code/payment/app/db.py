import os

from sqlmodel import create_engine, SQLModel, Session


DATABASE_USER_NAME = os.environ.get("DATABASE_USER_NAME")
DATABASE_USER_PWD = os.environ.get("DATABASE_USER_PWD")
DATABASE_HOST = os.environ.get("DATABASE_HOST")
DATABASE_PORT = os.environ.get("DATABASE_PORT")
DATABASE_NAME = os.environ.get("DATABASE_NAME")

DATABASE_URL = f"mysql+pymysql://{DATABASE_USER_NAME}:{DATABASE_USER_PWD}@{DATABASE_HOST}:{DATABASE_PORT}/{DATABASE_NAME}"

print("database url",DATABASE_URL)
engine = create_engine(DATABASE_URL, echo=True)


def init_db():
    SQLModel.metadata.create_all(engine)


def get_session():
    with Session(engine) as session:
        yield session