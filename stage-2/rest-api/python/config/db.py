from sqlalchemy import create_engine,MetaData

engine = create_engine("mysql+pymysql://test:newpassword@localhost:3306/testdb")
meta = MetaData()

conn = engine.connect()