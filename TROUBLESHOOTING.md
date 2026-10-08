# BINF6610 Assignment 

## Week 1: Troubleshooting and Debugging Report

### 1: MultiQC Blocked by Untrusted Homebrew Tap
- **Error:** `brew install multiqc` failed with `Error: Refusing to load formula brewsci/bio/multiqc from untrusted tap brewsci/bio`.
- **Evidence:** Terminal output said to run `brew trust brewsci/bio` before formulas could be evaluated or pulled from that repository.
- **Cause:** Homebrew requires explicit user approval before allowing formula downloads and builds from third-party.
- **Fix:** Ran `brew trust brewsci/bio` followed by `brew install multiqc`, allowing the installation to proceed and pass the environment check for Stage 8.

### 2: Pipeline Driver Termination Under `set -e`
- **Error:** Pipeline exited with status 1 immediately after Stage 0 printed `validation passed`, halting before Stage 1 (`qc_raw`) without logging any tool errors.
- **Evidence:** Running the pipeline in debug trace mode (`bash -x run_pipeline.sh samplesheet.csv ~/smoke-out`) showed execution stopped directly on the loop increment statement `(( n++ ))` right after evaluating `[[ "$stage" == "$LAST" ]]`.
- **Cause:** The script runs under strict mode (`set -euo pipefail`). In Bash arithmetic evaluation (`(( ... ))`), an expression that evaluates to `0` returns an exit status of 1 (falsy). Because `n` was initialized to `0`, the post-increment operator `(( n++ ))` returned `0` to the shell before incrementing, triggering `set -e` and killing the script.
- **Fix:** Replaced `(( n++ ))` with explicit variable assignment `n=$(( n + 1 ))`, which always returns exit code 0 regardless of the value and allows the driver loop to advance through all 10 stages.

### 3: Stage 7 VCF Deliverable Excluded by Git 
- **Error:** Acceptance Test 9 failed with `FAIL the whole pipeline ran on the smoke dataset: no smoke-run/cohort.filtered.vcf.gz in your repository`.
- **Evidence:** Checking `~/smoke-out/results/` confirmed `cohort.filtered.vcf.gz` was generated and copied to `smoke-run/`, but `git status` showed the working tree clean without detecting the new file. Running `git check-ignore -v smoke-run/cohort.filtered.vcf.gz` reported `.gitignore:16:*.vcf.gz`.
- **Cause:** The repository `.gitignore` included a broad rule `*.vcf.gz` to avoid tracking intermediate per-sample VCFs, which unintentionally blocked Git from tracking the final submission deliverable in `smoke-run/`.
- **Fix:** Added the exception rule `!smoke-run/cohort.filtered.vcf.gz` to `.gitignore` and staged the file using `git add -f smoke-run/cohort.filtered.vcf.gz`, resolving the test failure and verifying variant recoveries of 100%, 99%, and 92%.


## Week 2: Slurm HPC Troubleshooting and Failure Analysis


- ## Failure 1: The `TIMEOUT`

    -  ### Error Diagnostics
        - **Job ID:** `10732146` (Cohort Pipeline) / `10735021` (Verification Test)
        - **Partition:** `courses`
        - **Slurm State:** `TIMEOUT`
        - **Exit Code:** `0:0`
        - **Allocated Walltime:** `01:00:00`
        - **Elapsed Time:** `01:00:15`

    - ### Cause
        `02_cohort.sbatch` was initially configured with `#SBATCH --time=01:00:00`. The workflow processes 8 samples sequentially through GATK HaplotypeCaller followed by cohort joint genotyping. At the 1 hour mark, `slurmctld` issued `SIGTERM` followed by `SIGKILL` to all processes in the task cgroup, terminating execution during Stage 5.

    - ### Fix 
        Updated `02_cohort.sbatch` to request 2 hours:
        ```bash
        #SBATCH --time=02:00:00
        ```

- ## Failure 2: The Failed Task Under afterok

    - ### Error Diagnostics
        - **Job ID:** `10735414` (Child / Dependent Job) / `10735408` (Failing Parent Job)
        - **Partition:** `courses`
        - **Slurm State:** `CANCELLED` (DependencyNeverSatisfied)
        - **Exit Code:** `0:0` (Parent Exit Code: `1:0`)
        - **Elapsed Time:** `00:00:00`

    - ### Cause
        The cohort stage relies on the directive `--dependency=afterok:<ARRAY_JOB_ID>`. The `afterok` dependency rule requires that every upstream array task must complete cleanly with an exit code of `0`. Because upstream parent task `10735408` exited with a non-zero status (`1`), the Slurm controller determined that the dependency conditions could never be satisfied. Consequently, the scheduler marked the dependency as unattainable and cancelled dependent job `10735414` before any compute steps could execute.

    - ### Fix 
        Inspected failed task logs to resolve the upstream errors causing the non-zero exit code. Verified that all upstream array tasks run to completion with exit code `0:0` before triggering the downstream cohort workflow, preventing jobs from stalling in `DependencyNeverSatisfied`.

