# Inception

## Description

Inception is a system administration project from the 42 school curriculum. Its goal is to build a fully functional web infrastructure from scratch using Docker and Docker Compose, deployed inside a virtual machine. No pre-built Docker Hub images are allowed — every service image is hand-crafted starting from a clean Debian base.

The infrastructure exposes a WordPress site over HTTPS, served by NGINX as the sole entry point, with WordPress powered by PHP-FPM communicating with a MariaDB database backend. All three services run in isolated containers, connected through a custom Docker bridge network, with persistent data stored in named Docker volumes on the host filesystem.

```
[Browser] ──HTTPS:443──► [NGINX] ──FastCGI:9000──► [WordPress/php-fpm] ──TCP:3306──► [MariaDB]
                            │                               │
                       /var/www/html                  /var/www/html          /var/lib/mysql
                            └──────── wordpress_data ───────┘          mariadb_data
```

---

## Project Description

This project uses Docker to orchestrate a three-service web stack. Each service runs in its own dedicated container built from `debian:bookworm` (Debian 12, the penultimate stable release as of the project date). The Makefile at the root of the repository drives all build and lifecycle operations via Docker Compose.

Design choices made in this implementation:

- **Debian 12 (Bookworm)** as the base image for all containers, giving access to stable, well-tested packages including PHP 8.2 and MariaDB.
- **WP-CLI** for fully scripted, non-interactive WordPress installation — no manual browser-based setup required.
- **Docker secrets** for all passwords, mounted at `/run/secrets/` inside containers, never passed as environment variables or baked into images.
- **TCP socket (0.0.0.0:9000)** for PHP-FPM instead of the default Unix socket, required because NGINX and WordPress run in separate containers on the same Docker network.
- **Idempotent entrypoint scripts** that check whether the database or WordPress installation already exists before running setup, making the containers safe to restart without re-initialising.

### Virtual Machines vs Docker

**Virtual Machines** emulate complete hardware stacks. Each VM runs its own full OS kernel, allocates dedicated RAM and CPU, and takes minutes to boot. They offer strong isolation at the cost of significant overhead — a typical VM consumes several gigabytes of disk and hundreds of megabytes of RAM at idle.

**Docker containers** share the host kernel and start in seconds. They package only the application and its runtime dependencies, not a full OS. For a service-oriented architecture like Inception — where NGINX, WordPress, and MariaDB each have a clear, bounded responsibility — containers are the appropriate unit of isolation: lightweight, reproducible, and composable.

The tradeoff is that containers share the host kernel, so a kernel-level vulnerability could affect all containers simultaneously. VMs provide stronger security boundaries. In production, combining both (containers inside VMs) is common practice. For a learning environment like Inception, Docker's operational simplicity and speed are the right fit.

### Secrets vs Environment Variables

**Environment variables** (`.env` files) are appropriate for non-sensitive configuration: domain names, database names, WordPress titles, usernames. They are readable to any process in the container and can be accidentally logged or exposed via `docker inspect`.

**Docker secrets** are the correct mechanism for sensitive values: passwords, API keys, private keys. Docker mounts secrets as read-only files at `/run/secrets/<name>` inside the container, backed by in-memory `tmpfs` storage that is never written to disk unencrypted. Secrets are not visible in `docker inspect` output, not inherited by child processes, and are scoped only to the services that explicitly declare them in `docker-compose.yml`.

In this project, all passwords are stored in `secrets/*.txt` files, excluded from Git via `.gitignore`, and consumed at runtime by shell scripts that read `/run/secrets/<name>`.

### Docker Network vs Host Network

**Host network** (`--network=host`) removes network isolation: the container shares the host's network stack directly, binding to host ports without any virtual network overhead. This maximises performance but eliminates isolation — containers can access any port on the host, and port conflicts become a problem.

**User-defined Docker bridge networks** (as used here with the `inception` network) create an isolated virtual network with an internal DNS server. Containers on the same bridge resolve each other by service name (`wordpress`, `mariadb`, `nginx`) without needing IP addresses. Only explicitly declared ports are forwarded to the host machine. In Inception, only port 443 of the NGINX container is exposed externally; MariaDB and WordPress are completely unreachable from outside the Docker network.

The subject explicitly prohibits `network: host`, `--link`, and `links:`.

### Docker Named Volumes vs Bind Mounts

**Bind mounts** expose a host filesystem path directly into a container. They are simple but tightly coupled to the host's directory layout — moving the project to a different machine or user breaks them immediately. The subject explicitly prohibits bind mounts for the two data volumes.

