# TBRCa Pipeline

TBRCa is a Shiny plus Snakemake workflow for plate-based BCR/TCR assembly, QC, IGBlast annotation, optional clonality calling, and packaged result delivery.

The repository has two main components:

- [`frontend/`](/Users/tiagobrc/Desktop/TBRC/frontend): the Shiny submission app
- [`backend/`](/Users/tiagobrc/Desktop/TBRC/backend): the Snakemake workflow and helper scripts

## What This Repo Contains

The pipeline can:

- accept paired FASTQs from direct upload or a remote storage folder
- trim primers and assemble reads
- demultiplex by plate barcode
- build final FASTA outputs and QC summaries
- optionally run IGBlast
- optionally run clonality
- package outputs as `zip` or `tar.gz`
- optionally push results to a storage server

Typical packaged outputs include:

- `<sample>.final.fasta`
- `<sample>.imgt.ready.fasta`
- `qc/`
- `igblast/`
- `clonality/`

## Repository Layout

- [`frontend/ui.R`](/Users/tiagobrc/Desktop/TBRC/frontend/ui.R): Shiny UI
- [`frontend/server.R`](/Users/tiagobrc/Desktop/TBRC/frontend/server.R): submission logic and app-side orchestration
- [`frontend/global.R`](/Users/tiagobrc/Desktop/TBRC/frontend/global.R): shared helpers and config readers
- [`frontend/server_config.json`](/Users/tiagobrc/Desktop/TBRC/frontend/server_config.json): deployment-specific configuration
- [`frontend/scripts/`](/Users/tiagobrc/Desktop/TBRC/frontend/scripts): app-side launcher scripts
- [`frontend/www/`](/Users/tiagobrc/Desktop/TBRC/frontend/www): Shiny static assets
- [`environment.yml`](/Users/tiagobrc/Desktop/TBRC/environment.yml): saved `snakemake` conda environment
- [`backend/workflow/Snakefile`](/Users/tiagobrc/Desktop/TBRC/backend/workflow/Snakefile): Snakemake entry point
- [`backend/workflow/rules/`](/Users/tiagobrc/Desktop/TBRC/backend/workflow/rules): workflow rules
- [`backend/workflow/scripts/`](/Users/tiagobrc/Desktop/TBRC/backend/workflow/scripts): backend helper scripts
- [`backend/igblast/`](/Users/tiagobrc/Desktop/TBRC/backend/igblast): IGBlast setup helpers and reference structure

## Install Anywhere

This is the shortest path to get TBRCa running on a new machine, cluster, or Shiny host.

### 1. Clone the repository

```bash
git clone <repo-url> TBRC
cd TBRC
```

### 2. Create the saved Snakemake conda environment

The repository root [`environment.yml`](/Users/tiagobrc/Desktop/TBRC/environment.yml) is the saved backend environment snapshot.

```bash
conda env create -f environment.yml
conda activate snakemake
```

This environment already includes most core backend dependencies such as:

- `snakemake`
- `cutadapt`
- `pandaseq`
- `fastx_toolkit`
- `igblast`
- `R`
- `ggplot2`
- `ggplate`

Useful sanity checks:

```bash
which snakemake
which cutadapt
which pandaseq
which fastx_trimmer
which fastx_collapser
which igblastn
which Rscript
```

### 3. Install extra R packages not guaranteed by the saved environment

If the environment does not already contain everything needed on the target machine, install:

```bash
conda activate snakemake
Rscript -e "install.packages(c('shiny','shinythemes','DT','jsonlite','shinyalert','shinyWidgets'), repos='https://cloud.r-project.org')"
```

For clonality:

```bash
Rscript -e "install.packages('remotes', repos='https://cloud.r-project.org')"
Rscript -e "remotes::install_github('victoraLab/clonality')"
```

or:

```bash
R CMD INSTALL /path/to/clonality_0.10.tar.gz
```

### 4. Decide your deployment pattern

TBRCa can be run in three common ways:

1. Local development:
Shiny and Snakemake on the same machine.

2. Split deployment:
Shiny on one host, Snakemake on an HPC or backend server.

3. HPC-first:
Only the backend is deployed and tested before connecting the UI.

## Required Configuration

The main deployment configuration file is:

- [`frontend/server_config.json`](/Users/tiagobrc/Desktop/TBRC/frontend/server_config.json)

You should replace the machine-specific values with your own.

### Required `cluster` fields

These drive how the frontend launches the backend.

