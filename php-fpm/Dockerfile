FROM php:7.4-fpm

RUN set -eux; \
    savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		nano \
        procps \
        wget \
        libcurl4-openssl-dev \
        libmcrypt-dev \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        libwebp-dev \
        libxml2-dev \
        libxpm-dev \
        libonig-dev \
        libzip-dev \
	libzstd-dev \
    ; \
	rm -rf /var/lib/apt/lists/*; \
    \
    docker-php-ext-configure gd \
        --with-jpeg \
        --with-xpm \
        --with-webp \
        --with-freetype \
    ; \
    docker-php-ext-install -j$(nproc) \
        gd \
        intl \
        pdo \
        pdo_mysql \
    ; \
    \
    printf "\n" | pecl install apcu; \
    pecl install igbinary; \
    pecl install --onlyreqdeps --nobuild redis; \
    cd "$(pecl config-get temp_dir)/redis"; \
    phpize; \
    ./configure \
        --enable-redis-igbinary \
        --enable-redis-zstd \
    ; \
    make && make install; \
    \
    docker-php-ext-enable igbinary; \
    docker-php-ext-enable redis; \
    cd -; \
    \
    rm -rf /tmp/pear ~/.pearrc; \
    \
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
	find /usr/local -type f -executable -exec ldd '{}' ';' \
		| awk '/=>/ { print $(NF-1) }' \
		| sort -u \
		| xargs -r dpkg-query --search \
		| cut -d: -f1 \
		| sort -u \
		| xargs -r apt-mark manual \
	; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	\
    docker-php-ext-enable opcache; \
    docker-php-ext-enable apcu; \
    docker-php-ext-enable redis; \
    docker-php-ext-enable igbinary; \
    \
    php --version; \
    \
    [ -d /var/www/html ] && chmod 0751 /var/www/html \
;

RUN set -eux; \
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"; \
    EXPECTED_CHECKSUM="$(wget -q -O - https://composer.github.io/installer.sig)"; \
    ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"; \
    [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ] && { >&2 echo 'ERROR: Invalid installer checksum'; rm composer-setup.php; exit 1; }; \
    php composer-setup.php --quiet --install-dir=/usr/local/bin; \
    RESULT=$?; \
    php -r "unlink('composer-setup.php');"; \
    [ "${RESULT}" -eq "0" ] && (cd /usr/local/bin/;ln -s composer.phar composer;chmod 0751 composer*) \
;

ADD conf.d/php.ini /usr/local/etc/php/
ADD conf.d/www.conf /usr/local/etc/php-fpm.d/

#RUN echo '#!/bin/bash' > /healthcheck && \
#	echo 'env -i SCRIPT_NAME=/health SCRIPT_FILENAME=/health REQUEST_METHOD=GET cgi-fcgi -bind -connect 127.0.0.1:9000 || exit 1' >> /healthcheck && \
#	chmod +x /healthcheck

RUN set -eux; \
    cd /usr/local/etc/php; \
	[ -s php.ini ] || cp -ax php.ini-production php.ini; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
;
