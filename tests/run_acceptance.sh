#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# run_acceptance.sh — the tests that grade Assignment 5.
#
#   bash tests/run_acceptance.sh /path/to/your-repo
#   bash tests/run_acceptance.sh /path/to/your-repo smoke      # one test
#
# RUNS ON YOUR LAPTOP. It runs no pipeline, submits nothing, and never touches the
# cluster. Two tests read what you wrote; the rest read the two runs you committed:
# smoke-run-smk/, your laptop run on the smoke dataset, and cluster-run-smk/, your
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
joined() { local IFS=';'; printf '%s' "$*"; }

vcf_text() { { if [[ "$1" == *.gz ]]; then gzip -dc "$1"; else cat "$1"; fi; } 2>/dev/null; }
vcf_samples() { vcf_text "$1" | awk -F'\t' '/^#CHROM/ { for (i = 10; i <= NF; i++) print $i; exit }'; }

SMK="${REPO}/Snakefile"
SMOKE="${REPO}/smoke-run-smk"
CLUSTER="${REPO}/cluster-run-smk"
COHORT=(NA07357 NA10851 NA12003 NA12813 NA12873 NA12878 NA12891 NA12892)

printf '\n%sBINF6610 Assignment 5 — acceptance tests%s\n%srepo: %s%s\n\n' \
    "${C_OK}" "${C_RST}" "${C_DIM}" "${REPO}" "${C_RST}"