**Named volumes** are managed by Docker and have a lifecycle independent of any individual container. Data in a named volume persists across `docker compose down` and `docker compose up` cycles. In this project, named volumes are configured with `driver: local` and `driver_opts` pointing to `/home/ravazque/data/wordpress` and `/home/ravazque/data/mysql` on the host — satisfying the subject's requirement that volume data be accessible at that specific host path, while using the proper named volume mechanism.

---

## Instructions

### Prerequisites

- Docker 27.x or higher with Docker Compose v2
- IP forwarding enabled on the host: `net.ipv4.ip_forward = 1`
- The host directories `/home/ravazque/data/wordpress` and `/home/ravazque/data/mysql` must exist before first launch
- `ravazque.42.fr` must resolve to `127.0.0.1` in `/etc/hosts`

### Setup

```bash
# 1. Clone the repository
git clone <repo-url> inception && cd inception

# 2. Create the environment file
cp srcs/.env.example srcs/.env
# Edit srcs/.env — fill in all placeholder values

# 3. Create the secrets directory and password files (never commit these)
mkdir -p secrets
printf 'your_db_password'      > secrets/db_password.txt
printf 'your_root_password'    > secrets/db_root_password.txt
printf 'admin_pw\nuser_pw'     > secrets/credentials.txt

# 4. Add the local domain
echo "127.0.0.1 ravazque.42.fr" | sudo tee -a /etc/hosts
```

### Build and Run

```bash
make        # Build images and start all containers (detached)
make down   # Stop and remove containers (volume data is preserved)
make stop   # Pause containers without removing them
make start  # Resume paused containers
make logs   # Stream live logs from all containers
make clean  # Remove containers and all unused Docker images
make fclean # Full wipe including persistent volume data
make re     # fclean + full rebuild from scratch
```

### Access

| Endpoint | URL |
|---|---|
| WordPress site | `https://ravazque.42.fr` |
| Admin panel | `https://ravazque.42.fr/wp-admin` |

The browser will warn about a self-signed certificate — click Advanced → Accept the risk. This is expected behaviour for a self-signed TLS certificate.

---

## Resources

### Official Documentation

- [Docker Documentation](https://docs.docker.com/) — Dockerfiles, Compose, volumes, secrets, networking
- [Docker Compose File Reference](https://docs.docker.com/compose/compose-file/) — complete `docker-compose.yml` specification
- [NGINX Documentation](https://nginx.org/en/docs/) — TLS directives, FastCGI proxy, server blocks
- [MariaDB Knowledge Base](https://mariadb.com/kb/en/) — server configuration, user management, SQL
- [PHP-FPM Configuration](https://www.php.net/manual/en/install.fpm.configuration.php) — pool settings, process management, `clear_env`
- [WP-CLI Commands](https://developer.wordpress.org/cli/commands/) — scriptable WordPress management
- [OpenSSL Manual](https://www.openssl.org/docs/manpages.html) — self-signed certificate generation

### Recommended Reading

- [Best practices for writing Dockerfiles](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [PID 1 and signal handling in containers](https://cloud.google.com/architecture/best-practices-for-building-containers#signal-handling) — why `exec` matters in entrypoint scripts
- [Docker secrets overview](https://docs.docker.com/engine/swarm/secrets/)
- [FastCGI and PHP-FPM with NGINX](https://www.php.net/manual/en/install.fpm.configuration.php)
- [TLS 1.2 vs TLS 1.3](https://www.cloudflare.com/learning/ssl/why-use-tls-1.3/)

### AI Usage Disclosure

AI language model tools were used during this project for the following tasks:

- **Documentation:** Drafting and structuring README.md, USER_DOC.md, and DEV_DOC.md, and reviewing compliance with subject requirements.
- **Configuration review:** Cross-checking NGINX server block syntax and PHP-FPM pool parameters against official documentation.
- **Script logic review:** Reviewing the idempotency logic in MariaDB and WordPress entrypoint scripts to ensure correctness across multiple container restarts.
- **Debugging:** Interpreting Docker networking errors specific to Arch Linux environments using `systemd-resolved`.

All AI-generated content was reviewed, tested against actual running containers, and fully understood before inclusion. No configuration file or shell script was used without independent verification of its behaviour.

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
| Volume storage | Named volumes → `/home/ravazque/data/` |
| Container network | User-defined bridge (`inception`) |
| Restart policy | `always` on all services |
| Secrets | Docker secrets (files, `/run/secrets/`) |

> Complete setup guides are available in `docs/guide/guideEN.md` (English) and `docs/guide/guideES.md` (Spanish), covering Docker installation, every configuration file explained line by line, the full evaluation checklist, and the migration workflow to the VirtualBox VM evaluation environment.
> 