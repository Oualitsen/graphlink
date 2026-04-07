SITE_IMAGE = ghcr.io/oualitsen/graphlink-site:latest

get:
	fvm flutter pub get

compile_win:
	dart compile exe lib/src/main.dart -o glink.exe

compile:
	dart compile exe lib/src/main.dart -o glink

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

site-release: site-build site-deploy site-rollout
	@echo "✓ graphlink.dev deployed"

site-status:
	kubectl get deployment graphlink-site
	kubectl get ingress graphlink-site-ingress
	kubectl get certificate graphlink-site-tls
