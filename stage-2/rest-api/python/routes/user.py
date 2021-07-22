from fastapi import APIRouter
from config.db import conn
from models.index import users
from schemas.index import User

user = APIRouter()


@user.get("/")
async def read_data():
    return conn.execute(users.select()).fetchall()


@user.get("/{name}")
async def read_data(name: str):
    return conn.execute(users.select().where(users.c.id == id)).fetchall()


@user.post("/")
async def write_data(user: User):
    conn.execute(users.insert().values(
        name=user.name,
        email=user.email,
        password=user.password
    )).fetchall()
    

@user.put("/{name}")
async def update_data( name: str, user:User):
    
    conn.execute(users.update(
        name=user.name,
        email=user.email,
        password=user.password

    ).where(users.c.name == name)).fetchall()
    

@user.delete("/{name}")
async def delete_data():
    conn.execute(users.delete.where(users.c.name == name))
    return conn.execute(users.select()).fetchall()    