# Stage 1: Build React app
FROM node:22.23.4-alpine3.24 AS builder

ARG VITE_IDENTITY_URL="http://localhost:30083"
ARG VITE_FLIGHT_URL="http://localhost:30081"
ARG VITE_BOOKING_URL="http://localhost:30082"
ARG VITE_SEARCH_URL="http://localhost:30084"

ENV VITE_IDENTITY_URL=$VITE_IDENTITY_URL
ENV VITE_FLIGHT_URL=$VITE_FLIGHT_URL
ENV VITE_BOOKING_URL=$VITE_BOOKING_URL
ENV VITE_SEARCH_URL=$VITE_SEARCH_URL

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npm run build

# Stage 2: Serve with NGINX
FROM nginx:1.30.6-alpine3.24

# Pick up Alpine security fixes published after this image was built.
RUN apk upgrade --no-cache

COPY --from=builder --chown=101:101 /app/dist /usr/share/nginx/html

# Full nginx.conf: non-root pid and temp paths under /tmp, plus the
# /healthz/{startup,live,ready} probe endpoints. See nginx.conf.
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 3000

# Run as the image's numeric nginx user (UID 101), not root.
USER 101:101

CMD ["nginx", "-g", "daemon off;"]