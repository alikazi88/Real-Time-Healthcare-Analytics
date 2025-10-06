-- ============================================================================
-- HEALTHCARE ANALYTICS - ADVANCED SQL QUERIES
-- File: 03_analytics_queries.sql
-- Purpose: Complex analytical queries for healthcare dashboard
-- ============================================================================

-- ============================================================================
-- SECTION 1: KEY PERFORMANCE INDICATORS (KPIs)
-- ============================================================================

-- 1.1 Overall Hospital Performance Metrics
CREATE OR REPLACE VIEW v_hospital_kpis AS
SELECT 
    h.hospital_id,
    h.hospital_name,
    h.city,
    h.state,
    COUNT(DISTINCT a.admission_id) AS total_admissions,
    COUNT(DISTINCT a.patient_id) AS unique_patients,
    ROUND(AVG(a.length_of_stay_days), 2) AS avg_length_of_stay,
    ROUND(SUM(CASE WHEN a.readmission_within_30days = 1 THEN 1 ELSE 0 END) * 100.0 / 
          NULLIF(COUNT(a.admission_id), 0), 2) AS readmission_rate_30day,
    ROUND(SUM(CASE WHEN a.mortality_flag = 1 THEN 1 ELSE 0 END) * 100.0 / 
          NULLIF(COUNT(a.admission_id), 0), 2) AS mortality_rate,
    ROUND(AVG(b.total_charges), 2) AS avg_charges_per_admission,
    ROUND(SUM(b.total_charges), 2) AS total_revenue,
    h.total_beds,
    ROUND((COUNT(DISTINCT a.admission_id) * AVG(a.length_of_stay_days)) / 
          (h.total_beds * 365) * 100, 2) AS bed_occupancy_rate
FROM hospitals h
LEFT JOIN admissions a ON h.hospital_id = a.hospital_id
LEFT JOIN billing b ON a.admission_id = b.admission_id
WHERE a.admission_date >= ADD_MONTHS(CURRENT_DATE, -12)
GROUP BY h.hospital_id, h.hospital_name, h.city, h.state, h.total_beds;

-- 1.2 Department Performance Metrics
CREATE OR REPLACE VIEW v_department_performance AS
SELECT 
    d.department_id,
    d.department_name,
    h.hospital_name,
    COUNT(DISTINCT a.admission_id) AS total_admissions,
    ROUND(AVG(a.length_of_stay_days), 2) AS avg_los,
    ROUND(SUM(CASE WHEN a.readmission_within_30days = 1 THEN 1 ELSE 0 END) * 100.0 / 
          NULLIF(COUNT(a.admission_id), 0), 2) AS readmission_rate,
    ROUND(AVG(b.total_charges), 2) AS avg_revenue_per_admission,
    ROUND((COUNT(DISTINCT a.admission_id) * AVG(a.length_of_stay_days)) / 
          (d.total_beds * 365) * 100, 2) AS utilization_rate
FROM departments d
JOIN hospitals h ON d.hospital_id = h.hospital_id
LEFT JOIN admissions a ON d.department_id = a.department_id
LEFT JOIN billing b ON a.admission_id = b.admission_id
WHERE a.admission_date >= ADD_MONTHS(CURRENT_DATE, -12)
GROUP BY d.department_id, d.department_name, h.hospital_name, d.total_beds
ORDER BY total_admissions DESC;

-- ============================================================================
-- SECTION 2: READMISSION ANALYSIS
-- ============================================================================

-- 2.1 Readmission Patterns by Diagnosis
CREATE OR REPLACE VIEW v_readmission_by_diagnosis AS
SELECT 
    mc.condition_name,
    mc.category,
    COUNT(DISTINCT a.admission_id) AS total_admissions,
    SUM(CASE WHEN a.readmission_within_30days = 1 THEN 1 ELSE 0 END) AS readmissions_30day,
    ROUND(SUM(CASE WHEN a.readmission_within_30days = 1 THEN 1 ELSE 0 END) * 100.0 / 
          NULLIF(COUNT(a.admission_id), 0), 2) AS readmission_rate,
    ROUND(AVG(a.length_of_stay_days), 2) AS avg_los,
    ROUND(AVG(b.total_charges), 2) AS avg_cost
