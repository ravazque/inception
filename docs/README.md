*This project has been created as part of the 42 curriculum by ravazque.*

# INCEPTION

## Description

Inception is a system administration project from the 42 school curriculum. The goal is to build a complete web infrastructure from scratch using Docker and Docker Compose: an NGINX web server with TLS encryption, a WordPress site powered by PHP-FPM, and a MariaDB database — each running in its own container, all orchestrated by a single `docker compose` command.

Every container image is hand-crafted starting from a clean Debian base (`debian:bookworm`). No pre-built Docker Hub images are used. The infrastructure exposes a WordPress site over HTTPS only (port 443, TLSv1.2/1.3), with persistent data stored in Docker named volumes on the host filesystem.

```
[Browser] ──HTTPS:443──> [NGINX] ──FastCGI:9000──> [WordPress/php-fpm] ──TCP:3306──> [MariaDB]
                            |                               |
                       /var/www/html                  /var/www/html          /var/lib/mysql
                            └──────── wordpress_data ───────┘          mariadb_data
```

---

## Project Description

This project uses Docker to orchestrate a three-service web stack. Each service runs in its own dedicated container built from `debian:bookworm` (Debian 12, the penultimate stable release). The Makefile at the root of the repository drives all build and lifecycle operations via Docker Compose.

Design choices made in this implementation:

- **Debian 12 (Bookworm)** as the base image for all containers, giving access to stable, well-tested packages including PHP 8.2 and MariaDB.
- **WP-CLI** for fully scripted, non-interactive WordPress installation.
- **Docker secrets** for all passwords, mounted at `/run/secrets/` inside containers, never passed as environment variables or baked into images.
- **TCP socket (0.0.0.0:9000)** for PHP-FPM instead of the default Unix socket, required because NGINX and WordPress run in separate containers on the same Docker network.
- **Idempotent entrypoint scripts** that check whether the database or WordPress installation already exists before running setup.

### Virtual Machines vs Docker

**Virtual Machines** emulate complete hardware stacks. Each VM runs its own full OS kernel, allocates dedicated RAM and CPU, and takes minutes to boot. They offer strong isolation at the cost of significant overhead.

**Docker containers** share the host kernel and start in seconds. They package only the application and its runtime dependencies, not a full OS. For a service-oriented architecture like Inception — where NGINX, WordPress, and MariaDB each have a clear, bounded responsibility — containers are the appropriate unit of isolation: lightweight, reproducible, and composable.

The tradeoff is that containers share the host kernel, so a kernel-level vulnerability could affect all containers simultaneously. VMs provide stronger security boundaries. In production, combining both (containers inside VMs) is common practice.

### Secrets vs Environment Variables

**Environment variables** (`.env` files) are appropriate for non-sensitive configuration: domain names, database names, WordPress titles, usernames. They are readable to any process in the container and can be accidentally logged or exposed via `docker inspect`.

**Docker secrets** are the correct mechanism for sensitive values: passwords, API keys, private keys. Docker mounts secrets as read-only files at `/run/secrets/<name>` inside the container, backed by in-memory `tmpfs` storage. Secrets are not visible in `docker inspect` output and are scoped only to the services that explicitly declare them in `docker-compose.yml`.

In this project, all passwords are stored in `secrets/*.txt` files and consumed at runtime by shell scripts that read `/run/secrets/<name>`.

### Docker Network vs Host Network

**Host network** (`--network=host`) removes network isolation: the container shares the host's network stack directly. This eliminates isolation — containers can access any port on the host.

**User-defined Docker bridge networks** (as used here with the `inception` network) create an isolated virtual network with an internal DNS server. Containers on the same bridge resolve each other by service name (`wordpress`, `mariadb`, `nginx`) without needing IP addresses. Only explicitly declared ports are forwarded to the host. In Inception, only port 443 of the NGINX container is exposed externally.

### Docker Named Volumes vs Bind Mounts

**Bind mounts** expose a host filesystem path directly into a container. They are tightly coupled to the host's directory layout.

**Named volumes** are managed by Docker and have a lifecycle independent of any individual container. Data in a named volume persists across `docker compose down` and `docker compose up` cycles. In this project, named volumes are configured with `driver: local` and `driver_opts` pointing to `/home/ravazque/data/wordpress` and `/home/ravazque/data/mysql` on the host — satisfying the requirement that volume data be accessible at that specific host path, while using the proper named volume mechanism.

---

## Instructions

### Prerequisites

- Docker 27.x or higher with Docker Compose v2
- IP forwarding enabled: `net.ipv4.ip_forward = 1`
- Host directories `/home/ravazque/data/wordpress` and `/home/ravazque/data/mysql`
- `ravazque.42.fr` resolving to `127.0.0.1` in `/etc/hosts`

### Setup

```bash
# Clone the repository
git clone https://github.com/ravazque/inception.git
cd inception

# Create environment file from template (if not included)
cp srcs/.env.example srcs/.env
# Edit srcs/.env and fill in your values

# Create secrets directory and password files
mkdir -p secrets
printf 'your_db_password'      > secrets/db_password.txt
printf 'your_root_password'    > secrets/db_root_password.txt
printf 'admin_pw\nuser_pw'     > secrets/credentials.txt

# Create host data directories
sudo mkdir -p /home/ravazque/data/wordpress
sudo mkdir -p /home/ravazque/data/mysql

# Add the domain to /etc/hosts
echo "127.0.0.1 ravazque.42.fr" | sudo tee -a /etc/hosts

# Build and start all containers
make
```

### Usage

```bash
make            # Build and start all containers
make down       # Stop and remove containers (data preserved)
make stop       # Pause containers
make start      # Resume paused containers
make logs       # Stream live logs
make clean      # Remove containers and unused images
make fclean     # Full wipe including persistent data
make re         # Full rebuild from scratch
```

