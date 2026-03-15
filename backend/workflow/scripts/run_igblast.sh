#!/bin/bash

set -euo pipefail

QUERY_FASTA="$1"
OUTPUT_DIR="$2"
SAMPLE_NAME="$3"
SPECIES="${4:-human}"
PANEL="${5:-ig_all}"
DB_V="${6:-}"
DB_D="${7:-}"
DB_J="${8:-}"
AUX_PATH="${9:-}"
ORGANISM="${10:-human}"
IGBLAST_BIN="${IGBLAST_BIN:-igblastn}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
IGBLAST_ROOT="${BACKEND_DIR}/igblast"
DB_BUILD_ROOT="${IGBLAST_ROOT}/work"
REFS_ROOT="${IGBLAST_ROOT}/refs"
IGBLAST_DATA_DIR="${IGBLAST_ROOT}/internal_data"

resolve_aux_path() {
    local requested_path="${1:-}"
    local species_name="${2:-}"
    local organism_name="${3:-}"
    local search_dir=""
    local candidate=""
    local -a candidate_names=(
        "${species_name}.gl.aux"
        "${species_name}_gl.aux"
        "${organism_name}.gl.aux"
        "${organism_name}_gl.aux"
    )

    if [[ -n "${requested_path}" ]]; then
        if [[ -f "${requested_path}" ]]; then
            printf '%s' "${requested_path}"
            return 0
        fi
        if [[ -d "${requested_path}" ]]; then
            search_dir="${requested_path}"
        fi
    fi

    if [[ -z "${search_dir}" && -f "${REFS_ROOT}/${species_name}.gl.aux" ]]; then
        printf '%s' "${REFS_ROOT}/${species_name}.gl.aux"
        return 0
    fi

    if [[ -z "${search_dir}" && -n "${IGBLAST_DATA:-}" ]]; then
        candidate="$(cd "$(dirname "${IGBLAST_DATA}")" && pwd)/optional_file"
        if [[ -d "${candidate}" ]]; then
            search_dir="${candidate}"
        fi
    fi

    if [[ -z "${search_dir}" && -d "${IGBLAST_ROOT}/optional_file" ]]; then
        search_dir="${IGBLAST_ROOT}/optional_file"
    fi

    if [[ -n "${search_dir}" ]]; then
        for candidate in "${candidate_names[@]}"; do
            if [[ -f "${search_dir}/${candidate}" ]]; then
                printf '%s' "${search_dir}/${candidate}"
                return 0
            fi
        done
    fi

    return 0
}

normalize_optional() {
    local value="${1:-}"
    local lowered
    lowered="$(printf '%s' "${value}" | tr '[:upper:]' '[:lower:]')"
    if [[ -z "${value}" || "${lowered}" == "na" || "${lowered}" == "nan" || "${lowered}" == "null" ]]; then
        return 0
    fi
    printf '%s' "${value}"
}

SPECIES="$(normalize_optional "${SPECIES}")"
PANEL="$(normalize_optional "${PANEL}")"
DB_V="$(normalize_optional "${DB_V}")"
DB_D="$(normalize_optional "${DB_D}")"
DB_J="$(normalize_optional "${DB_J}")"
AUX_PATH="$(normalize_optional "${AUX_PATH}")"
ORGANISM="$(normalize_optional "${ORGANISM}")"
IGBLAST_BIN="$(normalize_optional "${IGBLAST_BIN}")"

SPECIES="${SPECIES:-human}"
PANEL="${PANEL:-ig_all}"
IGBLAST_BIN="${IGBLAST_BIN:-igblastn}"

if [[ "${ORGANISM}" == "NA" || -z "${ORGANISM}" ]]; then
    ORGANISM="${SPECIES}"
fi

if [[ -z "${DB_V}" || -z "${DB_J}" ]]; then
    PANEL_DIR="${DB_BUILD_ROOT}/${SPECIES}/${PANEL}"
    DB_V="${PANEL_DIR}/${SPECIES}_${PANEL}_V"
    DB_D="${PANEL_DIR}/${SPECIES}_${PANEL}_D"
    DB_J="${PANEL_DIR}/${SPECIES}_${PANEL}_J"
fi

if [[ -z "${DB_V}" || -z "${DB_J}" ]]; then
    echo "IGBlast skipped: missing V/J database paths." >&2
    exit 2
fi

if ! command -v "${IGBLAST_BIN}" >/dev/null 2>&1; then
    echo "IGBlast skipped: igblastn binary not found (${IGBLAST_BIN})." >&2
    exit 2
fi

if [[ -n "${IGBLAST_DATA:-}" && -d "${IGBLAST_DATA}" ]]; then
    export IGBLAST_DATA
elif [[ -d "${IGBLAST_DATA_DIR}" ]]; then
    export IGBLAST_DATA="${IGBLAST_DATA_DIR}"
else
    echo "IGBlast skipped: internal_data directory was not found. Place the IgBlast internal_data folder under ${IGBLAST_ROOT}/internal_data or set IGBLAST_DATA." >&2
    exit 2
fi

AUX_PATH="$(resolve_aux_path "${AUX_PATH}" "${SPECIES}" "${ORGANISM}")"

mkdir -p "${OUTPUT_DIR}"

IGBLAST_OUTPUT="${OUTPUT_DIR}/${SAMPLE_NAME}.igblast.tsv"
IGBLAST_ARGS=(
    -germline_db_V "${DB_V}"
    -germline_db_J "${DB_J}"
    -organism "${ORGANISM}"
    -query "${QUERY_FASTA}"
    -outfmt 19
    -out "${IGBLAST_OUTPUT}"
)

if [[ -n "${DB_D}" && "${DB_D}" != "NA" && -f "${DB_D}.nhr" ]]; then
    IGBLAST_ARGS+=(-germline_db_D "${DB_D}")
fi

if [[ -n "${AUX_PATH}" && "${AUX_PATH}" != "NA" ]]; then
    IGBLAST_ARGS+=(-auxiliary_data "${AUX_PATH}")
fi

if [[ ! -f "${DB_V}.nhr" || ! -f "${DB_V}.nin" || ! -f "${DB_V}.nsq" || ! -f "${DB_J}.nhr" || ! -f "${DB_J}.nin" || ! -f "${DB_J}.nsq" ]]; then
    echo "IGBlast skipped: built databases were not found for species=${SPECIES}, panel=${PANEL}. Run backend/igblast/setup_igblast_databases.sh first." >&2
    exit 2
fi

echo "IGBlast binary: ${IGBLAST_BIN}" >&2
echo "IGBlast species/panel: ${SPECIES}/${PANEL}" >&2
echo "IGBlast V DB: ${DB_V}" >&2
echo "IGBlast J DB: ${DB_J}" >&2
echo "IGBlast aux: ${AUX_PATH:-none}" >&2
echo "IGBlast internal_data: ${IGBLAST_DATA}" >&2

"${IGBLAST_BIN}" "${IGBLAST_ARGS[@]}"
echo "IGBlast output: ${IGBLAST_OUTPUT}"
