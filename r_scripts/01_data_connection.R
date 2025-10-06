# ============================================================================
# HEALTHCARE ANALYTICS - R ORACLE CONNECTION
# File: 01_data_connection.R
# Purpose: Connect to Oracle ADB and load data for analysis
# ============================================================================

# Install required packages (run once)
install_packages <- function() {
  packages <- c(
    "DBI",           # Database interface
    "dplyr",         # Data manipulation
    "tidyr",         # Data tidying
    "lubridate",     # Date handling
    "readr",         # Reading files
    "config",        # Configuration management
    "dotenv"         # Environment variables
  )
  
  new_packages <- packages[!(packages %in% installed.packages()[,"Package"])]
  if(length(new_packages)) install.packages(new_packages)
  
  # Load all packages
  lapply(packages, library, character.only = TRUE)
}

# Uncomment to install packages
install_packages()

# Load libraries
library(DBI)
library(ROracle)
library(dplyr)
library(tidyr)
library(lubridate)
library(readr)
library(dotenv)

# ============================================================================
# CONFIGURATION
# ============================================================================

# Load environment variables
load_dot_env()

# Database configuration
db_config <- list(
  lib_dir =Sys.getenv('ORACLE_CLIENT_LIB'),
  config_dir = Sys.getenv('WALLET_LOCATION'),
  user = Sys.getenv("DB_USER"),
  password = Sys.getenv("DB_PASSWORD"),
  dbname = Sys.getenv("DB_DSN")
)

# ============================================================================
# DATABASE CONNECTION FUNCTIONS
# ============================================================================

#' Connect to Oracle Autonomous Database
#' @return DBI connection object
connect_to_oracle <- function() {
  tryCatch({
    # Create Oracle driver
    drv <- dbDriver("Oracle")
    
    # Establish connection
    con <- dbConnect(
      drv,
      username = db_config$user,
      password = db_config$password,
      dbname = db_config$dbname
    )
    
    message("✓ Successfully connected to Oracle Database!")
    return(con)
    
  }, error = function(e) {
    stop(paste("✗ Failed to connect to database:", e$message))
  })
}

#' Disconnect from database
#' @param con Database connection object
disconnect_oracle <- function(con) {
  if (!is.null(con)) {
    dbDisconnect(con)
    message("✓ Disconnected from Oracle Database")
  }
}

#' Execute query and return results as data frame
#' @param con Database connection
#' @param query SQL query string
#' @return Data frame with query results
execute_query <- function(con, query) {
  tryCatch({
    result <- dbGetQuery(con, query)
    message(paste("✓ Query executed successfully. Rows returned:", nrow(result)))
    return(result)
  }, error = function(e) {
    stop(paste("✗ Query execution failed:", e$message))
  })
}

#' Load table into R data frame
#' @param con Database connection
#' @param table_name Name of the table
#' @return Data frame
load_table <- function(con, table_name) {
  query <- paste0("SELECT * FROM ", table_name)
  return(execute_query(con, query))
}

# ============================================================================
# DATA LOADING FUNCTIONS
# ============================================================================

#' Load all core tables
#' @param con Database connection
#' @return List of data frames
load_all_data <- function(con) {
  message("Loading all tables from database...")
  
  data_list <- list(
    patients = load_table(con, "patients"),
    hospitals = load_table(con, "hospitals"),
    departments = load_table(con, "departments"),
    medical_conditions = load_table(con, "medical_conditions"),
    admissions = load_table(con, "admissions"),
    patient_procedures = load_table(con, "patient_procedures"),
    procedures = load_table(con, "procedures"),
    patient_medications = load_table(con, "patient_medications"),
    medications = load_table(con, "medications"),
    lab_results = load_table(con, "lab_results"),
    billing = load_table(con, "billing")
  )
  
  message(paste("✓ Loaded", length(data_list), "tables"))
  
  # Print summary
  cat("\n=== DATA SUMMARY ===\n")
  for (name in names(data_list)) {
    cat(sprintf("%-25s: %d rows, %d columns\n", 
                name, nrow(data_list[[name]]), ncol(data_list[[name]])))
  }
  
  return(data_list)
}

#' Load analytical views
#' @param con Database connection
#' @return List of data frames
load_analytical_views <- function(con) {
  message("Loading analytical views...")
  
  views <- list(
    hospital_kpis = execute_query(con, "SELECT * FROM v_hospital_kpis"),
    dept_performance = execute_query(con, "SELECT * FROM v_department_performance"),
    readmission_by_dx = execute_query(con, "SELECT * FROM v_readmission_by_diagnosis"),
    monthly_revenue = execute_query(con, "SELECT * FROM v_monthly_revenue"),
    high_risk_patients = execute_query(con, "SELECT * FROM v_high_risk_patients"),
    capacity_metrics = execute_query(con, "SELECT * FROM v_capacity_metrics")
  )
  
  message(paste("✓ Loaded", length(views), "analytical views"))
  return(views)
}

