FROM node:20-alpine AS builder

WORKDIR /app

COPY package.json ./
RUN npm install

COPY . .
RUN npm run build

FROM alpine:3.19 AS probe-bin
WORKDIR /app
COPY probe.go .
RUN apk add --no-cache go && go build -o probe-server probe.go

FROM nginx:alpine

COPY --from=builder /app/dist /usr/share/nginx/html
COPY --from=probe-bin /app/probe-server /usr/local/bin/probe-server

# Write nginx config
RUN echo 'server { listen 3000; root /usr/share/nginx/html; index index.html; location / { try_files $uri $uri/ /index.html; } location /healthz { return 404; } }' > /etc/nginx/conf.d/default.conf

# Write supervisord config
RUN apk add --no-cache supervisor \
    && mkdir -p /var/log/supervisor \
    && mkdir -p /etc/supervisor/supervisord.d/

RUN printf '[supervisord]\nnodaemon=true\nlogfile=/var/log/supervisor/supervisord.log\npidfile=/var/run/supervisord.pid\n\n[program:nginx]\ncommand=nginx -g "daemon off;"\nautostart=true\nautorestart=true\nstderr_logfile=/dev/stderr\nstdout_logfile=/dev/stdout\n\n[program:probe]\ncommand=/usr/local/bin/probe-server\nenvironment=PROBE_PORT="8085"\nautostart=true\nautorestart=true\nstderr_logfile=/dev/stderr\nstdout_logfile=/dev/stdout\n' > /etc/supervisor/supervisord.conf

EXPOSE 3000 8085

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf", "-N"]