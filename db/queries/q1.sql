SELECT
    runs.run_id,
    pipelines.implementation,
    runs.platform,
    COUNT(run_samples.sample_id) AS n_samples,
    ROUND((julianday(runs.finished_at) - julianday(runs.started_at)) * 24 * 60, 1) AS minutes
FROM runs
JOIN pipelines ON pipelines.pipeline_id = runs.pipeline_id
JOIN run_samples ON run_samples.run_id = runs.run_id
GROUP BY runs.run_id
ORDER BY julianday(runs.started_at) ASC;
