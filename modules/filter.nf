process FILTER {
    container params.containers.gatk

    input:
    path vcf
    path ref
    path ref_index
    path ref_dict

    output:
    path "cohort.filtered.vcf.gz",     emit: vcf
    path "cohort.filtered.vcf.gz.tbi", emit: tbi
    path "variants.tsv",               emit: table

    script:
    """
    gatk IndexFeatureFile -I ${vcf}

    gatk VariantFiltration \
        -R ${ref} \
        -V ${vcf} \
        -O cohort.filtered.vcf.gz \
        --filter-name "LowQual" \
        --filter-expression "QUAL < 30.0"

    printf 'chrom\\tpos\\tref\\talt\\tqual\\tfilter\\n' > variants.tsv
    bcftools query -f '%CHROM\\t%POS\\t%REF\\t%ALT\\t%QUAL\\t%FILTER\\n' cohort.filtered.vcf.gz >> variants.tsv
    """
}
