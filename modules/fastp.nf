process FASTP {
    tag "${meta.id}"
    container params.containers.fastp

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("*.trim.fastq.gz"), emit: reads
    path "${meta.id}.fastp.json",            emit: json

    script:
    if (meta.single_end) {
        """
        fastp \
            -i ${reads[0]} \
            -o ${meta.id}.trim.fastq.gz \
            -j ${meta.id}.fastp.json \
            -h ${meta.id}.fastp.html
        """
    } else {
        """
        fastp \
            -i ${reads[0]} \
            -I ${reads[1]} \
            -o ${meta.id}_1.trim.fastq.gz \
            -O ${meta.id}_2.trim.fastq.gz \
            -j ${meta.id}.fastp.json \
            -h ${meta.id}.fastp.html
        """
    }
}
