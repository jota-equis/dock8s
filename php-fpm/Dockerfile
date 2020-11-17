FROM php:7.4-fpm

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		nano \
        procps \
        libcurl4-openssl-dev \
        libmcrypt-dev \
        libpng-dev \
        libxml2-dev \
        libonig-dev \
        libzip-dev; \
	rm -rf /var/lib/apt/lists/*

RUN set -eux; \
	[ -d /var/www/html ]; \
	chmod 0751 /var/www/html

gd

RUN docker-php-ext-enable gd iconv pdo_mysql curl bcmath mbstring json xml xmlrpc zip intl

opcache
apc
apcu
intl pdo pdo_mysql
