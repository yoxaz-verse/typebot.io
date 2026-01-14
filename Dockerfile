# ================= INSTALL BUN ===================
ARG BUN_VERSION=1.3.3
FROM debian:bullseye-slim AS build-bun
ARG BUN_VERSION

RUN apt-get update -qq \
    && apt-get install -qq --no-install-recommends \
       ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/* \
    && arch="$(dpkg --print-architecture)" \
    && case "${arch##*-}" in \
         amd64) build="x64-baseline";; \
         arm64) build="aarch64";; \
         *) echo "unsupported architecture"; exit 1 ;; \
       esac \
    && curl -fsSLO "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-linux-${build}.zip" \
    && unzip bun-linux-${build}.zip \
    && mv bun-linux-${build}/bun /usr/local/bin/bun \
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

COPY . .
RUN bunx turbo prune viewer --docker


# ================= BUILD ========================
FROM base AS builder

COPY --from=pruned /app/out/full/ .
COPY bun.lock bunfig.toml ./

RUN bun install

RUN SKIP_ENV_CHECK=true \
    bunx turbo build --filter=viewer


# ================= RELEASE ======================
FROM base AS release

ENV NODE_ENV=production
ENV PORT=3000

COPY --from=builder /app/node_modules ./node_modules

COPY --from=builder /app/apps/viewer/.next/standalone ./
COPY --from=builder /app/apps/viewer/.next/static ./apps/viewer/.next/static
COPY --from=builder /app/apps/viewer/public ./apps/viewer/public

EXPOSE 3000
CMD ["node", "server.js"]
