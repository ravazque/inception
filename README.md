# INCEPTION

## 📖 About

"inception" is a project at 42 Madrid that involves building a complete web infrastructure from scratch using Docker. Each service runs in its own container, built from a bare Debian image — no pre-built images allowed. The project introduces container orchestration, network configuration, TLS encryption, persistent storage, and service interdependency management.

The goal is to deploy a fully functional WordPress site backed by a MariaDB database and served through an NGINX reverse proxy with TLS, all orchestrated by a single `docker compose` command.

## 🎯 Objectives

- Understanding Docker image construction from scratch via Dockerfiles
- Learning container orchestration and service dependency management with Docker Compose
- Configuring TLS encryption (TLSv1.2/1.3) with self-signed certificates via OpenSSL
- Managing persistent storage through Docker volumes bound to the host filesystem
- Isolating services in a custom bridge network with internal DNS resolution
- Handling container lifecycle: automatic restart, graceful shutdown, and PID 1 processes
- Managing sensitive credentials through environment variables and `.env` files
- Connecting a reverse proxy (NGINX) to a PHP-FPM application (WordPress) over FastCGI

## 📋 Infrastructure Overview

<details>
<summary><strong>Services</strong></summary>

### Architecture

**Description:** A three-container web stack with NGINX as the sole entry point
**Access:** `https://ravazque.42.fr` (port 443, TLSv1.2/1.3 only)
**Behavior:** All traffic enters through NGINX, which proxies PHP requests to WordPress via FastCGI

```
[Browser] --HTTPS:443--> [NGINX] --FastCGI:9000--> [WordPress/php-fpm] --TCP:3306--> [MariaDB]
```

### NGINX
The gateway container. Listens exclusively on port 443 with TLS. Serves static WordPress files directly and forwards all `.php` requests to the WordPress container via FastCGI on port 9000. TLS certificate is generated at container startup using OpenSSL.

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
fastcgi_pass wordpress:9000;
```

### WordPress + php-fpm
The application container. Runs WordPress with PHP-FPM as the FastCGI process manager. WordPress is downloaded and configured at first startup using WP-CLI. Listens on TCP port 9000 (not a Unix socket, so NGINX can reach it across the Docker network). Contains two users: one administrator and one regular user.

```ini
listen = 0.0.0.0:9000
clear_env = no
```

### MariaDB
The database container. Stores all WordPress data. Database, user, and privileges are created at first startup via an initialization script. Listens on port 3306 bound to all interfaces so other containers can connect by hostname.

```ini
bind-address = 0.0.0.0
port         = 3306
```

</details>

<details>
<summary><strong>Volumes & Network</strong></summary>

### Volumes

Two named volumes with bind mounts to the host filesystem:

| Volume | Container path | Host path |
|---|---|---|
| `wordpress_data` | `/var/www/html` | `/home/ravazque/data/wordpress` |
| `mariadb_data` | `/var/lib/mysql` | `/home/ravazque/data/mysql` |

Both NGINX and WordPress mount `wordpress_data`, allowing NGINX to serve static files while WordPress manages them. Data persists across container restarts and rebuilds.

### Network

A single user-defined bridge network named `inception`. Docker's internal DNS resolves container names automatically — WordPress connects to `mariadb:3306` and NGINX connects to `wordpress:9000` without hardcoded IPs. No `--link`, `links:`, or `host` network mode is used.

```yaml
networks:
  inception:
    driver: bridge
```

### Container restart policy

All three services use `restart: always`. If a container crashes, Docker restarts it automatically without manual intervention.

</details>

<details>
<summary><strong>Environment Variables</strong></summary>

All credentials and configuration values are stored in `srcs/.env` and injected into containers via `env_file`. No passwords appear in any Dockerfile or compose file.

```env
DOMAIN_NAME=ravazque.42.fr

MYSQL_DATABASE=wordpress
MYSQL_USER=wpuser
MYSQL_PASSWORD=...
MYSQL_ROOT_PASSWORD=...

