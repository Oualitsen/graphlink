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
site-build:
	docker buildx build --platform linux/amd64 -t $(SITE_IMAGE) --push site/

site-deploy:
	kubectl apply -f k8s/graphlink-site.yaml

site-rollout:
	kubectl rollout restart deployment/graphlink-site

site-version:
	@VERSION=$$(grep '^version:' pubspec.yaml | sed 's/version: //'); \
	sed -i '' "s/?v=[0-9]*\.[0-9]*\.[0-9]*/?v=$$VERSION/g" site/index.html; \
	echo "✓ site/index.html asset versions updated to v$$VERSION"

site-release: site-version site-build site-deploy site-rollout
	@echo "✓ graphlink.dev deployed"

site-status:
	kubectl get deployment graphlink-site
	kubectl get ingress graphlink-site-ingress
	kubectl get certificate graphlink-site-tls