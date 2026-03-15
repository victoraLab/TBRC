# TBRC

TBRC is a Shiny plus Snakemake workflow for plate-based TCR and BCR sequencing runs.

The repository has two main parts:

- [`frontend/`](/Users/tiagobrc/Desktop/TBRC/frontend): the Shiny submission app
- [`backend/`](/Users/tiagobrc/Desktop/TBRC/backend): the Snakemake workflow, QC, packaging, and optional IGBlast/clonality steps

## What TBRC Does

The app lets users:

- submit runs from uploaded FASTQs or a storage-server folder
- choose barcode presets
- choose assembly and trimming settings
- optionally run IGBlast
- optionally run clonality analysis from IGBlast
- package final results as `zip` or `tar.gz`

The backend then:

- finds paired `R1` and `R2` FASTQ files
- trims and assembles reads
- demultiplexes by barcode
- creates final FASTA outputs
- writes QC outputs
- optionally runs IGBlast and clonality
- packages the run into an archive
- optionally transfers the archive to the configured storage server

## Output Layout

The final results archive contains a top-level run folder so extracted runs do not mix together.

Typical contents:

- `<sample>.final.fasta`
- `<sample>.imgt.ready.fasta`
- `qc/`
- `igblast/`
- `clonality/`

## Project Layout

- [`frontend/ui.R`](/Users/tiagobrc/Desktop/TBRC/frontend/ui.R): Shiny UI
- [`frontend/server.R`](/Users/tiagobrc/Desktop/TBRC/frontend/server.R): Shiny server logic
- [`frontend/global.R`](/Users/tiagobrc/Desktop/TBRC/frontend/global.R): shared app helpers
- [`frontend/server_config.json`](/Users/tiagobrc/Desktop/TBRC/frontend/server_config.json): machine-specific config
- [`backend/workflow/Snakefile`](/Users/tiagobrc/Desktop/TBRC/backend/workflow/Snakefile): workflow entry point
- [`backend/workflow/rules/`](/Users/tiagobrc/Desktop/TBRC/backend/workflow/rules): Snakemake rules
- [`backend/workflow/scripts/`](/Users/tiagobrc/Desktop/TBRC/backend/workflow/scripts): workflow helper scripts
- [`backend/igblast/`](/Users/tiagobrc/Desktop/TBRC/backend/igblast): IGBlast references, build scripts, and validation helpers

## Quick Start

### 1. Clone the repository

```bash
git clone <your-repo-url> TBRC
cd TBRC
```

### 2. Create the backend Conda environment

```bash
cd backend
conda env create -f environment.yml
conda activate snakemake
```

### 3. Install required R packages for optional QC and clonality

Minimal useful set:

```bash
Rscript -e "install.packages(c('ggplot2','dplyr','readr','ggplate'), repos='https://cloud.r-project.org')"
```

If you want clonality:

```bash
R CMD INSTALL /path/to/clonality_0.10.tar.gz
```

You can also install clonality directly from the Victora Lab GitHub repository:

```bash
Rscript -e "install.packages('remotes', repos='https://cloud.r-project.org')"
Rscript -e "remotes::install_github('victoraLab/clonality')"
```

### 4. Configure machine-specific settings

Edit [`frontend/server_config.json`](/Users/tiagobrc/Desktop/TBRC/frontend/server_config.json).

Important sections:

- `storage_server.*.rawdata_path`
- `storage_server.*.results_path`
- `storage_server.*.ssh_port`
- `storage_server.*.transfer_mode`
- `cluster.dtn_host`
- `cluster.ssh_host`
- `cluster.pipeline_root`
- `cluster.snakemake_env`
- `cluster.igblast_bin`
- `cluster.igblast_data`
- `cluster.igblast_auxiliary_data`

Keep real server names, usernames, and paths in your private deployment config or local config workflow if you do not want them committed.

## Local Installation

This is the best setup for development and validation before touching HPC or production Shiny deployment.

### Backend local run

Requirements:

- Conda
- the `snakemake` environment created from [`backend/environment.yml`](/Users/tiagobrc/Desktop/TBRC/backend/environment.yml)
- local FASTQ input files

The current backend is primarily driven by the Shiny-generated `sample.tsv` plus environment variables:

- `DATA_TABLE`
- `INPUTPATH`

If you want to test locally, create a small local input directory and a matching `sample.tsv`, then run Snakemake from [`backend/`](/Users/tiagobrc/Desktop/TBRC/backend).

Example shape:

```bash
cd /path/to/TBRC/backend
conda activate snakemake
export DATA_TABLE=/path/to/sample.tsv
export INPUTPATH=/path/to/fastq_folder
snakemake --cores 4
```

### Shiny local run

Requirements:

- R
- packages used by the app such as `shiny`, `DT`, `jsonlite`, `shinyalert`
- optional enhanced widgets via `shinyWidgets`

Run locally from [`frontend/`](/Users/tiagobrc/Desktop/TBRC/frontend):

```bash
cd /path/to/TBRC/frontend
Rscript -e "shiny::runApp('.', host='127.0.0.1', port=8080)"
```

The app has a fallback mode when `shinyWidgets` is missing, but installing it is recommended.

## New HPC / Backend Installation

Use this path when you are setting up the Snakemake side on a new cluster or server.

### 1. Copy the backend

