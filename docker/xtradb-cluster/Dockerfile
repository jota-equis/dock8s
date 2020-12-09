FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive \
    MYSQL_HOME=${MYSQL_HOME:-/srv/mysql} \
    LANG=${LANG:-en_US} \
    SRV_VER=${SRV_VER:-80}

RUN set -eux; \
  groupadd -r -g 3306 mysql; \
  useradd -Mlrp --disabled-password \
    -u 3306 \
    -g mysql \
    -s /bin/bash \
    -d $MYSQL_HOME \
    mysql \
  ; \
  [ ! -f "$MYSQL_HOME/.dock8s_has_config_files" ] && rm -Rf $MYSQL_HOME/*; \
  mkdir -pm0750 $MYSQL_HOME && chown -R 3306:3306 $MYSQL_HOME; \
  \
  apt-get update; \
    apt-get install -y --no-install-recommends \
      locales \
    ; \
    localedef -i $LANG -c -f UTF-8 -A /usr/share/locale/locale.alias $LANG.UTF-8; \
    export LANG=$LANG.utf8 \
  ; \
  apt-mark auto '.*' > /dev/null; \
  apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
  apt-get clean; \
  rm -Rf \
    /var/lib/apt/lists/* \
    /var/cache/apt/archives/* \
    /var/tmp/* \
    /tmp/* \
;

RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    gettext-base \
    gnupg \
    gosu \
    lsof \
    nano \
    netcat \
    openssl \
    pigz \
    procps \
    psmisc \
    pv \
    rsync \
  ; \
  \
  savedAptMark="$(apt-mark showmanual)"; \
  \
  apt-get install -y --no-install-recommends \
    curl \
    distro-info-data \
    lsb-release \
    wget \
  ; \
  \
  TMPD="$(mktemp)" && \
    wget --no-check-certificate -O "$TMPD" \
      'https://repo.percona.com/apt/percona-release_latest.buster_all.deb' && \
    dpkg -i "$TMPD" && \
    rm -f "$TMPD" \
  ; \
  apt-get update; \
  \
  percona-release enable-only tools release; \
  percona-release enable pxc-${SRV_VER} release; \
  percona-release enable pxb-${SRV_VER} release; \
  \
  apt-get update; \
  apt-mark auto '.*' > /dev/null; \
  [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
  \
  apt-get install -y --no-install-recommends \
    percona-toolkit \
    percona-xtrabackup-${SRV_VER} \
    percona-xtradb-cluster-common \
    percona-xtradb-cluster-client \
    percona-xtradb-cluster-server \
    percona-xtradb-cluster \
  ; \
  \
  rm -Rf \
    /usr/lib/python3/dist-packages/*; \
  apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
  apt-get clean; \
  rm -Rf \
    /var/lib/apt/lists/* \
    /var/cache/apt/archives/* \
    /var/tmp/* \
    /tmp/* \
    /var/lib/mysql* \
  ; \
  if [ -d "$MYSQL_HOME/data" ] && [ ! -f "$MYSQL_HOME/data/.dock8s_has_db_files" ]; then \
    rm -Rf "$MYSQL_HOME/data"; \
  fi \
;

COPY rootfs /

RUN set -eux; \
  mv /etc/mysql $MYSQL_HOME/default-etc; \
  chown -R 3306:3306 \
    $MYSQL_HOME \
    > /dev/null 2>&1 \
  ; \
  chmod 0751 \
    /docker-entrypoint.sh \
    $MYSQL_HOME \
    $MYSQL_HOME/etc \
    $MYSQL_HOME/bin \
    $MYSQL_HOME/bin/* \
    $MYSQL_HOME/bin/docker/* \
  ; \
  find $MYSQL_HOME/etc -type f -exec chmod 0640 {} + \
;

EXPOSE 3306 4444 4567 4568

WORKDIR $MYSQL_HOME

ENTRYPOINT [ "/docker-entrypoint.sh"]
CMD [ "mysqld" ]
