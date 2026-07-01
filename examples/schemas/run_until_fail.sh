#!/usr/bin/env bash
# Run each schema for LANG (default: dart) until one fails to generate/compile.
set -uo pipefail

LANG_ARG="${1:-dart}"

SCHEMAS=$(python3 run.py --list | awk '/^Schemas:/{flag=1;next}/^Languages:/{flag=0}flag{print $1}')

for schema in $SCHEMAS; do
  echo "=== $schema ($LANG_ARG) ==="
  if ! python3 run.py --schema "$schema" --language "$LANG_ARG"; then
    echo ">>> FAILED on schema: $schema"
    exit 1
  fi
done

echo "All schemas passed for $LANG_ARG"
