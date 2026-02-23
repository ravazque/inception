# 42 Inception — Complete Guide for CachyOS + Migration to VirtualBox/Arch

> **Login:** `ravazque` — replace `ravazque` with your login in EVERY path, command, and config file where it appears.

---

## Table of Contents

1. [What Inception is and what the subject demands](#1-what-inception-is-and-what-the-subject-demands)
2. [Docker and Docker Compose explained from scratch](#2-docker-and-docker-compose-explained-from-scratch)
3. [Installing Docker on CachyOS](#3-installing-docker-on-cachyos)
4. [Project directory structure](#4-project-directory-structure)
5. [The hostname: ravazque.42.fr](#5-the-hostname-ravazque42fr)
6. [The .env file](#6-the-env-file)
7. [MariaDB container](#7-mariadb-container)
8. [WordPress container](#8-wordpress-container)
9. [NGINX container](#9-nginx-container)
10. [The docker-compose.yml](#10-the-docker-composeyml)
11. [The Makefile](#11-the-makefile)
12. [How volumes and networking work](#12-how-volumes-and-networking-work)
13. [Building, running, and testing the project](#13-building-running-and-testing-the-project)
14. [Evaluation checklist](#14-evaluation-checklist)
15. [Common errors on Arch/CachyOS](#15-common-errors-on-archcachyos)
16. [Migration to VirtualBox with Arch + i3 on Ubuntu](#16-migration-to-virtualbox-with-arch--i3-on-ubuntu)

---

## 1. What Inception is and what the subject demands

Inception is a 42 school system administration project where you build a complete web infrastructure from scratch using Docker: an NGINX web server with TLS encryption, a WordPress site powered by php-fpm, and a MariaDB database — each running in its own container, all orchestrated by Docker Compose.

**What the subject requires in the mandatory part** (no bonus):

- **Three containers built from scratch.** It is **forbidden** to use pre-built Docker Hub images like `nginx:latest` or `wordpress:latest`. You must start from the **penultimate stable version of Debian or Alpine** and install everything yourself via your Dockerfiles.
- **NGINX container** — the single entry point to the infrastructure. Listens **only on port 443** with **TLSv1.2 or TLSv1.3**. Proxies PHP requests to the WordPress container.
- **WordPress + php-fpm container** — runs WordPress with php-fpm (no NGINX inside this container). Listens internally on port 9000.
- **MariaDB container** — the database backend. Listens internally on port 3306.
- **Two Docker volumes** — one for database files (`/var/lib/mysql`), one for the website files (`/var/www/html`). Both must be stored on the host at `/home/ravazque/data/`.
- **One Docker network** — a user-defined bridge network. Using `network: host`, `--link`, or `links:` is **forbidden**.
- **A `.env` file** in `srcs/` containing all credentials. No passwords in Dockerfiles.
- **A Makefile** at the project root that builds everything with docker-compose.
- **Domain name** `ravazque.42.fr` pointing to your local machine's IP.
- **Two WordPress users** — one administrator (whose username **must not** contain "admin") and one regular user.
- Containers must **restart automatically** on crash.
- **No infinite loops** (`tail -f`, `sleep infinity`, `while true`) in entrypoints.
- Each Docker image must be **named the same as its corresponding service**.

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

The 42 subject specifies an exact layout. Create it now:

```
inception/
├── Makefile
└── srcs/
    ├── .env
    ├── docker-compose.yml
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── conf/
        │   │   └── 50-server.cnf
        │   └── tools/
        │       └── setup.sh
        ├── nginx/
        │   ├── Dockerfile
        │   ├── conf/
        │   │   └── nginx.conf
        │   └── tools/
        │       └── setup.sh
        └── wordpress/
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

## 6. The .env file

Create `inception/srcs/.env`. This file holds every credential and configuration variable. Docker Compose reads it automatically.

```env
# Domain
DOMAIN_NAME=ravazque.42.fr

# MariaDB
MYSQL_DATABASE=wordpress
MYSQL_USER=wpuser
MYSQL_PASSWORD=wppass123
MYSQL_ROOT_PASSWORD=rootpass123

# WordPress admin (username MUST NOT contain "admin")
WP_TITLE=Inception
WP_ADMIN_USER=boss
WP_ADMIN_PASSWORD=bosspass123
WP_ADMIN_EMAIL=boss@student.42.fr

# WordPress regular user
WP_USER=editor
WP_USER_PASSWORD=editorpass123
WP_USER_EMAIL=editor@student.42.fr
```

**Important rules:**
- `WP_ADMIN_USER` **cannot** contain the word "admin" (or "Admin", "administrator", etc.).
- Use your own passwords — the ones above are just examples.
- **Never commit this file to a public git repository.**

---

## 7. MariaDB container

### `srcs/requirements/mariadb/Dockerfile`

```dockerfile
FROM debian:bullseye

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
- `FROM debian:bullseye` — starts from Debian 11 (penultimate stable version). No MariaDB installed yet.
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
- The `if` checks whether the database already exists — makes the script idempotent (safe to run multiple times).
- `'%'` in CREATE USER means the user can connect from any host.
- `exec mysqld_safe` — replaces the shell process with MariaDB, making it PID 1. This is what keeps the container alive and lets Docker manage it properly.

---

## 8. WordPress container

### `srcs/requirements/wordpress/Dockerfile`

```dockerfile
FROM debian:bullseye

RUN apt-get update && apt-get install -y \
    php7.4-fpm \
    php7.4-mysqli \
    php7.4-curl \
    php7.4-dom \
    php7.4-exif \
    php7.4-mbstring \
    php7.4-xml \
    php7.4-zip \
    php7.4-imagick \
    curl \
    mariadb-client \
    && rm -rf /var/lib/apt/lists/*

RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

COPY conf/www.conf /etc/php/7.4/fpm/pool.d/www.conf

RUN mkdir -p /run/php && chmod 755 /run/php

COPY tools/setup.sh /usr/local/bin/setup.sh
RUN chmod +x /usr/local/bin/setup.sh

EXPOSE 9000

WORKDIR /var/www/html

ENTRYPOINT ["/usr/local/bin/setup.sh"]
```

**Key points:**
- `php7.4-fpm` (FastCGI Process Manager) and all PHP extensions WordPress needs are installed.
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

exec php-fpm7.4 -F
```

**Key points:**
- The `while` loop waits until MariaDB accepts connections. The hostname `mariadb` is automatically resolved by Docker's internal DNS on our custom network. **This is not a forbidden infinite loop** — it has a clear exit condition (MariaDB becoming available) and is a standard readiness check pattern.
- `--dbhost=mariadb` — tells WordPress to connect to the MariaDB container using its Docker network hostname.
- `exec php-fpm7.4 -F` — starts PHP-FPM in foreground mode (`-F`), making it PID 1.

---

## 9. NGINX container

### `srcs/requirements/nginx/Dockerfile`

```dockerfile
FROM debian:bullseye

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
version: '3.8'

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
```

**Key points:**
- Only NGINX has `ports:` (`443:443`). MariaDB and WordPress don't expose ports to the host — they're only accessible within the Docker network.
- NGINX and WordPress mount the **same volume** `wordpress_data` at `/var/www/html`. WordPress writes files, NGINX reads them.
- `env_file: - .env` — injects all variables from `.env` as environment variables into the container.
- `restart: always` — if the container crashes, Docker restarts it automatically.
- Volumes use `driver_opts type: none, o: bind` for a direct bind mount from the host directory.
- The `inception` bridge network creates an isolated virtual network with Docker's internal DNS.

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

## 14. Evaluation checklist

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
docker exec -it mariadb mariadb -u wpuser -pwppass123 wordpress -e "SHOW TABLES;"

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
```

---

## 15. Common errors on Arch/CachyOS

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

## 16. Migration to VirtualBox with Arch + i3 on Ubuntu

The 42 Madrid subject requires the evaluation to happen on a virtual machine. You develop on CachyOS but the correction takes place on a VM with Arch + i3 running on Ubuntu via VirtualBox. This section guides you through a smooth migration with no surprises on evaluation day.

### General concept

The Inception source code (all Dockerfiles, configs, scripts, and the Makefile) is completely portable — it doesn't depend on anything specific to CachyOS. What changes between environments is: the Docker installation, the local DNS configuration (`/etc/hosts`), the host data directories, and some system-level settings.

### Step 1: Get your code into Git

First, your project must be in your 42 repository:

```bash
cd inception
git init  # if you haven't already
git add .
git commit -m "inception: mandatory part complete"
git push
```

**Do not include the `.env` file in Git.** Add it to `.gitignore`:

```bash
echo "srcs/.env" >> .gitignore
git add .gitignore
git commit -m "inception: add .env to gitignore"
```

### Step 2: Install VirtualBox on Ubuntu

On the Ubuntu machine (the evaluator's machine, or yours to prepare):

```bash
sudo apt update
sudo apt install -y virtualbox virtualbox-ext-pack
```

### Step 3: Create the VM with Arch Linux

**Recommended VM configuration:**
- **Type:** Linux, Arch Linux (64-bit)
- **RAM:** minimum 2 GB, recommended 4 GB
- **Disk:** minimum 20 GB (dynamic expansion is fine)
- **Network:** Bridged Adapter — the VM gets an IP on your local network. Alternatively use NAT with port forwarding (443 → 443).
- **CPUs:** minimum 2 vCPUs

**Installing Arch Linux in the VM:**

Download the Arch Linux ISO from [archlinux.org](https://archlinux.org/download/), mount the ISO in the VM, and follow the standard Arch installation. For Inception you don't need anything special — a base installation with:

```bash
# From the Arch live environment
pacstrap /mnt base base-devel linux linux-firmware networkmanager sudo nano git
genfstab -U /mnt >> /mnt/etc/fstab
arch-chroot /mnt
ln -sf /usr/share/zoneinfo/Europe/Madrid /etc/localtime
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "archvm" > /etc/hostname
passwd   # set root password
useradd -m -G wheel ravazque
passwd ravazque
# Edit /etc/sudoers and uncomment: %wheel ALL=(ALL) ALL
systemctl enable NetworkManager
```

### Step 4: Install i3 on the VM

i3 is a minimal tiling window manager. Install a basic graphical environment:

```bash
# As root or with sudo on the installed VM
pacman -Syu
pacman -S xorg xorg-xinit i3 i3status dmenu alacritty \
          firefox ttf-dejavu noto-fonts

# Configure xinit to launch i3
echo "exec i3" > ~/.xinitrc

# Start the graphical environment
startx
```

To start automatically on login, add to `~/.bash_profile` or `~/.zprofile`:

```bash
if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" -eq 1 ]; then
    exec startx
fi
```

### Step 5: Install Docker on the VM (Arch)

Exactly the same as on CachyOS — both are Arch-based:

```bash
sudo pacman -S docker docker-compose docker-buildx
sudo systemctl enable --now docker.service
sudo usermod -aG docker ravazque
newgrp docker

# Fix IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-docker.conf

# Fix Docker DNS
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<'EOF'
{
  "dns": ["1.1.1.1", "8.8.8.8"]
}
EOF
sudo systemctl restart docker
```

### Step 6: Clone the project in the VM

```bash
cd ~
git clone https://git.42madrid.com/ravazque/inception.git
# or your 42 repository URL
```

### Step 7: Create data directories and .env on the VM

The data directories **must exist on the VM host** before running the project:

```bash
sudo mkdir -p /home/ravazque/data/wordpress
sudo mkdir -p /home/ravazque/data/mysql
sudo chown -R ravazque:ravazque /home/ravazque/data

# If the VM disk uses Btrfs (not typical in a clean install):
# sudo chattr +C /home/ravazque/data/mysql
# sudo chattr +C /home/ravazque/data/wordpress
```

Create the `.env` manually on the VM (it's not in Git):

```bash
cat > ~/inception/srcs/.env <<'EOF'
DOMAIN_NAME=ravazque.42.fr
MYSQL_DATABASE=wordpress
MYSQL_USER=wpuser
MYSQL_PASSWORD=wppass123
MYSQL_ROOT_PASSWORD=rootpass123
WP_TITLE=Inception
WP_ADMIN_USER=boss
WP_ADMIN_PASSWORD=bosspass123
WP_ADMIN_EMAIL=boss@student.42.fr
WP_USER=editor
WP_USER_PASSWORD=editorpass123
WP_USER_EMAIL=editor@student.42.fr
EOF
```

### Step 8: Configure the hostname on the VM

```bash
echo "127.0.0.1 ravazque.42.fr" | sudo tee -a /etc/hosts
```

### Step 9: Launch the project on the VM

```bash
cd ~/inception
make
```

Verify it works exactly the same as on CachyOS:

```bash
make logs
# Wait for all three containers to be ready

# Open Firefox on the VM
firefox https://ravazque.42.fr
```

### Differences between CachyOS and plain Arch in VM

| Aspect | CachyOS | Plain Arch in VM |
|---|---|---|
| Kernel | linux-cachyos (optimized) | linux (standard) |
| `/home` filesystem | Btrfs common | ext4 by default (no CoW issue) |
| Package manager | pacman + yay | pacman |
| Graphical environment | KDE/GNOME typical | i3 minimal |
| Installation time | faster (pre-configured mirrors) | standard |
| Docker | Same packages, same config | Same packages, same config |

### Tips for evaluation day

- **Run `make re`** before the evaluator arrives to demonstrate the project builds from scratch without errors.
- **Know all files by heart** — the evaluator will ask you to explain each Dockerfile and the docker-compose.yml line by line.
- **Demo `docker kill` live** — demonstrate that the container restarts automatically with `restart: always`.
- **Show data persistence** — do `make down && make up` and show that the WordPress site content is still there.
- **Keep the checklist handy** — go through section 14 of this guide point by point before the evaluation.
- **If the evaluator asks to see passwords:** they're in `srcs/.env` which is not in Git — which is correct according to the subject.

### Quick setup script for the VM

Save this as `vm_setup.sh` in your repository (review it before running):

```bash
#!/bin/bash
# VM preparation script for the Inception evaluation
# Run as ravazque with sudo available

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

echo "=== Creating data directories ==="
sudo mkdir -p /home/${LOGIN}/data/wordpress
sudo mkdir -p /home/${LOGIN}/data/mysql
sudo chown -R ${LOGIN}:${LOGIN} /home/${LOGIN}/data

echo "=== Configuring hostname ==="
echo "127.0.0.1 ${LOGIN}.42.fr" | sudo tee -a /etc/hosts

echo "=== Setup complete! ==="
echo "Now create srcs/.env with your credentials and run 'make'"
```

---

*Guide written for the 42 Madrid Inception project. Login: ravazque.*