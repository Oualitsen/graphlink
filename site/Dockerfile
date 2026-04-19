# Stage 1: Build MkDocs docs
FROM python:3.12-alpine AS builder
RUN pip install --no-cache-dir mkdocs-material
WORKDIR /site
COPY mkdocs.yml .
COPY docs-src/ docs-src/
COPY hooks/ hooks/
RUN mkdocs build

# Stage 2: Serve with nginx
FROM nginx:1.27-alpine
RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/nginx.conf

# Landing page and root assets
COPY index.html favicon.svg robots.txt llms.txt llms-full.txt sitemap.xml /usr/share/nginx/html/
COPY css/ /usr/share/nginx/html/css/
COPY js/ /usr/share/nginx/html/js/

# MkDocs-built docs
COPY --from=builder /site/docs/ /usr/share/nginx/html/docs/

EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
