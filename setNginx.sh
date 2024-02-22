#!/bin/bash

email=$1

if command -v apt &> /dev/null; then
    install_packages="apt install -y"
    apt update
    apt upgrade -y
elif command -v dnf &> /dev/null; then
    install_packages="dnf install -y"
    dnf update -y
elif command -v yum &> /dev/null; then
    install_packages="yum install -y"
    yum update -y
fi

Install_Nginx() {
    $install_packages nginx
    cat << EOF > /etc/nginx/conf.d/redirect.conf > /dev/null
server {
    listen 80;
    server_name _;
    return 301 https://\$host\$request_uri;
}
EOF
    if nginx -t; then
        systemctl restart nginx
    fi
}

Install_ACME() {
    if [ ! -f /etc/nginx/ssl ]; then
        mkdir -p /etc/nginx/ssl && cd $_
        openssl dhparam -out dhparam.pem 4096
    fi

    if [ ! -f /usr/local/bin/acme.sh ]; then
        cd /tmp
        git clone --depth 1 https://github.com/acmesh-official/acme.sh.git
        ./acme.sh/acme.sh --install --home /usr/local/bin/acme.sh --accountemail $email --cert-home /etc/nginx/ssl
        source ~/.bashrc
        rm -rf /tmp/acme.sh
        acme.sh --upgrade --auto-upgrade
        acme.sh --set-default-ca --server letsencrypt
    fi

    if [ ! -f /var/www/html/.well-known/acme-challenge ]; then
        mkdir -p /var/www/html/.well-known/acme-challenge
        chown -R www-data:www-data /var/www/html/.well-known/acme-challenge
        chmod -R 555 /var/www/html/.well-known/acme-challenge
    fi

    cat << EOF > /etc/nginx/conf.d/letsencrypt-webroot.conf > /dev/null
server {
    listen 80;
    server_name _;
    location /.well-known/acme-challenge/ {
        alias /var/www/html/.well-known/acme-challenge/;
    }
}
EOF
    if nginx -t; then
        systemctl restart nginx
    fi
}

if [ -z $email ]; then
    echo "Usage: $0 <email>"
    exit 1
else
    Install_Nginx
    Install_ACME
fi
