"""
Healthcare Synthetic Data Generator
Generates realistic healthcare data for the analytics dashboard
"""

import random
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from faker import Faker
import cx_Oracle
import os

# Initialize Faker
fake = Faker('en_US')
Faker.seed(42)
random.seed(42)
np.random.seed(42)

# Reference data
BLOOD_TYPES = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
GENDERS = ['Male', 'Female', 'Other']
INSURANCE_PROVIDERS = ['Blue Cross', 'Aetna', 'UnitedHealthcare', 'Cigna', 'Humana', 'Medicare', 'Medicaid']
ADMISSION_TYPES = ['Emergency', 'Urgent', 'Elective', 'Transfer']
ADMISSION_SOURCES = ['Emergency Room', 'Physician Referral', 'Transfer from Other', 'Clinic Referral']
DISCHARGE_DISPOSITIONS = ['Home', 'Home Health Service', 'Skilled Nursing Facility', 'Rehab Facility', 'Expired', 'Left AMA']
HOSPITAL_TYPES = ['General', 'Specialty', 'Teaching', 'Community']

# Medical conditions with readmission risk weights
CONDITIONS = {
    'C10001': {'name': 'Diabetes Mellitus Type 2', 'risk': 0.3, 'los_mean': 4, 'los_std': 2},
    'C10002': {'name': 'Hypertension', 'risk': 0.15, 'los_mean': 3, 'los_std': 1},
    'C10003': {'name': 'Congestive Heart Failure', 'risk': 0.45, 'los_mean': 7, 'los_std': 3},
    'C10004': {'name': 'COPD', 'risk': 0.40, 'los_mean': 6, 'los_std': 2},
    'C10005': {'name': 'Acute Myocardial Infarction', 'risk': 0.35, 'los_mean': 8, 'los_std': 3},
    'C10006': {'name': 'Pneumonia', 'risk': 0.38, 'los_mean': 5, 'los_std': 2},
    'C10007': {'name': 'Chronic Kidney Disease', 'risk': 0.42, 'los_mean': 6, 'los_std': 3},
    'C10008': {'name': 'Sepsis', 'risk': 0.50, 'los_mean': 10, 'los_std': 4},
    'C10009': {'name': 'Stroke', 'risk': 0.40, 'los_mean': 9, 'los_std': 4},
    'C10010': {'name': 'Atrial Fibrillation', 'risk': 0.28, 'los_mean': 4, 'los_std': 2}
}

# Common procedures
PROCEDURES = [
    ('P60001', 'Cardiac Catheterization', 'High', 90),
    ('P60002', 'Coronary Artery Bypass Graft', 'Critical', 240),
    ('P60003', 'Hip Replacement', 'Medium', 120),
    ('P60004', 'Appendectomy', 'Medium', 60),
    ('P60005', 'Colonoscopy', 'Low', 30),
    ('P60006', 'Chest X-Ray', 'Low', 15),
    ('P60007', 'CT Scan', 'Low', 20),
    ('P60008', 'MRI', 'Low', 45),
    ('P60009', 'Dialysis', 'Medium', 180),
    ('P60010', 'Mechanical Ventilation', 'Critical', 360)
]

# Common medications
MEDICATIONS = [
    ('M70001', 'Metformin', 'Antidiabetic'),
    ('M70002', 'Lisinopril', 'Antihypertensive'),
    ('M70003', 'Atorvastatin', 'Statin'),
    ('M70004', 'Aspirin', 'Antiplatelet'),
    ('M70005', 'Warfarin', 'Anticoagulant'),
    ('M70006', 'Insulin', 'Antidiabetic'),
    ('M70007', 'Furosemide', 'Diuretic'),
    ('M70008', 'Albuterol', 'Bronchodilator'),
    ('M70009', 'Morphine', 'Analgesic'),
    ('M70010', 'Vancomycin', 'Antibiotic')
]

LAB_TESTS = [
    ('Hemoglobin', '13.5-17.5', 'g/dL'),
    ('White Blood Cell Count', '4.5-11.0', '10^9/L'),
    ('Glucose', '70-100', 'mg/dL'),
    ('Creatinine', '0.7-1.3', 'mg/dL'),
    ('Sodium', '135-145', 'mmol/L'),
    ('Potassium', '3.5-5.0', 'mmol/L'),
    ('BNP', '0-100', 'pg/mL'),
    ('Troponin', '0-0.04', 'ng/mL'),
    ('HbA1c', '4.0-5.6', '%'),
    ('D-Dimer', '0-500', 'ng/mL')
]

