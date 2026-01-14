# ================= INSTALL BUN ===================
ARG CACHE_BUST=2026-01-14-01
ARG BUN_VERSION=1.3.3
FROM debian:bullseye-slim AS build-bun
ARG BUN_VERSION

RUN apt-get update -qq \
    && apt-get install -qq --no-install-recommends \
       ca-certificates curl dirmngr gpg gpg-agent unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && arch="$(dpkg --print-architecture)" \
    && case "${arch##*-}" in \
         amd64) build="x64-baseline";; \
         arm64) build="aarch64";; \
         *) echo "unsupported architecture: $arch"; exit 1 ;; \
       esac \
    && tag="bun-v${BUN_VERSION}" \
    && curl -fsSLO "https://github.com/oven-sh/bun/releases/download/${tag}/bun-linux-${build}.zip" \
    && unzip "bun-linux-${build}.zip" \
    && mv "bun-linux-${build}/bun" /usr/local/bin/bun \
    && chmod +x /usr/local/bin/bun \
    && bun --version


# ================= BASE IMAGE ===================

FROM node:22-bullseye-slim AS base
COPY --from=build-bun /usr/local/bin/bun /usr/local/bin/bun

RUN ln -s /usr/local/bin/bun /usr/local/bin/bunx \
    && apt-get update -qy \
    && apt-get install -qy --no-install-recommends \
       openssl git python3 g++ build-essential \
    && rm -rf /var/lib/apt/lists/* \
    && bun --version

WORKDIR /app


# ================= TURBO PRUNE ===================

FROM base AS pruned
ARG SCOPE
RUN test -n "$SCOPE" || (echo "ERROR: SCOPE is required" && exit 1)

COPY . .
RUN bunx turbo prune "$SCOPE" --docker


# ================= BUILD ========================

FROM base AS builder
ARG SCOPE
RUN test -n "$SCOPE" || (echo "ERROR: SCOPE is required" && exit 1)

COPY --from=pruned /app/out/full/ .
COPY bun.lock bunfig.toml ./

RUN SENTRYCLI_SKIP_DOWNLOAD=1 bun install
RUN SKIP_ENV_CHECK=true \
    NEXT_PUBLIC_VIEWER_URL=http://localhost \
    bunx turbo build --filter="$SCOPE"


# ================= RELEASE ======================

FROM base AS release
ARG SCOPE
ARG APP_DIR

RUN test -n "$APP_DIR" || (echo "ERROR: APP_DIR is required" && exit 1)

ENV NODE_ENV=production
ENV PORT=3000

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/packages/prisma/postgresql ./packages/prisma/postgresql

COPY --from=builder /app/apps/${APP_DIR}/.next/standalone ./
COPY --from=builder /app/apps/${APP_DIR}/.next/static ./apps/${APP_DIR}/.next/static
COPY --from=builder /app/apps/${APP_DIR}/public ./apps/${APP_DIR}/public

RUN ./node_modules/.bin/prisma generate \
    --schema=packages/prisma/postgresql/schema.prisma

COPY scripts/${APP_DIR}-entrypoint.sh ./
RUN chmod +x ./${APP_DIR}-entrypoint.sh

EXPOSE 3000
ENTRYPOINT ./${APP_DIR}-entrypoint.sh
