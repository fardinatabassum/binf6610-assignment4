#!/bin/bash
#SBATCH -A binf6610.202710
#SBATCH -p courses
#SBATCH -c 4
#SBATCH --mem=16G
#SBATCH -t 00:30:00
#SBATCH -o logs/pull-%j.out

set -euo pipefail

export APPTAINER_CACHEDIR=/scratch/${USER}/apptainer-cache
mkdir -p /scratch/${USER}/containers
mkdir -p logs

apptainer pull /scratch/${USER}/containers/variant-call.sif \
    docker://fardinatabassum/variant-call@sha256:3ee02d026e15eaccadad9d182f2189e1e4e574e03d7bb81f6732e68c92301074
