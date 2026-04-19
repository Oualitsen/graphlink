IMAGE   = ghcr.io/oualitsen/graphlink-site:latest
CONTEXT = $(shell pwd)

install:
	pip install mkdocs-material

# Live-reload docs preview
serve-docs:
	mkdocs serve

# Build MkDocs docs (also regenerates llms.txt, llms-full.txt, sitemap.xml)
build:
	mkdocs build

# Build docs then serve the full site locally
serve: build
	python3 -m http.server 8080

# Build Docker image locally (arm64, for local testing only)
docker-build: build
	docker build -t $(IMAGE) $(CONTEXT)

# Run the Docker image locally
docker-run: docker-build
	docker run --rm -p 8080:8080 $(IMAGE)

# Build multi-platform image and push directly to GHCR
# (requires: docker login ghcr.io and docker buildx)
push: build
	docker buildx build --platform linux/amd64,linux/arm64 \
		-t $(IMAGE) --push $(CONTEXT)

# Deploy to Kubernetes (push first, then rolling restart)
deploy: push
	kubectl rollout restart deployment/graphlink-site
	kubectl rollout status deployment/graphlink-site

# Full release: build docs → build image → push → deploy
release: deploy
