#!/bin/bash
set -euo pipefail

bam="$1"
threshold="${2:-80}"

if [[ ! -f "$bam" ]]; then
    echo "BAM file not found: $bam" >&2
    exit 1
fi

# Calculate percentage of mapped reads using samtools flagstat
mapped_pct=$(samtools flagstat "$bam" | awk -F'[(%]' '/mapped %/ {print $2; exit}' || true)

if [[ -z "$mapped_pct" ]]; then
    # Fallback pattern for different samtools flagstat versions
    mapped_pct=$(samtools flagstat "$bam" | awk '/([0-9.]+)% : [0-9]+ mapped/ {print $1; exit}' || true)
fi

if [[ -z "$mapped_pct" ]]; then
    # General fallback: mapped reads / total reads * 100
    mapped_pct=$(samtools flagstat "$bam" | awk '
        NR==1 {total=$1}
        /mapped \(/ {mapped=$1; if (total > 0) printf "%.2f", (mapped/total)*100; exit}
    ')
fi

# Compare against threshold
is_valid=$(awk -v pct="$mapped_pct" -v thresh="$threshold" 'BEGIN {print (pct >= thresh) ? 1 : 0}')

if [[ "$is_valid" -ne 1 ]]; then
    echo "Check failed: mapping rate ${mapped_pct}% is below threshold ${threshold}%" >&2
    exit 1
fi

echo "Mapping rate OK: ${mapped_pct}% >= ${threshold}%"