WP_TITLE=Inception
WP_ADMIN_USER=...        # Must NOT contain "admin"
WP_ADMIN_PASSWORD=...
WP_ADMIN_EMAIL=...
WP_USER=...
WP_USER_PASSWORD=...
WP_USER_EMAIL=...
```

See `srcs/.env.example` for the full variable list.

</details>

## 🚀 Installation & Structure

<details>
<summary><strong>📥 Setup & Usage</strong></summary>

<br>

```bash
# Clone the repository
git clone https://github.com/ravazque/inception.git
cd inception

# Create your environment file from the example
cp srcs/.env.example srcs/.env
# Edit srcs/.env and fill in your credentials

# Create host data directories
sudo mkdir -p /home/ravazque/data/wordpress
sudo mkdir -p /home/ravazque/data/mysql

# Add the domain to /etc/hosts
echo "127.0.0.1 ravazque.42.fr" | sudo tee -a /etc/hosts

# Build and start all containers
make

# Stop all containers
make down

# View logs in real time
make logs

# Full clean (removes containers, images, and persistent data)
make fclean

# Rebuild everything from scratch
make re
```

<br>

</details>

<details>
<summary><strong>📁 Project Structure</strong></summary>

<br>

```
inception/
├── Makefile
├── .gitignore
├── docs/
│   ├── guideES.md                          # Complete setup guide (Spanish)
│   └── guideEN.md                          # Complete setup guide (English)
└── srcs/
    ├── .env.example                        # Environment variable template
    ├── docker-compose.yml                  # Service orchestration
    └── requirements/
        ├── nginx/
        │   ├── Dockerfile                  # NGINX image built from debian:bullseye
        │   ├── conf/
        │   │   └── nginx.conf              # NGINX site config (TLS + FastCGI proxy)
        │   └── tools/
        │       └── setup.sh                # Generates TLS cert, starts NGINX
        ├── wordpress/
        │   ├── Dockerfile                  # WordPress image built from debian:bullseye
        │   ├── conf/
        │   │   └── www.conf                # PHP-FPM pool config (TCP :9000, clear_env=no)
        │   └── tools/
        │       └── setup.sh                # Downloads WP, configures DB, creates users
        └── mariadb/
            ├── Dockerfile                  # MariaDB image built from debian:bullseye
            ├── conf/
            │   └── 50-server.cnf           # MariaDB config (bind 0.0.0.0:3306)
            └── tools/
                └── setup.sh                # Creates DB, user, grants, sets root password
```

<br>

</details>

## 💡 Key Learning Outcomes

The inception project teaches infrastructure and containerization fundamentals:

- **Container Isolation**: Understanding how Docker separates processes, filesystems, and networks
- **Service Orchestration**: Coordinating multi-container applications with dependency and startup order
- **TLS Configuration**: Generating certificates and enforcing modern TLS protocols on a web server
- **FastCGI Protocol**: Connecting a reverse proxy to a PHP application across a container network
- **Persistent Storage**: Designing volume strategies that survive container rebuilds
- **Process Management**: Running services as PID 1 with `exec`, proper foreground mode, and crash recovery
- **Credential Security**: Separating configuration from code using environment files
- **Database Initialization**: Scripted, idempotent database setup that works across fresh installs and restarts

## ⚙️ Technical Specifications

- **Base image**: `debian:bullseye` (all three containers)
- **Orchestration**: Docker Compose v3.8
- **Web server**: NGINX (custom build, port 443 only)
- **TLS**: Self-signed certificate, TLSv1.2 and TLSv1.3 only
- **Application**: WordPress + php-fpm 7.4
- **Database**: MariaDB (latest available in Debian bullseye)
- **CLI tooling**: WP-CLI for scripted WordPress setup
- **Volume type**: Local bind mounts to `/home/ravazque/data/`
- **Network**: Single user-defined bridge (`inception`)
- **Restart policy**: `always` on all services
- **Credentials**: Injected via `.env`, never hardcoded

---

> [!NOTE]
> Full setup and configuration guides are available in `docs/guideES.md` (Spanish) and `docs/guideEN.md` (English), covering Docker installation, every configuration file explained line by line, the full evaluation checklist, and the migration workflow to a VirtualBox VM.
>
