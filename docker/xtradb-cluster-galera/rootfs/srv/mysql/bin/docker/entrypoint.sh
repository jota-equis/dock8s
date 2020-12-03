#!/usr/bin/env bash

. /srv/mysql/bin/docker/get-env.sh
. /srv/mysql/bin/docker/functions.sh

init_config;

echo ""
exec "$@"
