#!/usr/bin/env bash
set -euo pipefail

stage_qc_raw() {
    local target="${TARGET_SAMPLE:-}"
    local id cond rep lt r1 r2 base
    while IFS=$'\t' read -r id cond rep lt r1 r2; do
        fastqc -q -o "$QC" "$r1" > "${LOG}/${id}.fastqc.log" 2>&1
        [[ "$lt" != paired ]] || fastqc -q -o "$QC" "$r2" >> "${LOG}/${id}.fastqc.log" 2>&1

        base=$(basename "$r1" .fastq.gz)
        [[ -s "${QC}/${base}_fastqc.zip" ]] || die "$id: fastqc produced no report"
        log "$id: raw qc done"
    done < <(rows "$SHEET" "$target")
}
