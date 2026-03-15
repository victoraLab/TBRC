#!/bin/bash

set -euo pipefail

# Usage function
usage() {
    echo "Usage: $0 [-i INPUT] [-o OUTPUT] [-d DESTINY] [-s SAMPLE] [-t TRIMMING_SEQ] [-y SHOULD_TRIM] [-u SERVER_USER] [-n SERVER_NAME] [-e NOTIFICATION_EMAIL] [-k SHOULD_KEEP] [-p SERVER_RESULTS_PATH] [-j SERVER_STORAGE] [-r SERVER_SSH_PORT] [-m SERVER_TRANSFER_MODE] [-g RUN_IGBLAST] [-q RUN_CLONALITY] [-f ARCHIVE_FORMAT] [-z IGBLAST_SPECIES] [-l IGBLAST_PANEL] [-b IGBLAST_BIN] [-c IGBLAST_ORGANISM] [-v IGBLAST_DB_V] [-w IGBLAST_DB_D] [-x IGBLAST_DB_J] [-I IGBLAST_DATA] [-a IGBLAST_AUX]"
    exit 1
}

# Parsing arguments using getopts
while getopts ":i:o:s:d:t:y:u:e:k:p:j:r:m:g:q:f:z:l:b:c:v:w:x:I:a:" opt; do
    case ${opt} in
        i) INPUT="${OPTARG}" ;;
        o) OUTPUT="${OPTARG}" ;;
        s) SAMPLE="${OPTARG}" ;;
        d) DESTINY="${OPTARG}" ;;
        t) TRIMMING_SEQ="${OPTARG}" ;;
        y) SHOULD_TRIM="${OPTARG}" ;;
        u) SERVER_USER="${OPTARG}" ;;
        e) NOTIFICATION_EMAIL="${OPTARG}" ;;
        k) SHOULD_KEEP="${OPTARG}" ;;
        p) SERVER_RESULTS_PATH="${OPTARG}" ;;
        j) SERVER_STORAGE="${OPTARG}" ;;
        r) SERVER_SSH_PORT="${OPTARG}" ;;
        m) SERVER_TRANSFER_MODE="${OPTARG}" ;;
        g) RUN_IGBLAST="${OPTARG}" ;;
        q) RUN_CLONALITY="${OPTARG}" ;;
        f) ARCHIVE_FORMAT="${OPTARG}" ;;
        z) IGBLAST_SPECIES="${OPTARG}" ;;
        l) IGBLAST_PANEL="${OPTARG}" ;;
        b) IGBLAST_BIN="${OPTARG}" ;;
        c) IGBLAST_ORGANISM="${OPTARG}" ;;
        v) IGBLAST_DB_V="${OPTARG}" ;;
        w) IGBLAST_DB_D="${OPTARG}" ;;
        x) IGBLAST_DB_J="${OPTARG}" ;;
        I) IGBLAST_DATA="${OPTARG}" ;;
        a) IGBLAST_AUX="${OPTARG}" ;;
        *) usage ;;
    esac
done

INHERITED_IGBLAST_DATA="${IGBLAST_DATA:-}"
FINAL_FASTA_PATH="${DESTINY}/split1/split2/collapsed/head/final/final.fasta"
RESULT_FASTA_PATH="${DESTINY}/${SAMPLE}.final.fasta"
IMGT_READY_FASTA_PATH="${DESTINY}/${SAMPLE}.imgt.ready.fasta"
QC_DIR="${DESTINY}/qc"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QC_SCRIPT="${SCRIPT_DIR}/fasta_qc.R"
PLATE_QC_SCRIPT="${SCRIPT_DIR}/plate_stats.R"
PLATE_DEPTH_QC_SCRIPT="${SCRIPT_DIR}/plate_depth_qc.R"
IGBLAST_SCRIPT="${SCRIPT_DIR}/run_igblast.sh"
CLONALITY_SCRIPT="${SCRIPT_DIR}/run_clonality.R"
PLATE_QC_DIR="${QC_DIR}/plates"
IGBLAST_DIR="${DESTINY}/igblast"
CLONALITY_DIR="${DESTINY}/clonality"
ARCHIVE_NAME="$(basename "${OUTPUT}")"
ARCHIVE_PATH="${DESTINY}/${ARCHIVE_NAME}"
ARCHIVE_FORMAT="${ARCHIVE_FORMAT:-zip}"
PACKAGE_ROOT="${DESTINY}/.package_${SAMPLE}"
PACKAGE_DIR="${PACKAGE_ROOT}/${SAMPLE}"

