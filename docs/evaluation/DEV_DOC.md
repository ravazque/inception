# DEV_DOC — Developer Documentation

## Inception — WordPress Infrastructure

This document describes how to set up the development environment, build the project, manage containers and volumes, and understand where data is stored.

---

## 1. Environment Setup from Scratch

### 1.1 System Requirements

**Operating system:** The project is developed and tested on Arch-based systems (CachyOS, Arch Linux). It is evaluated on a fresh Arch Linux installation inside a VirtualBox VM running on Ubuntu. Both environments require the same Docker setup.

**Required packages:**

| Package | Minimum version |
|---|---|
| Docker | 27.x |
| Docker Compose | v2.x (bundled with modern Docker) |
| Docker Buildx | any (bundled with modern Docker) |
| make | any |
| git | any |

### 1.2 Installing Docker (Arch / CachyOS)

```bash
# Install Docker and related tools
sudo pacman -S docker docker-compose docker-buildx

# Enable and start the Docker daemon
sudo systemctl enable --now docker.service

# Add your user to the docker group (avoids needing sudo for every docker command)
sudo usermod -aG docker ${USER}

# Apply the group change in the current session
newgrp docker
```

**Arch-specific: fix IP forwarding** (required for Docker container networking):

```bash
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-docker.conf
sudo sysctl --system
```

**Arch-specific: fix DNS for container builds** (Arch uses `systemd-resolved` on `127.0.0.53`, which containers cannot reach during image builds):

```bash
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<'EOF'
{
  "dns": ["1.1.1.1", "8.8.8.8"]
}
EOF
sudo systemctl restart docker
```

**Verify the installation:**

```bash
docker --version         # Docker version 27.x.x
docker compose version   # Docker Compose version v2.x.x
docker run hello-world   # Must succeed without sudo
```

### 1.3 Repository Structure

```
inception/
├── Makefile                                  ← drives all build and lifecycle operations
├── README.md                                 ← project overview (subject requirement)
├── USER_DOC.md                               ← user documentation (subject requirement)
├── DEV_DOC.md                                ← this file (subject requirement)
├── .gitignore                                ← excludes secrets/ and srcs/.env
│
├── secrets/                                  ← NOT in Git — create manually on each machine
│   ├── db_password.txt                       ← MariaDB user password
│   ├── db_root_password.txt                  ← MariaDB root password
│   └── credentials.txt                       ← WordPress passwords (line 1: admin, line 2: user)
│
├── docs/
│   └── guide/
│       ├── guideEN.md                        ← complete English setup and evaluation guide
│       └── guideES.md                        ← complete Spanish setup and evaluation guide
│
└── srcs/
    ├── .env                                  ← NOT in Git — create from .env.example
    ├── .env.example                          ← template with all required variable names
    ├── docker-compose.yml                    ← service orchestration
    └── requirements/
        ├── nginx/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/nginx.conf               ← HTTPS server block, FastCGI proxy
        │   └── tools/setup.sh                ← generates TLS cert, launches NGINX
        ├── wordpress/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/www.conf                 ← PHP-FPM pool (TCP :9000, clear_env=no)
        │   └── tools/setup.sh                ← waits for DB, installs WP, creates users
        └── mariadb/
            ├── Dockerfile
            ├── .dockerignore
            ├── conf/50-server.cnf            ← bind-address 0.0.0.0
            └── tools/setup.sh                ← creates DB, user, grants, sets root pw
```

### 1.4 Creating the Configuration Files

These files are excluded from Git and must be created on every new environment.

**`srcs/.env`** — non-sensitive configuration:

```bash
cat > srcs/.env <<'EOF'
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
```

> `WP_ADMIN_USER` must **not** contain "admin", "Admin", "administrator", or any variant.

**`secrets/` directory** — passwords only, never committed to Git:

