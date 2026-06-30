#!/usr/bin/env bash
# extract-image.sh — Extracts the image reference from a rollout.yaml file.
#
# Usage: ./extract-image.sh <path-to-rollout.yaml>
# Output: prints the full image@sha256:... reference to stdout.
set -euo pipefail

ROLLOUT_FILE="${1:?Usage: extract-image.sh <rollout.yaml>}"

# Use grep + sed — avoids yq dependency for a single extraction.
image=$(grep -oP 'image:\s*\K\S+' "$ROLLOUT_FILE" | head -1)

if [[ -z "$image" ]]; then
  echo "ERROR: No image found in $ROLLOUT_FILE" >&2
  exit 1
fi

echo "$image"
