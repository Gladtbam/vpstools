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
    dns=$2
else
    echo -e "${RED}请输入DNS API${NC}"
    exit 1
fi

if [ -n $3 ]; then
    domain=("${@:3}")
    server_name=${@:3}
    for i in ${domain[@]}; do
        if [[ $i =~ ^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$ ]]; then
            echo -e "${GREEN}域名: $i${NC}"
            acme_domain="$acme_domain -d $i"
        else
            echo -e "${RED}域名: $i 格式错误${NC}"
            exit 1
        fi
    done
else
    echo -e "${RED}请输入域名${NC}"
    exit 1
fi

AddSite() {
    if [ -f /etc/nginx/sites-available/${domain[0]} ]; then
        echo -e "${RED}域名已存在${NC}"
        exit 1
    fi

    if [ -z ${domain[0]} ]; then
        echo -e "${RED}请输入域名${NC}"
        exit 1
    fi

    mkdir -p /var/www/${domain[0]}
    chown -R www-data:www-data /var/www/${domain[0]}
    chmod -R 755 /var/www/${domain[0]}

    echo "\
server {
    listen 80;
    # listen [::]:80;
    server_name ${server_name};
    root /var/www/${domain[0]};
    index index.html index.htm index.php;

    location / {
        return 301 https://\$host\$request_uri;
    }

    location ~ /.well-known {
        allow all;
    }

    access_log /var/log/nginx/${domain[0]}.access.log;
}" > /etc/nginx/sites-available/${domain[0]}

    ln -s /etc/nginx/sites-available/${domain[0]} /etc/nginx/sites-enabled/${domain[0]}

    if nginx -t; then
        nginx -s reload
    else
        rm /etc/nginx/sites-enabled/${domain[0]}
        rm /etc/nginx/sites-available/${domain[0]}
        rm -rf /var/www/${domain[0]}
        echo -e "${RED}nginx HTTP 配置错误${NC}"
        exit 1
    fi

    AddSSL
}

AddSSL() {
    if [ $dns == "webroot" ]; then
        "/usr/local/bin/acme.sh"/acme.sh --issue $acme_domain --webroot /var/www/${domain[0]} -w /var/www/html
    else
        "/usr/local/bin/acme.sh"/acme.sh --issue --dns $dns $acme_domain
    fi

    if [ $? -eq 0 ]; then
        mkdir -p /etc/nginx/ssl/${domain[0]}
        "/usr/local/bin/acme.sh"/acme.sh --install-cert -d ${domain[0]} \
            --fullchain-file /etc/nginx/ssl/${domain[0]}/fullchain.cer \
            --key-file /etc/nginx/ssl/${domain[0]}/${domain[0]}.key \
            --ca-file /etc/nginx/ssl/${domain[0]}/ca.cer \
            --reloadcmd "systemctl reload nginx"
    else
        echo -e "${RED}证书申请失败${NC}"
        rm /etc/nginx/sites-enabled/$domain
        rm /etc/nginx/sites-available/$domain
        rm -rf /var/www/$domain
        exit 1
    fi

    if [ $? -eq 0 ]; then
        echo "\
server {
    listen 443 ssl;
    # listen [::]:443 ssl;
    http2 on;
    server_name ${server_name};
    root /var/www/${domain[0]};
    index index.html index.htm index.php;

    ssl_certificate /etc/nginx/ssl/${domain[0]}/fullchain.cer;
    ssl_certificate_key /etc/nginx/ssl/${domain[0]}/${domain[0]}.key;
    ssl_trusted_certificate /etc/nginx/ssl/${domain[0]}/ca.cer;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers on;

    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;
    
    ssl_stapling on;
    ssl_stapling_verify on;

    add_header Strict-Transport-Security 'max-age=31536000; includeSubDomains; preload' always;

    ssl_dhparam /etc/nginx/ssl/dhparam.pem;

    location ~ /.well-known {
        allow all;
    }

    access_log /var/log/nginx/${domain[0]}.access.log;
}" >> /etc/nginx/sites-available/${domain[0]}
    else
        echo -e "${RED}安装证书失败${NC}"
        echo -e "${RED}请手动安装证书${NC}"
        echo -e "acme.sh --install-cert -d ${domain[0]} \
            --fullchain-file /etc/nginx/ssl/${domain[0]}/fullchain.cer \
            --key-file /etc/nginx/ssl/${domain[0]}/${domain[0]}.key \
            --ca-file /etc/nginx/ssl/${domain[0]}/ca.cer \
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
    if [ -f /etc/nginx/sites-available/${domain[0]} ]; then
        if [ -f /etc/nginx/sites-enabled/${domain[0]} ]; then
            "/usr/local/bin/acme.sh"/acme.sh --revoke -d ${domain[0]}
            if [ $? -eq 0 ]; then
                rm /etc/nginx/sites-enabled/${domain[0]}
                rm -rf /etc/nginx/ssl/${domain[0]}
            else
                echo -e "${RED}证书删除失败${NC}"
                echo -e "${YELLOW}取消删除站点${NC}"
                exit 1
            fi
        fi
        rm /etc/nginx/sites-available/${domain[0]}
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
    if [ -f /etc/nginx/sites-available/${domain[0]} ]; then
        ln -s /etc/nginx/sites-available/${domain[0]} /etc/nginx/sites-enabled/${domain[0]}
        nginx -s reload
    else
        echo -e "${RED}站点不存在${NC}"
        exit 1
    fi
}

disablesite() {
    if [ -f /etc/nginx/sites-enabled/${domain[0]} ]; then
        rm /etc/nginx/sites-enabled/${domain[0]}
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
