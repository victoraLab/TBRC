# Keep server.R resilient to partial Shiny deploys where global.R might lag one
# version behind. The fallbacks below mirror the live helpers closely enough to
# keep the app usable until both files are in sync again.
if (!exists("APP_DIR")) {
  APP_DIR <- normalizePath(
    if (file.exists("server_config.json")) "." else "frontend",
    winslash = "/",
    mustWork = TRUE
  )
}

if (!exists("RUN_STATS_FILE")) {
  RUN_STATS_FILE <- file.path(APP_DIR, "run_stats.tsv")
}

if (!exists("format_duration_compact", mode = "function")) {
  format_duration_compact <- function(total_seconds) {
    total_seconds <- suppressWarnings(as.numeric(total_seconds))
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
}

if (!exists("read_run_stats", mode = "function")) {
  read_run_stats <- function() {
    if (!file.exists(RUN_STATS_FILE)) {
      return(data.frame())
    }

    tryCatch(
      read.table(RUN_STATS_FILE, sep = "\t", header = TRUE, stringsAsFactors = FALSE, check.names = FALSE),
      error = function(...) data.frame()
    )
  }
}

if (!exists("append_run_stat", mode = "function")) {
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
}

if (!exists("compute_run_metrics", mode = "function")) {
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

    list(
      dataset_count = dataset_count,
      total_time_saved_sec = total_time_saved_sec,
      estimated_runtime_sec = seconds_per_mb * typical_size_mb,
      has_runtime_model = TRUE
    )
  }
}

