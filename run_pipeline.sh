#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# run_pipeline.sh — full-cohort pipeline driver (stages 0-9)
#-----------------------------------------------------------------------------
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "${HERE}/lib/common.sh"
load_stages "${HERE}/stages"

SHEET="${1:?usage: run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]}"
OUT="${2:?usage: run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]}"
LAST="${3:-publish}"
TARGET_SAMPLE=""

setup_dirs "$OUT"

STAGES=(validate qc_raw trim align postprocess quantify merge analyze qc_report publish)

n=0
for stage in "${STAGES[@]}"; do
    log "===== stage ${n} : ${stage} ====="
    "stage_${stage}"
    [[ "$stage" == "$LAST" ]] && break
    n=$(( n + 1 ))
done
log "done"
