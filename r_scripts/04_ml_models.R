# ============================================================================
# HEALTHCARE ANALYTICS - MACHINE LEARNING MODELS
# File: 04_ml_models.R
# Purpose: Build and evaluate readmission prediction models
# ============================================================================

# Load required libraries
library(dplyr)
library(tidyr)
library(caret)
library(randomForest)
library(xgboost)
library(pROC)
library(ROSE)
library(ggplot2)
library(gridExtra)

# For SHAP values (explainability)
# install.packages("SHAPforxgboost")
library(SHAPforxgboost)

# ============================================================================
# LOAD DATA
# ============================================================================

# Load preprocessed data
train_data <- readRDS("data/processed/train_data.rds")
test_data <- readRDS("data/processed/test_data.rds")

cat("Training data:", nrow(train_data), "records\n")
cat("Test data:", nrow(test_data), "records\n")
cat("Readmission rate (train):", round(mean(train_data$target) * 100, 2), "%\n")
cat("Readmission rate (test):", round(mean(test_data$target) * 100, 2), "%\n")

# ============================================================================
# FEATURE SELECTION
# ============================================================================

# Define features for modeling
feature_cols <- c(
  # Demographics
  "patient_age_at_admission", "gender", "insurance_provider",
  
  # Admission characteristics
  "admission_type", "length_of_stay_days", "icu_stay_flag", "icu_days",
  
  # Diagnosis
  "diagnosis_category", "severity_level",
  
  # Hospital/Department
  "hospital_type", "department_type", "hospital_size",
  
  # Clinical complexity
  "num_procedures", "num_medications", "num_lab_tests", 
  "num_abnormal_labs", "abnormal_lab_rate",
  
  # Patient history
  "prior_admissions", "num_chronic_conditions",
  
  # Temporal features
  "day_of_week", "month", "is_weekend", "season",
  
  # Financial
  "total_charges", "cost_per_day", "high_cost",
  
  # Derived features
  "age_group", "los_category", "complex_case"
)

# Prepare data for modeling
prepare_model_data <- function(data, feature_cols) {
  # Select features and target
  model_data <- data %>%
    select(all_of(c(feature_cols, "target", "admission_id")))
  
  # Convert target to factor
  model_data$target <- factor(model_data$target, 
                              levels = c(0, 1), 
                              labels = c("No_Readmission", "Readmission"))
  
  # Handle any remaining missing values
  numeric_cols <- sapply(model_data, is.numeric)
  model_data[, numeric_cols] <- lapply(model_data[, numeric_cols], 
                                       function(x) ifelse(is.na(x), median(x, na.rm = TRUE), x))
  
  return(model_data)
}

train_prepared <- prepare_model_data(train_data, feature_cols)
test_prepared <- prepare_model_data(test_data, feature_cols)

# ============================================================================
# HANDLE CLASS IMBALANCE
# ============================================================================

cat("\nClass distribution before balancing:\n")
print(table(train_prepared$target))

# SMOTE (Synthetic Minority Over-sampling Technique)
set.seed(42)
train_balanced <- ROSE(target ~ . - admission_id, 
                       data = train_prepared, 
                       seed = 42)$data

cat("\nClass distribution after SMOTE:\n")
print(table(train_balanced$target))

# ============================================================================
# MODEL 1: LOGISTIC REGRESSION (BASELINE)
# ============================================================================

cat("\n=== TRAINING LOGISTIC REGRESSION ===\n")

# Train model
logistic_model <- glm(
  target ~ . - admission_id, 
  data = train_balanced, 
  family = "binomial"
)

# Predictions
logistic_pred_train <- predict(logistic_model, train_prepared, type = "response")
logistic_pred_test <- predict(logistic_model, test_prepared, type = "response")

# Convert to class predictions
logistic_class_test <- ifelse(logistic_pred_test > 0.5, "Readmission", "No_Readmission")
logistic_class_test <- factor(logistic_class_test, levels = levels(test_prepared$target))

# Evaluate
logistic_cm <- confusionMatrix(logistic_class_test, test_prepared$target, positive = "Readmission")
logistic_roc <- roc(test_prepared$target, logistic_pred_test)

cat("\nLogistic Regression Performance:\n")
print(logistic_cm$overall)
print(logistic_cm$byClass)
cat("AUC:", round(auc(logistic_roc), 4), "\n")

# ============================================================================
# MODEL 2: RANDOM FOREST
# ============================================================================

cat("\n=== TRAINING RANDOM FOREST ===\n")

# Set up cross-validation
ctrl <- trainControl(
  method = "cv",
  number = 5,
  classProbs = TRUE,
  summaryFunction = twoClassSummary,
  savePredictions = TRUE
)

# Train Random Forest
set.seed(42)
rf_model <- train(
  target ~ . - admission_id,
  data = train_balanced,
  method = "rf",
  trControl = ctrl,
  metric = "ROC",
  ntree = 300,
  importance = TRUE,
  tuneGrid = expand.grid(mtry = c(5, 7, 10))
)

