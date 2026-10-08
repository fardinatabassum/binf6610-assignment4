#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# run_sample.sh — single-sample pipeline driver (stages 0-5)
#-----------------------------------------------------------------------------
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "${HERE}/lib/common.sh"
load_stages "${HERE}/stages"

SHEET="${1:?usage: run_sample.sh <samplesheet.csv> <outdir> <sample_id> [last-stage]}"
OUT="${2:?usage: run_sample.sh <samplesheet.csv> <outdir> <sample_id> [last-stage]}"
TARGET_SAMPLE="${3:?usage: run_sample.sh <samplesheet.csv> <outdir> <sample_id> [last-stage]}"
LAST="${4:-quantify}"

# Refuse cohort stages (6-9) because single array tasks cannot run across all samples
case "$LAST" in
    merge|analyze|qc_report|publish|cohort)
        die "run_sample.sh cannot run cohort stages (6-9)"
        ;;
esac

setup_dirs "$OUT"

STAGES=(validate qc_raw trim align postprocess quantify)

n=0
for stage in "${STAGES[@]}"; do
    log "===== stage ${n} : ${stage} (${TARGET_SAMPLE}) ====="
    "stage_${stage}"
    [[ "$stage" == "$LAST" ]] && break
    n=$(( n + 1 ))
done
log "sample ${TARGET_SAMPLE} done"
