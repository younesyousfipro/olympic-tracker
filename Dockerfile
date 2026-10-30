FROM node:24-alpine AS build
WORKDIR /app
# Lock files first: the npm ci layer stays cached as long as dependencies do not change
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# Runs as user nginx (uid 101), not root. Ports below 1024 are reserved to root, so nginx listens on 8080
FROM nginxinc/nginx-unprivileged:1.27-alpine
COPY nginx/nginx.conf /etc/nginx/nginx.conf
# Angular 20 application builder outputs the static site in browser/
COPY --from=build /app/dist/olympic-games-starter/browser /app
EXPOSE 8080