def generate_patients(n=5000):
    """Generate synthetic patient data"""
    patients = []
    for i in range(n):
        patient_id = f"P{10001 + i}"
        dob = fake.date_of_birth(minimum_age=18, maximum_age=95)
        
        patient = {
            'patient_id': patient_id,
            'first_name': fake.first_name(),
            'last_name': fake.last_name(),
            'date_of_birth': dob,
            'gender': random.choice(GENDERS),
            'blood_type': random.choice(BLOOD_TYPES),
            'phone': fake.phone_number(),
            'email': fake.email(),
            'address': fake.street_address(),
            'city': fake.city(),
            'state': fake.state_abbr(),
            'zip_code': fake.zipcode(),
            'country': 'USA',
            'emergency_contact_name': fake.name(),
            'emergency_contact_phone': fake.phone_number(),
            'insurance_provider': random.choice(INSURANCE_PROVIDERS),
            'insurance_policy_number': fake.bothify(text='###-??-####').upper()
        }
        patients.append(patient)
    
    return pd.DataFrame(patients)

def generate_hospitals(n=25):
    """Generate hospital data"""
    hospitals = []
    for i in range(n):
        hospital_id = f"H{40001 + i}"
        total_beds = random.randint(100, 800)
        available_beds = random.randint(10, int(total_beds * 0.3))
        
        hospital = {
            'hospital_id': hospital_id,
            'hospital_name': f"{fake.city()} {random.choice(['Medical Center', 'General Hospital', 'Regional Hospital', 'Community Hospital'])}",
            'address': fake.street_address(),
            'city': fake.city(),
            'state': fake.state_abbr(),
            'zip_code': fake.zipcode(),
            'phone': fake.phone_number(),
            'total_beds': total_beds,
            'available_beds': available_beds,
            'hospital_type': random.choice(HOSPITAL_TYPES),
            'trauma_level': random.choice(['I', 'II', 'III', 'IV', None])
        }
        hospitals.append(hospital)
    
    return pd.DataFrame(hospitals)

def generate_departments(hospitals_df):
    """Generate department data for each hospital"""
    dept_names = ['Emergency', 'Cardiology', 'Neurology', 'Oncology', 'Orthopedics', 
                  'Pediatrics', 'Surgery', 'ICU', 'Internal Medicine', 'Radiology']
    
    departments = []
    dept_id_counter = 50001
    
    for _, hospital in hospitals_df.iterrows():
        num_depts = random.randint(5, 10)
        selected_depts = random.sample(dept_names, num_depts)
        
        for dept_name in selected_depts:
            total_beds = random.randint(10, 50)
            available_beds = random.randint(1, int(total_beds * 0.4))
            
            dept = {
                'department_id': f"D{dept_id_counter}",
                'hospital_id': hospital['hospital_id'],
                'department_name': dept_name,
                'department_type': dept_name,
                'head_physician': f"Dr. {fake.last_name()}",
                'total_beds': total_beds,
                'available_beds': available_beds
            }
            departments.append(dept)
            dept_id_counter += 1
    
    return pd.DataFrame(departments)