```bash
mkdir -p secrets
printf 'your_db_password'      > secrets/db_password.txt
printf 'your_root_password'    > secrets/db_root_password.txt
printf 'adminpw\nuserpw'       > secrets/credentials.txt
# Line 1 of credentials.txt = WordPress admin password
# Line 2 of credentials.txt = WordPress regular user password
```

**Host data directories** — where Docker volumes store persistent data:

```bash
sudo mkdir -p /home/ravazque/data/wordpress
sudo mkdir -p /home/ravazque/data/mysql
sudo chown -R ravazque:ravazque /home/ravazque/data
```

> On systems using Btrfs for `/home` (default on CachyOS), disable Copy-on-Write on the data directories **before** first use — databases perform very poorly with CoW enabled:
>
> ```bash
> sudo chattr +C /home/ravazque/data/mysql
> sudo chattr +C /home/ravazque/data/wordpress
> ```

**`/etc/hosts`** — local domain resolution:

```bash
echo "127.0.0.1 ravazque.42.fr" | sudo tee -a /etc/hosts
```

---

## 2. Building and Launching the Project

### 2.1 First Launch

```bash
cd inception
make
```

The first build downloads Debian packages for each container image. Typical build time: 3–8 minutes depending on network speed. Subsequent builds use the Docker layer cache and are much faster.

Follow the startup sequence in real time:

```bash
make logs
```

Expected sequence:
1. MariaDB starts and initialises the database (`CREATE DATABASE`, `CREATE USER`, `GRANT`)
2. WordPress waits in a loop until MariaDB accepts connections
3. WordPress downloads WordPress core, creates `wp-config.php`, installs WordPress, creates both users
4. PHP-FPM starts: `NOTICE: ready to handle connections`
5. NGINX generates the TLS certificate and starts

### 2.2 Makefile Targets

| Target | Effect |
|---|---|
| `make` / `make up` | Build images and start all containers (detached) |
| `make down` | Stop and remove containers (volume data preserved) |
| `make stop` | Pause running containers without removing them |
| `make start` | Resume paused containers |
| `make logs` | Stream live logs from all containers |
| `make clean` | `down` + remove all unused Docker images and build cache |
| `make fclean` | `clean` + wipe `/home/ravazque/data/` persistent data |
| `make re` | `fclean` + full rebuild from scratch |

> Use `make re` to verify the project builds cleanly from zero. This is what an evaluator will typically do at the start of the evaluation session.

---

## 3. Container and Volume Management

### 3.1 Container Status and Inspection

```bash
# List all containers and their status
docker compose -f srcs/docker-compose.yml ps

# Inspect a specific container's configuration
docker inspect nginx
docker inspect wordpress
docker inspect mariadb

# Check resource usage (CPU, memory, network I/O)
docker stats
```

### 3.2 Accessing Container Shells

```bash
# Open a shell inside a running container
docker exec -it nginx bash
docker exec -it wordpress bash
docker exec -it mariadb bash
```

Common inspection commands once inside a container:

```bash
# Inside nginx: check TLS certificate details
openssl x509 -in /etc/ssl/certs/nginx.crt -text -noout | grep -E "Subject|Not After|Protocol"

# Inside mariadb: connect to the database
mariadb -u ravazque -p$(cat /run/secrets/db_password) ravazquedb

# Inside wordpress: list WP-CLI information
wp --info --allow-root
wp user list --allow-root
```

### 3.3 Docker Network

```bash
# Verify the inception network exists
docker network ls | grep inception

# Inspect network details and connected containers
docker network inspect inception

# Verify containers can resolve each other by hostname
docker exec wordpress ping -c 1 mariadb
docker exec wordpress ping -c 1 nginx
```

### 3.4 Volume Management

```bash
# List named volumes
docker volume ls

# Inspect a volume and its mount point
docker volume inspect inception_wordpress_data
docker volume inspect inception_mariadb_data

# Verify host data directories contain data
ls -la /home/ravazque/data/wordpress/
ls -la /home/ravazque/data/mysql/
```