server <- function(input, output, session) {
  storage_server_transfer_mode <- reactive({
    selected_server <- input$server_name

    if (selected_server %in% server_names) {
      configured_mode <- get_storage_value(servers_config, selected_server, "transfer_mode")

      if (!is.na(configured_mode) && nzchar(configured_mode)) {
        return(configured_mode)
      }
    }

    "push"
  })

  known_users <- reactive({
    user_lookup <- character()

    sample_files <- character()
    runs_dir <- app_path("runs")
    if (dir.exists(runs_dir)) {
      # Accept both the current JSON handoff and legacy TSV metadata so older
      # runs still contribute user/email history.
      sample_files <- list.files(runs_dir, pattern = "^sample\\.(tsv|json)$", recursive = TRUE, full.names = TRUE)
    }

    for (sample_file in sample_files) {
      sample_data <- NULL

      if (grepl("\\.json$", sample_file, ignore.case = TRUE)) {
        sample_data <- tryCatch(
          jsonlite::fromJSON(sample_file, simplifyVector = TRUE),
          error = function(...) NULL
        )

        if (is.null(sample_data) || !all(c("user_id", "user_email") %in% names(sample_data))) {
          next
        }

        current_user <- trimws(as.character(sample_data$user_id[[1]]))
        current_email <- trimws(as.character(sample_data$user_email[[1]]))
      } else {
        sample_data <- tryCatch(
          read.table(sample_file, sep = "\t", header = TRUE, stringsAsFactors = FALSE, check.names = FALSE),
          error = function(...) NULL
        )

        if (is.null(sample_data) || !all(c("user_id", "user_email") %in% names(sample_data))) {
          next
        }

        if (nrow(sample_data) < 1) {
          next
        }

        current_user <- trimws(sample_data$user_id[[1]])
        current_email <- trimws(sample_data$user_email[[1]])
      }

      if (nzchar(current_user) && nzchar(current_email)) {
        user_lookup[current_user] <- current_email
      }
    }

    legacy_config <- app_path("..", "backend", "config", "config.yaml")
    if (file.exists(legacy_config)) {
      config_lines <- readLines(legacy_config, warn = FALSE)
      current_user <- NULL

      for (line in config_lines) {
        trimmed_line <- trimws(line)

        if (grepl("^user_id\\s*:\\s*", trimmed_line)) {
          current_user <- sub("^user_id\\s*:\\s*", "", trimmed_line)
        } else if (!is.null(current_user) && grepl("^user_email\\s*:\\s*", trimmed_line)) {
          current_email <- sub("^user_email\\s*:\\s*", "", trimmed_line)
          current_user <- trimws(current_user)
          current_email <- trimws(current_email)

          if (nzchar(current_user) && nzchar(current_email)) {
            user_lookup[current_user] <- current_email
          }

          current_user <- NULL
        }
      }
    }

    user_lookup
  })

  historical_run_count <- reactive({
    runs_dir <- app_path("runs")
    if (!dir.exists(runs_dir)) {
      return(0L)
    }

    sample_files <- list.files(runs_dir, pattern = "^sample\\.(json|tsv)$", recursive = TRUE, full.names = TRUE)
    length(unique(dirname(sample_files)))
  })
  
  storage_server_rawdata_path <- reactive({
    selected_server <- input$server_name
    if (selected_server %in% server_names) {
      return(get_storage_value(servers_config, selected_server, "rawdata_path"))
    }

    NA_character_
  })

  storage_server_results_path <- reactive({
    selected_server <- input$server_name
    if (selected_server %in% server_names) {
      return(get_storage_value(servers_config, selected_server, "results_path"))
    }

    NA_character_
  })

  current_run_name <- reactive({
    if (input$type_input == "Upload" && !is.null(input$input_files$name)) {
      uploaded_names <- input$input_files$name
      if (length(uploaded_names) >= 1) {
        r1_name <- uploaded_names[[1]]
        r2_name <- if (length(uploaded_names) >= 2) uploaded_names[[2]] else uploaded_names[[1]]
        base1 <- sub("\\.fastq(\\.gz)?$", "", r1_name, ignore.case = TRUE)
        base2 <- sub("\\.fastq(\\.gz)?$", "", r2_name, ignore.case = TRUE)
        for (pattern in c("([_\\.-])R1([_\\.-]|$)", "([_\\.-])R2([_\\.-]|$)", "([_\\.-])001([_\\.-]|$)", "([_\\.-])S\\d+([_\\.-]|$)", "([_\\.-])L\\d{3}([_\\.-]|$)")) {
          base1 <- gsub(pattern, "\\1", base1, ignore.case = TRUE)
          base2 <- gsub(pattern, "\\1", base2, ignore.case = TRUE)
        }
        base1 <- gsub("[_\\.-]+$", "", base1)
        base2 <- gsub("[_\\.-]+$", "", base2)
        if (nzchar(base1) && identical(base1, base2)) {
          return(base1)
        }
        return(sub("\\.gz$", "", uploaded_names[[1]], ignore.case = TRUE))
      }
    }

    basename(trimws(input$input_folder))
  })

  classify_uploaded_read <- function(file_name) {
    if (grepl("(^|[_\\.-])R1([_\\.-]|$)", file_name, ignore.case = TRUE)) {
      return("R1")
    }
    if (grepl("(^|[_\\.-])R2([_\\.-]|$)", file_name, ignore.case = TRUE)) {
      return("R2")
    }
    NA_character_
  }

  resolved_igblast_data <- reactive({
    get_cluster_value_or(
      servers_config,
      "igblast_data",
      file.path(get_cluster_value(servers_config, "pipeline_root"), "igblast", "internal_data")
    )
  })

  resolved_igblast_auxiliary_data <- reactive({
    get_cluster_value_or(
      servers_config,
      "igblast_auxiliary_data",
      file.path(get_cluster_value(servers_config, "pipeline_root"), "igblast", "refs")
    )
  })
  
  # One-row metadata table used for writing sample.tsv and validation.
  submission_row <- reactive({
    # Processing filename and path
    run_name <- current_run_name()
    source_path <- paste0(input$user_id, "/", run_name)
    
    
      
    # Creating a dataframe with the details of the submission
    data.frame(
      user_id = input$user_id,
      user_email = input$email,
      input_method = input$type_input,
      server_name = input$server_name,
      server_path = storage_server_rawdata_path(),
      server_results_path = storage_server_results_path(),
      server_ssh_port = get_storage_value(servers_config, input$server_name, "ssh_port"),
      server_transfer_mode = storage_server_transfer_mode(),
      primer_set = input$primer,
      trim_primers = input$trim_primers,
      sequence_number = input$n_read * 2,
      pipeline = input$method,
      luka_light_protocol = input$luka_light,
      run_igblast = input$run_igblast,
      run_clonality = input$run_clonality,
      archive_format = input$archive_format,
      igblast_species = input$igblast_species,
      igblast_panel = input$igblast_panel,
      igblast_bin = get_cluster_value_or(servers_config, "igblast_bin", "igblastn"),
      igblast_organism = input$igblast_species,
      igblast_db_v = get_cluster_value(servers_config, "igblast_db_v"),
      igblast_db_d = get_cluster_value(servers_config, "igblast_db_d"),
      igblast_db_j = get_cluster_value(servers_config, "igblast_db_j"),
      igblast_data = resolved_igblast_data(),
      igblast_auxiliary_data = resolved_igblast_auxiliary_data(),
      trim_seq = input$trim_sequence,
      keep_raw = input$keep_intermediate,
      source = source_path,
      dest = paste0("results/", source_path),
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
  })

  # Reactive function to create a transposed submission form for display in the UI.
  form <- reactive({
    as.data.frame(t(submission_row()), stringsAsFactors = FALSE)
  })
  
  # Reactive function to read barcode names file
  bc_names <- reactive({
    df <- read.table(app_path("bc", "bc_names.txt"), stringsAsFactors = FALSE)
    bcnames <- df[["bcname"]]
    names(bcnames) <- rownames(df)
    return(bcnames)
  })

  
  
  # Reactive to list folders in the "bc" directory
  folder_list <- reactive({
    list.dirs(app_path("bc"), recursive = FALSE, full.names = FALSE)
  })
  
  # Global variable to hold logs
  log <- reactiveVal("")
  addlog <- function(message) {
    log(paste0(isolate(log()), "\n", message))
  }
  progress_detail <- reactiveVal("Waiting for submission.")
  set_progress_detail <- function(...) {
    progress_detail(paste(..., collapse = "\n"))
  }
  notification_log_path <- app_path("notification_log.tsv")

  append_notification_log <- function(recipient, subject, status, context, detail = "") {
    log_entry <- data.frame(
      timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      recipient = as.character(recipient),
      subject = as.character(subject),
      status = as.character(status),
      context = as.character(context),
      detail = as.character(detail),
      stringsAsFactors = FALSE
    )

    write.table(
      log_entry,
      file = notification_log_path,
      sep = "\t",
      quote = TRUE,
      row.names = FALSE,
      col.names = !file.exists(notification_log_path),
      append = file.exists(notification_log_path)
    )
  }
  run_script <- function(script_path, args = character()) {
    output <- tryCatch(
      suppressWarnings(system2(script_path, args = args, stdout = TRUE, stderr = TRUE)),
      error = function(e) structure(conditionMessage(e), status = 1)
    )

    status <- attr(output, "status")
    if (is.null(status)) {
      status <- 0
    }

    list(
      status = status,
      output = paste(output, collapse = "\n")
    )
  }

  parse_numeric_marker <- function(output_text, marker_name) {
    if (is.null(output_text) || !nzchar(output_text)) {
      return(NA_real_)
    }

    marker_match <- regmatches(
      output_text,
      regexpr(sprintf("%s=([0-9]+)", marker_name), output_text, perl = TRUE)
    )

    if (length(marker_match) == 0 || !nzchar(marker_match)) {
      return(NA_real_)
    }

    as.numeric(sub(sprintf("^%s=", marker_name), "", marker_match))
  }

  append_run_history <- function(status_label, runtime_sec, input_bytes = NA_real_, backend_output = "") {
    # Persist only a compact summary per run; the full workflow logs still live
    # on the backend for detailed debugging.
    append_run_stat(
      data.frame(
        timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        user_id = input$user_id,
        run_name = current_run_name(),
        input_method = input$type_input,
        server_name = input$server_name,
        pipeline = input$method,
        archive_format = input$archive_format,
        input_bytes = as.numeric(input_bytes),
        runtime_sec = as.numeric(runtime_sec),
        status = as.character(status_label),
        backend_output = as.character(substr(backend_output, 1, 2000)),
        stringsAsFactors = FALSE,
        check.names = FALSE
      )
    )
  }

  estimated_input_bytes <- reactive({
    input_mode <- input$type_input
    if (is.null(input_mode) || !identical(input_mode, "Upload") || is.null(input$input_files$datapath)) {
      return(NA_real_)
    }

    upload_sizes <- suppressWarnings(file.info(input$input_files$datapath)$size)
    upload_sizes <- upload_sizes[is.finite(upload_sizes) & !is.na(upload_sizes)]
    if (!length(upload_sizes)) {
      return(NA_real_)
    }

    sum(upload_sizes)
  })

  run_metrics <- reactive({
    metrics <- compute_run_metrics(read_run_stats(), input_bytes = estimated_input_bytes())
    observed_count <- historical_run_count()

    # The structured runtime ledger is new, so fall back to the number of
    # historical run folders until enough completed runs populate run_stats.tsv.
    if (isTRUE(observed_count > metrics$dataset_count)) {
      metrics$dataset_count <- observed_count
      if (is.na(metrics$total_time_saved_sec) || metrics$total_time_saved_sec <= 0) {
        metrics$total_time_saved_sec <- observed_count * 6 * 60
      }
    }

    metrics
  })

  send_mail_message <- function(recipient, subject, body, context = "general") {
    if (is.null(recipient) || length(recipient) < 1 || is.na(recipient[[1]])) {
      recipient <- ""
    }
    recipient <- trimws(as.character(recipient[[1]]))
    if (!nzchar(recipient)) {
      append_notification_log(recipient, subject, "skipped", context, "No recipient provided")
      return(list(status = 0, message = "No email recipient provided."))
    }

    if (nzchar(Sys.which("mail"))) {
      output <- tryCatch(
        suppressWarnings(system2("mail", args = c("-s", subject, recipient), input = body, stdout = TRUE, stderr = TRUE)),
        error = function(e) structure(conditionMessage(e), status = 1)
      )
      status <- attr(output, "status")
      if (is.null(status)) {
        status <- 0
      }
      message_text <- paste(output, collapse = "\n")
      append_notification_log(recipient, subject, if (status == 0) "accepted" else "failed", context, message_text)
      return(list(status = status, message = message_text))
    }

    if (nzchar(Sys.which("sendmail"))) {
      message_text <- sprintf("To: %s\nSubject: %s\n\n%s\n", recipient, subject, body)
      output <- tryCatch(
        suppressWarnings(system2("sendmail", args = c("-t"), input = message_text, stdout = TRUE, stderr = TRUE)),
        error = function(e) structure(conditionMessage(e), status = 1)
      )
      status <- attr(output, "status")
      if (is.null(status)) {
        status <- 0
      }
      output_text <- paste(output, collapse = "\n")
      append_notification_log(recipient, subject, if (status == 0) "accepted" else "failed", context, output_text)
      return(list(status = status, message = output_text))
    }

    append_notification_log(recipient, subject, "failed", context, "Neither mail nor sendmail is available on the Shiny host.")
    list(status = 1, message = "Neither mail nor sendmail is available on the Shiny host.")
  }

  send_run_notifications <- function(status_label, sample_name, storage_name, archive_format, submitter_name, submitter_email) {
    admin_email <- get_cluster_value(servers_config, "notification_admin_email")
    user_subject <- sprintf("TBRC run %s %s", sample_name, status_label)
    user_body <- paste(
      sprintf("Your TBRC run %s is now %s.", sample_name, status_label),
      sprintf("Storage target: %s.", storage_name),
      sprintf("Archive format: %s.", archive_format),
      sep = "\n"
    )
    admin_subject <- sprintf("TBRC usage: %s ran %s (%s)", submitter_name, sample_name, status_label)
    admin_body <- paste(
      sprintf("TBRC was used by: %s", submitter_name),
      sprintf("User email: %s", submitter_email),
      sprintf("Run name: %s", sample_name),
      sprintf("Status: %s", status_label),
      sprintf("Storage target: %s", storage_name),
      sprintf("Archive format: %s", archive_format),
      sep = "\n"
    )

    list(
      user = send_mail_message(submitter_email, user_subject, user_body, context = "user_completion"),
      admin = send_mail_message(admin_email, admin_subject, admin_body, context = "admin_usage")
    )
  }

  write_submission_metadata <- function(path) {
    metadata_df <- submission_row()
    metadata_list <- as.list(metadata_df[1, , drop = TRUE])
    jsonlite::write_json(
      metadata_list,
      path = file.path(path, "sample.json"),
      auto_unbox = TRUE,
      pretty = TRUE,
      null = "null"
    )
  }

  summarize_backend_failure <- function(output_text, default_message) {
    if (is.null(output_text) || !nzchar(output_text)) {
      return(default_message)
    }

    if (grepl("Folder not found on", output_text, fixed = TRUE)) {
      return("The requested folder was not found on the selected server.")
    }

    if (grepl("Missing required arguments\\.", output_text) ||
        grepl("Error in rule", output_text, fixed = TRUE) ||
        grepl("Submitted batch job", output_text, fixed = TRUE) ||
        grepl("Missing output files:", output_text, fixed = TRUE) ||
        grepl("Complete log:", output_text, fixed = TRUE) ||
        grepl("server-side submission failed", output_text, fixed = TRUE)) {
      return(default_message)
    }

    output_text
  }

  # Update the choices for the folder dropdown
  observe({
    app_update_picker_input(session, "folder_dropdown", choices = folder_list())
  })

  observe({
    user_choices <- names(known_users())
    updateSelectizeInput(session, "user_id", choices = user_choices, selected = isolate(input$user_id), server = TRUE)
  })

  observeEvent(input$user_id, {
    selected_user <- ""
    if (!is.null(input$user_id)) {
      selected_user <- trimws(input$user_id)
    }
    remembered_email <- unname(known_users()[selected_user])

    if (length(remembered_email) > 0 && !is.na(remembered_email) && nzchar(remembered_email)) {
      updateTextInput(session, "email", value = remembered_email)
    }
  }, ignoreNULL = FALSE)

  observeEvent(input$run_clonality, {
    if (isTRUE(input$run_clonality) && !isTRUE(input$run_igblast)) {
      updateCheckboxInput(session, "run_igblast", value = TRUE)
    }
  }, ignoreInit = TRUE)
  
  # Reactive to read content of the selected barcode files
  barcode_content <- reactive({
    if (!is.null(input$folder_dropdown) && nzchar(input$folder_dropdown)) {
      folder_path <- app_path("bc", input$folder_dropdown)
      
      # Check if both files exist in the selected folder
      req(file.exists(file.path(folder_path, "BC1.txt")), file.exists(file.path(folder_path, "BC2.txt")))
      
      list(
        BC1 = readLines(file.path(folder_path, "BC1.txt"), warn = FALSE),
        BC2 = readLines(file.path(folder_path, "BC2.txt"), warn = FALSE)
      )
    } else {
      list(BC1 = NULL, BC2 = NULL)
    }
  })
  
  #Render barcode content files in screen
  output$barcode_display1 <- renderText({
    bc <- barcode_content()
    paste(c("Barcode 1:", bc$BC1), collapse = "\n")
  })
  
  output$barcode_display2 <- renderText({
    bc <- barcode_content()
    paste(c("Barcode 2:", bc$BC2), collapse = "\n")
  })
  
  
  output$log <- renderText({
    log()
  })
  
  output$progressDetail <- renderText({
    progress_detail()
  })
  
  observe({
    # If any fastq file is uploaded, set type_input to 'Upload' and set server_name to 'upload'
    if(!is.null(input$input_files$datapath)){
      app_update_radio_buttons(
        session,
        inputId = "type_input",
        choices = c("Upload", "Server"),
        selected = "Upload"
      )
      app_update_radio_buttons(
        session,
        inputId = "server_name",
        choices = c(server_names, "upload"),
        selected = "upload"
      )
    }
    
    # Depending on the value of type_input, update the text input and server_name input
    if(input$type_input == "Upload"){
      updateTextInput(
        session,
        inputId = "input_folder",
        value = "Not used when uploading..."
      )
      app_update_radio_buttons(
        session,
        inputId = "server_name",
        choices = c(server_names, "upload"),
        selected = "upload"
      )
    } else if(input$type_input == "Server") {
      
      updateTextInput(
        session,
        inputId = "input_folder",
        value = ""
      )
      app_update_radio_buttons(
        session,
        inputId = "server_name",
        choices = c(server_names, "upload")
      )
    }
  })
  
  
  # Observer to update the primer set selection if barcodes are uploaded
  observe({
    app_update_picker_input(
      session,
      inputId = "primer",
      choices = bc_names(),
      selected = "B2"
    )
  })
  
  output$datasetCountDisplay <- renderText({
    sprintf("%d datasets tracked", run_metrics()$dataset_count)
  })

  output$savedTimeDisplay <- renderText({
    sprintf("Total time saved: %s", format_duration_compact(run_metrics()$total_time_saved_sec))
  })

  output$runtimeEstimateDisplay <- renderText({
    metrics <- run_metrics()
    if (is.na(metrics$estimated_runtime_sec)) {
      return("Runtime estimate: not available yet")
    }

    estimate_label <- format_duration_compact(metrics$estimated_runtime_sec)
    if (isTRUE(metrics$has_runtime_model)) {
      sprintf("Estimated processing time: %s", estimate_label)
    } else {
      sprintf("Typical processing time: %s", estimate_label)
    }
  })
  
  # Render form table
  output$submission_form <- renderDataTable({
    form()
  }, options = list(pageLength = 12))
  
  #Barcode Uploader
  output$confirmation <- renderText({
    "Upload barcode files."
  })
  
  observeEvent(input$bcupload,{
    
    # Check if the two BC files are uploaded
    if (is.null(input$BC_files) | length(input$BC_files$datapath) != 2) {
      
      output$confirmation <- renderText({
        "Please upload both BC1 and BC2 files."
      })
      return()
    }
    
    base_dir <- app_path("bc")
    new_bc_dir <- file.path(base_dir, input$folder_name)
    
    # Create the directory if it doesn't exist
    if (!dir.exists(new_bc_dir)) {
      dir.create(new_bc_dir)
    }
    
    # Save the uploaded BC files to the folder
    # We will just use names BC1.txt and BC2.txt for simplicity. Ensure users upload them in the correct order.
    file.copy(input$BC_files$datapath[1], file.path(new_bc_dir, 'BC1.txt'))
    file.copy(input$BC_files$datapath[2], file.path(new_bc_dir, 'BC2.txt'))
    
    # Append barcode name and folder name to bc_names.txt
    cat(paste('"', input$bc_name, '" "', input$folder_name, '"\n', sep = ""), file = file.path(base_dir, 'bc_names.txt'), append = TRUE)
    
      output$confirmation <- renderText({
        paste("Uploaded", input$bc_name, "with folder name", input$folder_name)
      })
    
    
    
    result <- system2("bash", args = app_script("updatebarcodes.bash"))
    
    if(result != 0) {
      # This means there was an error in the rsync command or in the bash script execution
      output$confirmation <- renderText({
        paste("Error in syncing barcodes. Please check the server logs for details.")
      })
      return()
    }
    
    # Optionally, check the result for any error messages or status
    if(result != 0) {
      output$confirmation <- renderText({
        paste("Error in processing barcodes. Please check the server logs for details.")
      })
      return()
    }
    
  })
  
  # Observer to perform actions when the Run button is clicked
  observeEvent(input$run, {
    if (isTRUE(input$run_clonality) && !isTRUE(input$run_igblast)) {
      shinyalert(
        title = "IGBlast required",
        text = "Clonality analysis needs IGBlast output. Please enable Run IGBlast annotation.",
        type = "error"
      )
      return()
    }

    if (input$type_input == "Server" && !nzchar(trimws(input$input_folder))) {
      shinyalert(
        title = "Oops!",
        text = "Folder in server cannot be empty for Server submissions.",
        type = "error"
      )
      return()
    }

    # Check if there are missing arguments in the form
    required_form_fields <- c(
      "user_id",
      "user_email",
      "input_method",
      "primer_set",
      "trim_primers",
      "sequence_number",
      "pipeline",
      "luka_light_protocol",
      "run_igblast",
      "run_clonality",
      "archive_format",
      "igblast_species",
      "igblast_panel",
      "trim_seq",
      "keep_raw",
      "source",
      "dest"
    )

    if (input$type_input == "Server") {
      required_form_fields <- c(
        required_form_fields,
        "server_name",
        "server_path",
        "server_results_path",
        "server_ssh_port",
        "server_transfer_mode"
      )
    }

    required_values <- submission_row()[1, required_form_fields, drop = TRUE]

    if(any(is.na(required_values) | required_values == "")){
      shinyalert(title = "Oops!", text = "There are arguments missing. Please complete the form.", type = "error")
      return()
    }
    pgPaneUpdate("thispg", "validate", 100)
    pgPaneUpdate("thispg", "stage", 0)
    pgPaneUpdate("thispg", "dispatch", 0)
    pgPaneUpdate("thispg", "workflow", 0)
    pgPaneUpdate("thispg", "export", 0)
    
    # If Upload mode is on
    if(input$type_input == "Upload") {
      run_started_at <- Sys.time()
      set_progress_detail(
        "Validation complete.",
        "Preparing upload run folder.",
        "Copying uploaded FASTQ files into the local run directory.",
        "Submitting workflow launch command.",
        "Live rule-by-rule Snakemake status is not available in this UI yet."
      )
      pgPaneUpdate("thispg", "stage", 25)
      pgPaneUpdate("thispg", "stage", 65)
      pgPaneUpdate("thispg", "stage", 100)
      
      # Alert if no fastq files are uploaded
      if(is.null(input$input_files)){
        shinyalert(title = "Oops!", text = "No fastq files detected! Upload or change input method.", type = "error")
        return()
      }

      if (length(input$input_files$name) != 2) {
        shinyalert(title = "Oops!", text = "Upload mode requires exactly two FASTQ files: one R1 and one R2.", type = "error")
        return()
      }

      upload_roles <- vapply(input$input_files$name, classify_uploaded_read, character(1))
      if (!all(c("R1", "R2") %in% upload_roles)) {
        shinyalert(title = "Oops!", text = "Uploaded files must include one R1 and one R2 FASTQ file.", type = "error")
        return()
      }

      r1_index <- which(upload_roles == "R1")[1]
      r2_index <- which(upload_roles == "R2")[1]
      
      # processing path and creating directory
      path <- paste0("runs/", input$user_id, "/", current_run_name())
      dir.create(path, showWarnings = T, recursive = T)
      
      # Writing the submission metadata on the run folder
      write_submission_metadata(path)
      cmd_args <- c(
        "-u", input$user_id,
        "-d", input$input_files$datapath[r1_index],
        "-e", input$input_files$datapath[r2_index],
        "-n", input$input_files$name[r1_index],
        "-m", input$input_files$name[r2_index]
      )
      
      # Running the pipeline script with arguments
      pgPaneUpdate("thispg", "dispatch", 100)
      pgPaneUpdate("thispg", "workflow", 20)
      
      
      result <- run_script(app_script("goUpload.bash"), cmd_args)
      if (result$status != 0) {
        append_run_history(
          status_label = "failed",
          runtime_sec = as.numeric(difftime(Sys.time(), run_started_at, units = "secs")),
          input_bytes = estimated_input_bytes(),
          backend_output = result$output
        )
        failure_text <- summarize_backend_failure(
          result$output,
          "The server-side workflow failed. Please check the backend logs."
        )
        send_run_notifications(
          status_label = "failed",
          sample_name = current_run_name(),
          storage_name = input$server_name,
          archive_format = submission_row()[["archive_format"]][[1]],
          submitter_name = input$user_id,
          submitter_email = input$email
        )
        shinyalert(
          title = "Submission failed",
          text = failure_text,
          type = "error"
        )
        set_progress_detail("Upload submission failed.", failure_text)
        return()
      }

      append_run_history(
        status_label = "completed",
        runtime_sec = as.numeric(difftime(Sys.time(), run_started_at, units = "secs")),
        input_bytes = estimated_input_bytes(),
        backend_output = result$output
      )
      
      set_progress_detail(
        "Upload submission sent.",
        "Workflow command finished on the app side.",
        "Final bundle should include QC histograms, plate QC when available, and an .imgt.ready.fasta file.",
        sprintf(
          "If the selected storage server is in pull mode, Synology should fetch the %s archive from the HPC results folder.",
          form()["archive_format", "Submission"]
        )
      )
      
      pgPaneUpdate("thispg", "workflow", 100)
      pgPaneUpdate("thispg", "export", 100)

      email_result <- send_run_notifications(
        status_label = "completed",
        sample_name = current_run_name(),
        storage_name = input$server_name,
        archive_format = submission_row()[["archive_format"]][[1]],
        submitter_name = input$user_id,
        submitter_email = input$email
      )
      if (email_result$user$status != 0 || email_result$admin$status != 0) {
        set_progress_detail(progress_detail(), "Shiny-side completion email could not be sent.")
      }
    }
    
    
    # If Server mode is on and all fields were filled, run the pipeline
    if(input$type_input == "Server" & !any(is.na(required_values) | required_values == "")) {
      run_started_at <- Sys.time()
      set_progress_detail(
        "Validation complete.",
        "Preparing remote submission.",
        "Writing sample metadata into the local run folder.",
        "The server job will pull FASTQ files, run Snakemake, then export results.",
        sprintf(
          "Final packaging will use %s.",
          form()["archive_format", "Submission"]
        ),
        "Live rule-by-rule Snakemake status is not available in this UI yet."
      )
      # Run progress updates and folder creation code here
      fname <- current_run_name() #folder on server name (Run name)
      path <- paste0("runs/", input$user_id, "/", fname) #full path to the local run
      dir.create(path, showWarnings = T, recursive = T) #create the folder
      pgPaneUpdate("thispg", "stage", 25)
      pgPaneUpdate("thispg", "stage", 65)
      pgPaneUpdate("thispg", "stage", 100)
      # Writing the submission metadata on the run folder
      write_submission_metadata(path)
    
      # Running the pipeline script with arguments
      cmd_args <- c(
        "-u", input$user_id,
        "-s", input$server_name,
        "-f", input$input_folder,
        "-n", fname
      )
      if (isTRUE(input$run_local)) {
        cmd_args <- c(cmd_args, "-l")
      }
      
      
      pgPaneUpdate("thispg", "dispatch", 100)
      pgPaneUpdate("thispg", "workflow", 20)
      # Running the snakemake script on the cluster
      result <- run_script(app_script("goServer.bash"), cmd_args)
      server_input_bytes <- parse_numeric_marker(result$output, "TBRC_INPUT_BYTES")
      if (result$status != 0) {
        append_run_history(
          status_label = "failed",
          runtime_sec = as.numeric(difftime(Sys.time(), run_started_at, units = "secs")),
          input_bytes = server_input_bytes,
          backend_output = result$output
        )
        failure_text <- summarize_backend_failure(
          result$output,
          "The server-side workflow failed. Please check the backend logs."
        )
        send_run_notifications(
          status_label = "failed",
          sample_name = current_run_name(),
          storage_name = input$server_name,
          archive_format = submission_row()[["archive_format"]][[1]],
          submitter_name = input$user_id,
          submitter_email = input$email
        )
        failure_title <- if (grepl("Folder not found on", result$output, fixed = TRUE)) "Folder not found" else "Submission failed"
        shinyalert(
          title = failure_title,
          text = failure_text,
          type = "error"
        )
        set_progress_detail("Remote submission failed.", failure_text)
        return()
      }

      append_run_history(
        status_label = "completed",
        runtime_sec = as.numeric(difftime(Sys.time(), run_started_at, units = "secs")),
        input_bytes = server_input_bytes,
        backend_output = result$output
      )
      
      set_progress_detail(
        "Remote submission sent.",
        "The HPC command returned to the app.",
        "Look for pre-trim and post-trim histograms, plate QC, and the .imgt.ready.fasta file in the result bundle.",
        sprintf(
          "If the selected storage server is in pull mode, Synology should fetch the %s archive from the HPC results folder.",
          form()["archive_format", "Submission"]
        )
      )
      pgPaneUpdate("thispg", "workflow", 100)
      pgPaneUpdate("thispg", "export", 100)

      email_result <- send_run_notifications(
        status_label = "completed",
        sample_name = current_run_name(),
        storage_name = input$server_name,
        archive_format = submission_row()[["archive_format"]][[1]],
        submitter_name = input$user_id,
        submitter_email = input$email
      )
      if (email_result$user$status != 0 || email_result$admin$status != 0) {
        set_progress_detail(progress_detail(), "Shiny-side completion email could not be sent.")
      }
    }
    
  })
}
