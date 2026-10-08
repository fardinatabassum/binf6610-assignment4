#!/usr/bin/env bash
set -euo pipefail

stage_validate() {
    local target="${TARGET_SAMPLE:-}"
    local id cond rep lt r1 r2 problems=0 n1 n2 r1_ok r2_ok

    [[ -s "$SHEET" ]] || die "samplesheet missing or empty: $SHEET"

    while IFS=$'\t' read -r id cond rep lt r1 r2; do
        [[ -n "$id" ]] || { log "a row has no sample_id"; problems=$(( problems + 1 )); continue; }
        [[ -s "$r1" ]] || { log "$id: R1 missing or empty: $r1"; problems=$(( problems + 1 )); }
        if [[ "$lt" == paired ]]; then
            [[ -s "$r2" ]] || { log "$id: declared paired but R2 is missing"; problems=$(( problems + 1 )); }
        fi
        if [[ -z "$r2" && "$lt" == paired ]]; then
            log "$id: r2_fastq is empty but library_type says paired"
            problems=$(( problems + 1 ))
        fi

        r1_ok=0; r2_ok=0
        if [[ -s "$r1" ]]; then
            if gzip -t "$r1" 2>/dev/null; then r1_ok=1
            else log "$id: R1 is not a valid gzip file"; problems=$(( problems + 1 )); fi
        fi
        if [[ "$lt" == paired && -s "$r2" ]]; then
            if gzip -t "$r2" 2>/dev/null; then r2_ok=1
            else log "$id: R2 is not a valid gzip file"; problems=$(( problems + 1 )); fi
        fi

        if (( r1_ok )); then
            n1=$(gzip -dc "$r1" | wc -l)
            (( n1 % 4 == 0 )) || { log "$id: R1 has $n1 lines, not a whole number of records"; problems=$(( problems + 1 )); }
            if (( r2_ok )); then
                n2=$(gzip -dc "$r2" | wc -l)
                (( n1 == n2 )) || { log "$id: R1 has $(( n1 / 4 )) reads, R2 has $(( n2 / 4 ))"; problems=$(( problems + 1 )); }
            fi
        fi
    done < <(rows "$SHEET" "$target")

    if [[ -z "$target" ]]; then
        local dupes
        dupes=$(awk -F, 'NR>1 { print $1 }' "$SHEET" | sort | uniq -d)
        [[ -z "$dupes" ]] || { log "duplicate sample_id: $dupes"; problems=$(( problems + 1 )); }
    fi

    [[ -s "$REF" ]] || { log "reference missing or empty: $REF"; problems=$(( problems + 1 )); }
    (( problems == 0 )) || die "validation failed with ${problems} problem(s)"
    log "validation passed"
}