### 3.5 Useful One-Liners

```bash
# Check which process is PID 1 in each container (must not be bash/tail/sh)
docker exec nginx cat /proc/1/cmdline | tr '\0' ' '
docker exec wordpress cat /proc/1/cmdline | tr '\0' ' '
docker exec mariadb cat /proc/1/cmdline | tr '\0' ' '

# Verify no password appears in any Dockerfile
grep -ri "password\|passwd\|secret" srcs/requirements/*/Dockerfile

# Verify the 'latest' tag is not used anywhere
grep -r "latest" srcs/requirements/*/Dockerfile

# Check TLS protocol version
openssl s_client -connect ravazque.42.fr:443 2>/dev/null | grep -E "Protocol|Cipher"

# Check secrets are mounted correctly
docker exec mariadb ls /run/secrets/
docker exec wordpress ls /run/secrets/

# Show all environment variables inside a container (passwords should NOT appear here)
docker exec wordpress env | grep -v PASSWORD
```

---

## 4. Data Storage and Persistence

### 4.1 How Data Persists

Docker named volumes store data independently of container lifecycle. When containers are stopped or removed with `make down`, the volume data remains on the host filesystem and is remounted when containers are started again.

| Volume name | Container mount point | Host path |
|---|---|---|
| `inception_wordpress_data` | NGINX: `/var/www/html` | `/home/ravazque/data/wordpress/` |
| `inception_wordpress_data` | WordPress: `/var/www/html` | `/home/ravazque/data/wordpress/` |
| `inception_mariadb_data` | MariaDB: `/var/lib/mysql` | `/home/ravazque/data/mysql/` |

NGINX and WordPress share the same `wordpress_data` volume mounted at `/var/www/html`. This allows NGINX to serve static WordPress files directly without proxying them through PHP-FPM.

### 4.2 Persistence Verification

```bash
# Test: stop everything, restart, verify data is intact
make down

ls /home/ravazque/data/wordpress/ | head -5   # Files should still be there
ls /home/ravazque/data/mysql/ | head -5        # Database files should still be there

make
# Wait for all containers to be ready
# Visit https://ravazque.42.fr — the site content should be identical to before
```

### 4.3 Complete Data Wipe

```bash
make fclean
```

This removes all containers, images, and the contents of both host data directories. After `fclean`, a `make` will perform a fully fresh installation: WordPress will be installed again from scratch, a new database will be created, and new TLS certificates will be generated.

---

## 5. Troubleshooting

### Container exits immediately

```bash
docker logs <container_name>
```

Check for: missing environment variable, failed secret read, port already in use, database not ready.

### WordPress stuck waiting for MariaDB

The WordPress entrypoint script loops until MariaDB is reachable. If the loop never exits:
- Verify MariaDB is actually running: `docker ps | grep mariadb`
- Check MariaDB logs for initialization errors: `docker logs mariadb`
- Verify `MYSQL_DATABASE` and `MYSQL_USER` in `srcs/.env` match what the MariaDB setup script created

### 502 Bad Gateway from NGINX

NGINX cannot reach PHP-FPM. Verify:
- WordPress container is running: `docker ps | grep wordpress`
- `www.conf` has `listen = 0.0.0.0:9000` (not a Unix socket path)
- `nginx.conf` has `fastcgi_pass wordpress:9000`

### DNS resolution fails during image build

Arch/CachyOS uses `systemd-resolved` on `127.0.0.53`. Containers cannot reach this during build. Ensure `/etc/docker/daemon.json` sets explicit DNS servers (`1.1.1.1`, `8.8.8.8`) and restart the Docker daemon.

### Port 443 already in use

Another service on the host is listening on port 443. Identify it and stop it:

```bash
sudo ss -tlnp | grep 443
sudo systemctl stop nginx    # if nginx is running on the host
```
