# docker-observium

[![build](https://github.com/mews-se/docker-observium/actions/workflows/build.yml/badge.svg)](https://github.com/mews-se/docker-observium/actions/workflows/build.yml)
![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white)
![PHP](https://img.shields.io/badge/PHP_8.4-777BB4?logo=php&logoColor=white)
![MariaDB](https://img.shields.io/badge/MariaDB-003545?logo=mariadb&logoColor=white)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)

Unofficial Docker image for [Observium Community Edition](https://www.observium.org/).
Not affiliated with or endorsed by Observium Limited.

The image is rebuilt automatically every week, so it picks up new CE releases
and base image security updates without manual work. Built for `linux/amd64`
and `linux/arm64` (Raspberry Pi 4/5 and other 64-bit ARM boards work fine).

Published as **`ghcr.io/mews-se/observium`** (primary) and mirrored to
Docker Hub as **`mewsse/observium`** — same builds, same tags.

## Quick start

```
git clone https://github.com/mews-se/docker-observium.git
cd docker-observium
cp .env.example .env   # edit at least DB_PASS and the admin credentials
docker compose up -d
```

Then open `http://<host>:8080` and log in with the admin credentials from
your `.env`.

The stack runs three containers: `web` (Apache + PHP), `poller` (cron with
the standard Observium discovery/poller/housekeeping schedule) and `db`
(MariaDB). Database schema is created and upgraded automatically on start,
and the first admin user is created if the user table is empty.

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `DB_PASS` | *(required)* | Password for the database user |
| `DB_NAME` | `observium` | Database name |
| `DB_USER` | `observium` | Database user |
| `DB_HOST` | `db` | Database host |
| `TZ` | `UTC` | Timezone for PHP, logs and the poller schedule |
| `HTTP_PORT` | `8080` | Published web port (compose only) |
| `OBSERVIUM_ADMIN_USER` | *(empty)* | Admin user created on first start |
| `OBSERVIUM_ADMIN_PASS` | *(empty)* | Password for that admin user |

## Tags

| Tag | Meaning |
|---|---|
| `latest` | Most recent weekly build of the current CE release |
| `26.1` | Latest build of that CE release |
| `26.1-YYYYMMDD` | Pinned build from a specific date |

## Adding devices

Use the web UI, or the CLI:

```
docker compose exec web su -s /bin/bash www-data -c './add_device.php <hostname> <community>'
```

## Updating

```
docker compose pull
docker compose up -d
```

Schema upgrades run automatically on container start.

## Building locally

```
docker build -t ghcr.io/mews-se/observium .
```

Compose picks up the freshly built tag on the next `docker compose up -d`.

The Dockerfile downloads the latest CE tarball at build time; pass
`--build-arg OBSERVIUM_REFRESH=$(date +%s)` to force a fresh download.

Observium overwrites that tarball in place, so a build that gets replaced is
gone upstream. [observium-ce-archive](https://github.com/mews-se/observium-ce-archive)
keeps every build it sees, which is where to look if you need to pin an older
one or observium.org is unreachable on a build day.

## License

The files in this repository are MIT licensed. Observium itself is **not**
included in the repository; the Docker image downloads the unmodified
Observium Community Edition tarball from observium.org at build time.
Observium CE is distributed under its own license (a simplified QPL) —
see [docs.observium.org](https://docs.observium.org/licenses/) for details.
Observium is a trademark of Observium Limited.
