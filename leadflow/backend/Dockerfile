# -------------------
# Backend Dockerfile – Multi-stage, Non-root
# -------------------
FROM node:20-alpine AS builder
WORKDIR /app

# Install dependencies
COPY package*.json ./
RUN npm ci

# Copy source code and build
COPY . .
RUN npm run build
# Prune devDependencies to keep image lean
RUN npm prune --production

FROM node:20-alpine AS runner
WORKDIR /app

# Create non-root user for security hygiene
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copy built dist, node_modules, package.json, and migrations
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/migrations ./migrations

ENV PORT=3001
ENV NODE_ENV=production
EXPOSE 3001

USER appuser

CMD ["node", "dist/server.js"]