FROM admissions a
JOIN medical_conditions mc ON a.primary_diagnosis_id = mc.condition_id
LEFT JOIN billing b ON a.admission_id = b.admission_id
WHERE a.admission_date >= ADD_MONTHS(CURRENT_DATE, -12)
GROUP BY mc.condition_name, mc.category
HAVING COUNT(a.admission_id) >= 10
ORDER BY readmission_rate DESC;

-- 2.2 Patient Journey Analysis (Recursive CTE)
-- 2.2 Patient Journey Analysis (Oracle-compatible)
CREATE OR REPLACE VIEW v_patient_journey AS
SELECT
    a.patient_id,
    a.admission_id,
    a.admission_date,
    a.discharge_date,
    a.primary_diagnosis_id,
    mc.condition_name,
    a.length_of_stay_days,
    LEVEL AS admission_number,
    PRIOR a.admission_id AS previous_admission_id,
    TRUNC(a.admission_date) - TRUNC(PRIOR a.discharge_date) AS days_since_last_admission
FROM admissions a
JOIN medical_conditions mc ON a.primary_diagnosis_id = mc.condition_id
START WITH a.previous_admission_id IS NULL
CONNECT BY PRIOR a.admission_id = a.previous_admission_id
AND LEVEL <= 10
ORDER BY a.patient_id, admission_number;


-- 2.3 Readmission Risk Factors Analysis
CREATE OR REPLACE VIEW v_readmission_risk_factors AS
WITH admission_features AS (
    SELECT 
        a.admission_id,
        a.patient_id,
        a.readmission_within_30days,
        a.patient_age_at_admission,
        a.length_of_stay_days,
        a.icu_stay_flag,
        a.icu_days,
        mc.category AS diagnosis_category,
        b.total_charges,
        COUNT(DISTINCT pp.procedure_id) AS num_procedures,
        COUNT(DISTINCT pm.medication_id) AS num_medications,
        COUNT(DISTINCT CASE WHEN lr.abnormal_flag != 'Normal' THEN lr.lab_result_id END) AS abnormal_labs
    FROM admissions a
    JOIN medical_conditions mc ON a.primary_diagnosis_id = mc.condition_id
    LEFT JOIN billing b ON a.admission_id = b.admission_id
    LEFT JOIN patient_procedures pp ON a.admission_id = pp.admission_id
    LEFT JOIN patient_medications pm ON a.admission_id = pm.admission_id
    LEFT JOIN lab_results lr ON a.admission_id = lr.admission_id
    GROUP BY a.admission_id, a.patient_id, a.readmission_within_30days, 
             a.patient_age_at_admission, a.length_of_stay_days, a.icu_stay_flag,
             a.icu_days, mc.category, b.total_charges
)
SELECT 
    CASE 
        WHEN patient_age_at_admission < 40 THEN '18-39'
        WHEN patient_age_at_admission < 60 THEN '40-59'
        WHEN patient_age_at_admission < 75 THEN '60-74'
        ELSE '75+'
    END AS age_group,
    diagnosis_category,
    CASE WHEN icu_stay_flag = 1 THEN 'Yes' ELSE 'No' END AS icu_stay,
    COUNT(*) AS total_admissions,
    SUM(readmission_within_30days) AS readmissions,
    ROUND(SUM(readmission_within_30days) * 100.0 / COUNT(*), 2) AS readmission_rate,
    ROUND(AVG(length_of_stay_days), 2) AS avg_los,
    ROUND(AVG(num_procedures), 2) AS avg_procedures,
    ROUND(AVG(total_charges), 2) AS avg_charges
FROM admission_features
GROUP BY 
    CASE 
        WHEN patient_age_at_admission < 40 THEN '18-39'
        WHEN patient_age_at_admission < 60 THEN '40-59'
        WHEN patient_age_at_admission < 75 THEN '60-74'
        ELSE '75+'
    END,
    diagnosis_category,
    CASE WHEN icu_stay_flag = 1 THEN 'Yes' ELSE 'No' END
ORDER BY readmission_rate DESC;

-- ============================================================================
-- SECTION 3: FINANCIAL ANALYSIS
-- ============================================================================

