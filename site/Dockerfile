# Stage 1: Build MkDocs docs
FROM python:3.12-alpine AS builder
RUN pip install --no-cache-dir mkdocs-material
WORKDIR /site
COPY mkdocs.yml .
COPY docs-src/ docs-src/
COPY hooks/ hooks/
COPY overrides/ overrides/
COPY favicon.svg robots.txt ./
RUN mkdocs build
# Move root assets into dist so nginx serves them from /
RUN cp favicon.svg robots.txt dist/

# Stage 2: Serve with nginx
FROM nginx:1.27-alpine
RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/nginx.conf

# Everything served from the MkDocs build output
COPY --from=builder /site/dist/ /usr/share/nginx/html/

EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
