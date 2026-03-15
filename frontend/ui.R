# Define Shiny UI
shinyUI(fluidPage(theme = shinytheme("flatly"),
  # Custom CSS
  tags$style(HTML("
    :root {
      --sage-050: #f3f7f1;
      --sage-100: #edf4ea;
      --sage-200: #dde8db;
      --sage-300: #cdddcf;
      --sage-400: #8fad8d;
      --sage-500: #7f9e7c;
      --sage-700: #35523c;
      --ink-700: #294034;
      --paper: rgba(255, 255, 255, 0.78);
    }

    body {
      background:
        radial-gradient(circle at top left, rgba(143, 173, 141, 0.18), transparent 28%),
        linear-gradient(180deg, #f3f7f1 0%, #e7efe5 100%);
      color: var(--ink-700);
    }

    .well {
      background-color: transparent;
      border: none;
      box-shadow: none;
      padding: 0;
    }

    .main-panel {
      padding-left: 22px;
    }

    h1, h2, h3, h4, .control-label {
      color: var(--sage-700);
    }

    .hero {
      position: relative;
      overflow: hidden;
      background:
        linear-gradient(0deg, rgba(255,255,255,0.56), rgba(255,255,255,0.56)),
        url('bcr.png') right center / contain no-repeat,
        linear-gradient(180deg, #e7f3fb 0%, #f3f7f1 100%);
      border: 1px solid var(--sage-300);
      border-radius: 28px;
      padding: 30px 34px 28px 34px;
      margin-bottom: 22px;
      box-shadow: 0 20px 45px rgba(71, 99, 78, 0.09);
      min-height: 340px;
    }

    .hero-grid {
      position: relative;
      z-index: 2;
      display: flex;
      align-items: flex-end;
      min-height: 240px;
    }

    .hero-title {
      font-size: 32px;
      font-weight: 700;
      letter-spacing: 0.015em;
      margin: 0 0 10px 0;
      max-width: 760px;
    }

    .hero-subtitle {
      color: #4d6954;
      font-size: 15px;
      margin: 0;
      max-width: 720px;
      line-height: 1.55;
    }

    .hero-badge {
      display: none;
    }

    .hero-copy {
      display: inline-block;
      max-width: 620px;
      background: rgba(255, 255, 255, 0.78);
      border: 1px solid rgba(205, 221, 207, 0.72);
      border-radius: 24px;
      padding: 18px 22px;
      backdrop-filter: blur(4px);
      box-shadow: 0 10px 24px rgba(71, 99, 78, 0.08);
    }

    .panel-card {
      background: var(--paper);
      border: 1px solid var(--sage-300);
      border-radius: 20px;
      padding: 18px 18px 14px 18px;
      margin-bottom: 16px;
      box-shadow: 0 14px 28px rgba(71, 99, 78, 0.08);
      backdrop-filter: blur(4px);
    }

    .card-title {
      font-size: 16px;
      font-weight: 700;
      margin: 0 0 6px 0;
      color: var(--sage-700);
    }

    .card-note {
      font-size: 13px;
      color: #5f7965;
      margin-bottom: 14px;
      line-height: 1.45;
    }

    .metric-card {
      background: linear-gradient(135deg, rgba(143,173,141,0.18), rgba(255,255,255,0.92));
      border: 1px solid var(--sage-300);
      border-radius: 18px;
      padding: 16px 18px;
      margin-bottom: 16px;
    }

    .metric-label {
      text-transform: uppercase;
      letter-spacing: 0.08em;
      font-size: 11px;
      color: #5f7965;
      margin-bottom: 6px;
    }

    .metric-value {
      font-size: 22px;
      font-weight: 700;
      color: var(--sage-700);
    }

    .preview-box {
      background: rgba(248, 251, 246, 0.9);
      border: 1px solid var(--sage-300);
      border-radius: 16px;
      padding: 12px 14px;
      min-height: 140px;
      white-space: pre-wrap;
    }

    .btn-default,
    .bootstrap-select > .dropdown-toggle {
      background-color: var(--sage-100);
      border-color: #c8d8c7;
      color: var(--sage-700);
      border-radius: 10px;
    }

    .bootstrap-select .dropdown-menu {
      border-radius: 12px;
      border-color: #c8d8c7;
    }

    .form-control {
      border-radius: 12px;
      border-color: var(--sage-300);
      box-shadow: none;
    }

    .form-control:focus {
      border-color: var(--sage-400);
      box-shadow: 0 0 0 3px rgba(143, 173, 141, 0.18);
    }

    #run {
      background-color: var(--sage-400);
      border: none;
      color: white;
      padding: 15px 32px;
      text-align: center;
      display: inline-block;
      font-size: 16px;
      margin: 4px 2px;
      cursor: pointer; /* Add a mouse pointer on hover */
      border-radius: 4px; /* Rounded corners */
    }

    #run:hover {
      background-color: var(--sage-500);
    }

    .progress {
      background-color: var(--sage-200);
    }

    .irs-bar,
    .irs-bar-edge,
    .irs-single {
      background: var(--sage-400);
      border-color: var(--sage-400);
    }

    table.dataTable tbody tr {
      background-color: rgba(255, 255, 255, 0.6);
    }

    .status-box {
      margin-top: 14px;
      background: rgba(248, 251, 246, 0.92);
      border: 1px solid var(--sage-300);
      border-radius: 14px;
      padding: 12px 14px;
      color: #45604c;
      white-space: pre-wrap;
      font-size: 13px;
      line-height: 1.5;
    }

    .progress-layout {
      display: grid;
      grid-template-columns: minmax(280px, 0.9fr) minmax(320px, 1.1fr);
      gap: 16px;
      align-items: stretch;
    }

    .progress-stack {
      display: flex;
      flex-direction: column;
      gap: 16px;
      height: 100%;
    }

    @media (max-width: 991px) {
      .main-panel {
        padding-left: 15px;
        margin-top: 12px;
      }

      .hero-title {
        font-size: 24px;
      }

      .progress-layout {
        grid-template-columns: 1fr;
      }

      .hero {
        min-height: 250px;
        padding: 20px;
        background-position: center center, center center, center center;
      }

      .hero-grid {
        min-height: 190px;
      }

    }
  ")),

  useShinyalert(),
  tags$div(
    class = "hero",
    tags$div(
      class = "hero-grid",
      tags$div(
        class = "hero-copy",
        tags$div(
          class = "hero-title",
          "TBRCa Pipeline - T and B cell Receptor Clonality analysis"
        ),
        tags$p(
          class = "hero-subtitle",
          "Plant-based BCR/TCR receptor assembly, QC and annotation"
        )
      )
    )
  ),

  sidebarLayout(
    sidebarPanel(
      tags$div(
        class = "panel-card",
        tags$div(class = "card-title", "Submit Run"),
        tags$div(class = "card-note", "Set the owner, source, and destination for this sequencing run."),
        selectizeInput("user_id", "User name", choices = NULL, selected = NULL, options = list(create = TRUE, placeholder = "Choose an existing user or type a new one")),
        textInput("email", "User email", value = NULL, placeholder = "name@lab.org"),
        app_radio_buttons("type_input", "Method of input", choices = c("Upload", "Server"), selected = "Server", status = "success", outline = TRUE, animation = "pulse"),
        app_radio_buttons("server_name", "Server to send/get results", choices = c("empty"), status = "success", outline = TRUE, animation = "pulse"),
        textInput("input_folder",  "Folder in server", value = "", placeholder = "plate_001"),
        fileInput("input_files", "Upload paired FASTQ files (R1 and R2)", accept = c(".fastq.gz", ".fastq", ".gz"), multiple = TRUE)
      ),
      tags$div(
        class = "panel-card",
        tags$div(class = "card-title", "Pipeline Options"),
        tags$div(class = "card-note", "Choose barcode presets and processing behavior."),
        app_picker_input("primer", "Barcode set", choices = list("Loading..." = "placeholder"), options = list(`live-search` = TRUE)),
        app_radio_buttons("keep_intermediate", "Keep intermediate files", choices = c("FALSE", "TRUE"), selected = "FALSE", status = "success", outline = TRUE, animation = "pulse"),
        app_radio_buttons("trim_primers", "Trim primers", choices = c(TRUE, FALSE), selected = TRUE, status = "success", outline = TRUE, animation = "pulse"),
        app_switch_input("run_local", "Run on this server (not HPC)", FALSE, status = "success"),
        checkboxInput("run_igblast", "Run IGBlast annotation", FALSE),
        checkboxInput("run_clonality", "Run clonality analysis from IGBlast", FALSE),
        app_radio_buttons(
          "archive_format",
          "Final results archive format",
          choices = c(
            "ZIP (Recommended)" = "zip",
            "tar.gz" = "tar.gz"
          ),
          selected = "zip",
          status = "success",
          outline = TRUE,
          animation = "pulse"
        ),
        app_radio_buttons(
          "igblast_species",
          "IGBlast species",
          choices = c(
            "Human" = "human",
            "Mouse" = "mouse"
          ),
          selected = "mouse",
          status = "success",
          outline = TRUE,
          animation = "pulse"
        ),
        app_picker_input(
          "igblast_panel",
          "IGBlast receptor scope",
          choices = c(
            "Immunoglobulin heavy chain only (IgH)" = "igh",
            "Immunoglobulin light chains only (IgK + IgL)" = "ig_light",
            "All immunoglobulins (IgH + IgK + IgL)" = "ig_all",
            "TCR alpha only (TRA)" = "tra",
            "TCR beta only (TRB)" = "trb",
            "All TCR (TRA + TRB + TRD + TRG)" = "tcr_all",
            "All TCR and immunoglobulins" = "all_receptors"
          ),
          selected = "ig_all",
          options = list(`live-search` = TRUE)
        ),
        textInput("trim_sequence", "Trim sequence", value = "GGGAATTCGAGGTGCAGCTGCAGGAGTCTGG"),
        sliderInput("n_read", "Contigs or isoforms to retrieve", min = 1, max = 500, step = 1, value = 3),
        app_radio_buttons(
          "method",
          "Core assembly pipeline",
          choices = c(
            "Classic clonality assembly (classic_luka)" = "classic_luka"
          ),
          selected = "classic_luka",
          status = "success",
          outline = TRUE,
          animation = "pulse"
        ),
        app_radio_buttons(
          "luka_light",
          "Barcode preprocessing mode",
          choices = c(
            "Standard preprocessing" = "standard",
            "Light-chain rescue preprocessing" = "luka_light"
          ),
          selected = "standard",
          status = "success",
          outline = TRUE,
          animation = "pulse"
        ),
        app_action_button("run", "Run", style = "material-flat", color = "success", size = "md", block = TRUE)
      ),
      tags$div(
        class = "panel-card",
        tags$div(class = "card-title", "Upload New Barcodes"),
        tags$div(class = "card-note", "Add a BC1 and BC2 pair and sync it to the backend barcode store."),
        textInput("bc_name", "Barcode name"),
        textInput("folder_name", "Folder name"),
        fileInput("BC_files", "Upload BC1 and BC2 files", multiple = TRUE),
        app_action_button("bcupload", "Upload", style = "material-flat", color = "success", size = "sm", block = TRUE)
      )
    ),

    mainPanel(class = "main-panel",
      fluidRow(
        column(
          4,
          tags$div(
            class = "metric-card",
            tags$div(class = "metric-label", "Usage"),
            tags$div(class = "metric-value", textOutput("datasetCountDisplay", inline = TRUE))
          )
        ),
        column(
          4,
          tags$div(
            class = "metric-card",
            tags$div(class = "metric-label", "Estimated Manual Time Saved"),
            tags$div(class = "metric-value", textOutput("savedTimeDisplay", inline = TRUE))
          )
        ),
        column(
          4,
          tags$div(
            class = "metric-card",
            tags$div(class = "metric-label", "Processing Estimator"),
            tags$div(class = "metric-value", textOutput("runtimeEstimateDisplay", inline = TRUE))
          )
        )
      ),
      fluidRow(
        column(
          12,
          tags$div(
            class = "progress-layout",
            tags$div(
              class = "panel-card",
              tags$div(class = "card-title", "Run Progress"),
              tags$div(class = "card-note", "Submission progress in the app. Detailed live Snakemake rule tracking is not wired yet."),
              pgPaneUI(
                pane_id = "thispg",
                titles = c("Validate", "Stage", "Dispatch", "Workflow", "Export"),
                pg_ids = c("validate", "stage", "dispatch", "workflow", "export"),
                title_main = c("Run Progress"),
                opened = TRUE,
                top = "0%",
                right = "0%"
              )
            ),
            tags$div(
              class = "progress-stack",
              tags$div(
                class = "panel-card",
                tags$div(class = "card-title", "Status Detail"),
                tags$div(class = "card-note", "Narrative status updates from the app while the workflow is submitted and packaged."),
                tags$div(class = "status-box", textOutput("progressDetail"))
              ),
              tags$div(
                class = "panel-card",
                tags$div(class = "card-title", "Submission Preview"),
                tags$div(class = "card-note", "This is the metadata that will be written to the run folder and passed to the pipeline."),
                DT::dataTableOutput("submission_form")
              )
            )
          )
        )
      ),
      fluidRow(
        column(
          5,
          tags$div(
            class = "panel-card",
            tags$div(class = "card-title", "Barcode Library"),
            tags$div(class = "card-note", "Review the preset barcode folders currently available to the app."),
            app_picker_input("folder_dropdown", "Select a folder", choices = NULL, options = list(`live-search` = TRUE)),
            textOutput("confirmation")
          )
        ),
        column(
          7,
          tags$div(
            class = "panel-card",
            tags$div(class = "card-title", "Barcode Preview"),
            fluidRow(
              column(6, tags$div(class = "preview-box", verbatimTextOutput("barcode_display1"))),
              column(6, tags$div(class = "preview-box", verbatimTextOutput("barcode_display2")))
            )
          )
        )
      )
    )
  )
))
