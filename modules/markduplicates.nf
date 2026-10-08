process MARKDUPLICATES {
    tag "${meta.id}"
    container params.containers.gatk

    input:
    tuple val(meta), path(bam)

    output:
    tuple val(meta), path("${meta.id}.dedup.bam"), path("${meta.id}.dedup.bai"), emit: bam

    script:
    """
    gatk --java-options "-Xmx${task.memory.toGiga()}g" MarkDuplicates \
        -I ${bam} \
        -O ${meta.id}.dedup.bam \
        -M ${meta.id}.metrics.txt \
        --CREATE_INDEX true
    """
}
