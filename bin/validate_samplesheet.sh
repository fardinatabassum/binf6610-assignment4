#!/bin/bash
set -euo pipefail

sheet="$1"
ref="$2"

if [[ ! -f "$sheet" ]]; then
    echo "Samplesheet not found: $sheet" >&2
    exit 1
fi

if [[ ! -f "$ref" ]]; then
    echo "Reference not found: $ref" >&2
    exit 1
fi

sheet_dir=$(dirname "$sheet")

awk -F',' 'NR>1 {
    gsub(/\r/, "")
    # Column 5 is r1_fastq, Column 6 is r2_fastq
    if (NF >= 5 && $5 != "") print $5
    if (NF >= 6 && $6 != "") print $6
}' "$sheet" | while read -r r; do
    # Strip quotes or spaces
    cleaned=$(echo "$r" | tr -d '"' | xargs)
    [[ -z "$cleaned" ]] && continue

    # Resolve relative paths relative to the samplesheet's folder
    if [[ "$cleaned" = /* ]]; then
        target="$cleaned"
    else
        target="$sheet_dir/$cleaned"
    fi

    if [[ ! -f "$target" ]]; then
        echo "FASTQ file missing: $target" >&2
        exit 1
    fi
done

echo "Validation successful"
