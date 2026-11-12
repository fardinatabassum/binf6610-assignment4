SELECT
    runs.run_id,
    runs.folder || '/cohort.filtered.vcf.gz' AS file,
    outputs.sha256
FROM runs
JOIN outputs ON outputs.run_id = runs.run_id
WHERE outputs.path = 'cohort.filtered.vcf.gz';
