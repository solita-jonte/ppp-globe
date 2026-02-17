# Build stage: build the Vite frontend
FROM node:20-alpine AS build
WORKDIR /app

# Copy root-level package manifests so we can install dependencies
# (they live at the repo root, not inside src/Frontend)
COPY package.json package-lock.json* ./

# Install dependencies (use npm ci when lockfile is present)
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi

# Copy the frontend source and Vite config
COPY src/Frontend ./src/Frontend
COPY vite.config.mts ./vite.config.mts

# Set build-time API base URL (can be overridden via --build-arg)
ARG API_BASE_URL=http://127.0.0.1:7071/api
ENV VITE_API_BASE_URL=${API_BASE_URL}

# Build the app
WORKDIR /app/src/Frontend
RUN npm run build

# Runtime stage: serve static files
FROM node:20-alpine AS runtime
WORKDIR /app

# Install a simple static file server
RUN npm install -g serve

# Copy built assets from build stage
COPY --from=build /app/src/Frontend/dist ./dist
COPY --from=build /app/src/Frontend/countries.geojson ./dist

# Expose the port serve will listen on
EXPOSE 4173

# Serve the built app
CMD ["serve", "-s", "dist", "-l", "4173"]
