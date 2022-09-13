#!/bin/bash

CWD=$(pwd)

if [ ! -f ".env" ]; then
  echo "Environment file does not exist. Quitting."
  exit -1
fi

source ./.env

if [ "" = "$TRAEFIK_DOMAIN" ] ||
   [ "" = "$TRAEFIK_LE_EMAIL" ] ||
   [ "" = "$TRAEFIK_CF_EMAIL" ] ||
   [ "" = "$TRAEFIK_CF_DNS_TOKEN" ] ||
   [ "" = "$TRAEFIK_BASICAUTH_USER" ] ||
   [ "" = "$DIUN_MAIL_HOST" ] ||
   [ "" = "$DIUN_MAIL_PORT" ] ||
   [ "" = "$DIUN_MAIL_SSL" ] ||
   [ "" = "$DIUN_MAIL_LOCALNAME" ] ||
   [ "" = "$DIUN_MAIL_USERNAME" ] ||
   [ "" = "$DIUN_MAIL_PASSWORD" ] ||
   [ "" = "$DIUN_MAIL_FROM" ] ||
   [ "" = "$DIUN_MAIL_TO" ] ||
   [ "" = "$BACKUP_B2_KEYID" ] ||
   [ "" = "$BACKUP_B2_APPKEY" ] ||
   [ "" = "$BACKUP_B2_BUCKET" ]
then
  echo "Variables required in .env are missing."
  exit -1
fi

function replace {
  local escaped=$(echo "$1" | sed 's/\[/\\[/g' | sed 's/\]/\\]/g')
  local value=$(echo "$2" | sed 's/\//\\\//g')
  sed 's/'"$escaped"'/'"$value"'/g' "$3" -i
}

echo "Installing Docker."
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-compose
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ${USER}

echo "Installing required packages."
sudo apt-get install -y jq nano backblaze-b2

echo "Configuring firewall."
sudo ufw allow OpenSSH
sudo ufw allow http
sudo ufw allow https
sudo ufw enable

echo "Creating Docker network."
sudo -u ${USER} docker network create proxy

echo "Copying service files."
cp -r "$CWD/services" "$HOME/services"

echo "Disabling userland proxy."
echo "{\"userland-proxy\": false}" > /etc/docker/daemon.json
sudo systemctl restart docker

echo "Updating Traefik compose file."
cd "$HOME/services/traefik"
replace "[DOMAIN]" "$TRAEFIK_DOMAIN" "./docker-compose.yml"
replace "[LE_EMAIL]" "$TRAEFIK_LE_EMAIL" "./docker-compose.yml"
replace "[CF_EMAIL]" "$TRAEFIK_CF_EMAIL" "./docker-compose.yml"
replace "[CF_DNS_TOKEN]" "$TRAEFIK_CF_DNS_TOKEN" "./docker-compose.yml"
echo "          - \"$TRAEFIK_BASICAUTH_USER\"" >> "./fileConfig/basic-auth.yml"
./update_cf_ips.sh
sudo -u docker-compose up -d

echo "Installing Traefik Cloudflare IP updater to cron."
crontab -l | { cat; echo "0 7 1 * * $HOME/services/traefik/update_cf_ips.sh"; } | crontab -

echo "Updating Diun compose file."
cd "$HOME/services/diun"
replace "[MAIL_HOST]" "$DIUN_MAIL_HOST" "./docker-compose.yml"
replace "[MAIL_PORT]" "$DIUN_MAIL_PORT" "./docker-compose.yml"
replace "[MAIL_SSL]" "$DIUN_MAIL_SSL" "./docker-compose.yml"
replace "[MAIL_LOCALNAME]" "$DIUN_MAIL_LOCALNAME" "./docker-compose.yml"
replace "[MAIL_USERNAME]" "$DIUN_MAIL_USERNAME" "./docker-compose.yml"
replace "[MAIL_PASSWORD]" "$DIUN_MAIL_PASSWORD" "./docker-compose.yml"
replace "[MAIL_FROM]" "$DIUN_MAIL_FROM" "./docker-compose.yml"
replace "[MAIL_TO]" "$DIUN_MAIL_TO" "./docker-compose.yml"
sudo -u ${USER} docker-compose up -d

echo "Copying backup files."
cp -r "$CWD/backups" "$HOME/backups"

echo "Configuring backup script."
cd "$HOME/backups"
replace "[B2_KEYID]" "$BACKUP_B2_KEYID" "./backup.sh"
replace "[B2_APPKEY]" "$BACKUP_B2_APPKEY" "./backup.sh"
replace "[B2_BUCKET]" "$BACKUP_B2_BUCKET" "./backup.sh"

echo "Installing backup script to cron."
crontab -l | { cat; echo "0 7 * * * $HOME/backups/backup.sh"; } | crontab -

echo "All tasks completed successfully."
