process MULTIQC {
    container params.containers.multiqc

    input:
    path qc_files

    output:
    path "multiqc_report.html", emit: report

    script:
    """
    multiqc . -n multiqc_report.html
    """
}
