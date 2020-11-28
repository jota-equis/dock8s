FROM debian:10-slim

RUN set -eux; \
  export DEBIAN_FRONTEND=noninteractive \
  export MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"; \
  export SRV_VER="${SRV_VER:-5.7}"; \
  export SRV_PKG="percona-xtradb-cluster-server-${SRV_VER:-5.7}"; \
  \  
  groupadd -g 3306 mysql; \
  useradd -p --disabled-password -u 3306 -g mysql -s /bin/bash -d /srv/mysql mysql; \
  mkdir -pm0750 /srv/mysql; \
  chown -R mysql:mysql /srv/mysql; \
  \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    gettext-base \
    gnupg \
    lsof \
    nano \
    nc \
    pigz \
    procps \
    psmisc \
    rsync \
  ; \
  rm -rf /var/lib/apt/lists/*; \
  savedAptMark="$(apt-mark showmanual)";

COPY rootfs /

RUN set -eux; \
  chown -R mysql:mysql /srv/scripts /srv/mysql; \
  chmod 0750 /srv/scripts/*; \
  \
  apt-get update; \
  \
  if [ ! -z "$LANG" ]; then \
    apt-get install -y --no-install-recommends \
      locales \
    ; \
    echo -e "en_US.UTF-8 UTF-8\n$LANG UTF-8" > /etc/locale.gen; \
    export LANGUAGE="$LANG" LC_MESSAGES=POSIX LC_COLLATE=C; \
    dpkg-reconfigure locales; \
  fi \
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
  echo "$SRV_PKG $SRV_PKG/root-pass password $MYSQL_ROOT_PASSWORD" \
    | debconf-set-selections; \
  echo "$SRV_PKG $SRV_PKG/re-root-pass password $MYSQL_ROOT_PASSWORD" \
    | debconf-set-selections; \
  \
  apt-mark auto '.*' > /dev/null; \
  [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
  \
  apt-get install -y --no-install-recommends \
    percona-toolkit percona-xtrabackup-24 percona-xtradb-cluster-server-5.7 \
    percona-xtradb-cluster-client-5.7 percona-xtradb-cluster-common-5.7 \
  ; \
  \
  find /usr/ -type f -executable -exec ldd '{}' ';' \
    | awk '/=>/ { print $(NF-1) }' \
    | sort -u \
    | xargs -r dpkg-query --search \
    | cut -d: -f1 \
    | sort -u \
    | xargs -r apt-mark manual \
  ; \
  apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
  apt-get clean; \
  rm -rf /var/lib/apt/lists/* /var/tmp/* /tmp/*;

USER mysql
EXPOSE 3306 4444 4567 4568
ENTRYPOINT [ "/srv/scripts/entrypoint.sh"]
#CMD [ "/srv/scripts/run.sh" ]
