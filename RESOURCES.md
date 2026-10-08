# Resource Calibration and Utilization

| Stage / Job | Allocated (Original) | Observed (`seff` / Measured) | Final Setting |
| :--- | :--- | :--- | :--- |
| **01_persample (Array 1-8)** | 4 CPUs, 8 GB, 01:00:00 | 4 CPUs, ~5.2 GB, ~00:08:15 | 4 CPUs, 8 GB, 00:30:00 |
| **02_cohort (Joint Calling)** | 4 CPUs, 12 GB, 01:00:00 | 4 CPUs (53.7% eff), 9.05 GB (75.4% eff), 01:14:58 | 4 CPUs, 16 GB, 02:00:00 |

Initial cohort test runs requested a 1-hour walltime and 12 GB of memory, but running `seff 10732979` revealed an elapsed runtime of 1 hour 14 minutes and 58 seconds with peak memory reaching 9.05 GB. To prevent jobs from being terminated by Slurm walltime limits and to allow sufficient headroom for multi-sample variant joint calling, we adjusted the final allocation in `02_cohort.sbatch` to 4 CPUs, 16 GB RAM, and a 2-hour walltime.

## Decisions and Pipeline Adjustments

Based on the resource profiling from the test runs:

1. **Walltime Ceiling Adjustment:**
   - Measurement: Single-sample runs took ~12–15 minutes, while the joint genotyping cohort stage ran for ~1 hour 15 minutes.
   - Change Made: Increased `#SBATCH --time` in `02_cohort.sbatch` from `01:00:00` to `02:00:00` to provide an empirical safety buffer and prevent `TIMEOUT` evictions.

2. **CPU and Thread Allocation:**
   - Measurement: `bwa mem` and `samtools sort` showed near-linear speedup up to 4 cores, with diminishing returns beyond 8 cores on the shared node.
   - Change Made: Set `#SBATCH --cpus-per-task=4` and dynamically bound tool threads via `export THREADS="${SLURM_CPUS_PER_TASK}"`.

3. **Scratch Disk Usage:**
   - Measurement: Intermediate sorted BAMs generated 2–4 GB per sample of transient data.
   - Change Made: Set `TMPDIR="/tmp/${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}"` with an automatic exit trap (`trap 'rm -rf "${TMPDIR}"' EXIT`) to keep node scratch clean.