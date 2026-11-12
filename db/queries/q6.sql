SELECT
    run_samples.run_id,
    samples.sex,
    COUNT(*) AS n_samples
FROM run_samples
JOIN samples ON samples.sample_id = run_samples.sample_id
GROUP BY run_samples.run_id, samples.sex;