```json
{
  "cluster": {
    "dtn_host": "<dtn-host-or-empty>",
    "ssh_host": "<login-host-or-local-host>",
    "pipeline_root": "/absolute/path/to/TBRC",
    "snakemake_env": "snakemake",
    "path_prefix": "/path/to/conda/condabin:/path/to/custom/bin:/usr/local/bin:/usr/bin",
    "igblast_bin": "igblastn",
    "igblast_data": "/absolute/path/to/ncbi-igblast/internal_data",
    "igblast_auxiliary_data": "/absolute/path/to/ncbi-igblast/optional_file",
    "notification_admin_email": "admin@example.org"
  }
}
```

Field meanings:

- `dtn_host`: host used to pull raw data from a storage server onto the backend
- `ssh_host`: host where `snakemake.sh` is launched
- `pipeline_root`: absolute path to the deployed TBRC repository root on the backend host
- `snakemake_env`: conda environment name used for workflow execution
- `path_prefix`: `PATH` exported before `conda activate`, useful on HPC systems
- `igblast_bin`: usually `igblastn`
- `igblast_data`: path to the NCBI `internal_data/` directory
- `igblast_auxiliary_data`: path to the NCBI `optional_file/` directory or a specific `*.aux` file
- `notification_admin_email`: optional admin notification recipient from Shiny

### Required `storage_server` fields

Each storage target needs:

```json
{
  "storage_server": {
    "example_storage": {
      "rawdata_path": "user@host:/absolute/rawdata/path/",
      "results_path": "user@host:/absolute/results/path/",
      "ssh_port": 22,
      "web_port": 0,
      "transfer_mode": "push"
    }
  }
}
```

Field meanings:

- `rawdata_path`: remote `host:path` where input runs live
- `results_path`: remote `host:path` where final packaged runs should land
- `ssh_port`: SSH port for rsync/ssh
- `web_port`: optional metadata only; not required by the backend
- `transfer_mode`:
  - `push`: backend pushes results out at the end
  - `pull`: backend keeps results local and another system should fetch them later

## Local Development Setup

### Run the backend locally

The backend expects:

- `DATA_TABLE`: path to the run metadata file, now typically `sample.json`
- `INPUTPATH`: path to the FASTQ directory

Example:

```bash
conda activate snakemake
cd /path/to/TBRC/backend
export DATA_TABLE=/absolute/path/to/sample.json
export INPUTPATH=/absolute/path/to/input_fastqs
snakemake --cores 4
```

### Run the frontend locally

```bash
cd /path/to/TBRC/frontend
Rscript -e "shiny::runApp('.', host='127.0.0.1', port=8080)"
```

Local development notes:

- `frontend/scripts/goServer.bash` and `goUpload.bash` resolve paths relative to the repo
- upload mode works with paired `.fastq` or `.fastq.gz`
- server mode writes `sample.json` and launches the backend through the configured hosts

## HPC / Backend Installation

Use this when deploying the Snakemake side to a cluster or backend server.

### 1. Copy the repository or backend

```bash
rsync -aP backend/ <backend-user>@<backend-host>:/path/to/TBRC/backend/
rsync -aP environment.yml <backend-user>@<backend-host>:/path/to/TBRC/
```

If you want the IGBlast helpers, docs, and shared root files intact, it is often simpler to copy the whole repo.

### 2. Create the backend environment

```bash
cd /path/to/TBRC
conda env create -f environment.yml
conda activate snakemake
```

### 3. Confirm core tools

```bash
which snakemake
which cutadapt
which pandaseq
which fastx_trimmer
which fastx_collapser
which igblastn
which Rscript
```

### 4. Install clonality if needed

```bash
conda activate snakemake
Rscript -e "install.packages('remotes', repos='https://cloud.r-project.org')"
Rscript -e "remotes::install_github('victoraLab/clonality')"
```

### 5. Set up IGBlast

You need the NCBI IgBlast bundle in addition to the `igblastn` binary:

- `internal_data/`
- `optional_file/`

Then build the panel databases:

```bash
cd /path/to/TBRC/backend/igblast
./setup_igblast_databases.sh mouse ig_all
./setup_igblast_databases.sh human ig_all
./setup_igblast_databases.sh mouse tcr_all
./setup_igblast_databases.sh human tcr_all
```

Validate:

```bash
./check_igblast_setup.sh mouse ig_all
./check_igblast_setup.sh human ig_all
```

Optional smoke test:

```bash
./smoke_test_igblast.sh /path/to/sample.imgt.ready.fasta mouse ig_all
```

See also:

- [`backend/igblast_setup.md`](/Users/tiagobrc/Desktop/TBRC/backend/igblast_setup.md)