def generate_admissions(patients_df, hospitals_df, departments_df, n=15000):
    """Generate admission records with realistic patterns"""
    admissions = []
    start_date = datetime(2023, 1, 1)
    end_date = datetime(2024, 12, 31)
    
    # Track patient admissions for readmission calculation
    patient_admissions = {pid: [] for pid in patients_df['patient_id']}
    
    for i in range(n):
        admission_id = f"A{20001 + i}"
        patient = patients_df.sample(1).iloc[0]
        hospital = hospitals_df.sample(1).iloc[0]
        dept = departments_df[departments_df['hospital_id'] == hospital['hospital_id']].sample(1).iloc[0]
        
        # Random admission date
        admission_date = start_date + timedelta(days=random.randint(0, (end_date - start_date).days))
        
        # Select primary diagnosis
        condition_id = random.choice(list(CONDITIONS.keys()))
        condition_info = CONDITIONS[condition_id]
        
        # Length of stay based on condition
        los = max(1, int(np.random.normal(condition_info['los_mean'], condition_info['los_std'])))
        discharge_date = admission_date + timedelta(days=los)
        
        # Patient age at admission
        age = (admission_date.date() - patient['date_of_birth']).days // 365
        
        # Readmission logic
        previous_admissions = [a for a in patient_admissions[patient['patient_id']] if a['discharge_date'] < admission_date]
        readmission_flag = 0
        readmission_30day = 0
        previous_admission_id = None
        
        if previous_admissions:
            last_admission = max(previous_admissions, key=lambda x: x['discharge_date'])
            days_since_last = (admission_date - last_admission['discharge_date']).days
            
            if days_since_last <= 30:
                readmission_30day = 1
                readmission_flag = 1
                previous_admission_id = last_admission['admission_id']
            elif days_since_last <= 90:
                readmission_flag = 1
                previous_admission_id = last_admission['admission_id']
        
        # ICU stay based on condition severity
        icu_flag = 1 if random.random() < condition_info['risk'] * 0.5 else 0
        icu_days = random.randint(1, max(1, los // 2)) if icu_flag else 0
        
        # Mortality flag (low probability)
        mortality_flag = 1 if random.random() < 0.02 else 0
        
        admission = {
            'admission_id': admission_id,
            'patient_id': patient['patient_id'],
            'hospital_id': hospital['hospital_id'],
            'department_id': dept['department_id'],
            'admission_date': admission_date,
            'discharge_date': discharge_date if not mortality_flag else admission_date + timedelta(days=random.randint(1, 5)),
            'admission_type': random.choices(ADMISSION_TYPES, weights=[0.4, 0.3, 0.2, 0.1])[0],
            'admission_source': random.choice(ADMISSION_SOURCES),
            'primary_diagnosis_id': condition_id,
            'secondary_diagnoses': ','.join(random.sample([c for c in CONDITIONS.keys() if c != condition_id], random.randint(0, 3))),
            'attending_physician': f"Dr. {fake.last_name()}",
            'length_of_stay_days': los,
            'patient_age_at_admission': age,
            'readmission_flag': readmission_flag,
            'readmission_within_30days': readmission_30day,
            'previous_admission_id': previous_admission_id,
            'discharge_disposition': 'Expired' if mortality_flag else random.choice(DISCHARGE_DISPOSITIONS[:-1]),
            'mortality_flag': mortality_flag,
            'icu_stay_flag': icu_flag,
            'icu_days': icu_days
        }
        
        admissions.append(admission)
        patient_admissions[patient['patient_id']].append({
            'admission_id': admission_id,
            'discharge_date': admission['discharge_date']
        })
    
    return pd.DataFrame(admissions)

def generate_procedures(admissions_df, n_per_admission_avg=2):
    """Generate procedure records"""
    procedures_data = []
    proc_id_counter = 80001
    
    for _, admission in admissions_df.iterrows():
        num_procedures = np.random.poisson(n_per_admission_avg)
        
        for _ in range(num_procedures):
            proc = random.choice(PROCEDURES)
            proc_date = admission['admission_date'] + timedelta(
                days=random.randint(0, admission['length_of_stay_days'])
            )
            
            procedure = {
                'patient_procedure_id': f"PP{proc_id_counter}",
                'admission_id': admission['admission_id'],
                'procedure_id': proc[0],
                'procedure_date': proc_date,
                'duration_minutes': proc[3] + random.randint(-20, 20),
                'performing_physician': f"Dr. {fake.last_name()}",
                'outcome': random.choices(['Success', 'Complicated', 'Adverse Event'], weights=[0.85, 0.12, 0.03])[0],
                'complications': fake.sentence() if random.random() < 0.1 else None
            }
            procedures_data.append(procedure)
            proc_id_counter += 1
    
    return pd.DataFrame(procedures_data)

def generate_medications(admissions_df, n_per_admission_avg=3):
    """Generate medication records"""
    medications_data = []
    med_id_counter = 90001
    
    for _, admission in admissions_df.iterrows():
        num_meds = np.random.poisson(n_per_admission_avg)
        
        for _ in range(num_meds):
            med = random.choice(MEDICATIONS)
            start_date = admission['admission_date'] + timedelta(
                hours=random.randint(0, 24)
            )
            end_date = admission['discharge_date'] - timedelta(
                hours=random.randint(0, 12)
            )
            
            medication = {
                'patient_medication_id': f"PM{med_id_counter}",
                'admission_id': admission['admission_id'],
                'medication_id': med[0],
                'start_date': start_date,
                'end_date': end_date,
                'dosage': f"{random.randint(1, 100)} mg",
                'frequency': random.choice(['Once daily', 'Twice daily', 'Three times daily', 'Every 6 hours', 'As needed']),
                'prescribing_physician': f"Dr. {fake.last_name()}"
            }
            medications_data.append(medication)
            med_id_counter += 1
    
    return pd.DataFrame(medications_data)

def generate_lab_results(admissions_df, n_per_admission_avg=5):
    """Generate lab test results"""
    lab_data = []
    lab_id_counter = 100001
    
    for _, admission in admissions_df.iterrows():
        num_labs = np.random.poisson(n_per_admission_avg)
        
        for _ in range(num_labs):
            test = random.choice(LAB_TESTS)
            test_date = admission['admission_date'] + timedelta(
                hours=random.randint(0, admission['length_of_stay_days'] * 24)
            )
            
            # Parse reference range
            ref_range = test[1]
            if '-' in ref_range:
                low, high = map(float, ref_range.split('-'))
                # Generate value (80% normal, 20% abnormal)
                if random.random() < 0.8:
                    value = random.uniform(low, high)
                    abnormal = 'Normal'
                else:
                    if random.random() < 0.5:
                        value = random.uniform(low * 0.5, low)
                        abnormal = 'Low'
                    else:
                        value = random.uniform(high, high * 1.5)
                        abnormal = 'High'
            else:
                value = float(ref_range.split('-')[0])
                abnormal = 'Normal'
            
            lab = {
                'lab_result_id': f"L{lab_id_counter}",
                'admission_id': admission['admission_id'],
                'test_name': test[0],
                'test_date': test_date,
                'result_value': f"{value:.2f}",
                'result_unit': test[2],
                'reference_range': ref_range,
                'abnormal_flag': abnormal,
                'interpretation': fake.sentence() if abnormal != 'Normal' else None
            }
            lab_data.append(lab)
            lab_id_counter += 1
    
    return pd.DataFrame(lab_data)

def generate_billing(admissions_df):
    """Generate billing records"""
    billing_data = []
    
    for _, admission in admissions_df.iterrows():
        # Base cost calculation
        base_cost_per_day = 2500
        total_charges = base_cost_per_day * admission['length_of_stay_days']
        
        # Add ICU costs
        if admission['icu_stay_flag']:
            total_charges += admission['icu_days'] * 5000
        
        # Add procedure costs
        total_charges += random.randint(5000, 25000)
        
        # Insurance coverage (70-90%)
        coverage_rate = random.uniform(0.7, 0.9)
        insurance_covered = total_charges * coverage_rate
        patient_responsibility = total_charges - insurance_covered
        
        payment_status = random.choices(
            ['Paid', 'Partial', 'Pending', 'Outstanding'],
            weights=[0.6, 0.2, 0.15, 0.05]
        )[0]
        
        billing = {
            'billing_id': f"B{90001 + len(billing_data)}",
            'admission_id': admission['admission_id'],
            'total_charges': round(total_charges, 2),
            'insurance_covered': round(insurance_covered, 2),
            'patient_responsibility': round(patient_responsibility, 2),
            'payment_status': payment_status,
            'billing_date': admission['discharge_date'].date(),
            'payment_date': (admission['discharge_date'] + timedelta(days=random.randint(1, 90))).date() if payment_status == 'Paid' else None
        }
        billing_data.append(billing)
    
    return pd.DataFrame(billing_data)

def connect_to_oracle():
    """Establish connection to Oracle Autonomous Database"""
    try:
        # For local development, point to wallet location
        # Extract wallet files to a directory
        cx_Oracle.init_oracle_client(lib_dir=r"C:\oracle\instantclient_19_14")  # Windows
        # cx_Oracle.init_oracle_client(lib_dir="/usr/lib/oracle/19.14/client64/lib")  # Linux
        
        connection = cx_Oracle.connect(
            user=os.getenv('DB_USER'),
            password=os.getenv('DB_PASSWORD'),
            dsn=os.getenv('DB_DSN')
        )
        print("Successfully connected to Oracle Database!")
        return connection
    except Exception as e:
        print(f"Error connecting to database: {e}")
        return None

def insert_dataframe(connection, df, table_name):
    """Insert pandas DataFrame into Oracle table"""
    cursor = connection.cursor()
    
    # Prepare column names and placeholders
    columns = ', '.join(df.columns)
    placeholders = ', '.join([f':{i+1}' for i in range(len(df.columns))])
    
    insert_sql = f"INSERT INTO {table_name} ({columns}) VALUES ({placeholders})"
    
    # Convert DataFrame to list of tuples
    rows = [tuple(x) for x in df.to_numpy()]
    
    try:
        cursor.executemany(insert_sql, rows)
        connection.commit()
        print(f"Inserted {len(rows)} rows into {table_name}")
    except Exception as e:
        print(f"Error inserting into {table_name}: {e}")
        connection.rollback()
    finally:
        cursor.close()

def main():
    """Main execution function"""
    print("Starting healthcare data generation...")
    
    # Generate all datasets
    print("\n1. Generating patients...")
    patients_df = generate_patients(5000)
    
    print("2. Generating hospitals...")
    hospitals_df = generate_hospitals(25)
    
    print("3. Generating departments...")
    departments_df = generate_departments(hospitals_df)
    
    print("4. Generating admissions...")
    admissions_df = generate_admissions(patients_df, hospitals_df, departments_df, 15000)
    
    print("5. Generating procedures...")
    procedures_df = generate_procedures(admissions_df)
    
    print("6. Generating medications...")
    medications_df = generate_medications(admissions_df)
    
    print("7. Generating lab results...")
    lab_results_df = generate_lab_results(admissions_df)
    
    print("8. Generating billing...")
    billing_df = generate_billing(admissions_df)
    
    # Save to CSV files (as backup)
    print("\nSaving to CSV files...")
    patients_df.to_csv('data/patients.csv', index=False)
    hospitals_df.to_csv('data/hospitals.csv', index=False)
    departments_df.to_csv('data/departments.csv', index=False)
    admissions_df.to_csv('data/admissions.csv', index=False)
    procedures_df.to_csv('data/procedures.csv', index=False)
    medications_df.to_csv('data/medications.csv', index=False)
    lab_results_df.to_csv('data/lab_results.csv', index=False)
    billing_df.to_csv('data/billing.csv', index=False)
    
    print("\nCSV files created successfully!")
    
    # Connect to Oracle and insert data
    print("\nConnecting to Oracle Database...")
    connection = connect_to_oracle()
    
    if connection:
        print("\nInserting data into Oracle tables...")
        insert_dataframe(connection, patients_df, 'patients')
        insert_dataframe(connection, hospitals_df, 'hospitals')
        insert_dataframe(connection, departments_df, 'departments')
        insert_dataframe(connection, admissions_df, 'admissions')
        insert_dataframe(connection, procedures_df, 'patient_procedures')
        insert_dataframe(connection, medications_df, 'patient_medications')
        insert_dataframe(connection, lab_results_df, 'lab_results')
        insert_dataframe(connection, billing_df, 'billing')
        
        connection.close()
        print("\nData insertion completed!")
    else:
        print("\nCould not connect to database. CSV files are available for manual import.")
    
    print("\n" + "="*50)
    print("DATA GENERATION SUMMARY")
    print("="*50)
    print(f"Patients: {len(patients_df)}")
    print(f"Hospitals: {len(hospitals_df)}")
    print(f"Departments: {len(departments_df)}")
    print(f"Admissions: {len(admissions_df)}")
    print(f"Procedures: {len(procedures_df)}")
    print(f"Medications: {len(medications_df)}")
    print(f"Lab Results: {len(lab_results_df)}")
    print(f"Billing Records: {len(billing_df)}")
    print("\nReadmission Statistics:")
    print(f"Total Readmissions: {admissions_df['readmission_flag'].sum()}")
    print(f"30-Day Readmissions: {admissions_df['readmission_within_30days'].sum()}")
    print(f"30-Day Readmission Rate: {(admissions_df['readmission_within_30days'].sum() / len(admissions_df) * 100):.2f}%")
    print("="*50)

if __name__ == "__main__":
    main()