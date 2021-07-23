from sqlalchemy import create_engine,MetaData

engine = create_engine("mysql+pymysql://root:rootpassword@mysql_db_container:3306/testdb")
meta = MetaData()

conn = engine.connect()