```bash
rsync -aP backend/ <hpc-user>@<hpc-host>:/path/to/TBRC/backend/
```

### 2. Create the Conda environment on the HPC

```bash
cd /path/to/TBRC/backend
conda env create -f environment.yml
conda activate snakemake
```

### 3. Confirm core tools

```bash
which snakemake
which pandaseq
which fastx_trimmer
which fastx_collapser
which cutadapt
```

### 4. Confirm R availability if you want QC / clonality

```bash
which Rscript
Rscript -e "library(ggplot2); library(dplyr)"
```

### 5. Configure the frontend JSON so it points to this backend

Update in [`frontend/server_config.json`](/Users/tiagobrc/Desktop/TBRC/frontend/server_config.json):

- `cluster.ssh_host`
- `cluster.dtn_host`
- `cluster.pipeline_root`
- `cluster.snakemake_env`
- `cluster.path_prefix` if needed

### 6. Validate a backend run manually

At minimum, confirm that:

- Snakemake runs in the environment
- the backend can see input FASTQs
- the backend can write under its `results/` path

## New Shiny / Server Installation

Use this path when you are moving the web app to a new VM or lab server.

### 1. Copy the frontend

```bash
rsync -aP frontend/ <shiny-user>@<shiny-host>:/path/to/shiny/app/
```

### 2. Install required R packages on the Shiny host

At minimum:

```r
install.packages(c("shiny", "DT", "jsonlite", "shinyalert", "shinyWidgets"))
```

### 3. Update Shiny-side config

Edit [`frontend/server_config.json`](/Users/tiagobrc/Desktop/TBRC/frontend/server_config.json) on the deployed copy.

### 4. Check launcher scripts

The scripts in [`frontend/scripts/`](/Users/tiagobrc/Desktop/TBRC/frontend/scripts) now resolve paths relative to the repo, so you usually only need the JSON config to match the new machine.

### 5. Test the app

Verify:

- the app loads
- barcode presets populate
- a test submission writes the expected `sample.tsv`
- server-mode submissions reach the backend

## Storage Server Setup

Storage behavior is configured per storage target in [`frontend/server_config.json`](/Users/tiagobrc/Desktop/TBRC/frontend/server_config.json).

Relevant fields:

- `rawdata_path`
- `results_path`
- `ssh_port`
- `transfer_mode`

Supported transfer modes:

- `push`: backend pushes results to the storage server
- `pull`: backend keeps the archive locally and a trusted external machine should pull it later

If using push mode, confirm:

- SSH works from the backend host to the storage host
- the host key is trusted
- the destination directory is writable

## IGBlast Installation

TBRC supports species and receptor-scope selection in the UI.

Supported species:

- `human`
- `mouse`

Supported receptor scopes:

- `igh`
- `ig_light`
- `ig_all`
- `tra`
- `trb`
- `tcr_all`
- `all_receptors`

IGBlast requirements:

- `igblastn`
- `makeblastdb`
- `edit_imgt_file.pl`
- IMGT FASTAs under [`backend/igblast/db/`](/Users/tiagobrc/Desktop/TBRC/backend/igblast/db)
- `internal_data/` from the standalone NCBI IgBlast distribution
- optional aux files from `optional_file/`

To build databases:

```bash
cd /path/to/TBRC/backend/igblast
bash setup_igblast_databases.sh
```

To validate:

```bash
./check_igblast_setup.sh mouse ig_all
./smoke_test_igblast.sh /path/to/sample.imgt.ready.fasta mouse ig_all
```

Detailed notes are in [`backend/igblast_setup.md`](/Users/tiagobrc/Desktop/TBRC/backend/igblast_setup.md).

Clonality repository:

- [victoraLab/clonality](https://github.com/victoraLab/clonality)

## Deployment Workflow

This repo uses a split deployment model:

- deploy [`frontend/`](/Users/tiagobrc/Desktop/TBRC/frontend) to the Shiny host
- deploy [`backend/`](/Users/tiagobrc/Desktop/TBRC/backend) to the HPC/backend host

If you use the included helper script, keep private deployment values in:

- [`scripts/deploy_config.sh`](/Users/tiagobrc/Desktop/TBRC/scripts/deploy_config.sh)

The tracked template is:

- [`scripts/deploy_config.example.sh`](/Users/tiagobrc/Desktop/TBRC/scripts/deploy_config.example.sh)

Then run:

```bash
bash scripts/deploy_all.sh
```

## Troubleshooting

### IGBlast skipped

Check:

- `which igblastn`
- `cluster.igblast_data`
- `cluster.igblast_auxiliary_data`
- built DBs under [`backend/igblast/work`](/Users/tiagobrc/Desktop/TBRC/backend/igblast/work)

### QC folder is empty

Usually means `Rscript` or required R packages are missing in the backend environment.

### Results do not transfer

Check:

- storage server `ssh_port`
- trusted host keys on the backend host
- write permissions on the remote results folder
- `transfer_mode`

### Server-mode submission fails immediately

Check:

- `input_folder`
- `rawdata_path`
- that the folder exists on the selected storage server

## Notes

- `zip` remains the safest default archive for Mac users
- machine-specific settings should live in config, not hardcoded in scripts
- `luka_classic` remains the current production backend path unless you explicitly extend the workflow further
