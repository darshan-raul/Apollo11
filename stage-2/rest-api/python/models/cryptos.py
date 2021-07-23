from sqlalchemy import Table,Column
from sqlalchemy.sql.sqltypes import Integer,String
from config.db import meta


cryptos = Table (
    'cryptos',meta,
    Column('name',String(255)),
    Column('price',Integer),
    Column('percent',Integer)
)