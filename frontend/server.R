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
      sample_files <- list.files(runs_dir, pattern = "^sample\\.tsv$", recursive = TRUE, full.names = TRUE)
    }

    for (sample_file in sample_files) {
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
    if (input$type_input == "Upload" && !is.null(input$input_files$name[1])) {
      return(gsub("\\.gz$", "", input$input_files$name[1]))
    }

    basename(trimws(input$input_folder))
  })
  
  # Reactive function to create a submission form with the selected options for the pipeline
  form <- reactive({
    # Processing filename and path
    run_name <- current_run_name()
    source_path <- paste0(input$user_id, "/", run_name)
    
    
      
    # Creating a dataframe with the details of the submission
    df <- data.frame(
      row.names = "Submission",
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
      igblast_bin = get_cluster_value(servers_config, "igblast_bin"),
      igblast_organism = input$igblast_species,
      igblast_db_v = get_cluster_value(servers_config, "igblast_db_v"),
      igblast_db_d = get_cluster_value(servers_config, "igblast_db_d"),
      igblast_db_j = get_cluster_value(servers_config, "igblast_db_j"),
      igblast_data = get_cluster_value(servers_config, "igblast_data"),
      igblast_auxiliary_data = get_cluster_value(servers_config, "igblast_auxiliary_data"),
      trim_seq = input$trim_sequence,
      keep_raw = input$keep_intermediate,
      source = source_path,
      dest = paste0("results/", source_path)
    )
    
    # Transpose the dataframe and return it
    return(as.data.frame(t(df)))
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
  
  #Time Display counter
  output$savedTimeDisplay <- renderText({
    saved_time <- get_saved_time()
    hours_saved <- saved_time %/% 3600
    minutes_saved <- (saved_time %% 3600) %/% 60
    sprintf("Total time saved: %d hours and %d minutes", hours_saved, minutes_saved)
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
    
    
    
    update_barcodes <- shQuote(app_script("updatebarcodes.bash"))
    result <- system(update_barcodes)
    
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

    required_values <- form()[required_form_fields, "Submission", drop = TRUE]

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
      
      # processing path and creating directory
      path <- paste0("runs/", input$user_id, "/", gsub("\\.gz","", input$input_files$name[1]))
      dir.create(path, showWarnings = T, recursive = T)
      
      # Writing the submission form on the run folder
      write.table(t(form()), file = paste0(path,"/", "sample.tsv"), quote = F, row.names = F, sep = "\t")
      cmd_args <- c(
        "-u", input$user_id,
        "-d", input$input_files$datapath[1],
        "-e", input$input_files$datapath[2],
        "-n", input$input_files$name[1],
        "-m", input$input_files$name[2]
      )
      
      # Running the pipeline script with arguments
      pgPaneUpdate("thispg", "dispatch", 100)
      pgPaneUpdate("thispg", "workflow", 20)
      
      
      result <- run_script(app_script("goUpload.bash"), cmd_args)
      if (result$status != 0) {
        failure_text <- summarize_backend_failure(
          result$output,
          "The server-side workflow failed. Please check the backend logs."
        )
        shinyalert(
          title = "Submission failed",
          text = failure_text,
          type = "error"
        )
        set_progress_detail("Upload submission failed.", failure_text)
        return()
      }
      
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
    }
    
    
    # If Server mode is on and all fields were filled, run the pipeline
    if(input$type_input == "Server" & !any(is.na(required_values) | required_values == "")) {
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
      # Writing the submission form on the run folder
      write.table(t(form()), file = paste0(path, "/", "sample.tsv"), quote = F, row.names = F, sep = "\t") 
    
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
      if (result$status != 0) {
        failure_text <- summarize_backend_failure(
          result$output,
          "The server-side workflow failed. Please check the backend logs."
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
    }
    
    #Update Time counter
    increment_saved_time()
    # To update the displayed saved time after incrementing
    output$savedTimeDisplay <- renderText({
      saved_time <- get_saved_time()
      hours_saved <- saved_time %/% 3600
      minutes_saved <- (saved_time %% 3600) %/% 60
      sprintf("Total time saved: %d hours and %d minutes", hours_saved, minutes_saved)
    })
    
  })
}
