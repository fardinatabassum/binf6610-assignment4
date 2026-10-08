#!/usr/bin/env bash
set -euo pipefail

stage_merge() {
    local id cond rep lt r1 r2 gvcf_args=()
    while IFS=$'\t' read -r id cond rep lt r1 r2; do
        [[ -s "${VAR}/${id}.g.vcf.gz" ]] || die "missing GVCF for sample: $id"
        gvcf_args+=(-V "${VAR}/${id}.g.vcf.gz")
    done < <(rows "$SHEET")

    gatk CombineGVCFs \
        -R "$REF" \
        "${gvcf_args[@]}" \
        --tmp-dir "${TMPDIR:-/tmp}" \
        -O "${VAR}/cohort.g.vcf.gz" \
        2> "${LOG}/combine_gvcfs.log"

    gatk GenotypeGVCFs \
        -R "$REF" \
        -V "${VAR}/cohort.g.vcf.gz" \
        -O "${VAR}/cohort.raw.vcf.gz" \
        -L "$REGION" \
        --tmp-dir "${TMPDIR:-/tmp}" \
        2> "${LOG}/genotype_gvcfs.log"

    [[ -s "${VAR}/cohort.raw.vcf.gz" ]] || die "joint genotyping produced no raw VCF"
    log "cohort raw VCF generated"
}
