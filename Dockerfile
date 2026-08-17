FROM php:8.4-apache

RUN apt-get update && apt-get install -y --no-install-recommends \
        rrdtool snmp fping whois cron mariadb-client \
        libpng-dev libjpeg-dev libfreetype6-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" gd mysqli bcmath \
    && pecl install apcu \
    && docker-php-ext-enable apcu \
    && rm -rf /var/lib/apt/lists/*

# Consumed in the RUN below so a new build-arg value forces a fresh
# tarball download instead of reusing a stale cached layer.
ARG OBSERVIUM_REFRESH=unset

RUN echo "refresh: ${OBSERVIUM_REFRESH}" \
    && curl -fsSL https://www.observium.org/observium-community-latest.tar.gz | tar zx -C /opt \
    && mkdir -p /opt/observium/rrd /opt/observium/logs

COPY apache-observium.conf /etc/apache2/sites-available/000-default.conf
RUN a2enmod rewrite \
    && echo "ServerName observium" > /etc/apache2/conf-enabled/servername.conf \
    && { echo "memory_limit = 512M"; echo "max_execution_time = 300"; } \
        > /usr/local/etc/php/conf.d/observium.ini

WORKDIR /opt/observium

COPY entrypoint.sh /usr/local/bin/observium-entrypoint
RUN chmod +x /usr/local/bin/observium-entrypoint

LABEL org.opencontainers.image.source="https://github.com/mews-se/docker-observium" \
      org.opencontainers.image.description="Unofficial Docker image for Observium Community Edition"

ENTRYPOINT ["observium-entrypoint"]
CMD ["web"]
