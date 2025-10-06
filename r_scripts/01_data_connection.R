# Load libraries
library(DBI)
library(ROracle)
library(dplyr)
library(tidyr)
library(lubridate)
library(readr)

# ============================================================================
# CONFIGURATION
# ============================================================================

# Set Oracle environment variables
Sys.setenv(TNS_ADMIN = "E:/healthcare-analytics/wallet")
Sys.setenv(ORACLE_HOME = "C:/Oracle/instantclient_19_14")

# Database configuration (UPDATE THESE WITH YOUR VALUES!)
db_config <- list(
  user = "Admin",
  password = "Siberia@14568",  # CHANGE THIS!
  dbname = "healthcaredb_high"  # From your wallet tnsnames.ora
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
    message("✗ Failed to connect to database: ", e$message)
    message("\nTroubleshooting:")
    message("1. Check TNS_ADMIN: ", Sys.getenv("TNS_ADMIN"))
    message("2. Check wallet files exist in: ", Sys.getenv("TNS_ADMIN"))
    message("3. Verify connection string in tnsnames.ora")
    message("4. Check username/password are correct")
    stop(e$message)
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
# TEST CONNECTION
# ============================================================================

cat("\n")
cat("==================================================\n")
cat("  TESTING ORACLE CONNECTION                      \n")
cat("==================================================\n\n")

cat("Environment variables:\n")
cat("  TNS_ADMIN:", Sys.getenv("TNS_ADMIN"), "\n")
cat("  ORACLE_HOME:", Sys.getenv("ORACLE_HOME"), "\n\n")

# Test connection
cat("Attempting to connect to Oracle...\n")
con <- connect_to_oracle()

if (!is.null(con)) {
  # Test query
  test_query <- "SELECT 'Connection successful!' AS message, 
                       USER AS current_user, 
                       SYSDATE AS current_time 
                FROM DUAL"
  
  result <- execute_query(con, test_query)
  print(result)
  
  # Check tables
  tables_query <- "SELECT table_name FROM user_tables ORDER BY table_name"
  tables <- execute_query(con, tables_query)
  
  cat("\nAvailable tables:\n")
  print(tables)
  
  # Check row counts
  cat("\nRow counts:\n")
  for (table in tables$TABLE_NAME) {
    count <- dbGetQuery(con, paste0("SELECT COUNT(*) as cnt FROM ", table))
    cat(sprintf("  %-25s: %d rows\n", table, count$CNT))
  }
  
  disconnect_oracle(con)
}

cat("\n==================================================\n")
cat("  CONNECTION TEST COMPLETE                        \n")
cat("==================================================\n")