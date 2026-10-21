# Сервер Tethered. Контекст сборки — корень репозитория:
#   docker build -f server/Dockerfile .
# Компилятор работает на машине сборки, Go сам собирает под целевую
# архитектуру: образ для arm64 не требует эмуляции на этапе go build.
FROM --platform=$BUILDPLATFORM golang:1.25-alpine AS build
ARG TARGETOS TARGETARCH
WORKDIR /src/server
COPY server/go.mod server/go.sum ./
RUN go mod download
COPY server/ ./
COPY pocketbase/pb_hooks /src/pocketbase/pb_hooks
COPY pocketbase/pb_public /src/pocketbase/pb_public
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags="-s -w" -o /out/tethered ./cmd/tethered \
 && sh scripts/sync-hooks.sh /out/pb_hooks \
 && sh scripts/sync-public.sh /out/pb_public

FROM alpine:3.22
RUN apk add --no-cache ca-certificates tzdata \
 && adduser -D -H -u 10001 tethered \
 && mkdir /data /backups && chown tethered /data /backups
WORKDIR /app
COPY --from=build /out/tethered /app/tethered
COPY --from=build /out/pb_hooks /app/pb_hooks
COPY --from=build /out/pb_public /app/pb_public
ENV TETHERED_DATA_DIR=/data \
    TETHERED_HOOKS_DIR=/app/pb_hooks \
    TETHERED_PUBLIC_DIR=/app/pb_public \
    TETHERED_HTTP_ADDR=0.0.0.0:8090 \
    TETHERED_BACKUP__DIR=/backups
USER tethered
VOLUME /data /backups
EXPOSE 8090
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s \
  CMD wget -qO- http://127.0.0.1:8090/api/health >/dev/null || exit 1
ENTRYPOINT ["/app/tethered"]