-- 3.1 Revenue Analysis by Month and Department
CREATE OR REPLACE VIEW v_monthly_revenue AS
SELECT 
    TO_CHAR(a.admission_date, 'YYYY-MM') AS year_month,
    EXTRACT(YEAR FROM a.admission_date) AS year,
    EXTRACT(MONTH FROM a.admission_date) AS month,
    d.department_name,
    h.hospital_name,
    COUNT(DISTINCT a.admission_id) AS total_admissions,
    ROUND(SUM(b.total_charges), 2) AS total_revenue,
    ROUND(SUM(b.insurance_covered), 2) AS insurance_revenue,
    ROUND(SUM(b.patient_responsibility), 2) AS patient_revenue,
    ROUND(AVG(b.total_charges), 2) AS avg_revenue_per_admission,
    -- Month-over-month growth
    ROUND((SUM(b.total_charges) - LAG(SUM(b.total_charges)) OVER (
        PARTITION BY d.department_id ORDER BY TO_CHAR(a.admission_date, 'YYYY-MM')
    )) * 100.0 / NULLIF(LAG(SUM(b.total_charges)) OVER (
        PARTITION BY d.department_id ORDER BY TO_CHAR(a.admission_date, 'YYYY-MM')
    ), 0), 2) AS revenue_growth_pct
FROM admissions a
JOIN departments d ON a.department_id = d.department_id
JOIN hospitals h ON a.hospital_id = h.hospital_id
JOIN billing b ON a.admission_id = b.admission_id
WHERE a.admission_date >= ADD_MONTHS(CURRENT_DATE, -24)
GROUP BY TO_CHAR(a.admission_date, 'YYYY-MM'), 
         EXTRACT(YEAR FROM a.admission_date),
         EXTRACT(MONTH FROM a.admission_date),
         d.department_name, d.department_id, h.hospital_name
ORDER BY year_month DESC, total_revenue DESC;

-- 3.2 Payment Status and Collection Metrics
CREATE OR REPLACE VIEW v_payment_metrics AS
SELECT 
    h.hospital_name,
    b.payment_status,
    COUNT(*) AS num_bills,
    ROUND(SUM(b.total_charges), 2) AS total_billed,
    ROUND(SUM(b.insurance_covered), 2) AS insurance_collected,
    ROUND(SUM(b.patient_responsibility), 2) AS patient_owed,
    ROUND(SUM(CASE WHEN b.payment_status = 'Paid' THEN b.patient_responsibility ELSE 0 END), 2) AS patient_collected,
    ROUND(SUM(CASE WHEN b.payment_status IN ('Partial', 'Pending', 'Outstanding') 
               THEN b.patient_responsibility ELSE 0 END), 2) AS outstanding_amount,
    ROUND(AVG(CASE WHEN b.payment_date IS NOT NULL 
               THEN b.payment_date - b.billing_date END), 1) AS avg_days_to_payment
FROM billing b
JOIN admissions a ON b.admission_id = a.admission_id
JOIN hospitals h ON a.hospital_id = h.hospital_id
WHERE b.billing_date >= ADD_MONTHS(CURRENT_DATE, -12)
GROUP BY h.hospital_name, b.payment_status
ORDER BY h.hospital_name, outstanding_amount DESC;

-- ============================================================================
-- SECTION 4: CLINICAL QUALITY METRICS
-- ============================================================================

-- 4.1 Length of Stay Analysis with Statistical Outliers
CREATE OR REPLACE VIEW v_los_analysis AS
WITH los_stats AS (
    SELECT 
        mc.condition_name,
        AVG(a.length_of_stay_days) AS mean_los,
        STDDEV(a.length_of_stay_days) AS stddev_los,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY a.length_of_stay_days) AS q1_los,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY a.length_of_stay_days) AS median_los,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY a.length_of_stay_days) AS q3_los,
        COUNT(*) AS total_cases
    FROM admissions a
    JOIN medical_conditions mc ON a.primary_diagnosis_id = mc.condition_id
    WHERE a.admission_date >= ADD_MONTHS(CURRENT_DATE, -12)
    GROUP BY mc.condition_name
)
SELECT 
    condition_name,
    total_cases,
    ROUND(mean_los, 2) AS avg_los,
    ROUND(stddev_los, 2) AS std_dev,
    ROUND(median_los, 2) AS median_los,
    ROUND(q1_los, 2) AS q1_los,
    ROUND(q3_los, 2) AS q3_los,
    -- IQR method for outlier detection
    ROUND(q3_los + 1.5 * (q3_los - q1_los), 2) AS upper_outlier_threshold,
    ROUND(q1_los - 1.5 * (q3_los - q1_los), 2) AS lower_outlier_threshold