normalize_optional() {
    local value="${1:-}"
    local lowered
    lowered="$(printf '%s' "${value}" | tr '[:upper:]' '[:lower:]')"
    if [[ -z "${value}" || "${lowered}" == "na" || "${lowered}" == "nan" || "${lowered}" == "null" ]]; then
        return 0
    fi
    printf '%s' "${value}"
}

ARCHIVE_FORMAT="$(normalize_optional "${ARCHIVE_FORMAT}")"
IGBLAST_BIN="$(normalize_optional "${IGBLAST_BIN}")"
IGBLAST_SPECIES="$(normalize_optional "${IGBLAST_SPECIES}")"
IGBLAST_PANEL="$(normalize_optional "${IGBLAST_PANEL}")"
IGBLAST_DB_V="$(normalize_optional "${IGBLAST_DB_V}")"
IGBLAST_DB_D="$(normalize_optional "${IGBLAST_DB_D}")"
IGBLAST_DB_J="$(normalize_optional "${IGBLAST_DB_J}")"
IGBLAST_DATA="$(normalize_optional "${IGBLAST_DATA}")"
IGBLAST_AUX="$(normalize_optional "${IGBLAST_AUX}")"
IGBLAST_ORGANISM="$(normalize_optional "${IGBLAST_ORGANISM}")"

ARCHIVE_FORMAT="${ARCHIVE_FORMAT:-zip}"
EFFECTIVE_IGBLAST_DATA="${IGBLAST_DATA:-${INHERITED_IGBLAST_DATA}}"

mkdir -p "${DESTINY}"
mkdir -p "${QC_DIR}"
echo "Working directory: $(pwd)"
echo "Result directory: ${DESTINY}"

if [[ ! -f "${FINAL_FASTA_PATH}" ]]; then
    echo "Expected assembled FASTA was not found at ${FINAL_FASTA_PATH}." >&2
    echo "The barcode splitting/assembly stage likely finished without producing final.fasta. Check logs/${SAMPLE}.genfasta.err.log." >&2
    exit 1
fi

mv "${FINAL_FASTA_PATH}" "${RESULT_FASTA_PATH}"

if [[ "${SHOULD_TRIM,,}" == "true" ]] && command -v Rscript >/dev/null 2>&1; then
    Rscript "${QC_SCRIPT}" "${RESULT_FASTA_PATH}" "${QC_DIR}" "pre_trim"
fi

# Trim fasta file if specified
if [[ "${SHOULD_TRIM,,}" == "true" ]]; then
    cutadapt -g "${TRIMMING_SEQ}" -e 0.2 --discard-untrimmed -o "${IMGT_READY_FASTA_PATH}" "${RESULT_FASTA_PATH}"
else
    cp "${RESULT_FASTA_PATH}" "${IMGT_READY_FASTA_PATH}"
fi

if command -v Rscript >/dev/null 2>&1; then
    if [[ "${SHOULD_TRIM,,}" == "true" ]]; then
        Rscript "${QC_SCRIPT}" "${IMGT_READY_FASTA_PATH}" "${QC_DIR}" "post_trim"
    else
        Rscript "${QC_SCRIPT}" "${IMGT_READY_FASTA_PATH}" "${QC_DIR}" "final_output"
    fi
fi