#' Create modeling dataset with features
#' @param con Database connection
#' @return Data frame ready for modeling
create_modeling_dataset <- function(con) {
  message("Creating modeling dataset with engineered features...")
  
  query <- "
  SELECT 
    a.admission_id,
    a.patient_id,
    a.hospital_id,
    a.department_id,
    a.admission_date,
    a.discharge_date,
    a.admission_type,
    a.length_of_stay_days,
    a.patient_age_at_admission,
    a.readmission_flag,
    a.readmission_within_30days AS target,
    a.icu_stay_flag,
    a.icu_days,
    a.mortality_flag,
    -- Patient demographics
    p.gender,
    p.blood_type,
    p.insurance_provider,
    -- Diagnosis information
    mc.condition_name,
    mc.category AS diagnosis_category,
    mc.severity_level,
    -- Hospital characteristics
    h.hospital_type,
    h.total_beds AS hospital_size,
    -- Department info
    d.department_name,
    d.department_type,
    -- Billing information
    b.total_charges,
    b.insurance_covered,
    b.patient_responsibility,
    -- Aggregate features
    (SELECT COUNT(*) FROM patient_procedures pp WHERE pp.admission_id = a.admission_id) AS num_procedures,
    (SELECT COUNT(*) FROM patient_medications pm WHERE pm.admission_id = a.admission_id) AS num_medications,
    (SELECT COUNT(*) FROM lab_results lr WHERE lr.admission_id = a.admission_id) AS num_lab_tests,
    (SELECT COUNT(*) FROM lab_results lr WHERE lr.admission_id = a.admission_id AND lr.abnormal_flag != 'Normal') AS num_abnormal_labs,
    -- Patient history
    (SELECT COUNT(*) FROM admissions a2 WHERE a2.patient_id = a.patient_id AND a2.admission_date < a.admission_date) AS prior_admissions,
    (SELECT COUNT(*) FROM patient_medical_history pmh WHERE pmh.patient_id = a.patient_id AND pmh.status = 'Chronic') AS num_chronic_conditions
  FROM admissions a
  LEFT JOIN patients p ON a.patient_id = p.patient_id
  LEFT JOIN medical_conditions mc ON a.primary_diagnosis_id = mc.condition_id
  LEFT JOIN hospitals h ON a.hospital_id = h.hospital_id
  LEFT JOIN departments d ON a.department_id = d.department_id
  LEFT JOIN billing b ON a.admission_id = b.admission_id
  WHERE a.admission_date >= ADD_MONTHS(CURRENT_DATE, -24)
  "
  
  modeling_data <- execute_query(con, query)
  
  message(paste("✓ Modeling dataset created with", nrow(modeling_data), "records"))
  
  return(modeling_data)
}

# ============================================================================
# DATA PREPROCESSING FUNCTIONS
# ============================================================================

#' Clean and preprocess data for modeling
#' @param data Raw modeling dataset
#' @return Cleaned data frame
preprocess_data <- function(data) {
  message("Preprocessing data...")
  
  data_clean <- data %>%
    # Convert date columns
    mutate(
      admission_date = as.Date(admission_date),
      discharge_date = as.Date(discharge_date),
      day_of_week = wday(admission_date, label = TRUE),
      month = month(admission_date, label = TRUE),
      is_weekend = wday(admission_date) %in% c(1, 7),
      season = case_when(
        month(admission_date) %in% c(12, 1, 2) ~ "Winter",
        month(admission_date) %in% c(3, 4, 5) ~ "Spring",
        month(admission_date) %in% c(6, 7, 8) ~ "Summer",
        month(admission_date) %in% c(9, 10, 11) ~ "Fall"
      )
    ) %>%
    # Handle missing values
    mutate(
      icu_days = replace_na(icu_days, 0),
      num_procedures = replace_na(num_procedures, 0),
      num_medications = replace_na(num_medications, 0),
      num_lab_tests = replace_na(num_lab_tests, 0),
      num_abnormal_labs = replace_na(num_abnormal_labs, 0),
      prior_admissions = replace_na(prior_admissions, 0),
      num_chronic_conditions = replace_na(num_chronic_conditions, 0)
    ) %>%
    # Create derived features
    mutate(
      age_group = cut(patient_age_at_admission, 
                     breaks = c(0, 40, 60, 75, 100),
                     labels = c("18-39", "40-59", "60-74", "75+"),
                     include.lowest = TRUE),
      los_category = cut(length_of_stay_days,
                        breaks = c(0, 3, 7, 14, 100),
                        labels = c("Short", "Medium", "Long", "Extended"),
                        include.lowest = TRUE),
      cost_per_day = total_charges / pmax(length_of_stay_days, 1),
      high_cost = ifelse(total_charges > quantile(total_charges, 0.75, na.rm = TRUE), 1, 0),
      complex_case = ifelse(num_procedures >= 3 | num_medications >= 5 | icu_stay_flag == 1, 1, 0),
      abnormal_lab_rate = num_abnormal_labs / pmax(num_lab_tests, 1)
    ) %>%
    # Convert character columns to factors
    mutate(across(where(is.character), as.factor))
  
  # Remove rows with missing target variable
  data_clean <- data_clean %>%
    filter(!is.na(target))
  
  message(paste("✓ Preprocessing complete.", nrow(data_clean), "records retained"))
  
  # Check for remaining missing values
  missing_summary <- data_clean %>%
    summarise(across(everything(), ~sum(is.na(.)))) %>%
    pivot_longer(everything(), names_to = "column", values_to = "missing_count") %>%
    filter(missing_count > 0)
  
  if (nrow(missing_summary) > 0) {
    message("\nWarning: Missing values detected:")
    print(missing_summary)
  }
  
  return(data_clean)
}

