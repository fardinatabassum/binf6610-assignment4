process FASTQC {
    tag "${meta.id}"
    container params.containers.fastqc

    input:
    tuple val(meta), path(reads)

    output:
    path "*.zip", emit: zip

    script:
    """
    fastqc -q ${reads}
    """
}