FROM los_stats
ORDER BY total_cases DESC;

-- 4.2 ICU Utilization and Outcomes
CREATE OR REPLACE VIEW v_icu_metrics AS
SELECT 
    h.hospital_name,
    d.department_name,
    COUNT(DISTINCT a.admission_id) AS total_icu_admissions,
    ROUND(AVG(a.icu_days), 2) AS avg_icu_days,
    ROUND(SUM(CASE WHEN a.mortality_flag = 1 THEN 1 ELSE 0 END) * 100.0 / 
          COUNT(*), 2) AS icu_mortality_rate,
    ROUND(SUM(CASE WHEN a.readmission_within_30days = 1 THEN 1 ELSE 0 END) * 100.0 / 
          COUNT(*), 2) AS icu_readmission_rate,
    ROUND(AVG(b.total_charges), 2) AS avg_cost_per_icu_stay
FROM admissions a
JOIN hospitals h ON a.hospital_id = h.hospital_id
JOIN departments d ON a.department_id = d.department_id
LEFT JOIN billing b ON a.admission_id = b.admission_id
WHERE a.icu_stay_flag = 1
  AND a.admission_date >= ADD_MONTHS(CURRENT_DATE, -12)
GROUP BY h.hospital_name, d.department_name
ORDER BY total_icu_admissions DESC;

-- ============================================================================
-- SECTION 5: TIME SERIES ANALYSIS
-- ============================================================================

