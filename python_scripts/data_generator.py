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
from dotenv import load_dotenv

# Initialize
load_dotenv()
fake = Faker('en_US')
Faker.seed(42)
random.seed(42)
np.random.seed(42)

# Reference data
BLOOD_TYPES = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
GENDERS = ['Male', 'Female']
INSURANCE_PROVIDERS = ['Blue Cross', 'Aetna', 'UnitedHealthcare', 'Cigna', 'Humana', 'Medicare', 'Medicaid']
ADMISSION_TYPES = ['Emergency', 'Urgent', 'Elective', 'Transfer']
ADMISSION_SOURCES = ['Emergency Room', 'Physician Referral', 'Transfer from Other', 'Clinic Referral']
DISCHARGE_DISPOSITIONS = ['Home', 'Home Health Service', 'Skilled Nursing Facility', 'Rehab Facility', 'Left AMA']
HOSPITAL_TYPES = ['General', 'Specialty', 'Teaching', 'Community']

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

def connect_to_oracle():
    """Establish connection to Oracle Autonomous Database"""
    try:
        cx_Oracle.init_oracle_client(
            lib_dir=os.getenv('ORACLE_CLIENT_LIB'),
            config_dir=os.getenv('WALLET_LOCATION')
        )
        
        connection = cx_Oracle.connect(
            user=os.getenv('DB_USER'),
            password=os.getenv('DB_PASSWORD'),
            dsn=os.getenv('DB_DSN'),
            encoding="UTF-8"
        )
        print("✓ Successfully connected to Oracle Database!")
        return connection
    except Exception as e:
        print(f"✗ Error connecting to database: {e}")
        return None

def generate_patients(n=5000):
    """Generate synthetic patient data"""
    print(f"Generating {n} patients...")
    patients = []
    for i in range(n):
        patient_id = f"P{10001 + i}"
        dob = fake.date_of_birth(minimum_age=18, maximum_age=95)
        
        patient = (
            patient_id,
            fake.first_name(),
            fake.last_name(),
            dob,
            random.choice(GENDERS),
            random.choice(BLOOD_TYPES),
            fake.phone_number()[:20],
            fake.email(),
            fake.street_address()[:200],
            fake.city()[:50],
            fake.state_abbr(),
            fake.zipcode(),
            'USA',
            fake.name()[:100],
            fake.phone_number()[:20],
            random.choice(INSURANCE_PROVIDERS),
            fake.bothify(text='###-??-####').upper()
        )
        patients.append(patient)
    
    return patients

def generate_hospitals(n=25):
    """Generate hospital data"""
    print(f"Generating {n} hospitals...")
    hospitals = []
    for i in range(n):
        hospital_id = f"H{40001 + i}"
        total_beds = random.randint(100, 800)
        available_beds = random.randint(10, int(total_beds * 0.3))
        
        hospital = (
            hospital_id,
            f"{fake.city()} {random.choice(['Medical Center', 'General Hospital', 'Regional Hospital'])}",
            fake.street_address()[:200],
            fake.city()[:50],
            fake.state_abbr(),
            fake.zipcode(),
            fake.phone_number()[:20],
            total_beds,
            available_beds,
            random.choice(HOSPITAL_TYPES),
            random.choice(['I', 'II', 'III', 'IV', None])
        )
        hospitals.append(hospital)
    
    return hospitals

def generate_departments(hospitals, n_per_hospital=7):
    """Generate department data"""
    print("Generating departments...")
    dept_names = ['Emergency', 'Cardiology', 'Neurology', 'Oncology', 'Orthopedics', 
                  'Surgery', 'ICU', 'Internal Medicine']
    
    departments = []
    dept_id = 50001
    
    for hospital in hospitals:
        selected_depts = random.sample(dept_names, n_per_hospital)
        for dept_name in selected_depts:
            total_beds = random.randint(10, 50)
            available_beds = random.randint(1, int(total_beds * 0.4))
            
            dept = (
                f"D{dept_id}",
                hospital[0],  # hospital_id
                dept_name,
                dept_name,
                f"Dr. {fake.last_name()}",
                total_beds,
                available_beds
            )
            departments.append(dept)
            dept_id += 1
    
    return departments

