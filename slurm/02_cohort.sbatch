#!/usr/bin/env bash
#SBATCH --job-name=vcall-cohort
#SBATCH --export=NONE
#SBATCH --partition=courses
#SBATCH --account=binf6610.202710
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=02:00:00
#SBATCH --output=logs/cohort_%j.out

set -euo pipefail

# Load environment configuration relative to submission directory
source "${SLURM_SUBMIT_DIR}/conf/slurm.env"
mkdir -p logs

# Create private node-local scratch and clean up on exit
export TMPDIR="/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

# Propagate core allocation to child tools
export THREADS="${SLURM_CPUS_PER_TASK}"

# Run cohort stages 6-9 inside Apptainer
apptainer exec --cleanenv \
    --bind /courses,/scratch \
    --env THREADS="${SLURM_CPUS_PER_TASK}" \
    --env TMPDIR="${TMPDIR}" \
    "${SIF}" \
    bash "${PIPELINE_DIR}/run_pipeline.sh" "${SAMPLESHEET}" "${RUN_ROOT}" publish
