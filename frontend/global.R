# Load libraries
library(shiny)
library(shinythemes)
library(shinyalert)
library(spsComps)
library(DT)
library(jsonlite)

HAS_SHINYWIDGETS <- requireNamespace("shinyWidgets", quietly = TRUE)
if (HAS_SHINYWIDGETS) {
  library(shinyWidgets)
}


SERVER_CONFIG_FILE <- "server_config.json"
RUN_STATS_FILE <- "run_stats.tsv"
APP_DIR <- normalizePath(
  if (file.exists(SERVER_CONFIG_FILE)) "." else "frontend",
  winslash = "/",
  mustWork = TRUE
)
SERVER_CONFIG_FILE <- file.path(APP_DIR, SERVER_CONFIG_FILE)
RUN_STATS_FILE <- file.path(APP_DIR, RUN_STATS_FILE)

format_duration_compact <- function(total_seconds) {
  total_seconds <- as.numeric(total_seconds)
  if (is.na(total_seconds) || total_seconds < 0) {
    return("not available")
  }

  hours <- total_seconds %/% 3600
  minutes <- (total_seconds %% 3600) %/% 60

  if (hours > 0) {
    sprintf("%d hours and %d minutes", hours, minutes)
  } else {
    sprintf("%d minutes", minutes)
  }
}

read_run_stats <- function() {
  if (!file.exists(RUN_STATS_FILE)) {
    return(data.frame())
  }

  tryCatch(
    read.table(RUN_STATS_FILE, sep = "\t", header = TRUE, stringsAsFactors = FALSE, check.names = FALSE),
    error = function(...) data.frame()
  )
}

append_run_stat <- function(run_stat) {
  if (!is.data.frame(run_stat) || nrow(run_stat) != 1) {
    stop("append_run_stat expects a one-row data.frame", call. = FALSE)
  }

  write.table(
    run_stat,
    file = RUN_STATS_FILE,
    sep = "\t",
    quote = TRUE,
    row.names = FALSE,
    col.names = !file.exists(RUN_STATS_FILE),
    append = file.exists(RUN_STATS_FILE)
  )
}

compute_run_metrics <- function(
  run_stats,
  input_bytes = NA_real_,
  manual_minutes_per_dataset = 6,
  manual_minutes_per_100mb = 29
) {
  if (!is.data.frame(run_stats) || nrow(run_stats) == 0) {
    return(list(
      dataset_count = 0,
      total_time_saved_sec = 0,
      estimated_runtime_sec = NA_real_,
      has_runtime_model = FALSE
    ))
  }

  completed_mask <- rep(TRUE, nrow(run_stats))
  if ("status" %in% names(run_stats)) {
    completed_mask <- tolower(trimws(as.character(run_stats$status))) == "completed"
  }

  completed_runs <- run_stats[completed_mask, , drop = FALSE]
  dataset_count <- nrow(completed_runs)
  valid_saved_size <- suppressWarnings(as.numeric(completed_runs$input_bytes))
  saved_size_keep <- is.finite(valid_saved_size) & valid_saved_size > 0
  manual_seconds_per_byte <- (manual_minutes_per_100mb * 60) / (100 * 1024 * 1024)
  total_time_saved_sec <- sum(valid_saved_size[saved_size_keep] * manual_seconds_per_byte, na.rm = TRUE)

  if (!any(saved_size_keep)) {
    total_time_saved_sec <- dataset_count * manual_minutes_per_dataset * 60
  }

  if (dataset_count == 0) {
    return(list(
      dataset_count = 0,
      total_time_saved_sec = 0,
      estimated_runtime_sec = NA_real_,
      has_runtime_model = FALSE
    ))
  }

  valid_runtime <- suppressWarnings(as.numeric(completed_runs$runtime_sec))
  valid_size <- suppressWarnings(as.numeric(completed_runs$input_bytes))
  keep <- is.finite(valid_runtime) & valid_runtime > 0 & is.finite(valid_size) & valid_size > 0

  if (!any(keep)) {
    estimated_runtime_sec <- mean(valid_runtime[is.finite(valid_runtime) & valid_runtime > 0], na.rm = TRUE)
    if (is.nan(estimated_runtime_sec)) {
      estimated_runtime_sec <- NA_real_
    }
    return(list(
      dataset_count = dataset_count,
      total_time_saved_sec = total_time_saved_sec,
      estimated_runtime_sec = estimated_runtime_sec,
      has_runtime_model = FALSE
    ))
  }

  seconds_per_mb <- sum(valid_runtime[keep], na.rm = TRUE) / sum(valid_size[keep] / (1024 * 1024), na.rm = TRUE)
  target_input_bytes <- suppressWarnings(as.numeric(input_bytes))
  if (is.na(target_input_bytes) || !is.finite(target_input_bytes) || target_input_bytes <= 0) {
    typical_size_mb <- median(valid_size[keep] / (1024 * 1024), na.rm = TRUE)
  } else {
    typical_size_mb <- target_input_bytes / (1024 * 1024)
  }
  estimated_runtime_sec <- seconds_per_mb * typical_size_mb

  list(
    dataset_count = dataset_count,
    total_time_saved_sec = total_time_saved_sec,
    estimated_runtime_sec = estimated_runtime_sec,
    has_runtime_model = TRUE
  )
}

