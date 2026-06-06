# Stage 1: Build React app
FROM node:20-alpine AS builder

ARG VITE_IDENTITY_URL
ARG VITE_FLIGHT_URL
ARG VITE_BOOKING_URL
ARG VITE_SEARCH_URL

ENV VITE_IDENTITY_URL=$VITE_IDENTITY_URL
ENV VITE_FLIGHT_URL=$VITE_FLIGHT_URL
ENV VITE_BOOKING_URL=$VITE_BOOKING_URL
ENV VITE_SEARCH_URL=$VITE_SEARCH_URL

WORKDIR /app

COPY package.json ./
RUN npm install

COPY . .
RUN npm run build

# Stage 2: Serve with NGINX
FROM nginx:alpine

COPY --from=builder /app/dist /usr/share/nginx/html

RUN echo 'server { listen 3000; root /usr/share/nginx/html; index index.html; location / { try_files $uri $uri/ /index.html; } }' > /etc/nginx/conf.d/default.conf

EXPOSE 3000

CMD ["nginx", "-g", "daemon off;"]