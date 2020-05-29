#!/bin/sh

cat > $file <<EOF

server {
  listen 80;
  server_name $domain;
  server_tokens off;

  location / {
    return 301 https://\$host\$request_uri;
  }

  location /.well-known/acme-challenge/ {
    root /var/www/certbot;
  }
}

server {
  listen 443 ssl;
  server_name $domain;

  ssl_certificate /etc/letsencrypt/live/$base_domain/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$base_domain/privkey.pem;
  include /etc/letsencrypt/options-ssl-nginx.conf;
  ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

  location / {
    proxy_pass http://$proxy_pass:$port;
    proxy_http_version 1.1;
    proxy_set_header    Upgrade             \$http_upgrade;
    proxy_set_header    Connection          "upgrade";
    proxy_read_timeout  86400;
    proxy_set_header    Host                \$http_host;
    proxy_set_header    X-Real-IP           \$remote_addr;
    proxy_set_header    X-Forwarded-For     \$proxy_add_x_forwarded_for;
  }
}

EOF