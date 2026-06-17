# Stage 1: Build React app
FROM node:20-alpine AS builder

ARG VITE_IDENTITY_URL="http://localhost:30083"
ARG VITE_FLIGHT_URL="http://localhost:30081"
ARG VITE_BOOKING_URL="http://localhost:30082"
ARG VITE_SEARCH_URL="http://localhost:30084"

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
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 3000

CMD ["nginx", "-g", "daemon off;"]