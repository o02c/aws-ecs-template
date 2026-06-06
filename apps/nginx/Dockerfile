# Unprivileged variant: runs as uid 101 (nginx), writes its pid to /tmp/nginx.pid,
# and is built for a read-only root FS. It listens on an unprivileged port (our
# nginx.conf binds 8081) because Fargate can't grant NET_BIND_SERVICE to bind 80.
FROM public.ecr.aws/nginx/nginx-unprivileged:1.31-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
