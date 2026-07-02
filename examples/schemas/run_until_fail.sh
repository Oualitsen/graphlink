#!/usr/bin/env bash
# Run each schema for LANG (default: dart) until one fails to generate/compile.
set -uo pipefail

LANG_ARG="${1:-dart}"
START_FROM="${2:-}"

SCHEMAS=$(python3 run.py --list | awk '/^Schemas:/{flag=1;next}/^Languages:/{flag=0}flag{print $1}')

if [[ -n "$START_FROM" ]]; then
  SCHEMAS=$(echo "$SCHEMAS" | awk -v start="$START_FROM" '$0==start{flag=1} flag{print}')
  if [[ -z "$SCHEMAS" ]]; then
    echo "No schema found matching startFrom: $START_FROM" >&2
    exit 1
  fi
fi

for schema in $SCHEMAS; do
  echo "=== $schema ($LANG_ARG) ==="
  if ! python3 run.py --schema "$schema" --language "$LANG_ARG"; then
    echo ">>> FAILED on schema: $schema"
    exit 1
  fi
done

echo "All schemas passed for $LANG_ARG"
