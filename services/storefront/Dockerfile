# ---- Build stage ----
FROM node:20.13-alpine3.19 AS builder

WORKDIR /app

# Install dependencies first (cached layer)
COPY package.json package-lock.json* ./
RUN npm ci --prefer-offline

COPY . .

# NEXT_PUBLIC_API_URL is baked in at build time for static export
# Override via --build-arg in CI
ARG NEXT_PUBLIC_API_URL=http://localhost:8080
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL

RUN npm run build

# ---- Run stage ----
# nginx:alpine — minimal, well-maintained, ~23MB
FROM nginx:1.27-alpine3.19

# Remove default nginx config
RUN rm /etc/nginx/conf.d/default.conf

COPY nginx.conf /etc/nginx/conf.d/app.conf

# Copy the static export output from builder
COPY --from=builder /app/out /usr/share/nginx/html

EXPOSE 3000

HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:3000/healthz || exit 1

# nginx runs as root by default; drop to nginx user
USER nginx

CMD ["nginx", "-g", "daemon off;"]
