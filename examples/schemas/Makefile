SCHEMA ?= github
LANG   ?= dart

.PHONY: run list clean help

# Run a single schema + language combination
#   make SCHEMA=twitch LANG=java
#   make SCHEMA=github LANG=dart
run:
	python3 run.py --schema $(SCHEMA) --language $(LANG)

# Run one schema against all languages
#   make all-langs SCHEMA=spacex
all-langs:
	python3 run.py --schema $(SCHEMA) --all-langs

# Run all schemas against one language
#   make all-schemas LANG=kotlin
all-schemas:
	python3 run.py --all-schemas --language $(LANG)

# Run everything (every schema × every language)
all:
	python3 run.py --all

# List available schemas and languages
list:
	python3 run.py --list

# Wipe generated output across all languages
clean:
	rm -rf dart/lib/generated
	rm -rf java/client-app/src/main/java/dev/graphlink/github/generated
	rm -rf kotlin/client-app/src/main/kotlin/dev/graphlink/github/generated
	rm -rf typescript/client-app/src/generated

help:
	@echo "Usage:"
	@echo "  make SCHEMA=<name> LANG=<lang>    Single schema + language"
	@echo "  make all-langs SCHEMA=<name>      One schema, all languages"
	@echo "  make all-schemas LANG=<lang>      All schemas, one language"
	@echo "  make all                          All schemas × all languages"
	@echo "  make list                         List available schemas and languages"
	@echo "  make clean                        Wipe all generated code"
