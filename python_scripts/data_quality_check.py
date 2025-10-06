import cx_Oracle
import os
from dotenv import load_dotenv

load_dotenv()

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

print("="*60)
print("FIXING DATABASE AND RELOADING DATA")
print("="*60)

# Step 1: Drop all foreign key constraints
print("\n1. Dropping foreign key constraints...")
try:
    cursor.execute("""
        BEGIN
           FOR c IN (SELECT constraint_name, table_name 
                     FROM user_constraints 
                     WHERE constraint_type = 'R') 
           LOOP
              EXECUTE IMMEDIATE 'ALTER TABLE ' || c.table_name || ' DROP CONSTRAINT ' || c.constraint_name;
           END LOOP;
        END;
    """)
    print("✓ All foreign key constraints dropped")
except Exception as e:
    print(f"Note: {e}")

connection.commit()

# Step 2: Truncate all tables
print("\n2. Clearing existing data...")
tables = ['billing', 'admissions', 'departments', 'hospitals', 'patients']
for table in tables:
    try:
        cursor.execute(f"TRUNCATE TABLE {table}")
        print(f"✓ Cleared {table}")
    except Exception as e:
        print(f"  {table}: {e}")

connection.commit()

# Step 3: Verify medical_conditions exists
print("\n3. Checking medical conditions...")
cursor.execute("SELECT COUNT(*) FROM medical_conditions")
count = cursor.fetchone()[0]
print(f"✓ Medical conditions: {count} rows")

if count == 0:
    print("  Inserting medical conditions...")
    conditions = [
        ("C10001", "Diabetes Mellitus Type 2", "E11.9", "Endocrine", "Moderate"),
        ("C10002", "Hypertension", "I10", "Cardiovascular", "Moderate"),
        ("C10003", "Congestive Heart Failure", "I50.9", "Cardiovascular", "Severe"),
        ("C10004", "COPD", "J44.9", "Respiratory", "Severe"),
        ("C10005", "Acute Myocardial Infarction", "I21.9", "Cardiovascular", "Critical"),
        ("C10006", "Pneumonia", "J18.9", "Respiratory", "Severe"),
        ("C10007", "Chronic Kidney Disease", "N18.9", "Renal", "Severe"),
        ("C10008", "Sepsis", "A41.9", "Infectious", "Critical"),
        ("C10009", "Stroke", "I63.9", "Neurological", "Critical"),
        ("C10010", "Atrial Fibrillation", "I48.91", "Cardiovascular", "Moderate"),
    ]
    
    for cond in conditions:
        cursor.execute("""
            INSERT INTO medical_conditions 
            (condition_id, condition_name, icd10_code, category, severity_level, created_date)
            VALUES (:1, :2, :3, :4, :5, CURRENT_TIMESTAMP)
        """, cond)
    
    connection.commit()
    print("✓ Medical conditions inserted")

cursor.close()
connection.close()

print("\n" + "="*60)
print("DATABASE READY - Now run data generator")
print("="*60)
print("\nRun: python python_scripts\\data_generator.py")