#!/usr/bin/env bash
set -euo pipefail

stage_qc_report() {
    multiqc -q -f -o "$RES" "$QC" "$LOG" 2> "${LOG}/multiqc.log"
    [[ -s "${RES}/multiqc_report.html" ]] || die "multiqc produced no report"
    log "MultiQC report created"
}
