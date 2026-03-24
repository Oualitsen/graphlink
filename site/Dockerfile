FROM nginx:1.27-alpine

# Remove default nginx config
RUN rm /etc/nginx/conf.d/default.conf

# Copy hardened nginx config
COPY nginx.conf /etc/nginx/nginx.conf

# Copy static site files
COPY . /usr/share/nginx/html/

# Remove build artifacts that don't belong in the image
RUN rm -f /usr/share/nginx/html/Dockerfile \
          /usr/share/nginx/html/nginx.conf

# nginx in this config listens on 8080 (non-root port)
EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
