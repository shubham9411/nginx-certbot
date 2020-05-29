#!/bin/bash

if ! [ -x "$(command -v docker-compose)" ]; then
  echo 'Error: docker-compose is not installed.' >&2
  exit 1
fi

if ! [ -e .env ]; then
  echo "Please generate dotenv file first" >&2
  exit 1
fi

domains=($(cat .env | grep DOMAIN | awk -F "=" '{print $2}'))
base_domain=$(cat .env | grep BASE_DOMAIN | awk -F "=" '{print $2}')
port=$(cat .env | grep PORT | awk -F "=" '{print $2}')
email=$(cat .env | grep CERTBOT_EMAIL | awk -F "=" '{print $2}')
staging=$(cat .env | grep CERTBOT_STAGING | awk -F "=" '{print $2}')
docker_proxy_pass=$(cat .env | grep DOCKER_PROXY_PASS | awk -F "=" '{print $2}')
rsa_key_size=4096
data_path="./data/certbot"

# if [ -d "$data_path" ]; then
#   read -p "Existing data found for $domains. Continue and replace existing certificate? (y/N) " decision
#   if [ "$decision" != "Y" ] && [ "$decision" != "y" ]; then
#     exit
#   fi
# fi


if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] || [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then
  echo "### Downloading recommended TLS parameters ..."
  mkdir -p "$data_path/conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "$data_path/conf/options-ssl-nginx.conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "$data_path/conf/ssl-dhparams.pem"
  echo
fi

echo "### Creating dummy certificate for $domains ..."
path="/etc/letsencrypt/live/$domains"
mkdir -p "$data_path/conf/live/$domains"
docker-compose run --rm --entrypoint "\
  openssl req -x509 -nodes -newkey rsa:1024 -days 1\
    -keyout '$path/privkey.pem' \
    -out '$path/fullchain.pem' \
    -subj '/CN=localhost'" certbot
echo

echo "### Deleting dummy certificate for $domains ..."
docker-compose run --rm --entrypoint "\
  rm -Rf /etc/letsencrypt/live/$domains && \
  rm -Rf /etc/letsencrypt/archive/$domains && \
  rm -Rf /etc/letsencrypt/renewal/$domains.conf" certbot
echo


echo "### Requesting Let's Encrypt certificate for $domains ..."
#Join $domains to -d args
domain_args=""
for domain in "${domains[@]}"; do
  domain_args="$domain_args -d $domain"
done

# Select appropriate email arg
case "$email" in
  "") email_arg="--register-unsafely-without-email" ;;
  *) email_arg="--email $email" ;;
esac

# Enable staging mode if needed
if [ $staging != "0" ]; then staging_arg="--staging"; fi

echo "### Creating nginx confs ..."
for domain in "${domains[@]}"; do
  touch "$(pwd)/data/nginx/$domain.conf"
  base_domain=$base_domain domain=$domain proxy_pass=$docker_proxy_pass port=$port file="$(pwd)/data/nginx/$domain.conf" ./nginx.conf.sh
done
echo

docker-compose run --rm --entrypoint  "\
    certbot certonly --agree-tos \
    $staging_arg \
    $email_arg \
    --rsa-key-size $rsa_key_size \
    --noninteractive \
    --server https://acme-v02.api.letsencrypt.org/directory \
    --dns-route53 \
    -d  *.$base_domain" certbot
echo
