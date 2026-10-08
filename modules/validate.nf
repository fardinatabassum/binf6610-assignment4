process VALIDATE {
    container params.containers.tools

    input:
    path sheet
    path reads
    path ref
    path ref_index
    path ref_dict

    output:
    path sheet, emit: sheet

    script:
    """
    validate_samplesheet.sh ${sheet} ${ref}
    """
}
