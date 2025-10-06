import cx_Oracle
import os
from dotenv import load_dotenv

load_dotenv()

try:
    cx_Oracle.init_oracle_client(
        lib_dir=os.getenv('ORACLE_CLIENT_LIB'),
        config_dir=os.getenv('WALLET_LOCATION')
    )
    
    connection = cx_Oracle.connect(
        user=os.getenv('DB_USER'),
        password=os.getenv('DB_PASSWORD'),
        dsn=os.getenv('DB_DSN')
    )
    
    cursor = connection.cursor()
    cursor.execute("SELECT 'Connection Successful!' FROM DUAL")
    result = cursor.fetchone()
    print(result[0])
    
    cursor.close()
    connection.close()
    
except Exception as e:
    print(f"Connection failed: {e}")