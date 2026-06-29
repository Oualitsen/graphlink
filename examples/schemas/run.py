#!/usr/bin/env python3
"""
Generate and compile-check GraphLink client code from world GraphQL schemas.

Usage:
  python3 run.py --schema github --language dart
  python3 run.py --schema github --all-langs
  python3 run.py --all-schemas --language dart
  python3 run.py --all
  python3 run.py --list
  python3 run.py github              # shorthand: schema → all languages
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent

# Per-language config
LANGUAGES = {
    "dart": {
        "dir": "dart",
        "output_dir": "lib/generated",
        "generate_target": "generate",
        "check_target": "analyze-only",
    },
    "java": {
        "dir": "java",
        "output_dir": "client-app/src/main/java/dev/graphlink/github/generated",
        "generate_target": "generate",
        "check_target": "compile-only",
    },
    "kotlin": {
        "dir": "kotlin",
        "output_dir": "client-app/src/main/kotlin/dev/graphlink/github/generated",
        "generate_target": "generate",
        "check_target": "compile-only",
    },
    "typescript": {
        "dir": "typescript",
        "output_dir": "client-app/src/generated",
        "generate_target": "generate",
        "check_target": "compile-only",
    },
}


# ── helpers ──────────────────────────────────────────────────────────────────

def list_schemas():
    """Return sorted list of available schema names (stem of .graphql files)."""
    return sorted(p.stem for p in ROOT.glob("*.graphql"))


def set_schema_path(lang_dir: str, schema_name: str):
    """Rewrite schemaPaths in <lang_dir>/config.json to point at the given schema."""
    config_path = ROOT / lang_dir / "config.json"
    config = json.loads(config_path.read_text())
    config["schemaPaths"] = [f"../{schema_name}.graphql"]
    config_path.write_text(json.dumps(config, indent=4) + "\n")


def run_make(lang_dir: str, target: str) -> int:
    """Run make in a language directory. Output streams to terminal. Returns exit code."""
    result = subprocess.run(
        ["make", "-C", str(ROOT / lang_dir), target],
        cwd=str(ROOT),
    )
    return result.returncode


def generated_files_exist(lang_info: dict) -> bool:
    """Check whether the output directory has any generated files."""
    out = ROOT / lang_info["dir"] / lang_info["output_dir"]
    if not out.is_dir():
        return False
    return any(out.rglob("*"))


# ── main logic ───────────────────────────────────────────────────────────────

def resolve_schemas(args) -> list[str]:
    if args.all or args.all_schemas:
        return list_schemas()
    name = args.schema or args.schema_shorthand
    if name:
        return [name]
    print("Error: specify --schema <name>, --all-schemas, --all, or a shorthand name.")
    sys.exit(1)


def resolve_languages(args) -> list[str]:
    if args.all or args.all_langs:
        return list(LANGUAGES.keys())
    if args.language:
        return [l.strip() for l in args.language.split(",")]
    print("Error: specify --language <lang>, --all-langs, or --all.")
    sys.exit(1)


def validate(schemas: list[str], languages: list[str]):
    available_schemas = set(list_schemas())
    for s in schemas:
        if s not in available_schemas:
            print(f"Error: schema '{s}' not found. Available: {', '.join(sorted(available_schemas))}")
            sys.exit(1)

    for lang in languages:
        if lang not in LANGUAGES:
            print(f"Error: language '{lang}' not supported. Available: {', '.join(LANGUAGES.keys())}")
            sys.exit(1)


def run_one(schema: str, lang: str, info: dict) -> bool:
    """
    Run generation + check for one schema/language pair.
    All output streams to terminal. Returns True on success.
    """
    set_schema_path(info["dir"], schema)

    # Phase 1 — generate
    banner("generate", schema, lang)
    rc = run_make(info["dir"], info["generate_target"])

    if not generated_files_exist(info):
        print(f"\n  ✗  No files generated (graphlink hit an error)\n")
        return False

    # Phase 2 — compile / analyze
    banner("check", schema, lang)
    rc = run_make(info["dir"], info["check_target"])

    if rc != 0:
        print(f"\n  ✗  Check failed (exit {rc})\n")
        return False

    print(f"  ✓  {schema} → {lang}\n")
    return True


def banner(phase: str, schema: str, lang: str):
    """Print a section banner."""
    print(f"\n─── {phase} ({schema} → {lang}) ", end="", flush=True)
    print("─" * (50 - len(phase) - len(schema) - len(lang)))


def main():
    parser = argparse.ArgumentParser(
        description="Generate and compile-check GraphLink clients from world GraphQL schemas."
    )
    parser.add_argument("--schema", help="Schema name (without .graphql extension)")
    parser.add_argument("--language", "--lang",
                        help="Language: dart, java, kotlin, typescript (comma-separated ok)")
    parser.add_argument("--all-langs",   action="store_true", help="Run all supported languages")
    parser.add_argument("--all-schemas", action="store_true", help="Run all discovered schemas")
    parser.add_argument("--all",         action="store_true", help="All schemas × all languages")
    parser.add_argument("--list",        action="store_true", help="List available schemas and languages")
    parser.add_argument("schema_shorthand", nargs="?", help="Schema name (positional shorthand)")
    args = parser.parse_args()

    if args.list:
        print("Schemas:")
        for s in list_schemas():
            print(f"  {s}")
        print(f"\nLanguages: {', '.join(LANGUAGES.keys())}")
        return

    schemas = resolve_schemas(args)
    languages = resolve_languages(args)
    validate(schemas, languages)

    total = len(schemas) * len(languages)
    passed = 0
    failed = 0

    for schema in schemas:
        for lang in languages:
            info = LANGUAGES[lang]

            if total > 1:
                print(f"\n{'='*60}")
                print(f"[{passed + failed + 1}/{total}] {schema} → {lang}")
                print(f"{'='*60}")

            ok = run_one(schema, lang, info)
            if ok:
                passed += 1
            else:
                failed += 1

    if total > 1:
        print(f"{'='*60}")
        print(f"  {passed} passed, {failed} failed")
        print(f"{'='*60}")

    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