- ## Failure 3: The Out-of-Range Task
    - ### Error Diagnostics
        - **Job ID:** `10736261_9`
        - **Partition:** `courses`
        - **Slurm State:** `FAILED`
        - **Exit Code:** `64:0`
        - **Error Output:** `task 9: no such row in conf/samples.csv`
        - **Command Executed:**
            ```bash
            sbatch -A binf6610.202710 -p courses --time=00:01:00 --array=9 \
            --wrap='SAMPLE=$(awk -F, -v n="$SLURM_ARRAY_TASK_ID" "NR==n+1 {print \$1}" conf/samples.csv); if [ -z "$SAMPLE" ]; then echo "task $SLURM_ARRAY_TASK_ID: no such row in conf/samples.csv" >&2; exit 64; fi'
            ```
    - ### Cause
        - The sample sheet `conf/samples.csv` contains 8 samples (valid indices 1–8).
        - Passing an index beyond the manifest bounds (`task 9`) resolves an empty string for the sample identifier.
        - Without an explicit guard, downstream commands execute against empty variables, causing malformed directory trees or overwriting shared files.
    - ### Fix 
        - Implemented boundary validation logic ensuring non-empty row extraction prior to tool execution:
            ```bash
            SAMPLE=$(awk -F, -v n="${SLURM_ARRAY_TASK_ID}" 'NR==n+1 { print $1 }' "${SAMPLESHEET}")
            [[ -n "${SAMPLE}" ]] || { echo "task ${SLURM_ARRAY_TASK_ID}: no such row in ${SAMPLESHEET}" >&2; exit 64; }
            ```
        - Submitting index `9` terminated immediately with exit code `64:0` and logged the bounds check failure.

- ## 4. The Partial File

    - ### Error Diagnostics
        - **Pipeline Stage:** Stage 3 (Alignment) / Stage 5 (Variant Calling)
        - **Verification Tool:** `samtools quickcheck`
        - **Exit Code:** `2`
        - **Error Output:** `Truncated input file / EOF marker missing`
        - **Command Executed:**
            ```bash
            echo "TRUNCATED_RAW_BYTES_NO_EOF" > bad_sample.bam
            samtools quickcheck -vv bad_sample.bam
            ```
    - ### Cause
        - Mid-execution job terminations, node eviction, or scratch storage limits cause binary BAM or compressed VCF files to be written partially, omitting the required BGZF EOF marker block.
        - Downstream variant calling reading truncated inputs produces silent omissions or corrupt cohort-wide calls.
    - ### Fix 
        - Staged all intermediate outputs to temporary files (`${TARGET}.tmp`) and atomically moved them (`mv`) only upon exit code `0`.
        - Added integrity validation to reject partial files:
            ```bash
            samtools quickcheck "${OUTPUT_BAM}" || { echo "Error: partial or corrupt BAM detected." >&2; rm -f "${OUTPUT_BAM}"; exit 1; }
            ```
        - An artificially truncated BAM caused `samtools quickcheck` to exit with status code `2`, successfully triggering the error handler.


## Week 3: Containerization & Apptainer Failure Analysis

- ## Failure 1: Build Caching and Stale Package Metadata

    - ### Error Diagnostics
        - **Environment:** Docker Desktop on macOS (target platform: `linux/amd64`)
        - **Command Executed:**
            ```bash
            # Day 1 build (2026-10-01 11:56 EDT):
            mkdir -p /tmp/breakage1 && cd /tmp/breakage1
            cat << 'EOF' > Dockerfile
            FROM ubuntu
            RUN apt-get update && apt-get install -y curl
            EOF
            docker build --platform linux/amd64 -t breakage1:day1 .
            docker run --rm --platform linux/amd64 breakage1:day1 dpkg -l > /tmp/breakage1_day1_pkgs.txt

            # Day 2 build (2026-10-02 14:53 EDT — 27 hours later):
            docker build --platform linux/amd64 --pull --no-cache -t breakage1:day2 .
            docker run --rm --platform linux/amd64 breakage1:day2 dpkg -l > /tmp/breakage1_day2_pkgs.txt

            # Package state comparison:
            diff -u /tmp/breakage1_day1_pkgs.txt /tmp/breakage1_day2_pkgs.txt
            ```
        - **Comparison Output:**
            ```text
            --- /tmp/breakage1_day1_pkgs.txt 2026-10-01 11:56:13
            +++ /tmp/breakage1_day2_pkgs.txt 2026-10-02 14:53:51
            @@ -112,7 +112,7 @@
              ii  perl-base        5.40.1-7ubuntu0.3         amd64  minimal Perl system
              ii  procps           2:4.0.4-9ubuntu1          amd64  /proc file system utilities
              ii  publicsuffix     20260129.1928-1           all    accurate, machine-readable list of domain name suffixes
            - ii  rust-coreutils   0.8.0-0ubuntu3            amd64  Universal coreutils utils, written in Rust
            + ii  rust-coreutils   0.10.0-1ubuntu2~26.04.1   amd64  Universal coreutils utils, written in Rust
              ii  sed              4.9-2ubuntu1              amd64  GNU stream editor for filtering/transforming text
              ii  sensible-utils   0.0.26build1              all    Utilities for sensible alternative selection
              ii  sysvinit-utils   3.15-5ubuntu1             amd64  System-V-like utilities
            ```

    - ### Cause
        Without pinned versions or digest tags (`FROM ubuntu` unpinned), running `docker build` relies on existing local cache layers. When rebuilding a day later with `--pull --no-cache`, Docker was forced to query the remote registry and re-execute `apt-get update && apt-get install -y curl`. During that window, upstream Ubuntu package archives released an update to `rust-coreutils`, altering the image contents between Day 1 and Day 2 despite identical Dockerfile syntax.

    - ### Fix 
        Pin base images by immutable cryptographic digests and pin all package installations to exact versions rather than resolving latest repository state. For full reproducible builds, use `--no-cache` and `--pull` in automated pipelines to prevent subtle cache drift from masking upstream breaking changes.

