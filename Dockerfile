FROM node:24-alpine AS build
WORKDIR /app
# Lock files first: the npm ci layer stays cached as long as dependencies do not change
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:1.27-alpine
COPY nginx/nginx.conf /etc/nginx/nginx.conf
# Angular 20 application builder outputs the static site in browser/
COPY --from=build /app/dist/olympic-games-starter/browser /app
EXPOSE 80