cat("\nBest tuning parameters:\n")
print(rf_model$bestTune)

# Predictions
rf_pred_test <- predict(rf_model, test_prepared, type = "prob")[, "Readmission"]
rf_class_test <- predict(rf_model, test_prepared)

# Evaluate
rf_cm <- confusionMatrix(rf_class_test, test_prepared$target, positive = "Readmission")
rf_roc <- roc(test_prepared$target, rf_pred_test)

cat("\nRandom Forest Performance:\n")
print(rf_cm$overall)
print(rf_cm$byClass)
cat("AUC:", round(auc(rf_roc), 4), "\n")

# Feature importance
rf_importance <- varImp(rf_model)
cat("\nTop 10 Most Important Features:\n")
print(head(rf_importance$importance, 10))

# ============================================================================
# MODEL 3: XGBOOST (BEST PERFORMANCE)
# ============================================================================

cat("\n=== TRAINING XGBOOST ===\n")

# Prepare data for XGBoost
prepare_xgb_data <- function(data, feature_cols) {
  # Create model matrix (handles factors automatically)
  X <- model.matrix(target ~ . - admission_id, data = data)[, -1]
  y <- as.numeric(data$target) - 1  # Convert to 0/1
  return(list(X = X, y = y))
}

train_xgb <- prepare_xgb_data(train_balanced, feature_cols)
test_xgb <- prepare_xgb_data(test_prepared, feature_cols)

# Create DMatrix objects
dtrain <- xgb.DMatrix(data = train_xgb$X, label = train_xgb$y)
dtest <- xgb.DMatrix(data = test_xgb$X, label = test_xgb$y)

# Set parameters
params <- list(
  objective = "binary:logistic",
  eval_metric = "auc",
  max_depth = 6,
  eta = 0.1,
  subsample = 0.8,
  colsample_bytree = 0.8,
  min_child_weight = 1
)

# Train with cross-validation
set.seed(42)
xgb_cv <- xgb.cv(
  params = params,
  data = dtrain,
  nrounds = 500,
  nfold = 5,
  early_stopping_rounds = 20,
  verbose = FALSE,
  print_every_n = 50
)

best_iteration <- xgb_cv$best_iteration
cat("\nBest iteration:", best_iteration, "\n")

# Train final model
xgb_model <- xgb.train(
  params = params,
  data = dtrain,
  nrounds = best_iteration,
  watchlist = list(train = dtrain, test = dtest),
  verbose = FALSE
)

# Predictions
xgb_pred_test <- predict(xgb_model, dtest)
xgb_class_test <- ifelse(xgb_pred_test > 0.5, "Readmission", "No_Readmission")
xgb_class_test <- factor(xgb_class_test, levels = levels(test_prepared$target))

# Evaluate
xgb_cm <- confusionMatrix(xgb_class_test, test_prepared$target, positive = "Readmission")
xgb_roc <- roc(test_prepared$target, xgb_pred_test)

cat("\nXGBoost Performance:\n")
print(xgb_cm$overall)
print(xgb_cm$byClass)
cat("AUC:", round(auc(xgb_roc), 4), "\n")

# Feature importance
xgb_importance <- xgb.importance(model = xgb_model)
cat("\nTop 10 Most Important Features:\n")
print(head(xgb_importance, 10))

# ============================================================================
# MODEL COMPARISON
# ============================================================================

compare_models <- function() {
  comparison <- data.frame(
    Model = c("Logistic Regression", "Random Forest", "XGBoost"),
    Accuracy = c(logistic_cm$overall["Accuracy"], 
                rf_cm$overall["Accuracy"], 
                xgb_cm$overall["Accuracy"]),
    Sensitivity = c(logistic_cm$byClass["Sensitivity"], 
                   rf_cm$byClass["Sensitivity"], 
                   xgb_cm$byClass["Sensitivity"]),
    Specificity = c(logistic_cm$byClass["Specificity"], 
                   rf_cm$byClass["Specificity"], 
                   xgb_cm$byClass["Specificity"]),
    Precision = c(logistic_cm$byClass["Pos Pred Value"], 
                 rf_cm$byClass["Pos Pred Value"], 
                 xgb_cm$byClass["Pos Pred Value"]),
    F1_Score = c(logistic_cm$byClass["F1"], 
                rf_cm$byClass["F1"], 
                xgb_cm$byClass["F1"]),
    AUC = c(auc(logistic_roc), auc(rf_roc), auc(xgb_roc))
  )
  
  # Round numeric columns
  comparison[, 2:7] <- round(comparison[, 2:7], 4)
  
  return(comparison)
}

model_comparison <- compare_models()
cat("\n=== MODEL COMPARISON ===\n")
print(model_comparison)

# Identify best model
best_model_idx <- which.max(model_comparison$AUC)
best_model_name <- model_comparison$Model[best_model_idx]
cat("\nBest Model:", best_model_name, "\n")

# ============================================================================
# ROC CURVE COMPARISON
# ============================================================================

