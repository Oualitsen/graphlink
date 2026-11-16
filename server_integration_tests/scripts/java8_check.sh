#!/usr/bin/env bash
# Compiles generated Java sources with `javac --release 8`.
#
# usage: java8_check.sh <source-root> <generated-dir> <classpath-file>
#
# Files that import java.net.http are the opt-in JDK 11 transports (`java11` adapters); they are
# compiled at --release 11 first and put on the classpath, so only they may use Java 9+ APIs.
set -euo pipefail

root=$1
src=$2
cp=$(cat "$3")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

find "$src" -name '*.java' | sort > "$work/all"
grep -l 'java\.net\.http' $(cat "$work/all") > "$work/jdk11" || true
grep -vxF -f "$work/jdk11" "$work/all" > "$work/java8" || true

mkdir -p "$work/out11" "$work/out8"
if [ -s "$work/jdk11" ]; then
  javac --release 11 -nowarn -implicit:none -sourcepath "$root" -cp "$cp" \
    -d "$work/out11" @"$work/jdk11" > "$work/log11" 2>&1 || { cat "$work/log11"; echo "java8-check: JDK 11 transport files do not compile"; exit 2; }
fi

if javac --release 8 -Xlint:-options -nowarn -cp "$cp:$work/out11" -d "$work/out8" @"$work/java8" > "$work/log8" 2>&1; then
  echo "java8-check: $(wc -l < "$work/java8" | tr -d ' ') files compile with --release 8 ($(wc -l < "$work/jdk11" | tr -d ' ') JDK 11 transport files excluded)"
else
  grep -E 'error:' -A1 "$work/log8" | sed -E "s|$src/||"
  echo "java8-check: $(grep -c 'error:' "$work/log8") errors with --release 8"
  exit 1
fi
