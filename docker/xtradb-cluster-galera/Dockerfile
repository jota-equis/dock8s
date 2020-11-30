FROM debian:10-slim

RUN set -eux; \
  export \
    DEBIAN_FRONTEND=noninteractive \
    MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}" \
    SRV_VER="${SRV_VER:-5.7}" \
    SRV_PKG="percona-xtradb-cluster-server-${SRV_VER:-5.7}" \
    LANG="${LANG:-es_ES.UTF-8}" \
  ; \
  \
  groupadd -g 3306 mysql; \
  useradd -p --disabled-password -m \
    -u 3306 \
    -g mysql \
    -s /bin/bash \
    -d /srv/mysql \
    mysql \
  ; \
  \
  apt-get update; \
  \
  if [ ! -z "$LANG" ]; then \
    apt-get install -y --no-install-recommends \
      locales \
    ; \
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen; \
    echo "$LANG UTF-8" >> /etc/locale.gen; \
    \
    export \
      LANGUAGE="$LANG" \
      LC_MESSAGES=POSIX \
      LC_COLLATE=C \
    ; \
    dpkg-reconfigure locales; \
    apt-mark auto '.*' > /dev/null; \
  fi; \
  \
  apt-get install -y --no-install-recommends \
    gettext-base \
    gnupg \
    lsof \
    nano \
    netcat \
    pigz \
    procps \
    psmisc \
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
  echo "$SRV_PKG $SRV_PKG/root-pass password $MYSQL_ROOT_PASSWORD" | debconf-set-selections; \
  echo "$SRV_PKG $SRV_PKG/re-root-pass password $MYSQL_ROOT_PASSWORD" | debconf-set-selections; \
  \
  apt-mark auto '.*' > /dev/null; \
  [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
  \
  apt-get install -y --no-install-recommends \
    percona-toolkit \
    percona-xtrabackup-24 \
    percona-xtradb-cluster-server-5.7 \
    percona-xtradb-cluster-client-5.7 \
    percona-xtradb-cluster-common-5.7 \
  ; \
  \
  apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
  apt-get clean; \
  rm -Rf \
    /var/lib/apt/lists/* \
    /var/cache/apt/archives/* \
    /var/tmp/* \
    /tmp/* \
    /var/lib/mysql/* \
;

COPY rootfs /

RUN set -eux; \
  chown -R 3306:3306 \
    /srv/mysql \
    > /dev/null 2>&1 \
  ; \
  chmod 0750 \
    /srv/mysql \
    /srv/mysql/etc \
    /srv/mysql/bin \
    /srv/mysql/bin/* \
    /srv/mysql/bin/docker/* \
  ; \
  find /srv/mysql/etc -type f -exec chmod 0640 {} + \
;

USER 3306

EXPOSE 3306 4444 4567 4568

ENTRYPOINT [ "/srv/mysql/bin/docker/entrypoint.sh"]
CMD [ "/srv/mysql/bin/docker/run.sh" ]