-- 5.1 Daily Admission Trends with Moving Averages
CREATE OR REPLACE VIEW v_daily_admission_trends AS
SELECT 
    admission_date,
    daily_admissions,
    -- 7-day moving average
    ROUND(AVG(daily_admissions) OVER (
        ORDER BY admission_date 
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS ma_7day,
    -- 30-day moving average
    ROUND(AVG(daily_admissions) OVER (
        ORDER BY admission_date 
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ), 2) AS ma_30day,
    -- Year-over-year comparison
    LAG(daily_admissions, 365) OVER (ORDER BY admission_date) AS admissions_prior_year,
    ROUND((daily_admissions - LAG(daily_admissions, 365) OVER (ORDER BY admission_date)) * 100.0 / 
          NULLIF(LAG(daily_admissions, 365) OVER (ORDER BY admission_date), 0), 2) AS yoy_growth_pct
FROM (
    SELECT 
        TRUNC(admission_date) AS admission_date,
        COUNT(*) AS daily_admissions
    FROM admissions
    WHERE admission_date >= ADD_MONTHS(CURRENT_DATE, -24)
    GROUP BY TRUNC(admission_date)
)
ORDER BY admission_date DESC;

-- 5.2 Seasonal Patterns Analysis
CREATE OR REPLACE VIEW v_seasonal_patterns AS
SELECT 
    EXTRACT(MONTH FROM admission_date) AS month_num,
    TO_CHAR(admission_date, 'Month') AS month_name,
    TO_CHAR(admission_date, 'Day') AS day_of_week,
    mc.category AS diagnosis_category,
    COUNT(*) AS admission_count,
    ROUND(AVG(length_of_stay_days), 2) AS avg_los,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (
        PARTITION BY EXTRACT(MONTH FROM admission_date)
    ), 2) AS pct_of_month_admissions
FROM admissions a
JOIN medical_conditions mc ON a.primary_diagnosis_id = mc.condition_id
WHERE admission_date >= ADD_MONTHS(CURRENT_DATE, -24)
GROUP BY EXTRACT(MONTH FROM admission_date), 
         TO_CHAR(admission_date, 'Month'),
         TO_CHAR(admission_date, 'Day'),
         mc.category
ORDER BY month_num, admission_count DESC;

-- ============================================================================
-- SECTION 6: PATIENT SEGMENTATION
-- ============================================================================

-- 6.1 High-Risk Patient Identification
CREATE OR REPLACE VIEW v_high_risk_patients AS
WITH patient_metrics AS (
    SELECT 
        p.patient_id,
        p.first_name || ' ' || p.last_name AS patient_name,
        TRUNC((CURRENT_DATE - p.date_of_birth) / 365.25) AS current_age,
        COUNT(DISTINCT a.admission_id) AS total_admissions,
        SUM(CASE WHEN a.readmission_within_30days = 1 THEN 1 ELSE 0 END) AS num_readmissions,
        MAX(a.admission_date) AS last_admission_date,
        ROUND(AVG(a.length_of_stay_days), 2) AS avg_los,
        SUM(CASE WHEN a.icu_stay_flag = 1 THEN 1 ELSE 0 END) AS icu_admissions,
        COUNT(DISTINCT pmh.condition_id) AS num_chronic_conditions,
        ROUND(SUM(b.total_charges), 2) AS lifetime_costs
    FROM patients p
    LEFT JOIN admissions a ON p.patient_id = a.patient_id
    LEFT JOIN patient_medical_history pmh ON p.patient_id = pmh.patient_id
    LEFT JOIN billing b ON a.admission_id = b.admission_id
    WHERE a.admission_date >= ADD_MONTHS(CURRENT_DATE, -24)
    GROUP BY p.patient_id, p.first_name, p.last_name, p.date_of_birth
)
SELECT 
    patient_id,
    patient_name,
    current_age,
    total_admissions,
    num_readmissions,
    last_admission_date,
    TRUNC(CURRENT_DATE - last_admission_date) AS days_since_last_admission,
    avg_los,
    icu_admissions,
    num_chronic_conditions,
    lifetime_costs,
    -- Risk score calculation (0-100)
    ROUND(
        (CASE WHEN total_admissions > 5 THEN 20 ELSE total_admissions * 4 END) +
        (num_readmissions * 15) +
        (CASE WHEN current_age > 75 THEN 15 WHEN current_age > 65 THEN 10 ELSE 5 END) +
        (icu_admissions * 10) +
        (num_chronic_conditions * 5) +
        (CASE WHEN avg_los > 10 THEN 15 WHEN avg_los > 5 THEN 10 ELSE 5 END)
    , 0) AS risk_score
FROM patient_metrics
WHERE total_admissions > 0
ORDER BY risk_score DESC;

-- ============================================================================
-- SECTION 7: OPERATIONAL EFFICIENCY
-- ============================================================================

-- 7.1 Bed Turnover and Capacity Planning
CREATE OR REPLACE VIEW v_capacity_metrics AS
SELECT 
    h.hospital_name,
    d.department_name,
    d.total_beds,
    COUNT(DISTINCT a.admission_id) AS total_admissions_ytd,
    ROUND(AVG(a.length_of_stay_days), 2) AS avg_los,
    ROUND(SUM(a.length_of_stay_days) / (d.total_beds * 365) * 100, 2) AS occupancy_rate,
    ROUND(COUNT(DISTINCT a.admission_id) / d.total_beds, 2) AS bed_turnover_ratio,
    -- Available capacity projections
    ROUND(d.total_beds * (1 - (SUM(a.length_of_stay_days) / (d.total_beds * 365))), 1) AS avg_available_beds,
    ROUND((d.total_beds * 365 - SUM(a.length_of_stay_days)) / 
          NULLIF(AVG(a.length_of_stay_days), 0), 0) AS potential_additional_admissions
FROM hospitals h
JOIN departments d ON h.hospital_id = d.hospital_id
LEFT JOIN admissions a ON d.department_id = a.department_id
WHERE a.admission_date >= ADD_MONTHS(CURRENT_DATE, -12)
GROUP BY h.hospital_name, d.department_name, d.total_beds, d.department_id
ORDER BY occupancy_rate DESC;

-- Grant SELECT permissions on all views
GRANT SELECT ON v_hospital_kpis TO PUBLIC;
GRANT SELECT ON v_department_performance TO PUBLIC;
GRANT SELECT ON v_readmission_by_diagnosis TO PUBLIC;
GRANT SELECT ON v_readmission_risk_factors TO PUBLIC;
GRANT SELECT ON v_monthly_revenue TO PUBLIC;
GRANT SELECT ON v_payment_metrics TO PUBLIC;
GRANT SELECT ON v_los_analysis TO PUBLIC;
GRANT SELECT ON v_icu_metrics TO PUBLIC;
GRANT SELECT ON v_daily_admission_trends TO PUBLIC;
GRANT SELECT ON v_seasonal_patterns TO PUBLIC;
GRANT SELECT ON v_high_risk_patients TO PUBLIC;
GRANT SELECT ON v_capacity_metrics TO PUBLIC;