### Access

| Endpoint | URL |
|---|---|
| WordPress site | `https://ravazque.42.fr` |
| Admin panel | `https://ravazque.42.fr/wp-admin` |

The browser will warn about a self-signed certificate — this is expected. Click Advanced and accept the risk.

---

## Services

<details>
<summary><strong>Architecture</strong></summary>

### NGINX
The gateway container. Listens exclusively on port 443 with TLS. Serves static WordPress files directly and forwards all `.php` requests to the WordPress container via FastCGI on port 9000. TLS certificate is generated at container startup using OpenSSL.

### WordPress + PHP-FPM
The application container. Runs WordPress with PHP-FPM 8.2 as the FastCGI process manager. WordPress is downloaded and configured at first startup using WP-CLI. Listens on TCP port 9000. Contains two users: one administrator and one regular user.

### MariaDB
The database container. Stores all WordPress data. Database, user, and privileges are created at first startup via an initialization script. Listens on port 3306 bound to all interfaces so other containers can connect by hostname.

</details>

<details>
<summary><strong>Volumes & Network</strong></summary>

### Volumes

| Volume | Container path | Host path |
|---|---|---|
| `wordpress_data` | `/var/www/html` | `/home/ravazque/data/wordpress` |
| `mariadb_data` | `/var/lib/mysql` | `/home/ravazque/data/mysql` |

Both NGINX and WordPress mount `wordpress_data`. Data persists across container restarts and rebuilds.

### Network

A single user-defined bridge network named `inception`. Docker's internal DNS resolves container names automatically. No `--link`, `links:`, or `host` network mode is used.

### Restart Policy

All three services use `restart: always`.

</details>

---

## Project Structure

```
inception/
├── Makefile                                    # Build and lifecycle operations
├── README.md                                   # This file
├── USER_DOC.md                                 # User documentation
├── DEV_DOC.md                                  # Developer documentation
├── .gitignore
│
├── secrets/                                    # Docker secrets (password files)
│   ├── credentials.txt                         # WP passwords (line 1: admin, line 2: user)
│   ├── db_password.txt                         # MariaDB user password
│   └── db_root_password.txt                    # MariaDB root password
│
│
└── srcs/
    ├── .env                                    # Environment variables
    ├── .env.example                            # Template for .env
    ├── docker-compose.yml                      # Service orchestration
    └── requirements/
        ├── nginx/
        │   ├── Dockerfile                      # NGINX image (debian:bookworm)
        │   ├── .dockerignore
        │   ├── conf/nginx.conf                 # HTTPS + FastCGI proxy config
        │   └── tools/setup.sh                  # TLS cert generation + NGINX start
        ├── wordpress/
        │   ├── Dockerfile                      # WordPress image (debian:bookworm)
        │   ├── .dockerignore
        │   ├── conf/www.conf                   # PHP-FPM pool (TCP :9000)
        │   └── tools/setup.sh                  # WP download, DB config, user creation
        └── mariadb/
            ├── Dockerfile                      # MariaDB image (debian:bookworm)
            ├── .dockerignore
            ├── conf/50-server.cnf              # bind-address 0.0.0.0
            └── tools/setup.sh                  # DB + user creation, root pw
```

---

## Resources

### Official Documentation

- [Docker Documentation](https://docs.docker.com/) — Dockerfiles, Compose, volumes, secrets, networking
- [Docker Compose File Reference](https://docs.docker.com/compose/compose-file/)
- [NGINX Documentation](https://nginx.org/en/docs/) — TLS directives, FastCGI proxy
- [MariaDB Knowledge Base](https://mariadb.com/kb/en/) — server configuration, user management
- [PHP-FPM Configuration](https://www.php.net/manual/en/install.fpm.configuration.php)
- [WP-CLI Commands](https://developer.wordpress.org/cli/commands/)
- [OpenSSL Manual](https://www.openssl.org/docs/manpages.html)

### Recommended Reading

- [Best practices for writing Dockerfiles](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [PID 1 and signal handling in containers](https://cloud.google.com/architecture/best-practices-for-building-containers#signal-handling)
- [Docker secrets overview](https://docs.docker.com/engine/swarm/secrets/)
- [TLS 1.2 vs TLS 1.3](https://www.cloudflare.com/learning/ssl/why-use-tls-1.3/)

### AI Usage Disclosure

AI language model tools were used during this project for the following tasks:

- **Documentation:** Drafting and structuring README.md, USER_DOC.md, and DEV_DOC.md, and reviewing compliance with subject requirements.
- **Configuration review:** Cross-checking NGINX server block syntax and PHP-FPM pool parameters against official documentation.
- **Script logic review:** Reviewing the idempotency logic in MariaDB and WordPress entrypoint scripts to ensure correctness across multiple container restarts.
- **Debugging:** Interpreting Docker networking errors specific to Arch Linux environments using `systemd-resolved`.
- **Test scripts:** Generating automated verification scripts for pre-deployment validation.

All AI-generated content was reviewed, tested against actual running containers, and fully understood before inclusion.

---

## Technical Specifications

| Component | Detail |
|---|---|
| Base image | `debian:bookworm` (Debian 12) |
| Orchestration | Docker Compose v2 |
| Web server | NGINX — port 443 only |
| TLS | Self-signed certificate, TLSv1.2 + TLSv1.3 |
| Application server | WordPress 6.x + PHP-FPM 8.2 |
| Database | MariaDB (bookworm repository) |
| CLI tooling | WP-CLI |
| Volume storage | Named volumes with local driver → `/home/ravazque/data/` |
| Container network | User-defined bridge (`inception`) |
| Restart policy | `always` on all services |
| Secrets | Docker secrets (files at `/run/secrets/`) |

