from fastapi import APIRouter
from config.db import conn
from models.index import cryptos
from schemas.index import Crypto

crypto = APIRouter()


@crypto.get("/")
async def read_data():
    return conn.execute(cryptos.select()).fetchall()


@crypto.get("/{name}")
async def read_data(name: str):
    return conn.execute(cryptos.select().where(cryptos.c.name == name)).fetchall()


@crypto.post("/")
async def write_data(crypto: Crypto):
    conn.execute(cryptos.insert().values(
        name=crypto.name,
        price=crypto.price,
        percent=crypto.percent
    ))
    return conn.execute(cryptos.select()).fetchall()

@crypto.put("/{name}")
async def update_data( name: str, crypto: Crypto):
    
    conn.execute(cryptos.update(
        name=crypto.name,
        price=crypto.price,
        percent=crypto.percent

    ).where(cryptos.c.name == name)).fetchall()
    

@crypto.delete("/{name}")
async def delete_data():
    conn.execute(cryptos.delete.where(cryptos.c.name == name))
    return conn.execute(cryptos.select()).fetchall()    