## Shiny Server Installation

Use this when deploying the web app to a VM or application host.

### 1. Copy the frontend

```bash
rsync -aP frontend/ <shiny-user>@<shiny-host>:/path/to/shiny/app/
```

### 2. Install required R packages on the Shiny host

```r
install.packages(
  c("shiny", "shinythemes", "DT", "jsonlite", "shinyalert", "shinyWidgets"),
  repos = "https://cloud.r-project.org"
)
```

### 3. Edit deployed `server_config.json`

Update all cluster and storage variables on the deployed copy of:

- [`frontend/server_config.json`](/Users/tiagobrc/Desktop/TBRC/frontend/server_config.json)

### 4. Make sure the app can run bash helpers

The app uses:

- [`frontend/scripts/goUpload.bash`](/Users/tiagobrc/Desktop/TBRC/frontend/scripts/goUpload.bash)
- [`frontend/scripts/goServer.bash`](/Users/tiagobrc/Desktop/TBRC/frontend/scripts/goServer.bash)
- [`frontend/scripts/updatebarcodes.bash`](/Users/tiagobrc/Desktop/TBRC/frontend/scripts/updatebarcodes.bash)

So the Shiny host needs:

- `bash`
- `rsync`
- `ssh`
- `jq`

### 5. Verify static assets

The header image and any future static assets should live in:

- [`frontend/www/`](/Users/tiagobrc/Desktop/TBRC/frontend/www)

For example, the current header image is:

- [`frontend/www/bcr.png`](/Users/tiagobrc/Desktop/TBRC/frontend/www/bcr.png)

## Runtime Variables Used by the Backend

These are usually set automatically by the frontend launcher scripts:

- `DATA_TABLE`: path to `sample.json`
- `INPUTPATH`: path to the FASTQ input folder
- `PATH`: prefixed with `cluster.path_prefix`

For manual debugging, you can set them yourself:

```bash
export DATA_TABLE=/path/to/sample.json
export INPUTPATH=/path/to/input_folder
```

## Minimal Bring-Up Checklist

Use this checklist on a new machine or cluster.

### Backend checklist

- repo copied to backend host
- `conda env create -f environment.yml` completed
- `snakemake`, `cutadapt`, `pandaseq`, `fastx_trimmer`, `igblastn`, and `Rscript` available
- NCBI `internal_data/` downloaded
- NCBI `optional_file/` downloaded
- IGBlast panel DBs built under `backend/igblast/work`
- clonality installed if needed

### Frontend checklist

- frontend copied to Shiny host
- required R packages installed
- `server_config.json` updated with correct hosts and paths
- `bash`, `ssh`, `rsync`, and `jq` available
- Shiny can write under `frontend/runs/`
- `frontend/www/bcr.png` present if using the current header

### Storage checklist

- storage server accepts SSH/rsync from the expected host
- `rawdata_path` and `results_path` are valid
- `transfer_mode` matches the intended behavior

## First Validation Run

1. Start the Shiny app.
2. Submit one small test run.
3. Confirm that the run folder contains:
   - `sample.json`
4. Confirm the backend produces:
   - `<sample>.final.fasta`
   - `<sample>.imgt.ready.fasta`
   - `qc/`
5. If IGBlast is enabled, confirm:
   - `igblast/<sample>.igblast.tsv`
6. If clonality is enabled, confirm:
   - `clonality/<sample>.clonality.tsv`
7. Confirm the final archive is produced and, if using push mode, transferred to the storage server.

## Troubleshooting

- Metric cards show missing helper functions:
  frontend files were deployed out of sync; redeploy at least `global.R` and `server.R`.

- Header image does not appear:
  make sure the file lives under `frontend/www/`, not outside the app directory.

- IGBlast says built databases are missing:
  rebuild them with `backend/igblast/setup_igblast_databases.sh` in the live backend path.

- IGBlast says `internal_data` is missing:
  fix `cluster.igblast_data` or place `internal_data/` where the backend expects it.

- Server submission says folder not found:
  check `storage_server.<name>.rawdata_path`, `ssh_port`, and the requested folder name.

- Synology or NAS pull includes `@eaDir` files:
  current launcher scripts already exclude them, but older deployed copies may still need updating.

## Related Docs

- [`backend/README.md`](/Users/tiagobrc/Desktop/TBRC/backend/README.md)
- [`frontend/readme.md`](/Users/tiagobrc/Desktop/TBRC/frontend/readme.md)
- [`backend/igblast_setup.md`](/Users/tiagobrc/Desktop/TBRC/backend/igblast_setup.md)