if [[ -f "${DESTINY}/BC.stats.txt" && -f "${DESTINY}/collapsed.stats.txt" ]] && command -v Rscript >/dev/null 2>&1; then
    Rscript "${PLATE_QC_SCRIPT}" "${DESTINY}/" "${PLATE_QC_DIR}"
fi

if [[ -f "${IMGT_READY_FASTA_PATH}" ]] && command -v Rscript >/dev/null 2>&1; then
    if Rscript -e "quit(status = if (requireNamespace('ggplate', quietly = TRUE) && requireNamespace('clonality', quietly = TRUE)) 0 else 1)" >/dev/null 2>&1; then
        Rscript "${PLATE_DEPTH_QC_SCRIPT}" "${IMGT_READY_FASTA_PATH}" "${PLATE_QC_DIR}"
    else
        echo "Plate read-depth QC skipped because ggplate and/or clonality are not installed." >&2
    fi
fi

if [[ "${RUN_IGBLAST,,}" == "true" ]]; then
    if IGBLAST_DATA="${EFFECTIVE_IGBLAST_DATA}" IGBLAST_BIN="${IGBLAST_BIN:-igblastn}" "${IGBLAST_SCRIPT}" "${IMGT_READY_FASTA_PATH}" "${IGBLAST_DIR}" "${SAMPLE}" "${IGBLAST_SPECIES:-human}" "${IGBLAST_PANEL:-ig_all}" "${IGBLAST_DB_V:-}" "${IGBLAST_DB_D:-}" "${IGBLAST_DB_J:-}" "${IGBLAST_AUX:-}" "${IGBLAST_ORGANISM:-human}" 2>/tmp/tbrc_igblast.stderr; then
        echo "IGBlast completed."
    else
        IGBLAST_STATUS=$?
        cat /tmp/tbrc_igblast.stderr >&2 || true
        if [[ "${IGBLAST_STATUS}" -eq 2 ]]; then
            echo "IGBlast skipped because server-side dependencies or database paths are not configured." >&2
        else
            exit "${IGBLAST_STATUS}"
        fi
    fi
fi

if [[ "${RUN_CLONALITY,,}" == "true" ]]; then
    IGBLAST_OUTPUT="${IGBLAST_DIR}/${SAMPLE}.igblast.tsv"

    if [[ ! -f "${IGBLAST_OUTPUT}" ]]; then
        echo "Clonality skipped because IGBlast output was not found at ${IGBLAST_OUTPUT}." >&2
    elif command -v Rscript >/dev/null 2>&1; then
        if Rscript -e "quit(status = if (requireNamespace('clonality', quietly = TRUE)) 0 else 1)" >/dev/null 2>&1; then
            if Rscript "${CLONALITY_SCRIPT}" "${IGBLAST_OUTPUT}" "${CLONALITY_DIR}" "${SAMPLE}" "${IGBLAST_PANEL:-ig_all}"; then
                echo "Clonality completed."
            else
                CLONALITY_STATUS=$?
                if [[ "${CLONALITY_STATUS}" -eq 2 ]]; then
                    echo "Clonality skipped for the selected IGBlast receptor scope." >&2
                else
                    exit "${CLONALITY_STATUS}"
                fi
            fi
        else
            echo "Clonality skipped because the clonality R package is not installed." >&2
        fi
    else
        echo "Clonality skipped because Rscript is not available." >&2
    fi
fi

rm -f "${OUTPUT}" "${ARCHIVE_PATH}"
rm -rf "${PACKAGE_ROOT}"
mkdir -p "${PACKAGE_DIR}"
(
    cp "${IMGT_READY_FASTA_PATH}" "${PACKAGE_DIR}/"
    cp "${RESULT_FASTA_PATH}" "${PACKAGE_DIR}/"
    cp -R "${QC_DIR}" "${PACKAGE_DIR}/"
    if [[ -d "${IGBLAST_DIR}" ]]; then
        cp -R "${IGBLAST_DIR}" "${PACKAGE_DIR}/"
    fi
    if [[ -d "${CLONALITY_DIR}" ]]; then
        cp -R "${CLONALITY_DIR}" "${PACKAGE_DIR}/"
    fi
    cd "${PACKAGE_ROOT}"
    if [[ "${ARCHIVE_FORMAT}" == "tar.gz" ]]; then
        tar -czf "${ARCHIVE_PATH}" "${SAMPLE}"
    else
        zip -r "${ARCHIVE_PATH}" "${SAMPLE}"
    fi
)
rm -rf "${PACKAGE_ROOT}"