#' Split data into train and test sets
#' @param data Data frame to split
#' @param train_ratio Proportion for training (default 0.7)
#' @param seed Random seed for reproducibility
#' @return List with train and test data frames
train_test_split <- function(data, train_ratio = 0.7, seed = 42) {
  set.seed(seed)
  
  # Stratified split based on target variable
  train_indices <- data %>%
    group_by(target) %>%
    sample_frac(train_ratio) %>%
    pull(admission_id)
  
  train_data <- data %>% filter(admission_id %in% train_indices)
  test_data <- data %>% filter(!(admission_id %in% train_indices))
  
  message(paste("✓ Data split complete:"))
  message(paste("  Training set:", nrow(train_data), "records"))
  message(paste("  Test set:", nrow(test_data), "records"))
  message(paste("  Training readmission rate:", 
                round(mean(train_data$target) * 100, 2), "%"))
  message(paste("  Test readmission rate:", 
                round(mean(test_data$target) * 100, 2), "%"))
  
  return(list(train = train_data, test = test_data))
}

# ============================================================================
# EXPORT FUNCTIONS
# ============================================================================

#' Export data to CSV files
#' @param data_list List of data frames
#' @param output_dir Directory to save files
export_to_csv <- function(data_list, output_dir = "data") {
  # Create directory if it doesn't exist
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  message(paste("Exporting data to", output_dir))
  
  for (name in names(data_list)) {
    file_path <- file.path(output_dir, paste0(name, ".csv"))
    write_csv(data_list[[name]], file_path)
    message(paste("✓ Exported:", file_path))
  }
  
  message("✓ All data exported successfully")
}

#' Save R objects for later use
#' @param obj Object to save
#' @param name Name for the saved file
#' @param output_dir Directory to save files
save_rds <- function(obj, name, output_dir = "data") {
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  file_path <- file.path(output_dir, paste0(name, ".rds"))
  saveRDS(obj, file_path)
  message(paste("✓ Saved:", file_path))
}

# ============================================================================
# MAIN EXECUTION EXAMPLE
# ============================================================================

main <- function() {
  cat("\n")
  cat("==================================================\n")
  cat("  HEALTHCARE ANALYTICS - DATA LOADING PIPELINE   \n")
  cat("==================================================\n\n")
  
  # Connect to database
  con <- connect_to_oracle()
  
  # Load all data
  all_data <- load_all_data(con)
  
  # Load analytical views
  views <- load_analytical_views(con)
  
  # Create modeling dataset
  modeling_data <- create_modeling_dataset(con)
  
  # Preprocess data
  modeling_data_clean <- preprocess_data(modeling_data)
  
  # Split data
  data_split <- train_test_split(modeling_data_clean)
  
  # Export to CSV (optional backup)
  export_to_csv(all_data, "data/raw")
  export_to_csv(views, "data/views")
  
  # Save preprocessed data
  save_rds(modeling_data_clean, "modeling_data_clean", "data/processed")
  save_rds(data_split$train, "train_data", "data/processed")
  save_rds(data_split$test, "test_data", "data/processed")
  
  # Disconnect
  disconnect_oracle(con)
  
  cat("\n")
  cat("==================================================\n")
  cat("  DATA LOADING COMPLETE                          \n")
  cat("==================================================\n")
  
  # Return data for interactive use
  return(list(
    raw_data = all_data,
    views = views,
    modeling_data = modeling_data_clean,
    train = data_split$train,
    test = data_split$test
  ))
}

# Uncomment to run
healthcare_data <- main()