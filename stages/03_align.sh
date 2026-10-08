#!/usr/bin/env bash
set -euo pipefail

stage_align() {
    local target="${TARGET_SAMPLE:-}"
    local id cond rep lt r1 r2
    local sort_tmp="${TMPDIR:-/tmp}/sort_${target:-all}"
    mkdir -p "$sort_tmp"

    while IFS=$'\t' read -r id cond rep lt r1 r2; do
        if [[ "$lt" == paired ]]; then
            bwa mem -t "$THREADS" -R "@RG\tID:${id}\tSM:${id}" "$REF" \
                "${TRIM}/${id}_R1.fastq.gz" "${TRIM}/${id}_R2.fastq.gz" \
                2> "${LOG}/${id}.bwa.log" | samtools sort -@ "$THREADS" -T "${sort_tmp}/${id}" -o "${ALN}/${id}.bam"
        else
            bwa mem -t "$THREADS" -R "@RG\tID:${id}\tSM:${id}" "$REF" \
                "${TRIM}/${id}_R1.fastq.gz" \
                2> "${LOG}/${id}.bwa.log" | samtools sort -@ "$THREADS" -T "${sort_tmp}/${id}" -o "${ALN}/${id}.bam"
        fi
        samtools index -@ "$THREADS" "${ALN}/${id}.bam"
        [[ -s "${ALN}/${id}.bam" ]] || die "$id: bwa mem produced no BAM"
        log "$id: aligned and indexed"
    done < <(rows "$SHEET" "$target")
}
