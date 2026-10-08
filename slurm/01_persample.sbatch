#!/usr/bin/env bash
#SBATCH --job-name=vcall-sample
#SBATCH --export=NONE
#SBATCH --partition=courses
#SBATCH --account=binf6610.202710
#SBATCH --array=1-8
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=01:00:00
#SBATCH --output=logs/persample_%A_%a.out

set -euo pipefail

# Load environment configuration relative to submission directory
source "${SLURM_SUBMIT_DIR}/conf/slurm.env"
mkdir -p logs

# Create private node-local scratch and clean up on exit
export TMPDIR="/tmp/${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

# Propagate core allocation to child tools
export THREADS="${SLURM_CPUS_PER_TASK}"

# Extract sample ID from CSV row (skip header)
SAMPLE=$(awk -F, -v n="${SLURM_ARRAY_TASK_ID}" 'NR==n+1 { print $1 }' "${SAMPLESHEET}")

# Guard against out-of-range array indices
[[ -n "${SAMPLE}" ]] || { echo "task ${SLURM_ARRAY_TASK_ID}: no such row in ${SAMPLESHEET}" >&2; exit 64; }

# Execute stages 0-5 for this sample inside Apptainer
apptainer exec --cleanenv \
    --bind /courses,/scratch \
    --env THREADS="${SLURM_CPUS_PER_TASK}" \
    --env TMPDIR="${TMPDIR}" \
    "${SIF}" \
    bash "${PIPELINE_DIR}/run_sample.sh" "${SAMPLESHEET}" "${RUN_ROOT}" "${SAMPLE}"
