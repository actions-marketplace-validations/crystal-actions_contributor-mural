FROM crystallang/crystal:1.21-alpine AS builder
WORKDIR /build
COPY src ./src
RUN crystal build src/main.cr -o /hall-of-fame --release --static --no-debug

FROM alpine:3.21
LABEL org.opencontainers.image.source="https://github.com/hahwul/hall-of-fame"
LABEL org.opencontainers.image.description="Generate avatar-wall SVG art from GitHub users and contributors"
LABEL org.opencontainers.image.licenses="MIT"
RUN apk add --no-cache git ca-certificates
COPY --from=builder /hall-of-fame /usr/local/bin/hall-of-fame
ENTRYPOINT ["/usr/local/bin/hall-of-fame"]
