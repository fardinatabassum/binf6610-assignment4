CREATE TABLE pipelines (
    pipeline_id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    version TEXT NOT NULL,
    implementation TEXT NOT NULL,
    UNIQUE (name, version, implementation)
);

CREATE TABLE runs (
    run_id TEXT PRIMARY KEY,
    pipeline_id INTEGER NOT NULL REFERENCES pipelines (pipeline_id),
    started_at TEXT NOT NULL,
    finished_at TEXT NOT NULL,
    exit_status TEXT NOT NULL,
    platform TEXT NOT NULL,
    executor TEXT,
    samplesheet TEXT,
    reference TEXT,
    folder TEXT NOT NULL
);

CREATE TABLE samples (
    sample_id TEXT PRIMARY KEY,
    sex TEXT,
    population TEXT,
    family TEXT,
    father TEXT,
    mother TEXT,
    phenotype TEXT,
    is_synthetic_phenotype INTEGER
);

CREATE TABLE run_samples (
    run_id TEXT NOT NULL REFERENCES runs (run_id),
    sample_id TEXT NOT NULL REFERENCES samples (sample_id),
    condition TEXT NOT NULL,
    library_type TEXT,
    PRIMARY KEY (run_id, sample_id)
);

CREATE TABLE variants (
    run_id TEXT NOT NULL REFERENCES runs (run_id),
    chrom TEXT NOT NULL,
    pos INTEGER NOT NULL,
    ref TEXT NOT NULL,
    alt TEXT NOT NULL,
    qual REAL,
    filter TEXT NOT NULL
);

CREATE TABLE outputs (
    run_id TEXT NOT NULL REFERENCES runs (run_id),
    path TEXT NOT NULL,
    sha256 TEXT NOT NULL,
    PRIMARY KEY (run_id, path)
);
