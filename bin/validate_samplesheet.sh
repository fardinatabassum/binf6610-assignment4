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

awk -F',' 'NR>1 {
    gsub(/\r/, "")
    if ($5 != "") print $5
    if ($6 != "") print $6
}' "$sheet" | while read -r r; do
    base=$(basename "$r" | tr -d '"' | xargs)
    if [[ -n "$base" && ! -f "$base" ]]; then
        echo "FASTQ file missing: $base" >&2
        exit 1
    fi
done

echo "Validation successful"
