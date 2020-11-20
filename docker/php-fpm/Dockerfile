FROM php:7.4-fpm

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    LC_MESSAGES=POSIX \
    LC_COLLATE=C

#ADD conf.d/php.ini "$PHP_INI_DIR/php.ini.tpl"
#ADD conf.d/www.conf "$PHP_INI_DIR/../php-fpm.d/"

RUN set -eux; \
    [ -d /var/www/html ] && chmod 0751 /var/www/html; \
    \
    cd "$PHP_INI_DIR"; \
	[ -s php.ini.tpl ] mv -f php.ini.tpl php.ini || { cp -afx php.ini-production php.ini; rm -f php.ini.tpl; }; \
    cd -; \
    \
	apt-get update; \
	apt-get install -y --no-install-recommends \
	    nano \
        procps \
    ; \
    rm -rf /var/lib/apt/lists/*;

RUN set -eux; \
    savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
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
        localepurge \
        locales \
    ; \
	rm -rf /var/lib/apt/lists/*; \
    \
    echo -e "en\nen_US.UTF-8" > /etc/locale.gen; \
    [[ -z "${LANG}" || "${LANG}" = "en" || "${LANG}" = "en_US.UTF-8" ]] || echo "${LANG}" >> /etc/locale.gen; \
    locale-gen --purge en en_US.UTF-8 "${LANG}"; \
    echo -e "USE_DPKG\nMANDELETE\nDONTBOTHERNEWLOCALE" > /etc/locale.nopurge; \
    \
    printf "\n" | pecl install apcu; \
    \
    pecl install igbinary; \
    \
    pecl install --onlyreqdeps --nobuild redis; \
    \
    cd "$(pecl config-get temp_dir)/redis"; \
    phpize; \
    ./configure \
        --enable-redis-igbinary \
        --enable-redis-zstd \
    ; \
    make && make install; \
    cd -; \
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
# enable zstd ?
    docker-php-ext-enable igbinary; \
    docker-php-ext-enable redis; \
    docker-php-ext-enable apcu; \
    docker-php-ext-enable opcache; \
    \
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"; \
    EXPECTED_CHECKSUM="$(curl -s https://composer.github.io/installer.sig)"; \
    ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"; \
    [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ] && { >&2 echo 'ERROR: Invalid installer checksum'; exit 1; }; \
    php composer-setup.php --quiet --install-dir=/usr/local/bin; \
    RESULT=$?; \
    php -r "unlink('composer-setup.php');"; \
    [ "${RESULT}" -eq "0" ] && (cd /usr/local/bin/;ln -s composer.phar composer;chmod 0751 composer*); \
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
    localepurge; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /var/tmp/* /tmp/* ~/.pearrc; \
    \
#   echo '#!/bin/bash' > /healthcheck && \
#	echo 'env -i SCRIPT_NAME=/health SCRIPT_FILENAME=/health REQUEST_METHOD=GET cgi-fcgi -bind -connect 127.0.0.1:9000 || exit 1' >> /healthcheck && \
#	chmod +x /healthcheck
    php --version
