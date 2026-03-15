#!/bin/bash

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

require_tool rsync
require_tool ssh

USER_ID=""
DATA_PATH_1=""
DATA_PATH_2=""
FILE_NAME_1=""
FILE_NAME_2=""

while getopts "u:d:e:n:m:" flag; do
    case "${flag}" in
        u) USER_ID="${OPTARG}" ;;
        d) DATA_PATH_1="${OPTARG}" ;;
        e) DATA_PATH_2="${OPTARG}" ;;
        n) FILE_NAME_1="${OPTARG}" ;;
        m) FILE_NAME_2="${OPTARG}" ;;
        *) echo "Invalid option" >&2; exit 1 ;;
    esac
done

if [[ -z "${USER_ID}" || -z "${DATA_PATH_1}" || -z "${DATA_PATH_2}" || -z "${FILE_NAME_1}" || -z "${FILE_NAME_2}" ]]; then
    echo "Missing required arguments." >&2
    exit 1
fi

DTN_HOST="$(json_get_cluster_field dtn_host)"
SSH_HOST="$(json_get_cluster_field ssh_host)"
PIPELINE_ROOT="$(json_get_cluster_field pipeline_root)"
SNAKEMAKE_ENV="$(json_get_cluster_field snakemake_env)"
PATH_PREFIX="$(json_get_cluster_field path_prefix)"

RUN_DIR="runs/${USER_ID}/${FILE_NAME_1%.*}"
mkdir -p "${RUN_DIR}"
cp "${DATA_PATH_1}" "${RUN_DIR}/${FILE_NAME_1}"
cp "${DATA_PATH_2}" "${RUN_DIR}/${FILE_NAME_2}"
INPUT_BYTES="$(
    wc -c < "${RUN_DIR}/${FILE_NAME_1}" 2>/dev/null
    wc -c < "${RUN_DIR}/${FILE_NAME_2}" 2>/dev/null
)"
INPUT_BYTES="$(printf '%s\n' "${INPUT_BYTES}" | awk '{sum+=$1} END {print sum+0}')"
echo "TBRC_INPUT_BYTES=${INPUT_BYTES:-0}"

rsync -a -P "runs/${USER_ID}" "${DTN_HOST}:${PIPELINE_ROOT}/data/runs/"

DATA_TABLE="data/runs/${USER_ID}/${FILE_NAME_1%.*}/sample.json"
INPUTPATH="data/runs/${USER_ID}/${FILE_NAME_1%.*}"

ssh "${SSH_HOST}" "cd '${PIPELINE_ROOT}' && export PATH='${PATH_PREFIX}' && export DATA_TABLE='${DATA_TABLE}' && export INPUTPATH='${INPUTPATH}' && conda activate '${SNAKEMAKE_ENV}' && ./snakemake.sh"