- ## Failure 2: Missing Host Filesystem Bind Mounts

    - ### Error Diagnostics
        - **Pipeline Stage:** Stage 1 (Raw QC) / Stage 3 (Alignment)
        - **Runtime Engine:** Apptainer
        - **Exit Code:** `1`
        - **Error Output:**
            ```text
            /scratch/tabassum.f/w3-run/work/sample1: No such file or directory
            WARNING: Skipping user mount /courses: No such file or directory
            ```
        - **Command Executed:**
            ```bash
            # Removed explicit filesystem mappings from Apptainer invocation:
            apptainer exec --cleanenv "${SIF}" bash scripts/run_stage.sh
            ```

    - ### Cause
        Apptainer encapsulates execution inside an isolated container root filesystem. Directories outside standard user boundaries—such as `/courses` (where reference genomes and raw input FASTQs reside) and `/scratch` (where intermediate cluster run files are processed)—are invisible unless explicitly mounted.

    - ### Fix 
        Supplied explicit runtime bind directives in the Slurm batch submission script:
        ```bash
        apptainer exec --cleanenv --bind /courses,/scratch "${SIF}" ...
        ```
        With `--bind /courses,/scratch` restored, paths inside the container mapped to the host filesystem and the stage completed with exit code `0:0`.

- ## Failure 3: Thread Allocation to GATK HMM

    - ### Error Diagnostics
        - **Pipeline Stage:** Stage 3 (BWA-MEM Alignment) / Stage 5 (GATK HaplotypeCaller)
        - **Slurm CPUs Requested:** `4`
        - **Observed Thread Count:** `1`
        - **Command Executed:**
            ```bash
            # Executed container without variable propagation under --cleanenv:
            apptainer exec --cleanenv --bind /courses,/scratch "${SIF}" ...
            ```
        - **Error Output:**
            ```text
            [main] CMD: bwa mem -t 1 ...
            Using 1 thread(s) for PairHMM execution
            ```

    - ### Cause
        Apptainer's `--cleanenv` security boundary strips host environment variables to isolate execution. Consequently, `SLURM_CPUS_PER_TASK` does not leak into the container environment. Tools relying on thread variables default to a single thread, causing severe runtime bottlenecks and rendering multi-core Slurm allocations idle.

    - ### Fix 
        Explicitly forwarded the Slurm allocation across the container boundary using `--env THREADS="${SLURM_CPUS_PER_TASK}"` or setting `APPTAINERENV_THREADS="${SLURM_CPUS_PER_TASK}"`. In GATK, passed `--native-pair-hmm-threads "${THREADS}"`. The log confirmed execution scaled across all requested cores:
        ```text
        [main] CMD: bwa mem -t 4 ...
        Using 4 thread(s) for PairHMM execution
        ```

- ## Failure 4: CPU Architecture Incompatibilities (ARM64 vs AMD64)

    - ### Error Diagnostics
        - **Host Node Architecture:** `x86_64` (AMD64)
        - **Target Image Architecture:** `arm64` (aarch64)
        - **Exit Code:** `126` / `255`
        - **Error Output:**
            ```text
            FATAL:   container creation failed: mount /proc error: ...
            exec format error: binary cannot be executed
            ```
        - **Command Executed:**
            ```bash
            apptainer pull --arch arm64 arm.sif docker://ubuntu:24.04
            apptainer exec arm.sif uname -m
            ```

    - ### Cause
        Images compiled on Apple Silicon Macs default to the `arm64` instruction set architecture. When pulled or run on Explorer's `x86_64` AMD64 compute nodes, the Linux kernel cannot decode or execute the incompatible foreign binary instructions, immediately triggering an `exec format error`.

    - ### Fix 
        Forced target architecture compilation during image generation by providing `--platform linux/amd64` to the Docker build command:
        ```bash
        docker build --platform linux/amd64 -t fardinatabassum/variant-call:latest .
        ```
        Verifying the resulting SIF file on Explorer via `apptainer inspect --labels "${SIF}"` confirmed `org.label-schema.build-arch: amd64`, allowing execution without architectural faults.