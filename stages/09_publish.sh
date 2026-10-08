#!/usr/bin/env bash
set -euo pipefail

stage_publish() {
    PIPELINE_NAME=variant-calling \
        bash "${HERE}/lib/write_manifest.sh" "${RES}" "${SHEET}" "${REF}" "${REGION}"

    [[ -s "${RES}/manifest.json" ]] || die "write_manifest.sh produced no manifest.json"
    log "manifest written to ${RES}/manifest.json"
}
