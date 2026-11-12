SELECT
    run_id,
    COUNT(*) AS n_variants,
    SUM(filter = 'PASS') AS n_pass
FROM variants
GROUP BY run_id;