def generate_admissions(patients, hospitals, departments, n=15000):
    """Generate admission records"""
    print(f"Generating {n} admissions...")
    admissions = []
    start_date = datetime(2023, 1, 1)
    end_date = datetime(2024, 12, 31)
    
    # Create hospital-department mapping
    hosp_depts = {}
    for dept in departments:
        hosp_id = dept[1]
        if hosp_id not in hosp_depts:
            hosp_depts[hosp_id] = []
        hosp_depts[hosp_id].append(dept[0])
    
    patient_admissions = {}
    
    for i in range(n):
        admission_id = f"A{20001 + i}"
        patient = random.choice(patients)
        patient_id = patient[0]
        patient_dob = patient[3]
        
        hospital = random.choice(hospitals)
        hospital_id = hospital[0]
        dept_id = random.choice(hosp_depts[hospital_id])
        
        admission_date = start_date + timedelta(days=random.randint(0, (end_date - start_date).days))
        
        condition_id = random.choice(list(CONDITIONS.keys()))
        condition_info = CONDITIONS[condition_id]
        
        los = max(1, int(np.random.normal(condition_info['los_mean'], condition_info['los_std'])))
        discharge_date = admission_date + timedelta(days=los)
        
        age = (admission_date.date() - patient_dob).days // 365
        
        # Readmission logic
        if patient_id not in patient_admissions:
            patient_admissions[patient_id] = []
        
        previous_admissions = [a for a in patient_admissions[patient_id] if a['discharge_date'] < admission_date]
        readmission_flag = 0
        readmission_30day = 0
        previous_admission_id = None
        
        if previous_admissions:
            last_admission = max(previous_admissions, key=lambda x: x['discharge_date'])
            days_since = (admission_date - last_admission['discharge_date']).days
            
            if days_since <= 30:
                readmission_30day = 1
                readmission_flag = 1
                previous_admission_id = last_admission['admission_id']
            elif days_since <= 90:
                readmission_flag = 1
                previous_admission_id = last_admission['admission_id']
        
        # ICU logic - FIXED
        icu_flag = 1 if random.random() < condition_info['risk'] * 0.5 else 0
        if icu_flag and los > 1:
            max_icu_days = max(1, los // 2)
            icu_days = random.randint(1, max_icu_days)
        else:
            icu_days = 0
        
        mortality_flag = 1 if random.random() < 0.02 else 0
        
        admission = (
            admission_id, patient_id, hospital_id, dept_id,
            admission_date, 
            discharge_date if not mortality_flag else admission_date + timedelta(days=random.randint(1, 3)),
            random.choices(ADMISSION_TYPES, weights=[0.4, 0.3, 0.2, 0.1])[0],
            random.choice(ADMISSION_SOURCES),
            condition_id, None,
            f"Dr. {fake.last_name()}",
            los, age, readmission_flag, readmission_30day, previous_admission_id,
            'Expired' if mortality_flag else random.choice(DISCHARGE_DISPOSITIONS),
            mortality_flag, icu_flag, icu_days
        )
        
        admissions.append(admission)
        patient_admissions[patient_id].append({
            'admission_id': admission_id,
            'discharge_date': discharge_date
        })
        
        # Progress indicator
        if (i + 1) % 1000 == 0:
            print(f"  Generated {i + 1}/{n} admissions...")
    
    return admissions

def generate_billing(admissions):
    """Generate billing records"""
    print("Generating billing data...")
    billing = []
    
    for i, admission in enumerate(admissions):
        admission_id = admission[0]
        los = admission[11]
        icu_days = admission[18]
        
        total_charges = 2500 * los
        if icu_days:
            total_charges += icu_days * 5000
        total_charges += random.randint(5000, 25000)
        
        coverage_rate = random.uniform(0.7, 0.9)
        insurance_covered = total_charges * coverage_rate
        patient_responsibility = total_charges - insurance_covered
        
        payment_status = random.choices(
            ['Paid', 'Partial', 'Pending', 'Outstanding'],
            weights=[0.6, 0.2, 0.15, 0.05]
        )[0]
        
        billing_date = admission[5].date() if admission[5] else admission[4].date()
        payment_date = billing_date + timedelta(days=random.randint(1, 90)) if payment_status == 'Paid' else None
        
        bill = (
            f"B{90001 + i}",
            admission_id,
            round(total_charges, 2),
            round(insurance_covered, 2),
            round(patient_responsibility, 2),
            payment_status,
            billing_date,
            payment_date
        )
        billing.append(bill)
    
    return billing

def insert_data(connection, table_name, columns, data):
    """Bulk insert data into table"""
    cursor = connection.cursor()
    
    placeholders = ', '.join([f':{i+1}' for i in range(len(columns))])
    insert_sql = f"INSERT INTO {table_name} ({', '.join(columns)}) VALUES ({placeholders})"
    
    try:
        cursor.executemany(insert_sql, data)
        connection.commit()
        print(f"✓ Inserted {len(data)} rows into {table_name}")
    except Exception as e:
        print(f"✗ Error inserting into {table_name}: {e}")
        connection.rollback()
    finally:
        cursor.close()

def main():
    print("\n" + "="*60)
    print("HEALTHCARE DATA GENERATOR")
    print("="*60 + "\n")
    
    # Generate data
    patients = generate_patients(5000)
    hospitals = generate_hospitals(25)
    departments = generate_departments(hospitals, 7)
    admissions = generate_admissions(patients, hospitals, departments, 15000)
    billing = generate_billing(admissions)
    
    # Connect to database
    connection = connect_to_oracle()
    if not connection:
        print("\n✗ Could not connect to database. Exiting.")
        return
    
    # Insert data
    print("\n" + "="*60)
    print("INSERTING DATA INTO ORACLE DATABASE")
    print("="*60 + "\n")
    
    insert_data(connection, 'patients', [
        'patient_id', 'first_name', 'last_name', 'date_of_birth', 'gender',
        'blood_type', 'phone', 'email', 'address', 'city', 'state', 'zip_code',
        'country', 'emergency_contact_name', 'emergency_contact_phone',
        'insurance_provider', 'insurance_policy_number'
    ], patients)
    
    insert_data(connection, 'hospitals', [
        'hospital_id', 'hospital_name', 'address', 'city', 'state', 'zip_code',
        'phone', 'total_beds', 'available_beds', 'hospital_type', 'trauma_level'
    ], hospitals)
    
    insert_data(connection, 'departments', [
        'department_id', 'hospital_id', 'department_name', 'department_type',
        'head_physician', 'total_beds', 'available_beds'
    ], departments)
    
    insert_data(connection, 'admissions', [
        'admission_id', 'patient_id', 'hospital_id', 'department_id',
        'admission_date', 'discharge_date', 'admission_type', 'admission_source',
        'primary_diagnosis_id', 'secondary_diagnoses', 'attending_physician',
        'length_of_stay_days', 'patient_age_at_admission', 'readmission_flag',
        'readmission_within_30days', 'previous_admission_id', 'discharge_disposition',
        'mortality_flag', 'icu_stay_flag', 'icu_days'
    ], admissions)
    
    insert_data(connection, 'billing', [
        'billing_id', 'admission_id', 'total_charges', 'insurance_covered',
        'patient_responsibility', 'payment_status', 'billing_date', 'payment_date'
    ], billing)
    
    connection.close()
    
    print("\n" + "="*60)
    print("DATA GENERATION COMPLETE!")
    print("="*60)
    print(f"\n✓ Patients: {len(patients)}")
    print(f"✓ Hospitals: {len(hospitals)}")
    print(f"✓ Departments: {len(departments)}")
    print(f"✓ Admissions: {len(admissions)}")
    print(f"✓ Billing: {len(billing)}")
    print(f"\n✓ 30-Day Readmission Rate: {sum(1 for a in admissions if a[13]) / len(admissions) * 100:.2f}%")
    print("\nNext step: Create views and export for Tableau!\n")

if __name__ == "__main__":
    main()