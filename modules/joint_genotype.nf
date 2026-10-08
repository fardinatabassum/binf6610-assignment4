process JOINT_GENOTYPE {
    container params.containers.gatk

    input:
    path gvcfs
    path tbis
    path ref
    path ref_index
    path ref_dict
    val region

    output:
    path "cohort.raw.vcf.gz", emit: vcf

    script:
    def v_inputs = gvcfs.collect { "-V ${it}" }.join(' ')
    def region_arg = region ? "-L ${region}" : ""
    """
    gatk --java-options "-Xmx${task.memory.toGiga()}g" CombineGVCFs \
        -R ${ref} \
        ${v_inputs} \
        -O cohort.g.vcf.gz

    gatk --java-options "-Xmx${task.memory.toGiga()}g" GenotypeGVCFs \
        -R ${ref} \
        -V cohort.g.vcf.gz \
        -O cohort.raw.vcf.gz \
        ${region_arg}
    """
}
