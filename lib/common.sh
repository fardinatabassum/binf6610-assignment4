# shellcheck shell=bash
set -euo pipefail

PIPE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { log "ERROR: $*"; exit 65; }

# Configuration: defaults point to Explorer cluster shared paths
REF=${REF:-/courses/BINF6610.202710/data/refs/grch38-1000g/GRCh38_full_analysis_set_plus_decoy_hla.fa}
REGION=${REGION:-chr20:1-10000000}
THREADS=${THREADS:-${SLURM_CPUS_PER_TASK:-4}}
FASTQ_ROOT=${FASTQ_ROOT:-/courses/BINF6610.202710/data/fastq-variant}

export RUN_STARTED=${RUN_STARTED:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}

# Output layout derived from OUT
setup_dirs() {
    local out="${1:-${OUT}}"
    QC="${out}/qc_raw"
    TRIM="${out}/trim"
    ALN="${out}/align"
    POST="${out}/postprocess"
    VAR="${out}/variants"
    RES="${out}/results"
    LOG="${out}/logs"
    mkdir -p "$QC" "$TRIM" "$ALN" "$POST" "$VAR" "$RES" "$LOG"
}

# Source all modular stage scripts from stages/
load_stages() {
    local stages_dir="${1:-${PIPE_DIR}/stages}"
    for s in "${stages_dir}"/[0-9][0-9]_*.sh; do
        # shellcheck source=/dev/null
        source "$s"
    done
}

# rows <sheet> [sample_id] -> tab-separated fields per row
rows() {
    local sheet=$1 only=${2:-}
    awk -F, -v want="$only" -v root="$FASTQ_ROOT" '
        BEGIN { n = split("sample_id condition replicate library_type r1_fastq r2_fastq", need, " ") }
        NR == 1 {
            for (i = 1; i <= NF; i++) col[$i] = i
            for (i = 1; i <= n; i++)
                if (!(need[i] in col)) {
                    print "samplesheet has no column named " need[i] > "/dev/stderr"
                    exit 65
                }
            next
        }
        want != "" && $col["sample_id"] != want { next }
        {
            r1 = $col["r1_fastq"]; r2 = $col["r2_fastq"]
            if (r1 != "" && r1 !~ /^\//) r1 = root "/" r1
            if (r2 != "" && r2 !~ /^\//) r2 = root "/" r2
            print $col["sample_id"] "\t" $col["condition"] "\t" $col["replicate"] \
                  "\t" $col["library_type"] "\t" r1 "\t" r2
        }
    ' "$sheet"
}