#!/usr/bin/env bash
set -euo pipefail

stage_quantify() {
    local target="${TARGET_SAMPLE:-}"
    local id cond rep lt r1 r2
    while IFS=$'\t' read -r id cond rep lt r1 r2; do
        gatk HaplotypeCaller \
            -R "$REF" \
            -I "${POST}/${id}.md.bam" \
            -O "${VAR}/${id}.g.vcf.gz" \
            -L "$REGION" \
            --tmp-dir "${TMPDIR:-/tmp}" \
            -ERC GVCF \
            2> "${LOG}/${id}.haplotypecaller.log"

        [[ -s "${VAR}/${id}.g.vcf.gz" ]] || die "$id: HaplotypeCaller produced no GVCF"
        log "$id: gvcf generated"
    done < <(rows "$SHEET" "$target")
}
