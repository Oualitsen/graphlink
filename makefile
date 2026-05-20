SITE_IMAGE = ghcr.io/oualitsen/graphlink-site:latest

get:
	fvm flutter pub get

compile_win:
	dart compile exe lib/src/main.dart -o glink.exe

compile:
	dart compile exe lib/src/main.dart -o glink

deploy:
	dart compile exe lib/src/main.dart -o ~/bin/glink

generate-examples:
	find examples -name "Makefile" -o -name "makefile" | while read f; do \
		$(MAKE) -C "$$(dirname $$f)" generate; \
	done

clean-generated:
	find . -type d -name generated -exec rm -rf {} +

# ── Site ──────────────────────────────────────────────────

# Live-reload docs preview (MkDocs dev server on http://localhost:8000)
site-dev:
	cd site && mkdocs serve

# Build docs then serve the full site (landing + docs) on http://localhost:8080
site-local: site-docs
	cd site && python3 -m http.server 8082

# Build MkDocs docs only (regenerates dist/, llms.txt, sitemap.xml)
site-docs:
	cd site && mkdocs build

site-build:
	docker buildx build --platform linux/amd64 -t $(SITE_IMAGE) --push site/

site-deploy:
	kubectl apply -f k8s/graphlink-site.yaml -n default

# One-time cluster setup — apply ingress rules (do NOT run on every release)
site-setup:
	kubectl apply -f k8s/graphlink-site-ingress.yaml -n default

site-rollout:
	kubectl rollout restart deployment/graphlink-site -n default

site-version:
	@VERSION=$$(grep '^version:' pubspec.yaml | sed 's/version: //'); \
	sed -i '' "s/?v=[0-9]*\.[0-9]*\.[0-9]*/?v=$$VERSION/g" site/index.html; \
	sed -i '' "s/Open Source · MIT · v[0-9]*\.[0-9]*\.[0-9]*/Open Source · MIT · v$$VERSION/g" site/index.html; \
	echo "✓ site/index.html updated to v$$VERSION"

site-release: site-version site-build site-deploy site-rollout
	@echo "✓ graphlink.dev deployed"

site-status:
	kubectl get deployment graphlink-site -n default
	kubectl get ingress graphlink-site-ingress -n default
	kubectl get certificate graphlink-site-tls -n default