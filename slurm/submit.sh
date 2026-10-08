#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/conf/slurm.env"

# Slurm requires the log folder to exist before job start
mkdir -p "${HERE}/logs"
cd "${HERE}"

# Submit the array job (stages 0-5 for all 8 samples)
ARRAY_ID=$(sbatch --parsable 01_persample.sbatch)
echo "Submitted sample array job: ${ARRAY_ID}"

# Submit the cohort job (stages 6-9) gated on afterok
COHORT_ID=$(sbatch --parsable --dependency=afterok:${ARRAY_ID} --kill-on-invalid-dep=yes 02_cohort.sbatch)
echo "Submitted cohort job: ${COHORT_ID} (depends on ${ARRAY_ID})"
