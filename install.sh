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

if grep -q -E 'ID=(debian|ubuntu)' /etc/os-release; then
    install_packages="apt install -y"
    update_packages="apt update -y"
    apt update
    apt upgrade -y
elif grep -q -E 'ID=(rhel|fedora)' /etc/os-release; then
    install_packages="yum install -y"
    update_packages="yum update -y"
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
        nginx -s reload
    fi
}

Install_ACME() {
    read -p "请输入邮箱地址：" email
    if [ ! -f /etc/nginx/ssl ]; then
        mkdir -p /etc/nginx/ssl && cd $_
        time openssl dhparam -rand /dev/random -out dhparam.pem 4096
    fi

    if [ ! -f /usr/local/bin/acme.sh ]; then
        cd /tmp
        git clone --depth 1 https://github.com/acmesh-official/acme.sh.git
        ./acme.sh/acme.sh --install --home /usr/local/acme.sh --accountemail $email
        source ~/.bashrc
        rm -rf /tmp/acme.sh
        acme.sh --upgrade --auto-upgrade
        acme.sh --set-default-ca --server letsencrypt
    fi

    # if [ ! -f /var/www/html/.well-known/acme-challenge ]; then
    #     mkdir -p /var/www/html/.well-known/acme-challenge
    #     chown -R www-data:www-data /var/www/html/.well-known/acme-challenge
    #     chmod -R 555 /var/www/html/.well-known/acme-challenge
    # fi

#     cat << EOF > /etc/nginx/conf.d/letsencrypt-webroot.conf > /dev/null
# server {
#     listen 80;
#     server_name _;
#     location /.well-known/acme-challenge/ {
#         alias /var/www/html/.well-known/acme-challenge/;
#     }
# }
# EOF
#     if nginx -t; then
#         nginx -s reload
#     fi
# }

Install_MySQL() {
    echo "${YELLOW} 下载地址：https://dev.mysql.com/downloads/ ${NC}"
    echo "${YELLOW}请提供MySQL APT Repository的包下载链接${NC}："
    read mysql_repo
    wget $mysql_repo
    $install_packages ./$mysql_repo && rm -f $mysql_repo
    $update_packages

    echo "${BULE}安装MySQL${NC}"
    $install_packages mysql-server
}

Install_Nginx
Install_ACME
