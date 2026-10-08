#!/usr/bin/env bash
set -euo pipefail

stage_postprocess() {
    local target="${TARGET_SAMPLE:-}"
    local id cond rep lt r1 r2
    while IFS=$'\t' read -r id cond rep lt r1 r2; do
        gatk MarkDuplicates \
            -I "${ALN}/${id}.bam" \
            -O "${POST}/${id}.md.bam" \
            -M "${LOG}/${id}.metrics.txt" \
            --TMP_DIR "${TMPDIR:-/tmp}" \
            --CREATE_INDEX true \
            2> "${LOG}/${id}.markdup.log"

        [[ -s "${POST}/${id}.md.bam" ]] || die "$id: MarkDuplicates produced no BAM"
        log "$id: mark duplicates finished"
    done < <(rows "$SHEET" "$target")
}
