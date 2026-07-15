# ---- Build stage: install deps with full toolchain available ----
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install --omit=dev

# ---- Runtime stage: minimal image, no build tools, no dev deps ----
FROM node:20-alpine AS runtime
WORKDIR /app

# Run as non-root user (built into the node:alpine image)
USER node

COPY --chown=node:node --from=builder /app/node_modules ./node_modules
COPY --chown=node:node package.json ./
COPY --chown=node:node server.js ./

ENV NODE_ENV=production
EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD node -e "require('http').get('http://localhost:5000/health', r => process.exit(r.statusCode===200?0:1)).on('error', () => process.exit(1))"

CMD ["node", "server.js"]
