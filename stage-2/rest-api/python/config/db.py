from sqlalchemy import create_engine,MetaData
import os

dbpassword = os.getenv("dbpassword")
engine = create_engine("mysql+pymysql://root:{dbpassword}@mysql_db_container:3306/testdb")
meta = MetaData()

conn = engine.connect()