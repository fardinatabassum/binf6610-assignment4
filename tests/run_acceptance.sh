#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# run_acceptance.sh — the tests that grade Assignment 3.
#
#   bash tests/run_acceptance.sh /path/to/your-repo
#   bash tests/run_acceptance.sh /path/to/your-repo versions     # one test
#
# RUNS ON YOUR LAPTOP. It builds nothing, submits nothing, and never touches the
# cluster. Six tests read what you wrote; two read what the cluster produced and
# you committed under cluster-run-container/ -- the versions your image reports, and the
# manifest of the run that went through it.
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

C="${REPO}/containers"
RECIPE=""
for cand in "${C}/Dockerfile" "${C}"/*.def; do [[ -f "${cand}" ]] && { RECIPE="${cand}"; break; }; done
RUN="${REPO}/cluster-run-container"   # this week's run; cluster-run/ keeps last week's
SL="${REPO}/slurm"

# The tools and the versions the course conda environment has. The recipe pins
# the conda package name (gatk4); the tool itself reports "gatk".
declare -A WANT=( [bwa]=0.7.19 [samtools]=1.24 [bcftools]=1.24 [gatk4]=4.6.2.0
                  [fastqc]=0.12.1 [fastp]=1.3.7 [multiqc]=1.35 )
declare -A REPORTED=( [bwa]=0.7.19-r1273 [samtools]=1.24 [bcftools]=1.24 [gatk]=4.6.2.0
                      [fastqc]=0.12.1 [fastp]=1.3.7 [multiqc]=1.35 )

# A command written across several lines with trailing backslashes, joined into
# one line, so each apptainer call can be read whole.
joined() { awk '{ line = $0; while (sub(/\\[[:space:]]*$/, "", line)) { getline nxt; line = line " " nxt }
                  print line }' "$1" 2>/dev/null; }

printf '\n%sBINF6610 Assignment 3 — acceptance tests%s\n%srepo: %s%s\n\n' \
    "${C_OK}" "${C_RST}" "${C_DIM}" "${REPO}" "${C_RST}"

# --------------------------------------------------------------------- 1 (15)
if want pinned; then
    if [[ -z "${RECIPE}" ]]; then
        no "every version is pinned" 15 "no containers/Dockerfile (or .def)"
    else
        problems=()
        base=$(grep -iE '^[[:space:]]*(FROM|From:)[[:space:]]' "${RECIPE}" | tail -1 \
               | sed -E 's/^[^[:space:]]+[[:space:]]+//; s/[[:space:]]+AS[[:space:]].*$//I')
        if [[ -z "${base}" ]];           then problems+=( "no FROM line" )
        elif [[ "${base}" == *:latest ]]; then problems+=( "the base image is ':latest'" )
        elif [[ "${base}" != *:* && "${base}" != *@sha256:* ]]; then problems+=( "the base image '${base}' has no tag" ); fi
        # The pins may be in the recipe or in an env.yml beside it that the recipe COPYs in.
        PINFILES=( "${RECIPE}" )
        for y in "${C}"/*.yml "${C}"/*.yaml; do [[ -f "${y}" ]] && PINFILES+=( "${y}" ); done
        for t in "${!WANT[@]}"; do
            grep -qE "(^|[[:space:]])${t}=[0-9]" "${PINFILES[@]}" || problems+=( "${t} is not pinned" )
        done
        while IFS= read -r l; do
            [[ "${l}" == *=* ]] || problems+=( "unpinned apt-get install: $(cut -c1-48 <<< "${l}")" )
        done < <(grep -hE 'apt-get[[:space:]]+install' "${RECIPE}")
        if   (( ${#problems[@]} == 0 )); then ok "every version is pinned" 15
        elif (( ${#problems[@]} == 1 )) && [[ "${problems[0]}" == *latest* ]]; then part "every version is pinned" 5 15 "${problems[0]}"
        elif (( ${#problems[@]} == 1 )); then part "every version is pinned" 10 15 "${problems[0]}"
        else no "every version is pinned" 15 "${problems[0]}"; for ((i=1;i<${#problems[@]};i++)); do note "${problems[i]}"; done; fi
    fi
fi

# --------------------------------------------------------------------- 2 (20)
if want versions; then
    VI="${RUN}/versions-image.txt"; VC="${RUN}/versions-conda.txt"
    # Where the file sits is not what this test grades: a versions file left in last week's
    # directory still counts, with a note to move it.
    if [[ ! -s "${VI}" && -s "${REPO}/cluster-run/versions-image.txt" ]]; then
        VI="${REPO}/cluster-run/versions-image.txt"; VC="${REPO}/cluster-run/versions-conda.txt"
        note "versions-image.txt is in cluster-run/; step 8 puts it in cluster-run-container/"
    fi
    if [[ ! -s "${VI}" ]]; then
        no "the versions inside your image match the course environment" 20 \
           "no cluster-run-container/versions-image.txt — run tests/print_versions.sh inside your image (step 8)"
    else
        good=0; bad=()
        for t in "${!REPORTED[@]}"; do
            got=$(awk -v t="${t}" '$1 == t { print $2 }' "${VI}")
            if [[ "${got}" == "${REPORTED[$t]}" ]]; then good=$(( good + 1 ))
            else bad+=( "${t}: image reports '${got:-nothing}', the environment has ${REPORTED[$t]}" ); fi
        done
        if   (( good == 7 )); then ok "the versions inside your image match the course environment" 20
        elif (( good >= 5 )); then part "the versions inside your image match the course environment" 10 20 "${bad[0]}"
             for ((i=1;i<${#bad[@]};i++)); do note "${bad[i]}"; done
        else no "the versions inside your image match the course environment" 20 "${good} of 7 match"
             for b in "${bad[@]}"; do note "${b}"; done; fi
        if [[ -s "${VC}" ]] && ! diff -q "${VC}" "${VI}" >/dev/null; then
            note "versions-conda.txt and versions-image.txt differ — the diff is the finding:"
            diff "${VC}" "${VI}" | grep -E '^[<>]' | sed 's/^/          /'
        fi
    fi
fi

# --------------------------------------------------------------------- 3 (5)
if want job; then
    J=""
    for cand in "${SL}/pull.sbatch" "${C}"/build*.sbatch "${SL}"/build*.sbatch; do [[ -f "${cand}" ]] && { J="${cand}"; break; }; done
    if [[ -z "${J}" ]]; then
        no "the image is fetched by a job" 5 "no slurm/pull.sbatch (or a build job for the .def route)"
    elif ! grep -qE '^#SBATCH' "${J}"; then
        no "the image is fetched by a job" 5 "$(basename "${J}") has no #SBATCH lines, so it is not a job"
    else
        cache=$(grep -hE 'APPTAINER_CACHEDIR=' "${J}" | head -1)
        if [[ -z "${cache}" || "${cache}" == *'$HOME'* || "${cache}" == *'~/'* || "${cache}" == */home/* ]]; then
            no "the image is fetched by a job" 5 "APPTAINER_CACHEDIR is not moved out of your home directory"
        else ok "the image is fetched by a job" 5; fi
    fi
fi

# --------------------------------------------------------------------- 4 (15)
check_script() {   # prints: ok | noexec | noclean | nobind | conda
    local f=$1 entry=$2 l
    [[ -f "${f}" ]] || { echo missing; return; }
    grep -qE '^[^#]*(conda|source)[[:space:]]+activate' "${f}" && { echo conda; return; }
    l=$(joined "${f}" | grep -E 'apptainer[[:space:]]+exec' | grep -F "${entry}" | head -1)
    [[ -z "${l}" ]] && { echo noexec; return; }
    [[ "${l}" == *--cleanenv* ]] || { echo noclean; return; }
    [[ "${l}" == *--bind* || "${l}" == *' -B '* ]] || { echo nobind; return; }
    echo ok
}
if want scripts; then
    s1=$(check_script "${SL}/01_persample.sbatch" run_sample.sh)
    s2=$(check_script "${SL}/02_cohort.sbatch"    run_pipeline.sh)
    why() { case $1 in missing) echo "the file is missing";; conda) echo "it still activates conda";;
                       noexec) echo "its pipeline line is not run through apptainer exec";;
                       noclean) echo "no --cleanenv";; nobind) echo "no --bind";; esac; }
    if [[ "${s1}" == ok && "${s2}" == ok ]]; then ok "both job scripts run the pipeline through the image" 15
    elif [[ "${s1}" == ok || "${s2}" == ok ]] || [[ "${s1}" == no* && "${s2}" == no* && "${s1}" != noexec && "${s2}" != noexec ]]; then
        part "both job scripts run the pipeline through the image" 10 15 \
             "01_persample: ${s1/ok/done}$( [[ ${s1} != ok ]] && echo " — $(why ${s1})")   02_cohort: ${s2/ok/done}$( [[ ${s2} != ok ]] && echo " — $(why ${s2})")"
    else
        no "both job scripts run the pipeline through the image" 15 \
           "01_persample: $(why ${s1})   02_cohort: $(why ${s2})"
    fi
fi

# --------------------------------------------------------------------- 5 (10)
if want variables; then
    set_vars=$(grep -hoE '^[[:space:]]*export[[:space:]]+[A-Z_][A-Z0-9_]*' "${SL}"/0*.sbatch 2>/dev/null \
               | awk '{ print $2 }' | sort -u)
    missing=(); have_threads=0
    for v in ${set_vars}; do
        grep -rqE "\\\$\{?${v}\b" "${REPO}/lib" "${REPO}/stages" "${REPO}"/run_*.sh 2>/dev/null || continue
        # Either spelling carries it: --env NAME=value (alone or in a comma list), or the
        # APPTAINERENV_NAME= prefix that Apptainer's documentation also uses.
        if grep -qE -e "APPTAINERENV_${v}=|--env[= ]+[\"']?([A-Za-z_][A-Za-z0-9_]*=[^,[:space:]]*,)*${v}=" \
                "${SL}"/0*.sbatch 2>/dev/null; then
            [[ "${v}" == THREADS ]] && have_threads=1
        else missing+=( "${v}" ); fi
    done
    if   (( ${#missing[@]} == 0 && have_threads )); then ok "the job's variables reach the container" 10
    elif (( have_threads )); then part "the job's variables reach the container" 5 10 \
         "your job scripts set these and your pipeline reads them, but they are not carried in: ${missing[*]}"
    else others=(); for v in "${missing[@]}"; do [[ "${v}" == THREADS ]] || others+=( "${v}" ); done
         no "the job's variables reach the container" 10 \
         "THREADS is not carried in with --env THREADS=… — the pipeline then uses its own default${others:+; also missing: ${others[*]}}"; fi
fi

# --------------------------------------------------------------------- 6 (15)
if want cohort; then
    vcf=$(ls "${RUN}"/*.vcf.gz 2>/dev/null | head -1)
    man="${RUN}/manifest.json"
    # The container field, as write_manifest.sh writes it: "container": "/path/to/image.sif"
    container_of() { grep -oE '"container"[[:space:]]*:[[:space:]]*"[^"]*"' "$1" 2>/dev/null \
                         | sed -E 's/.*:[[:space:]]*"//; s/"$//'; }
    if [[ -z "${vcf}" || ! -s "${man}" ]]; then
        hint=""; [[ -s "${REPO}/cluster-run/manifest.json" && "$(container_of "${REPO}/cluster-run/manifest.json" | head -1)" == *.sif ]] \
            && hint=" — this week's run looks like it went into cluster-run/, which keeps last week's"
        no "the cohort ran through the image" 15 "cluster-run-container/ needs the cohort VCF and manifest.json from the containerised run (step 7)${hint}"
    else
        cont=$(container_of "${man}" | head -1)
        # Step 9: the two record checksums, last week's and this week's. They need not match; a
        # difference needs one sentence saying why -- a few words on a line with no checksum.
        RS="${RUN}/records-sha256.txt"
        sums=$(grep -oE '\b[0-9a-f]{64}\b' "${RS}" 2>/dev/null | head -2)
        nsum=$(grep -c . <<< "${sums}")
        words=$(grep -vE '[0-9a-f]{64}' "${RS}" 2>/dev/null | grep -oE '[A-Za-z]+' | wc -l | tr -d ' ')
        if [[ "${cont}" != *.sif ]]; then
            part "the cohort ran through the image" 5 15 \
                 "the manifest's container field is '${cont:-absent}' — stage 9 should call write_manifest.sh (step 6), which records it, and the cohort must run through the image (step 7)"
        elif (( nsum < 2 )); then
            part "the cohort ran through the image" 10 15 \
                 "cluster-run-container/records-sha256.txt needs both record checksums, last week's and this week's (step 9)"
        elif [[ "$(sed -n 1p <<< "${sums}")" == "$(sed -n 2p <<< "${sums}")" ]]; then
            ok "the cohort ran through the image" 15; note "container: ${cont}"; note "the records match last week's"
        elif (( words >= 5 )); then
            ok "the cohort ran through the image" 15; note "container: ${cont}"; note "the records differ from last week's, and records-sha256.txt says why"
        else
            part "the cohort ran through the image" 10 15 \
                 "the two record checksums differ; add one sentence to records-sha256.txt saying why (step 9)"
        fi
    fi
fi

# --------------------------------------------------------------------- 7 (10)
if want IMAGE; then
    IM="${REPO}/IMAGE.md"
    if [[ ! -s "${IM}" ]]; then no "IMAGE.md" 10 "missing or empty"
    else
        dig=0; base=0; vers=0
        # The pushed image's digest. A digest of the BASE image does not count: IMAGE.md records
        # that one too, and it names the image you started from, not the one you built.
        base_repo=$(grep -iE '^[[:space:]]*(FROM|From:)[[:space:]]' "${RECIPE:-/dev/null}" 2>/dev/null | tail -1 \
                    | sed -E 's/^[^[:space:]]+[[:space:]]+//; s/[[:space:]]+AS[[:space:]].*$//I; s/@.*$//; s/:[^/]*$//' \
                    | sed -E 's#^docker\.io/##; s#^library/##')
        while IFS= read -r ref; do
            r=${ref%%@*}; r=${r#docker.io/}; r=${r#library/}
            [[ -n "${base_repo}" && "${r}" == "${base_repo}" ]] && continue
            dig=1; break
        done < <(grep -oE '[A-Za-z0-9._/:<>-]+@sha256:[0-9a-f]{64}' "${IM}")
        # the .def route has no registry digest; its build job id stands in for it
        (( dig == 0 )) && grep -qiE '\.def' "${IM}" && grep -qE '\b[0-9]{7,9}\b' "${IM}" && dig=1
        grep -qiE 'FROM |base image|micromamba|ubuntu|debian' "${IM}" && base=1
        n=0; for t in "${!WANT[@]}"; do grep -qiE "${t%4}" "${IM}" && n=$(( n + 1 )); done; (( n >= 7 )) && vers=1
        # No .sif checksum: /scratch is emptied every month, and two pulls of one digest
        # give different checksums anyway. The pushed digest is what gets the image back.
        if   (( dig && base && vers )); then ok "IMAGE.md" 10
        else m=""; (( base )) || m+="base image; "; (( vers )) || m+="the seven versions; "
             (( dig )) || m+="the pushed image's @sha256: digest; "
             if (( dig + base + vers >= 2 )); then part "IMAGE.md" 5 10 "missing: ${m%; }"
             else no "IMAGE.md" 10 "missing: ${m%; }"; fi; fi
    fi
fi

# --------------------------------------------------------------------- 8 (10)
if want TROUBLE; then
    TS="${REPO}/TROUBLESHOOTING.md"
    if [[ ! -s "${TS}" ]]; then no "TROUBLESHOOTING.md" 10 "missing or empty"
    else
        n=0
        grep -qiE -- '--pull|no-cache|dpkg'                              "${TS}" && n=$(( n + 1 ))
        grep -qiE -- 'bind|No such file|Skipping'                        "${TS}" && n=$(( n + 1 ))
        grep -qiE -- 'native-pair-hmm-threads|Requested threads|--env[= ]+THREADS|APPTAINERENV_THREADS' "${TS}" && n=$(( n + 1 ))
        grep -qiE -- 'arm64|architecture'                                "${TS}" && n=$(( n + 1 ))
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
