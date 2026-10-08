#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# run_acceptance.sh — the tests that grade Assignment 4.
#
#   bash tests/run_acceptance.sh /path/to/your-repo
#   bash tests/run_acceptance.sh /path/to/your-repo smoke      # one test
#
# RUNS ON YOUR LAPTOP. It runs no pipeline, submits nothing, and never touches the
# cluster. Three tests read what you wrote; the rest read the two runs you committed:
# smoke-run-nf/, your laptop run on the smoke dataset, and cluster-run-nf/, your
# Explorer run on the eight samples. Each is a copy of that run's results/ folder.
#-----------------------------------------------------------------------------
set -uo pipefail

if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
    printf 'error: bash >= 4.3 required, found %s\n' "${BASH_VERSION}" >&2
    printf '       macOS ships 3.2.57 as /bin/bash. Use the one week 0 installed:\n' >&2
    printf '       /opt/homebrew/bin/bash tests/run_acceptance.sh .\n' >&2
    exit 70
fi

REPO=${1:-.}
FILTER=${2:-}
REPO=$(cd -- "${REPO}" && pwd) || { printf 'error: no such directory\n' >&2; exit 66; }
HERE=$(cd -- "$(dirname -- "$0")" && pwd)

pass=0 fail=0 points=0
declare -a FAILURES=()
if [[ -t 1 ]]; then C_OK=$'\033[0;32m'; C_BAD=$'\033[0;31m'; C_DIM=$'\033[0;90m'; C_RST=$'\033[0m'
else C_OK='' C_BAD='' C_DIM='' C_RST=''; fi

want() { [[ -z "${FILTER}" ]] || [[ "$1" == *"${FILTER}"* ]]; }
ok()   { pass=$(( pass + 1 )); points=$(( points + $2 ))
         printf '  %sPASS%s  %2d/%-2d  %s\n' "${C_OK}" "${C_RST}" "$2" "$2" "$1"; }
part() { pass=$(( pass + 1 )); points=$(( points + $2 ))
         printf '  %sPART%s  %2d/%-2d  %s\n' "${C_OK}" "${C_RST}" "$2" "$3" "$1"
         [[ -n "${4:-}" ]] && printf '        %s%s%s\n' "${C_DIM}" "$4" "${C_RST}"; }
no()   { fail=$(( fail + 1 )); FAILURES+=( "$1" )
         printf '  %sFAIL%s   0/%-2d  %s\n' "${C_BAD}" "${C_RST}" "$2" "$1"
         [[ -n "${3:-}" ]] && printf '        %s%s%s\n' "${C_DIM}" "$3" "${C_RST}"; }
note() { printf '        %s%s%s\n' "${C_DIM}" "$1" "${C_RST}"; }

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1" | awk '{ print $1 }'
           else shasum -a 256 "$1" | awk '{ print $1 }'; fi; }
vcf_text() { { if [[ "$1" == *.gz ]]; then gzip -dc "$1"; else cat "$1"; fi; } 2>/dev/null; }
vcf_samples() { vcf_text "$1" | awk -F'\t' '/^#CHROM/ { for (i = 10; i <= NF; i++) print $i; exit }'; }

SMOKE="${REPO}/smoke-run-nf"
CLUSTER="${REPO}/cluster-run-nf"
COHORT=(NA07357 NA10851 NA12003 NA12813 NA12873 NA12878 NA12891 NA12892)

printf '\n%sBINF6610 Assignment 4 — acceptance tests%s\n%srepo: %s%s\n\n' \
    "${C_OK}" "${C_RST}" "${C_DIM}" "${REPO}" "${C_RST}"

