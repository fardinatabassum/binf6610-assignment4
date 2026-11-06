#!/usr/bin/env bash
set -euo pipefail

stage_analyze() {
    gatk VariantFiltration \
        -R "$REF" \
        -V "${VAR}/cohort.raw.vcf.gz" \
        -O "${RES}/cohort.filtered.vcf.gz" \
        --filter-name "LowQual" \
        --filter-expression "QUAL < 30.0" \
        --tmp-dir "${TMPDIR:-/tmp}" \
        2> "${LOG}/variant_filtration.log"

    [[ -s "${RES}/cohort.filtered.vcf.gz" ]] || die "VariantFiltration produced no filtered VCF"
    log "cohort variants filtered"
}
