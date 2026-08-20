# DSH nginx 站点配置模板（去敏版）。install.sh 用 envsubst 渲染后写入
# /etc/nginx/sites-available/dsh 并软链到 sites-enabled。
# 功能：80 → 301 跳转 443；443 SSL + Basic Auth + 反代 dsh-web。
# 证书：${SSL_CERT_PATH} / ${SSL_KEY_PATH} 由 install.sh 注入（默认自签）。
#       正式证书（LetsEncrypt 等）见 scripts/setup-letsencrypt.sh（可选，需域名）。
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    # Harmless before Certbot is configured; required for HTTP-01 renewal.
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/certbot;
        default_type text/plain;
    }
    location / {
        return 301 https://$host$request_uri;
    }
}
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _;

    ssl_certificate     ${SSL_CERT_PATH};
    ssl_certificate_key ${SSL_KEY_PATH};
    ssl_protocols TLSv1.2 TLSv1.3;

    client_max_body_size 110m;

    # ---- Basic Auth：浏览器加密打开时的登录账号 ----
    auth_basic "DSH Login";
    auth_basic_user_file /etc/nginx/.htpasswd;

    # Static proof consumed by the client-only settings trust plugin. Using a
    # static content handler (not `return`) ensures Nginx runs Basic Auth first.
    location = /api/dsh-public-auth {
        alias ${DEPLOY_DIR}/public-auth.json;
        default_type application/json;
        add_header Cache-Control "no-store";
    }

    # 压缩静态资源（前端 JS/CSS 体积大，gzip 减 60-70%）
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_types text/plain text/css application/json application/javascript text/javascript application/xml application/xml+rss image/svg+xml application/wasm;

    # 不缓冲流式响应（SSE/事件流即时下发）
    proxy_buffering off;
    proxy_request_buffering off;

    proxy_connect_timeout 60s;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # Only the core /assets/ filenames are content-hashed. Plugin bundle URLs
    # are stable across upgrades and must flow through the uncached location /.
    location ~* ^/assets/.*\.(js|css|svg|png|woff2?|map)$ {
        proxy_set_header Host 127.0.0.1;
        proxy_set_header Origin http://127.0.0.1;
        # 必须保留：location 内任何 proxy_set_header 都会整体替换 server 级继承，
        # 少了这两行 WebSocket 升级头就会被剥掉 → /api/events.* 全部 426，实时推送全挂。
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        # Basic Auth terminates at Nginx; never forward its credential upstream.
        proxy_set_header Authorization "";
        proxy_pass http://127.0.0.1:${DSH_PORT};
        add_header Cache-Control "public, max-age=31536000, immutable";
    }

    location / {
        proxy_set_header Host 127.0.0.1;
        proxy_set_header Origin http://127.0.0.1;
        # 同上：必须保留 Upgrade/Connection，否则 WebSocket 升级失败
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Authorization "";
        proxy_pass http://127.0.0.1:${DSH_PORT};
    }
}