# --------------------------------------------------------------------- 1 (10)
# The pipeline is a Snakefile, laid out as the session showed.
#
# The rules are counted from the file: a line `rule <name>:` at the start. Each rule's
# block runs to the next line that starts in column 0 with a word, so a `log:` is
# counted for the rule it is written in.
if want layout; then
    if [[ ! -f "${SMK}" ]]; then no "the pipeline is a Snakefile" 10 "no Snakefile at the top of the repository"
    else
        m=()
        read -r first n nolog < <(awk '
            /^rule[ \t]+[A-Za-z_][A-Za-z_0-9]*[ \t]*:/ {
                name = $2; sub(/:.*/, "", name)
                if (!first) first = name
                n++; cur = name; haslog[cur] = 0; next }
            /^[A-Za-z]/ { cur = "" }
            cur != "" && /^[ \t]+log:/ { haslog[cur] = 1 }
            END { for (r in haslog) if (r != "all" && !haslog[r]) bad++
                  print (first ? first : "-"), n + 0, bad + 0 }' "${SMK}")
        [[ "${first}" == "all" ]] || m+=( "rule all as the first rule (the first is ${first})" )
        (( n >= 10 )) || m+=( "at least ten rules (${n} found)" )
        (( nolog == 0 )) || m+=( "a log: in every rule but all (${nolog} without)" )
        grep -qE '^include:[[:space:]]*"rules/publish\.smk"' "${SMK}" && [[ -f "${REPO}/rules/publish.smk" ]] \
            || m+=( 'include: "rules/publish.smk", and the file' )
        grep -qE '^/?\.snakemake/?$' "${REPO}/.gitignore" 2>/dev/null || m+=( ".snakemake/ in .gitignore" )
        if   (( ${#m[@]} == 0 )); then ok "the pipeline is a Snakefile" 10
                                    note "${n} rules, every one but all with a log"
        elif (( ${#m[@]} <= 2 )); then part "the pipeline is a Snakefile" 5 10 "missing: $(joined "${m[@]}")"
        else no "the pipeline is a Snakefile" 10 "missing: $(joined "${m[@]}")"; fi
    fi
fi

# --------------------------------------------------------------------- 2 (10)
# The two profiles, and the head job that uses the Explorer one.
if want profile; then
    LP="${REPO}/profiles/laptop/profile.yaml"
    EP="${REPO}/profiles/explorer/profile.yaml"
    # Snakemake 9 also reads a profile's config.yaml, kept for backwards compatibility,
    # so a profile under that name works and is read here too.
    [[ -f "${LP}" || ! -f "${LP%/*}/config.yaml" ]] || LP="${LP%/*}/config.yaml"
    [[ -f "${EP}" || ! -f "${EP%/*}/config.yaml" ]] || EP="${EP%/*}/config.yaml"
    HJ="${REPO}/slurm/snakemake.sbatch"
    bad=() why=()
    if ! grep -qE '^(cores|c):[[:space:]]*[0-9]+' "${LP}" 2>/dev/null; then
        bad+=( laptop ); why+=( "${LP#"${REPO}/"} sets no cores" ); fi
    e=()
    grep -qE '^executor:[[:space:]]*slurm' "${EP}" 2>/dev/null                    || e+=( "executor: slurm" )
    grep -qE 'slurm_account:[[:space:]]*"?binf6610\.202710' "${EP}" 2>/dev/null   || e+=( "slurm_account binf6610.202710" )
    grep -qE 'slurm_partition:[[:space:]]*"?courses' "${EP}" 2>/dev/null          || e+=( "slurm_partition courses" )
    grep -qE '^(software-deployment-method|sdm):[[:space:]]*\[?[[:space:]]*apptainer' "${EP}" 2>/dev/null \
                                                                                  || e+=( "software-deployment-method: apptainer" )
    if (( ${#e[@]} )); then bad+=( explorer ); why+=( "${EP#"${REPO}/"}: no $(joined "${e[@]}")" ); fi
    h=()
    grep -qE '^#SBATCH.*(--account[= ]|-A[ ])binf6610\.202710' "${HJ}" 2>/dev/null || h+=( "#SBATCH account binf6610.202710" )
    grep -qE '^#SBATCH.*(--partition[= ]|-p[ ])courses' "${HJ}" 2>/dev/null        || h+=( "#SBATCH partition courses" )
    grep -qE '^[^#]*snakemake[[:space:]].*--profile[[:space:]=]+profiles/explorer' "${HJ}" 2>/dev/null \
                                                                                   || h+=( "snakemake --profile profiles/explorer" )
    if (( ${#h[@]} )); then bad+=( head ); why+=( "slurm/snakemake.sbatch: no $(joined "${h[@]}")" ); fi
    if   (( ${#bad[@]} == 0 )); then ok "the two profiles and the head job" 10
    elif (( ${#bad[@]} == 1 )); then part "the two profiles and the head job" 5 10 "${why[0]}"
    else no "the two profiles and the head job" 10 "$(joined "${why[@]}")"; fi
fi

# --------------------------------------------------------------------- 3 (10)
# The laptop run found the variants planted in the smoke dataset.
#
# A planted SNV counts as found when that sample has a non-reference genotype at
# that position, whatever the FILTER column says -- the same rule as weeks 1-4.
# The course's reference solution, run with the laptop profile: 100, 99 and 92 %.
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
        no "the laptop run found the planted variants" 10 \
           "no smoke-run-smk/cohort.filtered.vcf.gz: copy the run's results/ into smoke-run-smk/ and commit it"
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
        if (( ${#problems[@]} == 0 )); then ok "the laptop run found the planted variants" 10
                                            note "planted SNVs found: ${found[*]}"
        else part "the laptop run found the planted variants" 5 10 \
                  "the run finished, but: $(joined "${problems[@]}"). The bar is ${SMOKE_MIN_PCT} % per sample."; fi
    fi
fi

# --------------------------------------------------------------------- 4 (10)
# The Explorer run called all eight samples.
if want cluster; then
    CVCF="${CLUSTER}/cohort.filtered.vcf.gz"
    if [[ ! -s "${CVCF}" ]]; then no "the Explorer run has all eight samples" 10 "no cluster-run-smk/cohort.filtered.vcf.gz"
    else
        header=$(vcf_samples "${CVCF}"); missing=()
        for s in "${COHORT[@]}"; do grep -qx "${s}" <<< "${header}" || missing+=( "${s}" ); done
        if   (( ${#missing[@]} == 0 )); then ok "the Explorer run has all eight samples" 10
        elif (( ${#missing[@]} < ${#COHORT[@]} )); then part "the Explorer run has all eight samples" 5 10 "not in the VCF: ${missing[*]}"
        else no "the Explorer run has all eight samples" 10 "none of the eight samples is a column of the VCF"; fi
    fi
fi

# --------------------------------------------------------------------- 5 (5)
# Every rule on Explorer was its own Slurm job: the head jobs' logs say so.
# A run that stopped and was submitted again has two or more head jobs, each submitting
# what was left, so every *.out in cluster-run-smk/ is counted. The reference solution's
# one head job submitted 44 jobs for 46 steps (publish and all are local rules); the bar
# is 40, which eight samples cannot reach in one allocation.
SLURM_MIN_JOBS=40
if want cluster; then
    shopt -s nullglob; HLS=( "${CLUSTER}"/*.out ); shopt -u nullglob
    if (( ${#HLS[@]} == 0 )); then no "every rule on Explorer was its own Slurm job" 5 \
                                "no head-job log in cluster-run-smk/: copy the run's slurm/variant-call-smk-*.out there"
    else
        n=$(cat "${HLS[@]}" | grep -cE 'has been submitted with SLURM jobid [0-9]+')
        if (( n >= SLURM_MIN_JOBS )); then ok "every rule on Explorer was its own Slurm job" 5
                                         note "${n} jobs submitted to Slurm, in ${#HLS[@]} head-job log(s)"
        else no "every rule on Explorer was its own Slurm job" 5 \
                "${#HLS[@]} head-job log(s) show ${n} jobs submitted to Slurm, fewer than ${SLURM_MIN_JOBS}: run with --profile profiles/explorer"; fi
    fi
fi

# --------------------------------------------------------------------- 6 (5)
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
    if (( ${#m[@]} == 0 )); then ok "variants.tsv and samples.tsv" 5
    else no "variants.tsv and samples.tsv" 5 "in cluster-run-smk/: $(joined "${m[@]}")"; fi
fi

# --------------------------------------------------------------------- 7 (10)
# Both runs' manifests: what ran, where, in which images, on which samples, producing which files.
manifest_problems() {        # manifest_problems <run dir> <kind> <executor> <samples> <images: yes|no>
    python3 - "$@" <<'PY' 2>&1
import hashlib, json, os, sys
run, kind, executor, n, images = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5]
path = os.path.join(run, "manifest.json")
try:
    m = json.load(open(path))
except FileNotFoundError:
    print("no manifest.json"); sys.exit()
except ValueError as e:
    print("manifest.json is not JSON: %s" % e); sys.exit()
p = []
pl = m.get("pipeline", {}); pf = m.get("platform", {})
if pl.get("name") != "variant-call":          p.append("pipeline.name is not variant-call")
if not pl.get("version"):                     p.append("no pipeline.version")
if pl.get("implementation") != "snakemake":   p.append("pipeline.implementation is not snakemake")
if pf.get("kind") != kind:                    p.append("platform.kind is not %s" % kind)
if pf.get("executor") != executor:            p.append("platform.executor is not %s" % executor)
has = bool(pf.get("containers"))
if images == "yes" and not has:               p.append("no images recorded: did the rules run under Apptainer?")
if images == "no" and has:                    p.append("images recorded, but the laptop run uses none")
if len(m.get("samples", [])) != n:            p.append("%d samples, not %d" % (len(m.get("samples", [])), n))
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
        ps=$(manifest_problems "${SMOKE}" laptop local 3 no)
        pc=$(manifest_problems "${CLUSTER}" singularity-hpc slurm 8 yes)
        if   [[ -z "${ps}" && -z "${pc}" ]]; then ok "both runs' manifest.json" 10
        elif [[ -z "${ps}" || -z "${pc}" ]]; then
            part "both runs' manifest.json" 5 10 "$([[ -n "${ps}" ]] && printf 'smoke-run-smk: %s' "${ps}")$([[ -n "${pc}" ]] && printf 'cluster-run-smk: %s' "${pc}")"
        else no "both runs' manifest.json" 10 "smoke-run-smk: ${ps}; cluster-run-smk: ${pc}"; fi
    fi
fi

# --------------------------------------------------------------------- 8 (5)
# The records compared with last week's run.
if want records; then
    RS="${CLUSTER}/records-sha256.txt"
    if [[ ! -s "${RS}" ]]; then no "the records compared with week 4" 5 "no cluster-run-smk/records-sha256.txt"
    else
        mapfile -t hashes < <(grep -oE '\b[0-9a-f]{64}\b' "${RS}")
        words=$(grep -vE '^[[:space:]]*[0-9a-f]{64}' "${RS}" | wc -w | tr -d ' ')
        if (( ${#hashes[@]} < 2 )); then no "the records compared with week 4" 5 "two checksums, last week's run and this one's"
        elif [[ "${hashes[0]}" == "${hashes[1]}" ]] || (( words >= 5 )); then ok "the records compared with week 4" 5
             [[ "${hashes[0]}" == "${hashes[1]}" ]] && note "identical to last week's records"
        else no "the records compared with week 4" 5 "they differ, and there is no sentence saying why"; fi
    fi
fi

# --------------------------------------------------------------------- 9 (5)
if want TROUBLE; then
    TS="${REPO}/TROUBLESHOOTING.md"
    if [[ ! -s "${TS}" ]]; then no "TROUBLESHOOTING.md" 5 "missing or empty"
    else
        n=0 m=()
        grep -qiE -- 'rerun-incomplete|IncompleteFiles|Terminating processes' "${TS}" && n=$(( n + 1 )) || m+=( "1, Ctrl-C" )
        grep -qiE -- 'same wildcards|RuleException'               "${TS}" && n=$(( n + 1 )) || m+=( "2, the log" )
        grep -qiE -- 'AmbiguousRule|ambiguous'                    "${TS}" && n=$(( n + 1 )) || m+=( "3, wildcard_constraints" )
        grep -qiE -- '\b127\b|command not found'                  "${TS}" && n=$(( n + 1 )) || m+=( "4, no Apptainer" )
        if (( n == 4 )); then ok "TROUBLESHOOTING.md" 5
        else no "TROUBLESHOOTING.md" 5 "${n} of the four failures are described; not found: $(joined "${m[@]}")"; fi
    fi
fi

# ---------------------------------------------------------------------------
printf '\n  %d passed, %d failed — %d/70 points\n' "${pass}" "${fail}" "${points}"
if (( fail )); then
    printf '\n  %sstill to do:%s\n' "${C_BAD}" "${C_RST}"
    for f in "${FAILURES[@]}"; do printf '    - %s\n' "${f}"; done
    printf '\n'; exit 1
fi
printf '\n'
