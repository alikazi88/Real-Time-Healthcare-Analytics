import cx_Oracle
import pandas as pd
import os
from dotenv import load_dotenv

load_dotenv()

# Connect to Oracle
cx_Oracle.init_oracle_client(
    lib_dir=os.getenv('ORACLE_CLIENT_LIB'),
    config_dir=os.getenv('WALLET_LOCATION')
)

connection = cx_Oracle.connect(
    user=os.getenv('DB_USER'),
    password=os.getenv('DB_PASSWORD'),
    dsn=os.getenv('DB_DSN')
)

print("Connected to database. Exporting data for Tableau...\n")

# Create export directory
os.makedirs('tableau_data', exist_ok=True)

# Export base tables (these have data!)
base_tables = {
    'patients': 'SELECT * FROM patients',
    'hospitals': 'SELECT * FROM hospitals',
    'departments': 'SELECT * FROM departments',
    'medical_conditions': 'SELECT * FROM medical_conditions',
    'admissions': 'SELECT * FROM admissions',
    'billing': 'SELECT * FROM billing',
}

for name, query in base_tables.items():
    try:
        df = pd.read_sql(query, connection)
        filename = f'tableau_data/{name}.csv'
        df.to_csv(filename, index=False)
        print(f"✓ Exported {name}: {len(df)} rows → {filename}")
    except Exception as e:
        print(f"✗ Error exporting {name}: {e}")

# Also export calculated metrics (create on-the-fly)
print("\nCreating calculated metrics...\n")

# Hospital KPIs
try:
    query = """
    SELECT 
        h.hospital_id,
        h.hospital_name,
        h.city,
        h.state,
        h.total_beds,
        COUNT(DISTINCT a.admission_id) AS total_admissions,
        COUNT(DISTINCT a.patient_id) AS unique_patients,
        ROUND(AVG(a.length_of_stay_days), 2) AS avg_length_of_stay,
        ROUND(SUM(CASE WHEN a.readmission_within_30days = 1 THEN 1 ELSE 0 END) * 100.0 / 
              NULLIF(COUNT(a.admission_id), 0), 2) AS readmission_rate_30day,
        ROUND(AVG(b.total_charges), 2) AS avg_charges_per_admission
    FROM hospitals h
    LEFT JOIN admissions a ON h.hospital_id = a.hospital_id
    LEFT JOIN billing b ON a.admission_id = b.admission_id
    GROUP BY h.hospital_id, h.hospital_name, h.city, h.state, h.total_beds
    """
    df = pd.read_sql(query, connection)
    df.to_csv('tableau_data/hospital_kpis.csv', index=False)
    print(f"✓ Exported hospital_kpis: {len(df)} rows")
except Exception as e:
    print(f"✗ Error: {e}")

# Readmission by diagnosis
try:
    query = """
    SELECT 
        mc.condition_name,
        mc.category,
        COUNT(DISTINCT a.admission_id) AS total_admissions,
        SUM(CASE WHEN a.readmission_within_30days = 1 THEN 1 ELSE 0 END) AS readmissions_30day,
        ROUND(SUM(CASE WHEN a.readmission_within_30days = 1 THEN 1 ELSE 0 END) * 100.0 / 
              NULLIF(COUNT(a.admission_id), 0), 2) AS readmission_rate,
        ROUND(AVG(a.length_of_stay_days), 2) AS avg_los
    FROM admissions a
    JOIN medical_conditions mc ON a.primary_diagnosis_id = mc.condition_id
    GROUP BY mc.condition_name, mc.category
    HAVING COUNT(a.admission_id) >= 10
    ORDER BY readmission_rate DESC
    """
    df = pd.read_sql(query, connection)
    df.to_csv('tableau_data/readmission_by_diagnosis.csv', index=False)
    print(f"✓ Exported readmission_by_diagnosis: {len(df)} rows")
except Exception as e:
    print(f"✗ Error: {e}")

# Monthly revenue
try:
    query = """
    SELECT 
        TO_CHAR(a.admission_date, 'YYYY-MM') AS year_month,
        EXTRACT(YEAR FROM a.admission_date) AS year,
        EXTRACT(MONTH FROM a.admission_date) AS month,
        COUNT(DISTINCT a.admission_id) AS total_admissions,
        ROUND(SUM(b.total_charges), 2) AS total_revenue,
        ROUND(AVG(b.total_charges), 2) AS avg_revenue_per_admission
    FROM admissions a
    JOIN billing b ON a.admission_id = b.admission_id
    GROUP BY TO_CHAR(a.admission_date, 'YYYY-MM'),
             EXTRACT(YEAR FROM a.admission_date),
             EXTRACT(MONTH FROM a.admission_date)
    ORDER BY year_month DESC
    """
    df = pd.read_sql(query, connection)
    df.to_csv('tableau_data/monthly_revenue.csv', index=False)
    print(f"✓ Exported monthly_revenue: {len(df)} rows")
except Exception as e:
    print(f"✗ Error: {e}")

connection.close()

print("\n✓ All data exported to tableau_data/ folder")
print("\nFiles ready for Tableau:")
for file in os.listdir('tableau_data'):
    if file.endswith('.csv'):
        size = os.path.getsize(f'tableau_data/{file}') / 1024
        print(f"  - {file} ({size:.1f} KB)")