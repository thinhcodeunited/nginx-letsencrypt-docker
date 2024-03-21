#!/bin/bash

domains=(anvietthinh.com xstar.anvietthinh.com nsfw.anvietthinh.com) # Thêm các domain bạn muốn cài đặt chứng chỉ SSL vào đây
rsa_key_size=4096
data_path="./data/certbot"
email="" # Thay đổi thành địa chỉ email của bạn
staging=0 # Đặt thành 1 nếu bạn đang thử nghiệm để tránh giới hạn yêu cầu

if [ -d "$data_path" ]; then
  read -p "Dữ liệu đã tồn tại cho các tên miền $domains. Tiếp tục và thay thế chứng chỉ hiện tại không? (y/N) " decision
  if [ "$decision" != "Y" ] && [ "$decision" != "y" ]; then
    exit
  fi
fi

if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] || [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then
  echo "### Đang tải các tham số TLS được khuyến nghị..."
  mkdir -p "$data_path/conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "$data_path/conf/options-ssl-nginx.conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "$data_path/conf/ssl-dhparams.pem"
  echo
fi

for domain in "${domains[@]}"; do
  echo "### Đang tạo chứng chỉ giả cho $domain ..."
  path="/etc/letsencrypt/live/$domain"
  mkdir -p "$data_path/conf/live/$domain"
  docker compose run --rm --entrypoint "\
    openssl req -x509 -nodes -newkey rsa:$rsa_key_size -days 1\
      -keyout '$path/privkey.pem' \
      -out '$path/fullchain.pem' \
      -subj '/CN=localhost'" certbot
  echo
done

echo "### Đang khởi động nginx ..."
docker compose up --force-recreate -d nginx
echo

for domain in "${domains[@]}"; do
  echo "### Đang xóa chứng chỉ giả cho $domain ..."
  docker compose run --rm --entrypoint "\
    rm -Rf /etc/letsencrypt/live/$domain && \
    rm -Rf /etc/letsencrypt/archive/$domain && \
    rm -Rf /etc/letsencrypt/renewal/$domain.conf" certbot
  echo
done

for domain in "${domains[@]}"; do
  echo "### Yêu cầu chứng chỉ Let's Encrypt cho $domain ..."
  docker compose run --rm --entrypoint "\
    certbot certonly --webroot -w /var/www/certbot \
      $staging_arg \
      $email_arg \
      -d $domain \
      --rsa-key-size $rsa_key_size \
      --agree-tos \
      --force-renewal" certbot
  echo
done

echo "### Tải lại nginx ..."
docker compose exec nginx nginx -s reload

