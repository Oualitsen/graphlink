FROM alpine AS prep
ARG TARGETARCH
COPY glink-linux-x86_64 /tmp/glink-amd64
COPY glink-linux-arm64 /tmp/glink-arm64
RUN cp /tmp/glink-${TARGETARCH} /tmp/glink && chmod +x /tmp/glink

FROM scratch
COPY --from=prep /tmp/glink /glink
ENTRYPOINT ["/glink"]
