from sqlalchemy import create_engine,MetaData
import os

user_name = os.getenv("user_name")
user_password = os.getenv("user_password")
mysql_host = os.getenv("mysql_host")
mysql_db= os.getenv("mysql_db")


#engine = create_engine(f"mysql+pymysql://{user_name}:{user_password}@{mysql_host}:3306/{mysql_db}")
engine = create_engine(f"mysql+pymysql://test:newpassword@localhost:3306/testdb")
meta = MetaData()

conn = engine.connect()