get_storage_entry <- function(config, server_name) {
  entry <- config$storage_server[[server_name]]

  if (is.null(entry)) {
    return(NULL)
  }

  if (is.character(entry)) {
    return(list(
      rawdata_path = unname(entry),
      results_path = sub("rawdata/?$", "results/", unname(entry))
    ))
  }

  entry
}

get_storage_value <- function(config, server_name, field_name) {
  entry <- get_storage_entry(config, server_name)

  if (is.null(entry)) {
    return(NA_character_)
  }

  value <- entry[[field_name]]
  if (is.null(value) || identical(value, "")) {
    return(NA_character_)
  }

  unname(value)
}

get_cluster_value <- function(config, field_name) {
  value <- config$cluster[[field_name]]

  if (is.null(value) || identical(value, "")) {
    return(NA_character_)
  }

  unname(as.character(value))
}

get_cluster_value_or <- function(config, field_name, fallback) {
  value <- get_cluster_value(config, field_name)
  if (is.na(value) || identical(value, "")) {
    return(fallback)
  }
  value
}

app_script <- function(script_name) {
  file.path(APP_DIR, "scripts", script_name)
}

app_path <- function(...) {
  file.path(APP_DIR, ...)
}

app_radio_buttons <- function(inputId, label, choices = NULL, selected = NULL, ...) {
  if (HAS_SHINYWIDGETS) {
    shinyWidgets::prettyRadioButtons(inputId, label, choices = choices, selected = selected, ...)
  } else {
    shiny::radioButtons(inputId, label, choices = choices, selected = selected)
  }
}

app_update_radio_buttons <- function(session, inputId, choices = NULL, selected = NULL) {
  if (HAS_SHINYWIDGETS) {
    shinyWidgets::updatePrettyRadioButtons(session, inputId = inputId, choices = choices, selected = selected)
  } else {
    shiny::updateRadioButtons(session, inputId = inputId, choices = choices, selected = selected)
  }
}

app_picker_input <- function(inputId, label, choices = NULL, selected = NULL, options = NULL, ...) {
  if (HAS_SHINYWIDGETS) {
    shinyWidgets::pickerInput(inputId, label, choices = choices, selected = selected, options = options, ...)
  } else {
    shiny::selectInput(inputId, label, choices = choices, selected = selected, selectize = TRUE)
  }
}

app_update_picker_input <- function(session, inputId, choices = NULL, selected = NULL) {
  if (HAS_SHINYWIDGETS) {
    shinyWidgets::updatePickerInput(session, inputId = inputId, choices = choices, selected = selected)
  } else {
    shiny::updateSelectInput(session, inputId = inputId, choices = choices, selected = selected)
  }
}

app_switch_input <- function(inputId, label, value = FALSE, ...) {
  shiny::checkboxInput(inputId, label, value)
}

app_action_button <- function(inputId, label, ...) {
  if (HAS_SHINYWIDGETS) {
    shinyWidgets::actionBttn(inputId, label, ...)
  } else {
    shiny::actionButton(inputId, label)
  }
}

# Read JSON file and extract server names
servers_config <- fromJSON(SERVER_CONFIG_FILE, simplifyVector = FALSE)

# Extract server names
server_names <- names(servers_config$storage_server)

igblast_species_choices <- c(
  "Human" = "human",
  "Mouse" = "mouse"
)

igblast_panel_choices <- c(
  "Immunoglobulin heavy chain only (IgH)" = "igh",
  "Immunoglobulin light chains only (IgK + IgL)" = "ig_light",
  "All immunoglobulins (IgH + IgK + IgL)" = "ig_all",
  "TCR alpha only (TRA)" = "tra",
  "TCR beta only (TRB)" = "trb",
  "All TCR (TRA + TRB + TRD + TRG)" = "tcr_all",
  "All TCR and immunoglobulins" = "all_receptors"
)
