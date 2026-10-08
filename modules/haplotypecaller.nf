process HAPLOTYPECALLER {
    tag "${meta.id}"
    container params.containers.gatk

    input:
    tuple val(meta), path(bam), path(bai)
    path ref
    path ref_index
    path ref_dict
    val region

    output:
    path "${meta.id}.g.vcf.gz",     emit: gvcf
    path "${meta.id}.g.vcf.gz.tbi", emit: tbi

    script:
    def region_arg = region ? "-L ${region}" : ""
    """
    gatk --java-options "-Xmx${task.memory.toGiga()}g" HaplotypeCaller \
        -R ${ref} \
        -I ${bam} \
        -O ${meta.id}.g.vcf.gz \
        -ERC GVCF \
        ${region_arg} \
        --native-pair-hmm-threads ${task.cpus}
    """
}
