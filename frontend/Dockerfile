# syntax = docker/dockerfile:1

FROM node:22-slim AS build
WORKDIR /app

RUN corepack enable && corepack prepare pnpm@9.15.4 --activate

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY frontend/package.json frontend/
RUN pnpm install --frozen-lockfile --filter @ringle/frontend

COPY frontend/ frontend/

ARG VITE_API_BASE_URL=""
ARG VITE_TZ_OFFSET="0"
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL
ENV VITE_TZ_OFFSET=$VITE_TZ_OFFSET
RUN pnpm --filter @ringle/frontend run build

# Serve static files with nginx
FROM nginx:alpine
COPY --from=build /app/frontend/dist /usr/share/nginx/html
COPY frontend/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