# --------------------------------------------------------------------- 1 (10)
# The pipeline is Nextflow, laid out as the session showed.
if want layout; then
    m=()
    grep -qE '^[[:space:]]*workflow[[:space:]]*\{' "${REPO}/main.nf" 2>/dev/null || m+=( "a workflow block in main.nf" )
    n=$(cat "${REPO}"/modules/*.nf 2>/dev/null | grep -cE '^[[:space:]]*process[[:space:]]+[A-Za-z_]+[[:space:]]*\{')
    (( n >= 10 )) && [[ -f "${REPO}/modules/publish.nf" ]] \
        || m+=( "one process per stage in modules/ ($n found), publish.nf among them" )
    [[ -x "${REPO}/bin/run_manifest.sh" ]] || m+=( "bin/run_manifest.sh, executable" )
    grep -qE '^/?work/?$' "${REPO}/.gitignore" 2>/dev/null && grep -qE '^/?\.nextflow' "${REPO}/.gitignore" 2>/dev/null \
        || m+=( "work/ and .nextflow* in .gitignore" )
    if   (( ${#m[@]} == 0 )); then ok "the pipeline is main.nf, modules/ and bin/" 10
    elif (( ${#m[@]} <= 2 )); then part "the pipeline is main.nf, modules/ and bin/" 5 10 "missing: $(IFS=';'; printf '%s' "${m[*]}")"
    else no "the pipeline is main.nf, modules/ and bin/" 10 "missing: $(IFS=';'; printf '%s' "${m[*]}")"; fi
fi

# --------------------------------------------------------------------- 2 (10)
# Nextflow itself runs as a Slurm job, with both image caches off the home quota.
if want head; then
    HJ="${REPO}/slurm/nextflow.sbatch"
    if [[ ! -f "${HJ}" ]]; then no "the head job, slurm/nextflow.sbatch" 10 "no slurm/nextflow.sbatch"
    else
        m=()
        grep -qE '^#SBATCH.*(--account[= ]|-A[ ])binf6610\.202710' "${HJ}" || m+=( "#SBATCH account binf6610.202710" )
        grep -qE '^#SBATCH.*(--partition[= ]|-p[ ])courses' "${HJ}"        || m+=( "#SBATCH partition courses" )
        grep -qE '^[^#]*NXF_APPTAINER_CACHEDIR=/scratch/' "${HJ}"          || m+=( "NXF_APPTAINER_CACHEDIR under /scratch" )
        grep -qE '(^|[^_A-Z])APPTAINER_CACHEDIR=/scratch/' "${HJ}"          || m+=( "APPTAINER_CACHEDIR under /scratch" )
        if ! grep -qE '^[^#]*nextflow run .*-profile explorer' "${HJ}"; then
            no "the head job, slurm/nextflow.sbatch" 10 "it does not run 'nextflow run ... -profile explorer'"
        elif (( ${#m[@]} == 0 )); then ok "the head job, slurm/nextflow.sbatch" 10
        else part "the head job, slurm/nextflow.sbatch" 5 10 "missing: $(IFS=';'; printf '%s' "${m[*]}")"; fi
    fi
fi

# --------------------------------------------------------------------- 3 (15)
# The laptop run found the variants planted in the smoke dataset.
#
# A planted SNV counts as found when that sample has a non-reference genotype at
# that position, whatever the FILTER column says -- the same rule as weeks 1-3.
# The course's reference solution, run under -profile docker: 100, 99 and 92 %.
SMOKE_MIN_PCT=80
smoke_calls() {              # smoke_calls <vcf> -> "sample<TAB>pos" per non-reference genotype
    vcf_text "$1" | awk -F'\t' '
        /^##/     { next }
        /^#CHROM/ { for (i = 10; i <= NF; i++) name[i] = $i; next }
        {
            n = split($9, fmt, ":"); g = 0
            for (k = 1; k <= n; k++) if (fmt[k] == "GT") g = k
            if (!g) next
            for (i = 10; i <= NF; i++) { split($i, f, ":"); if (f[g] ~ /[1-9]/) print name[i] "\t" $2 }
        }'
}
if want smoke; then
    SVCF="${SMOKE}/cohort.filtered.vcf.gz"
    if [[ ! -s "${SVCF}" ]]; then
        no "the laptop run found the planted variants" 15 \
           "no smoke-run-nf/cohort.filtered.vcf.gz: copy the run's results/ into smoke-run-nf/ and commit it"
    else
        calls=$(smoke_calls "${SVCF}"); header=$(vcf_samples "${SVCF}")
        problems=() found=()
        for s in smoke_01 smoke_02 smoke_03; do
            truth="${HERE}/smoke-truth/${s}.truth.txt"
            grep -qx "${s}" <<< "${header}" || { problems+=( "no column for ${s}" ); continue; }
            total=$(awk -F'\t' '$3 != "-" && $4 != "-"' "${truth}" | wc -l | tr -d ' ')
            hits=$(awk -F'\t' -v s="${s}" 'NR == FNR { if ($1 == s) seen[$2] = 1; next }
                                           $3 != "-" && $4 != "-" && ($2 in seen)' \
                       <(printf '%s\n' "${calls}") "${truth}" | wc -l | tr -d ' ')
            pct=$(( total > 0 ? 100 * hits / total : 0 ))
            found+=( "${s} ${hits}/${total} (${pct} %)" )
            (( pct >= SMOKE_MIN_PCT )) || problems+=( "${s} found ${pct} %" )
        done
        if (( ${#problems[@]} == 0 )); then ok "the laptop run found the planted variants" 15
                                            note "planted SNVs found: ${found[*]}"
        else part "the laptop run found the planted variants" 10 15 \
                  "the run finished, but: $(IFS=';'; printf '%s' "${problems[*]}"). The bar is ${SMOKE_MIN_PCT} % per sample."; fi
    fi
fi

# --------------------------------------------------------------------- 4 (5)
# Every task of the laptop run ran in an image: the docker profile was on.
if want smoke; then
    TR="${SMOKE}/pipeline_info/trace.txt"
    if [[ ! -s "${TR}" ]]; then no "every laptop task ran in an image" 5 "no smoke-run-nf/pipeline_info/trace.txt"
    else
        read -r rows bare < <(awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == "container") c = i; next }
                                          { n++; if (!c || $c == "" || $c == "-") b++ }
                                          END { print n + 0, (c ? b + 0 : n + 0) }' "${TR}")
        if (( rows >= 10 && bare == 0 )); then ok "every laptop task ran in an image" 5
        else no "every laptop task ran in an image" 5 \
                "${bare} of ${rows} tasks have no container in the trace: run with -profile docker, and trace the container field"; fi
    fi
fi

# --------------------------------------------------------------------- 5 (10)
# The Explorer run called all eight samples.
if want cluster; then
    CVCF="${CLUSTER}/cohort.filtered.vcf.gz"
    if [[ ! -s "${CVCF}" ]]; then no "the Explorer run has all eight samples" 10 "no cluster-run-nf/cohort.filtered.vcf.gz"
    else
        header=$(vcf_samples "${CVCF}"); missing=()
        for s in "${COHORT[@]}"; do grep -qx "${s}" <<< "${header}" || missing+=( "${s}" ); done
        if (( ${#missing[@]} == 0 )); then ok "the Explorer run has all eight samples" 10
        else part "the Explorer run has all eight samples" 5 10 "not in the VCF: ${missing[*]}"; fi
    fi
fi

# --------------------------------------------------------------------- 6 (10)
# Every task of the Explorer run was a Slurm job, in an Apptainer image.
if want cluster; then
    TR="${CLUSTER}/pipeline_info/trace.txt"
    if [[ ! -s "${TR}" ]]; then no "every Explorer task was a Slurm job in an image" 10 "no cluster-run-nf/pipeline_info/trace.txt"
    else
        read -r rows nojob noimg < <(awk -F'\t' '
            NR == 1 { for (i = 1; i <= NF; i++) { if ($i == "native_id") j = i; if ($i == "container") c = i }; next }
            { n++; if (!j || $j !~ /^[0-9]+$/) a++; if (!c || $c !~ /\.(img|sif)$/) b++ }
            END { print n + 0, a + 0, b + 0 }' "${TR}")
        if (( rows >= 8 && nojob == 0 && noimg == 0 )); then ok "every Explorer task was a Slurm job in an image" 10
        elif (( rows >= 8 && (nojob < rows || noimg < rows) )); then
            part "every Explorer task was a Slurm job in an image" 5 10 \
                 "${nojob} of ${rows} tasks have no Slurm job id and ${noimg} no image; trace native_id and container"
        else no "every Explorer task was a Slurm job in an image" 10 \
                "${rows} tasks; ${nojob} without a Slurm job id, ${noimg} without an image: run with -profile explorer"; fi
    fi
fi

# --------------------------------------------------------------------- 7 (10)
# The two tables, variants.tsv (stage 7) and samples.tsv (stage 9).
if want tables; then
    m=()
    V="${CLUSTER}/variants.tsv"; S="${CLUSTER}/samples.tsv"
    if [[ "$(head -1 "${V}" 2>/dev/null)" != $'chrom\tpos\tref\talt\tqual\tfilter' ]]; then
        m+=( "variants.tsv with the header chrom pos ref alt qual filter, tab-separated" )
    else
        nv=$(awk 'NR > 1' "${V}" | wc -l | tr -d ' ')
        nr=$(vcf_text "${CLUSTER}/cohort.filtered.vcf.gz" | grep -vc '^#')
        (( nv == nr )) || m+=( "a row of variants.tsv for each of the VCF's ${nr} records (it has ${nv})" )
    fi
    if [[ "$(head -1 "${S}" 2>/dev/null)" != $'sample_id\tcondition' ]]; then
        m+=( "samples.tsv with the header sample_id condition, tab-separated" )
    else
        ns=$(awk 'NR > 1' "${S}" | wc -l | tr -d ' ')
        (( ns == ${#COHORT[@]} )) || m+=( "a row of samples.tsv for each of the eight samples (it has ${ns})" )
    fi
    if   (( ${#m[@]} == 0 )); then ok "variants.tsv and samples.tsv" 10
    elif (( ${#m[@]} == 1 )); then part "variants.tsv and samples.tsv" 5 10 "in cluster-run-nf/: ${m[0]}"
    else no "variants.tsv and samples.tsv" 10 "in cluster-run-nf/: $(IFS=';'; printf '%s' "${m[*]}")"; fi
fi

# --------------------------------------------------------------------- 8 (10)
# Both runs' manifests: what ran, where, on which samples, producing which files.
manifest_problems() {        # manifest_problems <run dir> <kind> <executor> <samples>
    python3 - "$@" <<'PY' 2>&1
import hashlib, json, os, sys
run, kind, executor, n = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
path = os.path.join(run, "manifest.json")
try:
    m = json.load(open(path))
except FileNotFoundError:
    print("no manifest.json"); sys.exit()
except ValueError as e:
    print("manifest.json is not JSON: %s" % e); sys.exit()
p = []
if m.get("pipeline", {}).get("name") != "variant-call": p.append("pipeline.name is not variant-call")
if not m.get("pipeline", {}).get("version"):            p.append("no pipeline.version")
if m.get("platform", {}).get("kind") != kind:           p.append("platform.kind is not %s" % kind)
if m.get("platform", {}).get("executor") != executor:   p.append("platform.executor is not %s" % executor)
if len(m.get("samples", [])) != n:                      p.append("%d samples, not %d" % (len(m.get("samples", [])), n))
vcf = os.path.join(run, "cohort.filtered.vcf.gz")
out = {o.get("path"): o.get("checksum", "") for o in m.get("outputs", [])}
if "cohort.filtered.vcf.gz" not in out:
    p.append("outputs does not list cohort.filtered.vcf.gz")
elif os.path.exists(vcf):
    got = "sha256:" + hashlib.sha256(open(vcf, "rb").read()).hexdigest()
    if out["cohort.filtered.vcf.gz"] != got: p.append("the committed VCF is not the one this manifest describes")
print("; ".join(p))
PY
}
if want manifest; then
    if ! command -v python3 >/dev/null; then no "both runs' manifest.json" 10 "this test needs python3"
    else
        ps=$(manifest_problems "${SMOKE}" docker-local local 3)
        pc=$(manifest_problems "${CLUSTER}" singularity-hpc slurm 8)
        if   [[ -z "${ps}" && -z "${pc}" ]]; then ok "both runs' manifest.json" 10
        elif [[ -z "${ps}" || -z "${pc}" ]]; then
            part "both runs' manifest.json" 5 10 "$([[ -n "${ps}" ]] && printf 'smoke-run-nf: %s' "${ps}")$([[ -n "${pc}" ]] && printf 'cluster-run-nf: %s' "${pc}")"
        else no "both runs' manifest.json" 10 "smoke-run-nf: ${ps}; cluster-run-nf: ${pc}"; fi
    fi
fi

# --------------------------------------------------------------------- 9 (10)
# The records compared with last week's run.
if want records; then
    RS="${CLUSTER}/records-sha256.txt"
    if [[ ! -s "${RS}" ]]; then no "the records compared with week 3" 10 "no cluster-run-nf/records-sha256.txt"
    else
        mapfile -t hashes < <(grep -oE '\b[0-9a-f]{64}\b' "${RS}")
        words=$(grep -vE '^[[:space:]]*[0-9a-f]{64}' "${RS}" | wc -w | tr -d ' ')
        if (( ${#hashes[@]} < 2 )); then part "the records compared with week 3" 5 10 "two checksums, last week's run and this one's"
        elif [[ "${hashes[0]}" == "${hashes[1]}" ]] || (( words >= 5 )); then ok "the records compared with week 3" 10
             [[ "${hashes[0]}" == "${hashes[1]}" ]] && note "identical to last week's records"
        else part "the records compared with week 3" 5 10 "they differ, and there is no sentence saying why"; fi
    fi
fi

# --------------------------------------------------------------------- 10 (10)
if want TROUBLE; then
    TS="${REPO}/TROUBLESHOOTING.md"
    if [[ ! -s "${TS}" ]]; then no "TROUBLESHOOTING.md" 10 "missing or empty"
    else
        n=0
        grep -qiE -- '-resume|cached'                                 "${TS}" && n=$(( n + 1 ))
        grep -qiE -- 'fromPath|queue channel|value channel|one sample' "${TS}" && n=$(( n + 1 ))
        grep -qiE -- '\.command\.(sh|err|run)'                        "${TS}" && n=$(( n + 1 ))
        grep -qiE -- '\b140\b|USR2|time limit|timelimit|TIMEOUT'      "${TS}" && n=$(( n + 1 ))
        if   (( n == 4 )); then ok "TROUBLESHOOTING.md" 10
        elif (( n >= 2 )); then part "TROUBLESHOOTING.md" 5 10 "${n} of the four failures are described"
        else no "TROUBLESHOOTING.md" 10 "${n} of the four failures are described"; fi
    fi
fi

# ---------------------------------------------------------------------------
printf '\n  %d passed, %d failed — %d/100 points\n' "${pass}" "${fail}" "${points}"
if (( fail )); then
    printf '\n  %sstill to do:%s\n' "${C_BAD}" "${C_RST}"
    for f in "${FAILURES[@]}"; do printf '    - %s\n' "${f}"; done
    printf '\n'; exit 1
fi
printf '\n'
