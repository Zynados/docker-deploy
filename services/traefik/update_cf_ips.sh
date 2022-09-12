#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
HASH=""
DATA=$(curl -X GET "https://api.cloudflare.com/client/v4/ips" 2>/dev/null)
NEW_HASH=`echo $DATA | md5sum | awk '{ print $1 }'`
if [[ "$NEW_HASH" == "$HASH" ]]; then
  echo "No changes."
  exit 0
fi

sed "s/HASH=\".*\"/HASH=\"$NEW_HASH\"/" "$DIR/${BASH_SOURCE[0]}" -i

IPS=`echo "$DATA" | jq -r '.result.ipv4_cidrs+=[.result.ipv6_cidrs[]]|.result.ipv4_cidrs|join(",")'`
IPS=`echo "$IPS" | sed 's/\./\\\\./g'`
IPS=`echo "$IPS" | sed "s?\/?\\\\\/?g"`
echo "Saved changes."
sed 's/trustedIPs=.*"/trustedIPs='172.18.0.0\\\/16,"$IPS"'"/g' "$DIR/docker-compose.yml" -i
docker-compose up -d