plot_roc_comparison <- function() {
  # Plot ROC curves
  plot(logistic_roc, col = "blue", main = "ROC Curve Comparison", 
       lwd = 2, legacy.axes = TRUE)
  plot(rf_roc, col = "green", add = TRUE, lwd = 2)
  plot(xgb_roc, col = "red", add = TRUE, lwd = 2)
  
  legend("bottomright", 
         legend = c(
           paste("Logistic Regression (AUC =", round(auc(logistic_roc), 3), ")"),
           paste("Random Forest (AUC =", round(auc(rf_roc), 3), ")"),
           paste("XGBoost (AUC =", round(auc(xgb_roc), 3), ")")
         ),
         col = c("blue", "green", "red"),
         lwd = 2)
}

# Save plot
png("models/roc_comparison.png", width = 800, height = 600)
plot_roc_comparison()
dev.off()

cat("\n✓ ROC curve saved to models/roc_comparison.png\n")

# ============================================================================
# SHAP VALUES FOR MODEL EXPLAINABILITY
# ============================================================================

cat("\n=== CALCULATING SHAP VALUES ===\n")

# Calculate SHAP values for XGBoost
shap_values <- shap.values(xgb_model = xgb_model, X_train = train_xgb$X)
shap_long <- shap.prep(shap_contrib = shap_values$shap_score, X_train = train_xgb$X)

# SHAP summary plot
png("models/shap_summary.png", width = 1000, height = 800)
shap.plot.summary(shap_long)
dev.off()

cat("✓ SHAP summary plot saved to models/shap_summary.png\n")

# ============================================================================
# SAVE MODELS
# ============================================================================

save_models <- function() {
  # Create models directory
  if (!dir.exists("models")) {
    dir.create("models", recursive = TRUE)
  }
  
  # Save R models
  saveRDS(logistic_model, "models/logistic_model.rds")
  saveRDS(rf_model, "models/rf_model.rds")
  xgb.save(xgb_model, "models/xgb_model.json")
  
  # Save model comparison
  write.csv(model_comparison, "models/model_comparison.csv", row.names = FALSE)
  
  # Save feature importance
  write.csv(xgb_importance, "models/feature_importance.csv", row.names = FALSE)
  
  # Save metadata
  metadata <- list(
    training_date = Sys.Date(),
    train_size = nrow(train_prepared),
    test_size = nrow(test_prepared),
    best_model = best_model_name,
    best_auc = max(model_comparison$AUC),
    features_used = feature_cols,
    model_params = params
  )
  
  saveRDS(metadata, "models/model_metadata.rds")
  
  cat("\n✓ All models saved to models/ directory\n")
}

save_models()

# ============================================================================
# GENERATE PREDICTIONS FOR ALL ADMISSIONS
# ============================================================================

generate_risk_scores <- function() {
  cat("\n=== GENERATING RISK SCORES ===\n")
  
  # Load full dataset
  modeling_data <- readRDS("data/processed/modeling_data_clean.rds")
  
  # Prepare for prediction
  full_prepared <- prepare_model_data(modeling_data, feature_cols)
  full_xgb <- prepare_xgb_data(full_prepared, feature_cols)
  dfull <- xgb.DMatrix(data = full_xgb$X)
  
  # Generate predictions
  risk_scores <- predict(xgb_model, dfull)
  
  # Create risk score dataframe
  risk_df <- data.frame(
    admission_id = full_prepared$admission_id,
    risk_score = round(risk_scores, 4),
    risk_category = cut(risk_scores,
                       breaks = c(0, 0.25, 0.5, 0.75, 1),
                       labels = c("Low", "Medium", "High", "Very High"),
                       include.lowest = TRUE),
    actual_readmission = as.numeric(full_prepared$target) - 1
  )
  
  # Save risk scores
  write.csv(risk_df, "data/processed/risk_scores.csv", row.names = FALSE)
  
  cat("✓ Risk scores generated for", nrow(risk_df), "admissions\n")
  cat("Risk category distribution:\n")
  print(table(risk_df$risk_category))
  
  return(risk_df)
}

risk_scores <- generate_risk_scores()

# ============================================================================
# SUMMARY
# ============================================================================

cat("\n")
cat("==================================================\n")
cat("  MODEL TRAINING COMPLETE                        \n")
cat("==================================================\n")
cat("\nFiles Generated:\n")
cat("  - models/logistic_model.rds\n")
cat("  - models/rf_model.rds\n")
cat("  - models/xgb_model.json\n")
cat("  - models/model_comparison.csv\n")
cat("  - models/feature_importance.csv\n")
cat("  - models/model_metadata.rds\n")
cat("  - models/roc_comparison.png\n")
cat("  - models/shap_summary.png\n")
cat("  - data/processed/risk_scores.csv\n")
cat("\nBest Model:", best_model_name, "\n")
cat("Best AUC:", round(max(model_comparison$AUC), 4), "\n")
cat("==================================================\n")