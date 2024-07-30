#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

if [ $EUID -ne 0 ]; then
    echo -e "${RED}请使用root用户运行${NC}"
    exit 1
fi

if [ -n $2 ]; then
    domain=$2
    echo $domain
fi

AddSite() {
    if [ -f /etc/nginx/sites-available/$domain ]; then
        echo -e "${RED}域名已存在${NC}"
        exit 1
    fi

    if [ -z $domain ]; then
        echo -e "${RED}请输入域名${NC}"
        exit 1
    fi

    mkdir -p /var/www/$domain
    chown -R www-data:www-data /var/www/$domain
    chmod -R 755 /var/www/$domain

    echo " \
server {
    listen 80;
    # listen [::]:80;
    server_name $domain;
    root /var/www/$domain;
    index index.html index.htm index.php;

    location / {
        return 301 https://\$host\$request_uri;
    }

    location ~ /.well-known {
        allow all;
    }

    access_log /var/log/nginx/$domain.access.log;
}" > /etc/nginx/sites-available/$domain

    ln -s /etc/nginx/sites-available/$domain /etc/nginx/sites-enabled/$domain

    if nginx -t; then
        nginx -s reload
    else
        rm /etc/nginx/sites-enabled/$domain
        rm /etc/nginx/sites-available/$domain
        rm -rf /var/www/$domain
        echo -e "${RED}nginx HTTP 配置错误${NC}"
        exit 1
    fi

    AddSSL
}

AddSSL() {
    "/usr/local/bin/acme.sh"/acme.sh --issue -d $domain --webroot /var/www/$domain -w /var/www/html --log
    if [ $? -eq 0 ]; then
        echo -e "${RED}证书申请失败${NC}"
        rm /etc/nginx/sites-enabled/$domain
        rm /etc/nginx/sites-available/$domain
        rm -rf /var/www/$domain
        exit 1
    else
        mkdir -p /etc/nginx/ssl/${domain}
        "/usr/local/bin/acme.sh"/acme.sh --installcert -d $domain \
            --fullchain-file /etc/nginx/ssl/${domain}/fullchain.cer \
            --keypath /etc/nginx/ssl/${domain}/${domain}.key \
            --ca-file /etc/nginx/ssl/${domain}/ca.cer \
            --reloadcmd "systemctl reload nginx"
    fi

    if [ $? -eq 0 ]; then
        echo " \
server {
    listen 443 ssl http2;
    # listen [::]:443 ssl http2;
    server_name $domain;
    root /var/www/$domain;
    index index.html index.htm index.php;

    ssl_certificate /etc/nginx/ssl/${domain}/fullchain.cer;
    ssl_certificate_key /etc/nginx/ssl/${domain}/${domain}.key;
    ssl_trusted_certificate /etc/nginx/ssl/${domain}/ca.cer;
    ssl_session_timeout 5m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'TLS13+AESGCM+AES128:TLS13+AESGCM+AES256:TLS13+CHACHA20:TLS13+AES128+CCM:TLS13+AES256+CCM:TLS13+AES128+CCM8:TLS13+AES256+CCM8:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-CCM-SHA256:ECDHE-ECDSA-AES256-CCM-SHA384:ECDHE-ECDSA-AES128-CCM8-SHA256:ECDHE-ECDSA-AES256-CCM8-SHA256:ECDHE-RSA-AES128-CCM-SHA256:ECDHE-RSA-AES256-CCM-SHA384:ECDHE-RSA-AES128-CCM8-SHA256:ECDHE-RSA-AES256-CCM8-SHA256';
    ssl_session_cache shared:SSL:10m;

    ssl_dhparam /etc/nginx/ssl/dhparam.pem;

    location ~ /.well-known {
        allow all;
    }

    access_log /var/log/nginx/$domain.access.log;
}" >> /etc/nginx/sites-available/$domain
    else
        echo -e "${RED}安装证书失败${NC}"
        echo -e "${RED}请手动安装证书${NC}"
        echo -e "acme.sh --installcert -d $domain \
            --fullchain-file /etc/nginx/ssl/${domain}/fullchain.cer \
            --keypath /etc/nginx/ssl/${domain}/${domain}.key \
            --ca-file /etc/nginx/ssl/${domain}/ca.cer \
            --reloadcmd \"systemctl reload nginx\""
        exit 1
    fi

    if nginx -t; then
        nginx -s reload
    else
        echo -e "${RED}nginx HTTPS 配置错误${NC}"
        exit 1
    fi
}

removesite() {
    if [ -f /etc/nginx/sites-available/$domain ]; then
        if [ -f /etc/nginx/sites-enabled/$domain ]; then
            rm /etc/nginx/sites-enabled/$domain
        fi
        rm /etc/nginx/sites-available/$domain
        nginx -s reload
    else
        echo -e "${RED}站点不存在${NC}"
        exit 1
    fi
}
listsite() {
    echo "已启用的站点:"
    ls /etc/nginx/sites-enabled/ | grep -v 'default' | tr ' ' '\n' | while read line; do echo -e "\e[35m$line\e[0m"; done
}

listsiteall() {
    echo "所有站点:"
    ls /etc/nginx/sites-available/ | grep -v 'default' | tr ' ' '\n' | while read line; do echo -e "\e[35m$line\e[0m"; done
}

enablesite() {
    if [ -f /etc/nginx/sites-available/$domain ]; then
        ln -s /etc/nginx/sites-available/$domain /etc/nginx/sites-enabled/$domain
        nginx -s reload
    else
        echo -e "${RED}站点不存在${NC}"
        exit 1
    fi
}

disablesite() {
    if [ -f /etc/nginx/sites-enabled/$domain ]; then
        rm /etc/nginx/sites-enabled/$domain
        nginx -s reload
    else
        echo -e "${RED}站点不存在或未启用${NC}"
        exit 1
    fi
}
case $1 in
    list)
        listsite
        ;;
    listall)
        listsiteall
        ;;
    add)
        AddSite
        ;;
    remove)
        removesite
        ;;
    enable)
        enablesite
        ;;
    disable)
        disablesite
        ;;
    *)
        echo -e "${RED}Usage: $0 {list|listall}${NC}"
        echo -e "${RED}Usage: $0 {add|remove|enable|disable} domain${NC}"
        exit 1
        ;;
esac
exit 0