echo "Packaged output target: ${OUTPUT}"
echo "Packaged archive path: ${ARCHIVE_PATH}"
if [[ -f "${ARCHIVE_PATH}" ]]; then
    ls -lh "${ARCHIVE_PATH}"
else
    echo "Packaged archive not found at ${ARCHIVE_PATH}" >&2
    exit 1
fi

# Remove intermediates before transfer so cleanup still happens if rsync fails.
if [[ "${SHOULD_KEEP,,}" == "false" ]]; then
    rm -rf "${DESTINY}/split1/"
    rm -f "${DESTINY}/${SAMPLE}.fasta"
    rm -f "${DESTINY}/${SAMPLE}_S1_R1_001.fastq"
    rm -f "${DESTINY}/${SAMPLE}_S1_R2_001.fastq"
    rm -f "${DESTINY}/BC.stats.txt"
    rm -f "${DESTINY}/collapsed.stats.txt"
fi

# Transfer to the configured results destination
if [[ "${SERVER_TRANSFER_MODE:-push}" == "pull" ]]; then
    echo "Transfer mode: pull"
    echo "Remote rsync skipped. Synology should pull: ${ARCHIVE_PATH}"
elif [[ -n "${SERVER_RESULTS_PATH:-}" && "${SERVER_RESULTS_PATH}" != "NA" ]]; then
    REMOTE_RESULTS_DIR="${SERVER_RESULTS_PATH%/}/${SERVER_USER}/"
    REMOTE_HOST="${REMOTE_RESULTS_DIR%%:*}"
    REMOTE_PATH="${REMOTE_RESULTS_DIR#*:}"
    SSH_ARGS=()
    RSYNC_SSH=()

    if [[ "${REMOTE_HOST}" == "${REMOTE_PATH}" ]]; then
        echo "Results destination is not in host:path format: ${SERVER_RESULTS_PATH}" >&2
        exit 1
    fi

    if [[ -n "${SERVER_SSH_PORT:-}" && "${SERVER_SSH_PORT}" != "NA" ]]; then
        SSH_ARGS=(-p "${SERVER_SSH_PORT}")
        RSYNC_SSH=(-e "ssh -p ${SERVER_SSH_PORT}")
    fi

    echo "Transfer destination: ${REMOTE_RESULTS_DIR}"
    echo "Transfer ssh port: ${SERVER_SSH_PORT:-default}"
    ssh "${SSH_ARGS[@]}" "${REMOTE_HOST}" "mkdir -p '${REMOTE_PATH%/}'"
    rsync -avP "${RSYNC_SSH[@]}" "${ARCHIVE_PATH}" "${REMOTE_RESULTS_DIR}"
    REMOTE_FILE_PATH="${REMOTE_PATH%/}/$(basename "${ARCHIVE_PATH}")"
    echo "Remote file check: ${REMOTE_HOST}:${REMOTE_FILE_PATH}"
    ssh "${SSH_ARGS[@]}" "${REMOTE_HOST}" "ls -lh '${REMOTE_FILE_PATH}'"
fi

echo "${SERVER_STORAGE} ok."

# Send an email notification
mail -s "Your Clonality Run ${SAMPLE} is completed" "${NOTIFICATION_EMAIL}" <<< "Your clonality run is completed successfully and it was uploaded to the folder: pipelines/tbrc/results/ of ${SERVER_STORAGE}."
