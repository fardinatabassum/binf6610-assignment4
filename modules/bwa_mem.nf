process BWA_MEM {
    tag "${meta.id}"
    container params.containers.bwa

    input:
    tuple val(meta), path(reads)
    path ref
    path ref_index

    output:
    tuple val(meta), path("${meta.id}.sorted.bam"), emit: bam

    script:
    def rg = "@RG\\tID:${meta.id}\\tSM:${meta.id}"
    """
    bwa mem -t ${task.cpus} -R "${rg}" ${ref} ${reads} | \
        samtools sort -@ ${task.cpus} -o ${meta.id}.sorted.bam -
    """
}
