#!/bin/bash
set -euo pipefail

ROLE="${1:-web}"

: "${DB_HOST:=db}"
: "${DB_NAME:=observium}"
: "${DB_USER:=observium}"
: "${DB_PASS:?DB_PASS must be set}"
: "${TZ:=UTC}"

echo "date.timezone = ${TZ}" > /usr/local/etc/php/conf.d/timezone.ini
ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime && echo "${TZ}" > /etc/timezone

if [ ! -f /opt/observium/config.php ]; then
    cat > /opt/observium/config.php <<EOF
<?php
\$config['db_extension'] = 'mysqli';
\$config['db_host'] = '${DB_HOST}';
\$config['db_user'] = '${DB_USER}';
\$config['db_pass'] = '${DB_PASS}';
\$config['db_name'] = '${DB_NAME}';
\$config['fping'] = '/usr/bin/fping';
\$config['fping6'] = '/usr/bin/fping';
EOF
fi

wait_for_db() {
    local tries=60
    until mariadb-admin ping -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" --silent 2>/dev/null; do
        tries=$((tries - 1))
        if [ "$tries" -le 0 ]; then
            echo "ERROR: database at ${DB_HOST} not reachable, giving up" >&2
            exit 1
        fi
        sleep 2
    done
}

schema_ready() {
    mariadb -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" \
        -e 'SELECT 1 FROM devices LIMIT 1' >/dev/null 2>&1
}

chown -R www-data:www-data /opt/observium/rrd /opt/observium/logs

case "$ROLE" in
    web)
        wait_for_db
        php ./discovery.php -u

        if [ -n "${OBSERVIUM_ADMIN_USER:-}" ] && [ -n "${OBSERVIUM_ADMIN_PASS:-}" ]; then
            user_count=$(mariadb -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" \
                -N -e 'SELECT COUNT(*) FROM users' 2>/dev/null || echo 0)
            if [ "$user_count" = "0" ]; then
                php ./adduser.php "$OBSERVIUM_ADMIN_USER" "$OBSERVIUM_ADMIN_PASS" 10
            fi
        fi

        exec apache2-foreground
        ;;
    poller)
        wait_for_db
        until schema_ready; do
            echo "poller: waiting for database schema..."
            sleep 5
        done

        cat > /etc/cron.d/observium <<'EOF'
33  */6 * * *  www-data  /opt/observium/observium-wrapper discovery >> /dev/null 2>&1
*/5 *   * * *  www-data  /opt/observium/observium-wrapper discovery --host new >> /dev/null 2>&1
*/5 *   * * *  www-data  /opt/observium/observium-wrapper poller >> /dev/null 2>&1
13  5   * * *  www-data  /opt/observium/housekeeping.php -ysel >> /dev/null 2>&1
47  4   * * *  www-data  /opt/observium/housekeeping.php -yrptb >> /dev/null 2>&1
EOF
        chmod 644 /etc/cron.d/observium

        exec cron -f
        ;;
    *)
        exec "$@"
        ;;
esac
