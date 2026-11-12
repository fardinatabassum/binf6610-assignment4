SELECT
    samples.sample_id,
    samples.sex,
    COUNT(run_samples.run_id) AS n_runs
FROM samples
LEFT JOIN run_samples ON run_samples.sample_id = samples.sample_id
GROUP BY samples.sample_id
ORDER BY samples.sample_id ASC;
