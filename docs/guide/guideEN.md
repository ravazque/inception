# 42 Inception — Complete Guide for CachyOS + Migration to VirtualBox/Arch

> **Login:** `ravazque` — replace `ravazque` with your login in EVERY path, command, and config file where it appears.

---

## Table of Contents

1. [What Inception is and what the subject demands](#1-what-inception-is-and-what-the-subject-demands)
2. [Docker and Docker Compose explained from scratch](#2-docker-and-docker-compose-explained-from-scratch)
3. [Installing Docker on CachyOS](#3-installing-docker-on-cachyos)
4. [Project directory structure](#4-project-directory-structure)
5. [The hostname: ravazque.42.fr](#5-the-hostname-ravazque42fr)
6. [The .env file and secrets](#6-the-env-file-and-secrets)
7. [MariaDB container](#7-mariadb-container)
8. [WordPress container](#8-wordpress-container)
9. [NGINX container](#9-nginx-container)
10. [The docker-compose.yml](#10-the-docker-composeyml)
11. [The Makefile](#11-the-makefile)
12. [How volumes and networking work](#12-how-volumes-and-networking-work)
13. [Building, running, and testing the project](#13-building-running-and-testing-the-project)
14. [Required documentation files (README, USER_DOC, DEV_DOC)](#14-required-documentation-files-readme-user_doc-dev_doc)
15. [Evaluation checklist](#15-evaluation-checklist)
16. [Common errors on Arch/CachyOS](#16-common-errors-on-archcachyos)
17. [Migration to VirtualBox with Arch + i3 on Ubuntu](#17-migration-to-virtualbox-with-arch--i3-on-ubuntu)

---

## 1. What Inception is and what the subject demands

Inception is a 42 school system administration project where you build a complete web infrastructure from scratch using Docker: an NGINX web server with TLS encryption, a WordPress site powered by php-fpm, and a MariaDB database — each running in its own container, all orchestrated by Docker Compose.

**What the subject requires in the mandatory part** (no bonus):

- **Three containers built from scratch.** It is **forbidden** to use pre-built Docker Hub images like `nginx:latest` or `wordpress:latest`. You must start from the **penultimate stable version of Debian or Alpine** and install everything yourself via your Dockerfiles. As of February 2026, Debian 13 (Trixie) is the current stable, so the penultimate is **Debian 12 (Bookworm)**.
- **The `latest` tag is explicitly prohibited.** Always use a specific version tag (e.g., `debian:bookworm`).
- **NGINX container** — the single entry point to the infrastructure. Listens **only on port 443** with **TLSv1.2 or TLSv1.3**. Proxies PHP requests to the WordPress container.
- **WordPress + php-fpm container** — runs WordPress with php-fpm (no NGINX inside this container). Listens internally on port 9000.
- **MariaDB container** — the database backend. Listens internally on port 3306.
- **Two Docker named volumes** — one for database files (`/var/lib/mysql`), one for the website files (`/var/www/html`). Both must be stored on the host at `/home/ravazque/data/`. Bind mounts are **not allowed** for these volumes.
- **One Docker network** — a user-defined bridge network. Using `network: host`, `--link`, or `links:` is **forbidden**.
- **A `.env` file** in `srcs/` containing environment variables. No passwords in Dockerfiles.
- **Docker secrets** are strongly recommended for storing passwords. A `secrets/` directory at the project root holds the secret files. **Any credentials found in your Git repository outside of properly configured secrets will result in project failure.**
- **A Makefile** at the project root that builds everything with docker-compose.
- **Domain name** `ravazque.42.fr` pointing to your local machine's IP.
- **Two WordPress users** — one administrator (whose username **must not** contain "admin") and one regular user.
- Containers must **restart automatically** on crash.
- **No infinite loops** (`tail -f`, `sleep infinity`, `while true`) in entrypoints.
- Each Docker image must be **named the same as its corresponding service**.
- **A `.dockerignore`** file in each service directory.
- **Three documentation files** at the repo root: `README.md`, `USER_DOC.md`, `DEV_DOC.md`.

---

## 2. Docker and Docker Compose explained from scratch

**Docker** is a tool that lets you run applications inside isolated "containers." Think of a container as a lightweight mini-computer running inside your real machine. Each container has its own OS files, installed programs, and network — but shares your machine's kernel, so it starts in seconds (unlike a full virtual machine). A **Dockerfile** is a recipe that tells Docker how to build a container image: start from a base OS, install packages, copy config files, define what runs when the container starts.

**Docker Compose** is a companion tool to define and run **multiple containers together** using a single YAML file (`docker-compose.yml`). Instead of three separate `docker build` and `docker run` commands, you describe all three services, their networks, and volumes in one file and type `docker compose up`. Compose handles everything: building images, creating networks, starting containers in the right order.

**Key vocabulary for Inception:**

- **Image** — a snapshot/template of a container (built from a Dockerfile)
- **Container** — a running instance of an image
- **Volume** — persistent storage that survives container restarts and rebuilds
- **Network** — a virtual network connecting containers so they communicate by name
- **Port mapping** — forwarding a port from your host machine into a container (e.g., `443:443`)
- **Secret** — a file containing sensitive data (passwords) mounted read-only at `/run/secrets/` inside containers

---

## 3. Installing Docker on CachyOS

CachyOS is Arch-based and has Docker in its repositories. Run these commands in order:

```bash
# Step 1: Update your system first (critical on rolling-release distros)
sudo pacman -Syu

# Step 2: Install Docker, Docker Compose, and Buildx
sudo pacman -S docker docker-compose docker-buildx

# Step 3: Enable Docker to start at boot AND start it right now
sudo systemctl enable --now docker.service

# Step 4: Add your user to the docker group (so you don't need sudo for every docker command)
sudo usermod -aG docker ${USER}

# Step 5: Apply the group change (either log out and back in, or run:)
newgrp docker
```

Now configure two things that Arch-based systems need for Docker networking:

```bash
# Step 6: Enable IP forwarding (Docker needs this for container networking)
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-docker.conf
sudo sysctl --system

# Step 7: Fix DNS for containers
# Arch's systemd-resolved uses 127.0.0.53 which containers can't reach
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<'EOF'
{
  "dns": ["1.1.1.1", "8.8.8.8"]
}
EOF
sudo systemctl restart docker
```

**Verify everything works:**

```bash
docker --version          # Should show Docker 27.x or higher
docker compose version    # Should show Docker Compose v2.x or higher
docker run hello-world    # Should print "Hello from Docker!"
```

If `docker run hello-world` fails with "permission denied," log out completely and log back in so the group change takes effect.

---

## 4. Project directory structure

The 42 subject specifies an exact layout. **Important: the folder is called `srcs` (with an 's'), not `src`.** Create it now:

```
inception/
├── Makefile
├── secrets/
│   ├── credentials.txt
│   ├── db_password.txt
│   └── db_root_password.txt
└── srcs/
    ├── .env
    ├── docker-compose.yml
    └── requirements/
        ├── mariadb/
        │   ├── .dockerignore
        │   ├── Dockerfile
        │   ├── conf/
        │   │   └── 50-server.cnf
        │   └── tools/
        │       └── setup.sh
        ├── nginx/
        │   ├── .dockerignore
        │   ├── Dockerfile
        │   ├── conf/
        │   │   └── nginx.conf
        │   └── tools/
        │       └── setup.sh
        └── wordpress/
            ├── .dockerignore
            ├── Dockerfile
            ├── conf/
            │   └── www.conf
            └── tools/
                └── setup.sh
```

Create all directories at once:

```bash
mkdir -p inception/srcs/requirements/nginx/{conf,tools}
mkdir -p inception/srcs/requirements/wordpress/{conf,tools}
mkdir -p inception/srcs/requirements/mariadb/{conf,tools}
mkdir -p inception/secrets
```

Create the host directories where Docker volumes will store persistent data:

```bash
sudo mkdir -p /home/ravazque/data/wordpress
sudo mkdir -p /home/ravazque/data/mysql
sudo chown -R ravazque:ravazque /home/ravazque/data
```

> **Btrfs (CachyOS uses it by default):** If your `/home` uses Btrfs, disable Copy-on-Write on these directories BEFORE storing any data. Databases perform very poorly with CoW enabled:
>
> ```bash
> sudo chattr +C /home/ravazque/data/mysql
> sudo chattr +C /home/ravazque/data/wordpress
> ```

Create a `.dockerignore` file in each service directory to keep build contexts clean:

```bash
# Same content for all three — run this from inception/
for service in nginx wordpress mariadb; do
cat > srcs/requirements/$service/.dockerignore <<'EOF'
.git
.gitignore
README.md
EOF
done
```

---

## 5. The hostname: ravazque.42.fr

The subject requires the domain `ravazque.42.fr` to resolve to your local IP. Edit `/etc/hosts`:

```bash
echo "127.0.0.1 ravazque.42.fr" | sudo tee -a /etc/hosts
```

Verify with:

```bash
ping -c 1 ravazque.42.fr
# Should show replies from 127.0.0.1
```

---

## 6. The .env file and secrets

### The `.env` file

Create `inception/srcs/.env`. This file holds configuration variables and references. Docker Compose reads it automatically.

```env
# Domain
DOMAIN_NAME=ravazque.42.fr

# MariaDB
MYSQL_DATABASE=wordpress
MYSQL_USER=wpuser

# WordPress admin (username MUST NOT contain "admin")
WP_TITLE=Inception
WP_ADMIN_USER=boss
WP_ADMIN_EMAIL=boss@student.42.fr

# WordPress regular user
WP_USER=editor
WP_USER_EMAIL=editor@student.42.fr

# Paths to secrets (used by Docker Compose secrets config)
SECRETS_DIR=../secrets
```

### The secrets directory

Create the password files in `inception/secrets/`. Each file contains only the password, with no trailing newline:

```bash
cd inception

printf 'wppass123' > secrets/db_password.txt
printf 'rootpass123' > secrets/db_root_password.txt
printf 'bosspass123\neditorpass123' > secrets/credentials.txt
```

> `credentials.txt` stores WordPress passwords — line 1 is the admin password, line 2 is the regular user password.

### The `.gitignore`

Create `inception/.gitignore` to keep secrets out of Git:

```gitignore
srcs/.env
secrets/
```

**Important rules:**
- `WP_ADMIN_USER` **cannot** contain the word "admin" (or "Admin", "administrator", etc.).
- Use your own passwords — the ones above are just examples.
- **Never commit `.env` or `secrets/` to a public git repository.**

---

## 7. MariaDB container

### `srcs/requirements/mariadb/Dockerfile`

```dockerfile
FROM debian:bookworm

RUN apt-get update && apt-get install -y \
    mariadb-server \
    mariadb-client \
    && rm -rf /var/lib/apt/lists/*

COPY conf/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf

RUN mkdir -p /var/run/mysqld \
    && chown -R mysql:mysql /var/run/mysqld \
    && chmod 755 /var/run/mysqld

EXPOSE 3306

COPY tools/setup.sh /usr/local/bin/setup.sh
RUN chmod +x /usr/local/bin/setup.sh

ENTRYPOINT ["/usr/local/bin/setup.sh"]
```

**Line by line:**
- `FROM debian:bookworm` — starts from Debian 12 (penultimate stable version as of Feb 2026; Debian 13 Trixie is the current stable). No MariaDB installed yet.
- `RUN apt-get update && apt-get install -y ...` — installs MariaDB server and client. The `rm` cleans up the package cache to keep the image small.
- `COPY conf/50-server.cnf ...` — copies your custom MariaDB configuration, replacing the default.
- `RUN mkdir -p /var/run/mysqld ...` — creates the runtime directory MariaDB needs for its socket and PID file, with correct ownership.
- `EXPOSE 3306` — documents that this container uses port 3306 (informational; the Docker network handles connectivity).
- `ENTRYPOINT` — runs the setup script when the container starts.

### `srcs/requirements/mariadb/conf/50-server.cnf`

```ini
[mysqld]
datadir         = /var/lib/mysql
socket          = /var/run/mysqld/mysqld.sock
port            = 3306
bind-address    = 0.0.0.0
```

- `bind-address = 0.0.0.0` — **critical line**. The default is `127.0.0.1` (only accepts local connections). Changing to `0.0.0.0` allows connections from other containers on the Docker network (WordPress needs to connect to MariaDB).

### `srcs/requirements/mariadb/tools/setup.sh`

```bash
#!/bin/bash

# Read passwords from Docker secrets
MYSQL_PASSWORD=$(cat /run/secrets/db_password)
MYSQL_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)

# Start MariaDB temporarily to run SQL setup commands
mysqld_safe &
sleep 5

# Only run setup if the database doesn't already exist
if ! mysql -e "USE ${MYSQL_DATABASE}" 2>/dev/null; then
    mysql -e "CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;"
    mysql -e "CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    mysql -e "GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';"
    mysql -e "FLUSH PRIVILEGES;"
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
fi

# Shut down the temporary instance
mysqladmin -u root -p${MYSQL_ROOT_PASSWORD} shutdown

# Start MariaDB in the foreground (keeps the container alive)
exec mysqld_safe
```

**Key points:**
- Passwords are read from Docker secrets (`/run/secrets/`), not from environment variables. This is the recommended approach.
- The `if` checks whether the database already exists — makes the script idempotent (safe to run multiple times).
- `'%'` in CREATE USER means the user can connect from any host.
- `exec mysqld_safe` — replaces the shell process with MariaDB, making it PID 1. This is what keeps the container alive and lets Docker manage it properly.

---

## 8. WordPress container

### `srcs/requirements/wordpress/Dockerfile`

```dockerfile
FROM debian:bookworm

RUN apt-get update && apt-get install -y \
    php8.2-fpm \
    php8.2-mysqli \
    php8.2-curl \
    php8.2-dom \
    php8.2-exif \
    php8.2-mbstring \
    php8.2-xml \
    php8.2-zip \
    php8.2-imagick \
    curl \
    mariadb-client \
    && rm -rf /var/lib/apt/lists/*

RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

COPY conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf

RUN mkdir -p /run/php && chmod 755 /run/php

COPY tools/setup.sh /usr/local/bin/setup.sh
RUN chmod +x /usr/local/bin/setup.sh

EXPOSE 9000

WORKDIR /var/www/html

ENTRYPOINT ["/usr/local/bin/setup.sh"]
```

**Key points:**
- `php8.2-fpm` (FastCGI Process Manager) and all PHP extensions WordPress needs are installed. Debian 12 Bookworm ships PHP 8.2.
- `mariadb-client` is included so WP-CLI can verify the database connection.
- WP-CLI is downloaded during the build phase, not in the entrypoint, so it doesn't repeat on every start.

### `srcs/requirements/wordpress/conf/www.conf`

```ini
[www]
user = www-data
group = www-data
listen = 0.0.0.0:9000
listen.owner = www-data
listen.group = www-data

pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3

clear_env = no
```

**Key points:**
- `listen = 0.0.0.0:9000` — by default PHP-FPM listens on a Unix socket. We change it to TCP port 9000 so NGINX (in a different container) can reach it over the Docker network.
- `clear_env = no` — **critical for Inception**. By default PHP-FPM clears all environment variables for security. Setting it to `no` allows `.env` variables (database credentials, etc.) to pass through to WordPress.

### `srcs/requirements/wordpress/tools/setup.sh`

```bash
#!/bin/bash

# Read passwords from Docker secrets
MYSQL_PASSWORD=$(cat /run/secrets/db_password)
WP_ADMIN_PASSWORD=$(head -n 1 /run/secrets/credentials)
WP_USER_PASSWORD=$(sed -n '2p' /run/secrets/credentials)

# Wait for MariaDB to be fully ready
echo "Waiting for MariaDB..."
while ! mariadb -h mariadb -u${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE} -e "SELECT 1" &>/dev/null; do
    sleep 2
done
echo "MariaDB is ready!"

# Only install WordPress if wp-config.php doesn't exist yet
if [ ! -f /var/www/html/wp-config.php ]; then
    wp core download --allow-root

    wp config create \
        --dbname=${MYSQL_DATABASE} \
        --dbuser=${MYSQL_USER} \
        --dbpass=${MYSQL_PASSWORD} \
        --dbhost=mariadb \
        --allow-root

    wp core install \
        --url=https://${DOMAIN_NAME} \
        --title="${WP_TITLE}" \
        --admin_user=${WP_ADMIN_USER} \
        --admin_password=${WP_ADMIN_PASSWORD} \
        --admin_email=${WP_ADMIN_EMAIL} \
        --skip-email \
        --allow-root

    wp user create ${WP_USER} ${WP_USER_EMAIL} \
        --role=author \
        --user_pass=${WP_USER_PASSWORD} \
        --allow-root
fi

chown -R www-data:www-data /var/www/html

exec php-fpm8.2 -F
```

**Key points:**
- Passwords are read from Docker secret files. `credentials` has the admin password on line 1 and the regular user password on line 2.
- The `while` loop waits until MariaDB accepts connections. The hostname `mariadb` is automatically resolved by Docker's internal DNS on our custom network. **This is not a forbidden infinite loop** — it has a clear exit condition (MariaDB becoming available) and is a standard readiness check pattern.
- `--dbhost=mariadb` — tells WordPress to connect to the MariaDB container using its Docker network hostname.
- `exec php-fpm8.2 -F` — starts PHP-FPM in foreground mode (`-F`), making it PID 1.

---

## 9. NGINX container

### `srcs/requirements/nginx/Dockerfile`

```dockerfile
FROM debian:bookworm

RUN apt-get update && apt-get install -y \
    nginx \
    openssl \
    && rm -rf /var/lib/apt/lists/*

COPY conf/nginx.conf /etc/nginx/sites-enabled/default
COPY tools/setup.sh /usr/local/bin/setup.sh
RUN chmod +x /usr/local/bin/setup.sh

EXPOSE 443

ENTRYPOINT ["/usr/local/bin/setup.sh"]
CMD ["nginx", "-g", "daemon off;"]
```

**Key points:**
- `openssl` is installed to generate the self-signed TLS certificate.
- `CMD ["nginx", "-g", "daemon off;"]` — starts NGINX in the foreground. `daemon off;` prevents NGINX from forking into the background (required for Docker). The ENTRYPOINT script runs first, then passes execution to this CMD.

### `srcs/requirements/nginx/conf/nginx.conf`

```nginx
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ravazque.42.fr;

    ssl_certificate     /etc/ssl/certs/nginx.crt;
    ssl_certificate_key /etc/ssl/private/nginx.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    root /var/www/html;
    index index.php index.html;

    location / {
        try_files $uri $uri/ /index.php$is_args$args;
    }

    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass wordpress:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_read_timeout 300;
    }
}
```

**Key points:**
- `listen 443 ssl` — HTTPS only, port 443 only. The subject explicitly requires this.
- `ssl_protocols TLSv1.2 TLSv1.3` — the subject forbids TLS 1.0 and 1.1.
- `fastcgi_pass wordpress:9000` — forwards PHP requests to the WordPress container. Docker automatically resolves `wordpress` to the container's IP.
- `fastcgi_read_timeout 300` — prevents timeouts during the initial WordPress installation.

### `srcs/requirements/nginx/tools/setup.sh`

```bash
#!/bin/bash

# Generate a self-signed TLS certificate if one doesn't exist yet
if [ ! -f /etc/ssl/certs/nginx.crt ]; then
    echo "Generating self-signed SSL certificate..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/nginx.key \
        -out /etc/ssl/certs/nginx.crt \
        -subj "/C=ES/ST=Madrid/L=Madrid/O=42Madrid/CN=ravazque.42.fr"
    echo "SSL certificate generated!"
fi

# Execute the CMD from the Dockerfile (nginx -g 'daemon off;')
exec "$@"
```

**Key points:**
- `-x509 -nodes` — self-signed certificate with no passphrase on the private key (NGINX needs to read it without human input).
- `-newkey rsa:2048` — generates a new 2048-bit RSA key pair.
- `CN=ravazque.42.fr` — the Common Name must match the `server_name` in nginx.conf.
- `exec "$@"` — the magic that connects ENTRYPOINT and CMD. `"$@"` expands to the CMD from the Dockerfile. `exec` replaces the shell with NGINX, making it PID 1.

---

## 10. The docker-compose.yml

Create `inception/srcs/docker-compose.yml`:

```yaml
services:
  nginx:
    container_name: nginx
    build: ./requirements/nginx
    image: nginx
    ports:
      - "443:443"
    volumes:
      - wordpress_data:/var/www/html
    networks:
      - inception
    depends_on:
      - wordpress
    restart: always

  wordpress:
    container_name: wordpress
    build: ./requirements/wordpress
    image: wordpress
    volumes:
      - wordpress_data:/var/www/html
    networks:
      - inception
    depends_on:
      - mariadb
    env_file:
      - .env
    secrets:
      - db_password
      - credentials
    restart: always

  mariadb:
    container_name: mariadb
    build: ./requirements/mariadb
    image: mariadb
    volumes:
      - mariadb_data:/var/lib/mysql
    networks:
      - inception
    env_file:
      - .env
    secrets:
      - db_password
      - db_root_password
    restart: always

volumes:
  wordpress_data:
    driver: local
    driver_opts:
      type: none
      device: /home/ravazque/data/wordpress
      o: bind
  mariadb_data:
    driver: local
    driver_opts:
      type: none
      device: /home/ravazque/data/mysql
      o: bind

networks:
  inception:
    driver: bridge

secrets:
  db_password:
    file: ../secrets/db_password.txt
  db_root_password:
    file: ../secrets/db_root_password.txt
  credentials:
    file: ../secrets/credentials.txt
```

**Key points:**
- **No `version:` key** — the `version` key is deprecated in modern Docker Compose v2 and generates warnings. Omitting it is correct.
- Only NGINX has `ports:` (`443:443`). MariaDB and WordPress don't expose ports to the host — they're only accessible within the Docker network.
- NGINX and WordPress mount the **same volume** `wordpress_data` at `/var/www/html`. WordPress writes files, NGINX reads them.
- `env_file: - .env` — injects non-secret variables from `.env` as environment variables into the container.
- `secrets:` — each service lists which secrets it needs. Docker Compose mounts them read-only at `/run/secrets/<secret_name>` inside the container.
- `restart: always` — if the container crashes, Docker restarts it automatically.
- Volumes use `driver_opts type: none, o: bind` with `driver: local` — this creates Docker named volumes that store data at the specified host path. This satisfies the subject's requirement for named volumes (not raw bind mounts).
- The `inception` bridge network creates an isolated virtual network with Docker's internal DNS.
- The `secrets:` block at the bottom maps secret names to files relative to the docker-compose.yml location.

---

## 11. The Makefile

Create `inception/Makefile`:

```makefile
all: up

up:
	@mkdir -p /home/ravazque/data/wordpress
	@mkdir -p /home/ravazque/data/mysql
	@docker compose -f srcs/docker-compose.yml --env-file srcs/.env up -d --build

down:
	@docker compose -f srcs/docker-compose.yml --env-file srcs/.env down

stop:
	@docker compose -f srcs/docker-compose.yml --env-file srcs/.env stop

start:
	@docker compose -f srcs/docker-compose.yml --env-file srcs/.env start

logs:
	@docker compose -f srcs/docker-compose.yml logs -f

clean: down
	@docker system prune -af
	@docker volume rm $$(docker volume ls -q) 2>/dev/null || true

fclean: clean
	@sudo rm -rf /home/ravazque/data/wordpress/*
	@sudo rm -rf /home/ravazque/data/mysql/*

re: fclean all

.PHONY: all up down stop start logs clean fclean re
```

> **Important:** Recipe lines in Makefiles must be indented with **tabs**, not spaces. Using spaces will cause a Makefile error.

**Available commands:**
- `make` or `make up` — builds and starts everything.
- `make down` — stops and removes containers (data in volumes persists).
- `make logs` — shows real-time logs from all containers. Extremely useful for debugging.
- `make clean` — removes containers and unused Docker images.
- `make fclean` — full cleanup: also wipes the host's persistent data directories.
- `make re` — full cleanup and rebuild from scratch.

---

## 12. How volumes and networking work

**Volumes** are Docker's way of persisting data beyond a container's lifetime. When you do `docker compose down`, containers are destroyed but volumes survive. When you `docker compose up` again, new containers mount the same volumes and find all their data intact.

`wordpress_data` maps to `/home/ravazque/data/wordpress` on your host. Both NGINX and WordPress mount this volume at `/var/www/html` — that's why NGINX can serve files that WordPress creates. `mariadb_data` maps to `/home/ravazque/data/mysql` and is only mounted by MariaDB at `/var/lib/mysql`.

**The bridge network** (`inception`) creates an isolated virtual network. Docker runs an internal DNS server on this network, so containers can reach each other by name — WordPress connects to `mariadb` on port 3306, and NGINX sends PHP requests to `wordpress` on port 9000. No container needs to know another's IP address. Only NGINX's port 443 is exposed to your host machine; MariaDB and WordPress are completely hidden from the outside world.

---

## 13. Building, running, and testing the project

### First launch

From the `inception/` directory:

```bash
make
```

The first build takes several minutes while it downloads Debian packages. Watch the logs:

```bash
make logs
```

When you see `NOTICE: ready to handle connections` from PHP-FPM and `MariaDB is ready!`, everything is up.

### Verify containers are running

```bash
docker compose -f srcs/docker-compose.yml ps
```

You should see three containers with status `Up`.

### Test the website

Open your browser and go to:
```
https://ravazque.42.fr
```

Your browser will warn about a self-signed certificate — this is normal and expected. Click "Advanced" → "Accept the Risk". Your WordPress site should appear.

---

## 14. Required documentation files (README, USER_DOC, DEV_DOC)

The subject requires three markdown files at the repository root. **These are mandatory for validation.**

### `README.md`

Must include:
- **First line** (italicized): `*This project has been created as part of the 42 curriculum by ravazque.*`
- **Description** section: what the project is, its goal, brief overview.
- **Instructions** section: how to install and run the project.
- **Resources** section: references (Docker docs, tutorials, etc.) and a description of how AI was used — for which tasks and which parts.
- **Project description** section with comparisons:
  - Virtual Machines vs Docker
  - Secrets vs Environment Variables
  - Docker Network vs Host Network
  - Docker Volumes vs Bind Mounts
- Must be written in **English**.

### `USER_DOC.md`

User documentation explaining:
- What services the stack provides.
- How to start and stop the project.
- How to access the website and the WordPress admin panel.
- Where to find and manage credentials.
- How to check that services are running correctly.

### `DEV_DOC.md`

Developer documentation explaining:
- How to set up the environment from scratch (prerequisites, config files, secrets).
- How to build and launch with the Makefile and Docker Compose.
- Useful commands for managing containers and volumes.
- Where project data is stored and how it persists.

---

## 15. Evaluation checklist

Go through each point before the evaluation:

```bash
# TLS works correctly
openssl s_client -connect ravazque.42.fr:443 2>/dev/null | grep -i "protocol\|cipher"
# Should show TLSv1.2 or TLSv1.3

# The custom Docker network exists
docker network ls | grep inception

# All three containers are on the network
docker network inspect inception --format '{{range .Containers}}{{.Name}} {{end}}'
# Should list: nginx wordpress mariadb

# Volumes exist and have data
docker volume ls
ls /home/ravazque/data/wordpress/    # Should contain WordPress files
ls /home/ravazque/data/mysql/        # Should contain database files

# The database has WordPress tables
docker exec -it mariadb mariadb -u wpuser -p$(cat secrets/db_password.txt) wordpress -e "SHOW TABLES;"

# Two WordPress users exist
docker exec -it wordpress wp user list --allow-root
# Should show the admin (without "admin" in the name) and the regular user

# Container restarts after a crash
docker kill nginx
# Wait a few seconds
docker ps    # nginx should reappear with status "Up"

# Data persists after restart
make down && make up
# Visit https://ravazque.42.fr — the site should look exactly the same

# Port 80 is NOT accessible (only 443 should work)
curl -v http://ravazque.42.fr 2>&1 | head -5
# Should fail with "Connection refused"

# Secrets are mounted correctly
docker exec -it mariadb cat /run/secrets/db_password
# Should print the password

# No passwords in Dockerfiles
grep -r "password\|pass" srcs/requirements/*/Dockerfile
# Should return nothing

# No "latest" tag used
grep -r "latest" srcs/requirements/*/Dockerfile
# Should return nothing

# Required documentation files exist
ls README.md USER_DOC.md DEV_DOC.md
```

---

## 16. Common errors on Arch/CachyOS

**"Cannot connect to the Docker daemon"**
The Docker service isn't running or you're not in the docker group. Run `sudo systemctl start docker` and make sure you ran `sudo usermod -aG docker ${USER}` and logged out/in.

**DNS resolution fails inside containers (packages won't download during build)**
Arch uses `systemd-resolved` which containers can't access. Make sure you created `/etc/docker/daemon.json` with explicit DNS servers (`1.1.1.1`, `8.8.8.8`) and restarted Docker.

**MariaDB container keeps restarting**
Check logs with `docker logs mariadb`. Common causes: the `/home/ravazque/data/mysql` directory doesn't exist, or it has leftover corrupted data from a previous failed attempt (wipe it with `make fclean` and rebuild). On Btrfs, run `chattr +C` on the directory.

**WordPress shows the installation page instead of the site**
The setup script didn't run properly. Check `docker logs wordpress`. Common cause: MariaDB wasn't ready when WordPress tried to connect. Make sure the `while` loop in `setup.sh` is working and that environment variables are being passed (check `docker exec wordpress env`).

**"bind: address already in use" on port 443**
Another service on your host is using port 443. Stop it: `sudo systemctl stop nginx` or `sudo systemctl stop apache2`. Check what's using the port with `sudo ss -tlnp | grep 443`.

**Permission denied errors on volume directories**
Make sure the host directories are owned by your user: `sudo chown -R ravazque:ravazque /home/ravazque/data`. On Btrfs, also run `sudo chattr +C` on both data directories.

**nftables/iptables conflicts**
CachyOS may use nftables. If Docker networking is broken, install the compatibility layer: `sudo pacman -S iptables-nft` and restart Docker.

**NGINX returns "502 Bad Gateway"**
NGINX can't reach PHP-FPM. Check that the WordPress container is running (`docker ps`), that `www.conf` has `listen = 0.0.0.0:9000`, and that nginx.conf has `fastcgi_pass wordpress:9000`. Also check `docker logs wordpress` for PHP-FPM startup errors.

---

## 17. Migration to VirtualBox with Arch + i3 on Ubuntu

The 42 Madrid subject requires the evaluation to happen on a virtual machine. You develop on CachyOS but the correction takes place on a VM with Arch + i3 running on Ubuntu via VirtualBox. This section guides you through a smooth migration with no surprises on evaluation day.

### General concept

The Inception source code (all Dockerfiles, configs, scripts, and the Makefile) is completely portable — it doesn't depend on anything specific to CachyOS. What changes between environments is: the Docker installation, the local DNS configuration (`/etc/hosts`), the host data directories, and some system-level settings.

## 0. Project Deployment Architecture — What Goes Where

Before doing anything else, understand the two-layer environment used in the 42 evaluation:

```
┌─────────────────────────────────────────────────────────────┐
│  UBUNTU HOST MACHINE (evaluator's machine or yours)         │
│                                                             │
│  Only has: VirtualBox installed                             │
│  Does NOT have: Docker, the project, secrets, .env          │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  ARCH LINUX VIRTUAL MACHINE (inside VirtualBox)       │  │
│  │                                                       │  │
│  │  Has everything:                                      │  │
│  │  ├── Arch Linux + i3 window manager                   │  │
│  │  ├── Docker + Docker Compose                          │  │
│  │  ├── The cloned Git repository (Dockerfiles, etc.)    │  │
│  │  ├── srcs/.env (created manually, NOT from Git)       │  │
│  │  ├── secrets/ (created manually, NOT from Git)        │  │
│  │  ├── /home/ravazque/data/ (host data directories)     │  │
│  │  ├── /etc/hosts entry for ravazque.42.fr              │  │
│  │  └── Firefox or Chromium (to access the WordPress UI) │  │
│  │                                                       │  │
│  │  Docker network (bridge):                             │  │
│  │  ├── Container: nginx      (port 443 ← only one open) │  │
│  │  ├── Container: wordpress  (internal port 9000 only)  │  │
│  │  └── Container: mariadb    (internal port 3306 only)  │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### What the Ubuntu host machine needs

| Item | Required on Ubuntu host? | Notes |
|---|---|---|
| VirtualBox | ✅ Yes | Install with `sudo apt install virtualbox` |
| Docker | ❌ No | Docker runs INSIDE the VM |
| The Git repository | ❌ No | Clone runs INSIDE the VM |
| secrets/ directory | ❌ No | Created INSIDE the VM |
| srcs/.env file | ❌ No | Created INSIDE the VM |
| Firefox / browser | Optional | Only needed if testing from host (not required) |
| SSH client | Optional | Only if you prefer working via SSH instead of directly in the VM |

### What the Arch VM needs

| Item | Required in Arch VM? | How to get it |
|---|---|---|
| Docker + Compose | ✅ Yes | `sudo pacman -S docker docker-compose docker-buildx` |
| Git | ✅ Yes | `sudo pacman -S git` |
| The project repository | ✅ Yes | `git clone <your-42-repo-url>` |
| srcs/.env | ✅ Yes | Create manually (see section 6) |
| secrets/ directory | ✅ Yes | Create manually (see section 6) |
| /home/ravazque/data/ | ✅ Yes | `sudo mkdir -p /home/ravazque/data/{wordpress,mysql}` |
| /etc/hosts entry | ✅ Yes | `echo "127.0.0.1 ravazque.42.fr" | sudo tee -a /etc/hosts` |
| Firefox | ✅ Yes | `sudo pacman -S firefox` — needed to demo the site in the VM |
| i3 + Xorg | ✅ Yes | Graphical environment for the VM desktop |
| openssh (server) | ⚠️ Optional | Only if you want to SSH from Ubuntu into the VM |

### What is and is not in your Git repository

| File/Directory | In Git? | Reason |
|---|---|---|
| `Makefile` | ✅ Yes | Safe, no credentials |
| `srcs/docker-compose.yml` | ✅ Yes | Safe, references secrets but doesn't contain them |
| `srcs/.env.example` | ✅ Yes | Template only, no real values |
| `srcs/requirements/*/Dockerfile` | ✅ Yes | Safe, no passwords |
| `srcs/requirements/*/conf/*` | ✅ Yes | Safe configuration files |
| `srcs/requirements/*/tools/setup.sh` | ✅ Yes | Scripts read passwords from secrets, don't hardcode them |
| `README.md`, `USER_DOC.md`, `DEV_DOC.md` | ✅ Yes | Required by subject |
| `docs/guide/guideEN.md`, `guideES.md` | ✅ Yes | Documentation |
| `srcs/.env` | ❌ NOT in Git | Contains real values, excluded by .gitignore |
| `secrets/` | ❌ NOT in Git | Contains passwords, excluded by .gitignore |

> **Critical:** The `.gitignore` must contain both `srcs/.env` and `secrets/`. Verify this before every push:
> ```bash
> git status   # srcs/.env and secrets/ must NOT appear in the output
> ```

---

## 17. Migration to VirtualBox with Arch + i3 on Ubuntu (Complete Guide)

This section covers the complete workflow to go from developing on CachyOS to running the evaluation on a fresh Arch VM inside VirtualBox on Ubuntu. Read section 0 first to understand what goes where.

### Step 1 — Push your code to Git (on CachyOS, before anything else)

```bash
cd inception

# Verify secrets and .env are excluded
git status   # Neither srcs/.env nor secrets/ should appear

# Commit and push
git add .
git commit -m "inception: complete mandatory part"
git push
```

### Step 2 — Install VirtualBox on Ubuntu

On the Ubuntu host machine:

```bash
sudo apt update
sudo apt install -y virtualbox virtualbox-ext-pack
```

Reboot if prompted.

### Step 3 — Create and configure the Arch Linux VM

Download the Arch Linux ISO from [archlinux.org/download](https://archlinux.org/download/).

In VirtualBox, create a new VM:
- **Type:** Linux → Arch Linux (64-bit)
- **RAM:** 4 GB minimum (2 GB if disk space is tight)
- **Disk:** 25 GB dynamic VDI
- **CPUs:** 2 vCPUs minimum
- **Network adapter:**
  - **Bridged Adapter** — the VM gets its own IP on your local network. Use this if you want the VM to be reachable from the Ubuntu host (e.g., via SSH or browser on Ubuntu).
  - **NAT + Port Forwarding** — simpler, no local network IP needed. Set up port forwarding: Host 443 → Guest 443, Host 2222 → Guest 22 (for SSH if desired).

Mount the Arch ISO in the VM's optical drive and start the VM.

### Step 4 — Install Arch Linux in the VM

Inside the VM, boot from the ISO live environment:

```bash
# 1. Load keyboard layout (if needed)
loadkeys es    # for Spanish keyboard

# 2. Connect to internet (wired usually works automatically in VMs)
ping -c 1 archlinux.org

# 3. Partition the disk (simple layout for a VM)
fdisk /dev/sda
# Create: /dev/sda1 (1M, BIOS boot) and /dev/sda2 (rest, Linux filesystem)

mkfs.ext4 /dev/sda2
mount /dev/sda2 /mnt

# 4. Install base system
pacstrap /mnt base base-devel linux linux-firmware networkmanager sudo nano git openssh

# 5. Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# 6. Enter the new system
arch-chroot /mnt

# 7. Basic configuration
ln -sf /usr/share/zoneinfo/Europe/Madrid /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "archvm" > /etc/hostname

# 8. Set root password and create your user
passwd
useradd -m -G wheel ravazque
passwd ravazque

# 9. Enable sudo for wheel group
EDITOR=nano visudo   # Uncomment: %wheel ALL=(ALL:ALL) ALL

# 10. Enable networking and SSH at boot
systemctl enable NetworkManager
systemctl enable sshd    # optional, only if you want SSH access

# 11. Install bootloader
pacman -S grub
grub-install /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg

# 12. Exit and reboot
exit
umount /mnt
reboot
```

Remove the ISO from the VM's optical drive before the VM reboots.

### Step 5 — Install i3 graphical environment in the VM

Log in as `ravazque` after reboot:

```bash
sudo pacman -Syu
sudo pacman -S xorg xorg-xinit i3 i3status dmenu alacritty firefox ttf-dejavu noto-fonts

# Configure startx to launch i3
echo "exec i3" > ~/.xinitrc

# (Optional) Auto-start graphical environment on login
cat >> ~/.bash_profile <<'EOF'
if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" -eq 1 ]; then
    exec startx
fi
EOF

# Start i3 manually now
startx
```

Once inside i3: `$mod+Enter` opens a terminal (alacritty), `$mod+d` opens dmenu launcher.

### Step 6 — Install Docker inside the VM

Open a terminal in i3 (`$mod+Enter`) and run:

```bash
sudo pacman -S docker docker-compose docker-buildx
sudo systemctl enable --now docker.service
sudo usermod -aG docker ravazque

# Apply group change in current session
newgrp docker

# Fix IP forwarding (required for Docker networking on Arch)
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-docker.conf

# Fix DNS for container builds (Arch systemd-resolved issue)
sudo mkdir -p /etc/docker
echo '{"dns": ["1.1.1.1", "8.8.8.8"]}' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker

# Verify
docker run hello-world
```

### Step 7 — SSH setup (optional but recommended)

SSH lets you work from the Ubuntu host's terminal instead of the VM's desktop. This is optional — you can also work directly inside i3.

**If using NAT + Port Forwarding (Host 2222 → Guest 22):**

Inside the VM:
```bash
sudo systemctl enable --now sshd
```

From the Ubuntu host:
```bash
ssh -p 2222 ravazque@127.0.0.1
```

**If using Bridged Adapter:**

Find the VM's IP from inside the VM:
```bash
ip addr show | grep "inet " | grep -v 127
```

From the Ubuntu host:
```bash
ssh ravazque@<vm-ip-address>
```

**Copy files from Ubuntu host to VM via SSH (if needed):**

```bash
# Copy a local .env or secrets to the VM
scp -P 2222 my_local_env ravazque@127.0.0.1:/home/ravazque/inception/srcs/.env
scp -P 2222 -r my_secrets/ ravazque@127.0.0.1:/home/ravazque/inception/secrets/
```

> **Note:** You can also write the `.env` and `secrets/` files directly inside the VM without SSH. SSH is purely a convenience for those who prefer working from the Ubuntu terminal.

### Step 8 — Clone the project inside the VM

Inside the VM (in a terminal in i3 or via SSH):

```bash
cd ~
git clone https://git.42madrid.com/ravazque/inception.git
# Replace with your actual 42 Git repository URL
```

### Step 9 — Create host data directories in the VM

```bash
sudo mkdir -p /home/ravazque/data/wordpress
sudo mkdir -p /home/ravazque/data/mysql
sudo chown -R ravazque:ravazque /home/ravazque/data
```

> The VM uses a fresh ext4 filesystem by default — no Btrfs CoW issue. The `chattr +C` step from the CachyOS guide is not needed here.

### Step 10 — Create .env and secrets in the VM

These are **not in Git** and must be created manually every time you set up a new environment:

```bash
# Create .env
cat > ~/inception/srcs/.env <<'EOF'
DOMAIN_NAME=ravazque.42.fr
MYSQL_DATABASE=ravazquedb
MYSQL_USER=ravazque
WP_TITLE=RavazquePage
WP_ADMIN_USER=ravazque_wp
WP_ADMIN_EMAIL=ravazque@student.42madrid.fr
WP_USER=ravazque
WP_USER_EMAIL=your@email.com
SECRETS_DIR=../secrets
EOF

# Create secrets
mkdir -p ~/inception/secrets
printf 'your_db_password'   > ~/inception/secrets/db_password.txt
printf 'your_root_password' > ~/inception/secrets/db_root_password.txt
printf 'adminpw\nuserpw'    > ~/inception/secrets/credentials.txt
```

### Step 11 — Configure the domain in the VM

```bash
echo "127.0.0.1 ravazque.42.fr" | sudo tee -a /etc/hosts
ping -c 1 ravazque.42.fr   # Should reply from 127.0.0.1
```

> **Important:** This `/etc/hosts` entry must be in the VM, NOT on the Ubuntu host. The WordPress site runs inside the VM and is tested from inside the VM (using Firefox in i3).

### Step 12 — Launch and test the project in the VM

```bash
cd ~/inception
make
make logs   # Watch startup sequence
```

Open Firefox inside i3 and navigate to `https://ravazque.42.fr`. Accept the certificate warning. The WordPress site should appear.

### Differences: CachyOS vs Arch VM

| Aspect | CachyOS (development) | Arch Linux VM (evaluation) |
|---|---|---|
| Kernel | linux-cachyos (optimized) | linux (standard) |
| `/home` filesystem | Btrfs (CoW issue → use chattr +C) | ext4 (no CoW issue) |
| Package manager | pacman + yay | pacman only |
| Graphical environment | KDE/GNOME typically | i3 (minimal) |
| Docker packages | Same as Arch | Same as Arch |
| IP forwarding fix | Required | Required |
| DNS fix | Required | Required |
| Btrfs chattr step | Required | Not needed |
| secrets/ and .env | Created locally (not in Git) | Must be recreated in VM |
| SSH server | Optional | Optional |

### Quick VM setup script

Save this in your repository as `vm_setup.sh` and run it inside the VM after cloning:

```bash
#!/bin/bash
# Run inside the Arch VM after cloning the repository
# Usage: bash vm_setup.sh
set -e

LOGIN="ravazque"

echo "=== Installing Docker ==="
sudo pacman -S --noconfirm docker docker-compose docker-buildx
sudo systemctl enable --now docker.service
sudo usermod -aG docker ${LOGIN}

echo "=== Configuring IP forwarding ==="
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-docker.conf

echo "=== Configuring Docker DNS ==="
sudo mkdir -p /etc/docker
echo '{"dns": ["1.1.1.1", "8.8.8.8"]}' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker

echo "=== Creating host data directories ==="
sudo mkdir -p /home/${LOGIN}/data/wordpress
sudo mkdir -p /home/${LOGIN}/data/mysql
sudo chown -R ${LOGIN}:${LOGIN} /home/${LOGIN}/data

echo "=== Configuring local domain ==="
echo "127.0.0.1 ${LOGIN}.42.fr" | sudo tee -a /etc/hosts

echo ""
echo "=== Setup complete! Next steps: ==="
echo "1. Log out and back in (or run: newgrp docker)"
echo "2. Create srcs/.env with your values"
echo "3. Create secrets/ with your passwords"
echo "4. Run: make"
```

### Evaluation day checklist

Before the evaluator arrives:

```bash
# 1. Do a full rebuild to prove it works from scratch
make re

# 2. Follow logs until all containers are ready
make logs

# 3. Open Firefox in i3 and verify the site
# https://ravazque.42.fr — site should load
# https://ravazque.42.fr/wp-admin — admin panel should load

# 4. Run the evaluation checklist (section 15)
# Especially:
docker compose -f srcs/docker-compose.yml ps          # All 3 running
openssl s_client -connect ravazque.42.fr:443 2>/dev/null | grep Protocol
docker network inspect inception --format '{{range .Containers}}{{.Name}} {{end}}'
docker exec wordpress wp user list --allow-root
docker kill nginx && sleep 5 && docker ps | grep nginx  # Restart test
```
