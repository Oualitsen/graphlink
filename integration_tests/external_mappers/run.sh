#!/usr/bin/env bash
# Generates a Spring server whose mappings involve @glExternal types, then compiles the generated
# mapper classes against hand-written stub entities and runs them.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

sed -e "s|OUT_DIR|$work/generated|" -e "s|SCHEMA_PATH|$here/schema.graphql|" "$here/config.json" > "$work/config.json"
cp "$here/schema.graphql" "$work/schema.graphql"

(cd "$root" && dart run lib/src/main.dart -c "$work/config.json")

test -f "$work/generated/mappers/UserEntityMapper.java"
test -f "$work/generated/mappers/UserMapper.java"

mkdir -p "$work/classes"
javac -d "$work/classes" \
  "$here"/stub/com/acme/persistence/*.java \
  "$work"/generated/types/*.java \
  "$work"/generated/mappers/*.java \
  "$here/Main.java"
java -cp "$work/classes" Main
