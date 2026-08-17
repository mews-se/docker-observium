#!/bin/bash
set -euo pipefail

ROLE="${1:-web}"

: "${DB_HOST:=db}"
: "${DB_NAME:=observium}"
: "${DB_USER:=observium}"
: "${TZ:=UTC}"

echo "date.timezone = ${TZ}" > /usr/local/etc/php/conf.d/timezone.ini
ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime && echo "${TZ}" > /etc/timezone

# single quotes and backslashes in the values must not break the generated php
phpq() { printf %s "$1" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g"; }

write_config() {
    cat > /opt/observium/config.php <<EOF
<?php
\$config['db_extension'] = 'mysqli';
\$config['db_host'] = '$(phpq "$DB_HOST")';
\$config['db_user'] = '$(phpq "$DB_USER")';
\$config['db_pass'] = '$(phpq "$DB_PASS")';
\$config['db_name'] = '$(phpq "$DB_NAME")';
\$config['fping'] = '/usr/bin/fping';
\$config['fping6'] = '/usr/bin/fping';
EOF
}

wait_for_db() {
    local tries=60
    # a real query, not mariadb-admin ping - ping reports success on access denied
    until mariadb -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e 'SELECT 1' >/dev/null 2>&1; do
        tries=$((tries - 1))
        if [ "$tries" -le 0 ]; then
            echo "ERROR: database at ${DB_HOST} not reachable or credentials rejected, giving up" >&2
            exit 1
        fi
        sleep 2
    done
}

schema_ready() {
    mariadb -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" \
        -e 'SELECT 1 FROM devices LIMIT 1' >/dev/null 2>&1
}

if [ "$ROLE" = web ] || [ "$ROLE" = poller ]; then
    : "${DB_PASS:?DB_PASS must be set}"
    [ -f /opt/observium/config.php ] || write_config
    # skip the recursive chown when ownership is already right - it costs
    # real time on an rrd volume with years of data
    for d in /opt/observium/rrd /opt/observium/logs; do
        [ "$(stat -c %U "$d")" = www-data ] || chown -R www-data:www-data "$d"
    done
fi

case "$ROLE" in
    web)
        wait_for_db
        # as www-data so first-boot files in the shared volumes get the
        # owner the poller's cron jobs expect
        setpriv --reuid www-data --regid www-data --init-groups php ./discovery.php -u

        if [ -n "${OBSERVIUM_ADMIN_USER:-}" ] && [ -n "${OBSERVIUM_ADMIN_PASS:-}" ]; then
            user_count=$(mariadb -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" \
                -N -e 'SELECT COUNT(*) FROM users' 2>/dev/null || echo 0)
            if [ "$user_count" = "0" ]; then
                setpriv --reuid www-data --regid www-data --init-groups \
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

        # cron gives jobs PATH=/usr/bin:/bin - php in this image lives in /usr/local/bin
        cat > /etc/cron.d/observium <<'EOF'
PATH=/usr/local/bin:/usr/bin:/bin
33  */6 * * *  www-data  /opt/observium/observium-wrapper discovery >> /dev/null 2>> /opt/observium/logs/cron-errors.log
*/5 *   * * *  www-data  /opt/observium/observium-wrapper discovery --host new >> /dev/null 2>> /opt/observium/logs/cron-errors.log
*/5 *   * * *  www-data  /opt/observium/observium-wrapper poller >> /dev/null 2>> /opt/observium/logs/cron-errors.log
13  5   * * *  www-data  /opt/observium/housekeeping.php -ysel >> /dev/null 2>> /opt/observium/logs/cron-errors.log
47  4   * * *  www-data  /opt/observium/housekeeping.php -yrptb >> /dev/null 2>> /opt/observium/logs/cron-errors.log
EOF
        chmod 644 /etc/cron.d/observium

        exec cron -f
        ;;
    *)
        exec "$@"
        ;;
esac
