#!/bin/bash

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

require_tool jq
require_tool rsync
require_tool ssh

STORAGE_SERVER_NAME=""
USER_ID=""
INPUT_FOLDER=""
RUN_NAME=""
LOCAL_RUN=0

while getopts ":s:u:f:n:l" opt; do
  case "${opt}" in
    s) STORAGE_SERVER_NAME="${OPTARG}" ;;
    u) USER_ID="${OPTARG}" ;;
    f) INPUT_FOLDER="${OPTARG}" ;;
    n) RUN_NAME="${OPTARG}" ;;
    l) LOCAL_RUN=1 ;;
    \?) echo "Invalid option: -${OPTARG}" >&2; exit 1 ;;
    :) echo "Option -${OPTARG} requires an argument." >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

if [[ -z "${STORAGE_SERVER_NAME}" || -z "${USER_ID}" || -z "${INPUT_FOLDER}" || -z "${RUN_NAME}" ]]; then
  echo "Missing required arguments." >&2
  exit 1
fi

RAWDATA_SERVER="$(json_get_storage_field "${STORAGE_SERVER_NAME}" rawdata_path)"
STORAGE_SERVER_SSH_PORT="$(json_get_storage_field "${STORAGE_SERVER_NAME}" ssh_port)"
DTN_HOST="$(json_get_cluster_field dtn_host)"
SSH_HOST="$(json_get_cluster_field ssh_host)"
PIPELINE_ROOT="$(json_get_cluster_field pipeline_root)"
SNAKEMAKE_ENV="$(json_get_cluster_field snakemake_env)"
PATH_PREFIX="$(json_get_cluster_field path_prefix)"

if [[ -z "${RAWDATA_SERVER}" || "${RAWDATA_SERVER}" == "null" ]]; then
  echo "Server not recognized or missing configuration: ${STORAGE_SERVER_NAME}" >&2
  exit 1
fi

REMOTE_STORAGE_HOST="${RAWDATA_SERVER%%:*}"
REMOTE_STORAGE_BASE_PATH="${RAWDATA_SERVER#*:}"
REMOTE_INPUT_PATH="${REMOTE_STORAGE_BASE_PATH%/}/${INPUT_FOLDER}"

if [[ "${REMOTE_STORAGE_HOST}" == "${REMOTE_STORAGE_BASE_PATH}" ]]; then
  echo "Storage server path is not in host:path format: ${RAWDATA_SERVER}" >&2
  exit 1
fi

# sample.json is written locally by the app, then copied to the HPC run folder
# before Snakemake starts.
DATA_TABLE="data/runs/${USER_ID}/${RUN_NAME}/sample.json"
INPUTPATH="data/runs/${USER_ID}/${RUN_NAME}/"

if [[ "${LOCAL_RUN}" == "1" ]]; then
  cd "${BACKEND_DIR}"
  export PATH="${PATH_PREFIX}"
  export DATA_TABLE="${DATA_TABLE}"
  export INPUTPATH="${INPUTPATH}"
  conda activate "${SNAKEMAKE_ENV}"
  ./snakemake.sh
  exit 0
fi

RSYNC_SSH_OPTION="$(rsync_transport_args "${STORAGE_SERVER_SSH_PORT}")"
STORAGE_SSH_CHECK=""
if [[ -n "${STORAGE_SERVER_SSH_PORT}" && "${STORAGE_SERVER_SSH_PORT}" != "null" ]]; then
  STORAGE_SSH_CHECK="-p ${STORAGE_SERVER_SSH_PORT}"
fi

REMOTE_CHECK_COMMAND="ssh ${STORAGE_SSH_CHECK} '${REMOTE_STORAGE_HOST}' \"test -d '${REMOTE_INPUT_PATH}'\""
if ! ssh "${DTN_HOST}" "${REMOTE_CHECK_COMMAND}"; then
  echo "Folder not found on ${STORAGE_SERVER_NAME}: ${INPUT_FOLDER}" >&2
  exit 1
fi

# Pull the raw run folder onto the DTN first, excluding Synology metadata
# folders that otherwise confuse FASTQ discovery downstream.
REMOTE_PULL_COMMAND="mkdir -p '${PIPELINE_ROOT}/data/runs/${USER_ID}' && rsync -a -P --exclude='@eaDir/' --exclude='@eaDir'"
if [[ -n "${RSYNC_SSH_OPTION}" ]]; then
  REMOTE_PULL_COMMAND="${REMOTE_PULL_COMMAND} ${RSYNC_SSH_OPTION}"
fi
REMOTE_PULL_COMMAND="${REMOTE_PULL_COMMAND} '${RAWDATA_SERVER}${INPUT_FOLDER}' '${PIPELINE_ROOT}/data/runs/${USER_ID}/'"

ssh "${DTN_HOST}" "${REMOTE_PULL_COMMAND}"
rsync -a -P "runs/${USER_ID}/${RUN_NAME}/" "${DTN_HOST}:${PIPELINE_ROOT}/data/runs/${USER_ID}/${RUN_NAME}/"
# Emit a lightweight marker that the Shiny app can parse to improve the
# runtime estimator without opening or recomputing FASTQ sizes itself.
INPUT_BYTES="$(ssh "${DTN_HOST}" "find '${PIPELINE_ROOT}/data/runs/${USER_ID}/${RUN_NAME}' -maxdepth 2 -type f \\( -iname '*.fastq' -o -iname '*.fastq.gz' \\) ! -path '*/@eaDir/*' -printf '%s\n' | paste -sd+ - | sed 's/^$/0/' | bc")"
echo "TBRC_INPUT_BYTES=${INPUT_BYTES:-0}"
ssh "${SSH_HOST}" "cd '${PIPELINE_ROOT}' && export PATH='${PATH_PREFIX}' && export DATA_TABLE='${DATA_TABLE}' && export INPUTPATH='${INPUTPATH}' && conda activate '${SNAKEMAKE_ENV}' && ./snakemake.sh"
