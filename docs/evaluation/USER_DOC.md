# USER_DOC — User Documentation

## Inception — WordPress Infrastructure

This document explains how to operate the Inception infrastructure as an end user or administrator.

---

## 1. Services Provided

The Inception stack runs three services, each in its own Docker container:

| Service | Role | Internal access |
|---|---|---|
| **NGINX** | HTTPS reverse proxy, sole entry point | Port 443 (exposed to host) |
| **WordPress + PHP-FPM** | Web application and PHP processor | Port 9000 (internal only) |
| **MariaDB** | Relational database backend | Port 3306 (internal only) |

Only NGINX is reachable from outside the Docker network. WordPress and MariaDB are internal services that cannot be accessed directly from the host or the internet.

All three containers are configured to restart automatically if they crash (`restart: always`).

---

## 2. Starting and Stopping the Project

All operations are performed from the root of the repository using `make`.

### Start the project

```bash
make
```

This command builds all Docker images (if not already built) and starts all three containers in the background. On the first run, it also creates the host data directories automatically.

To verify that all containers are running:

```bash
docker compose -f srcs/docker-compose.yml ps
```

All three containers (`nginx`, `wordpress`, `mariadb`) should show status `running`.

### Stop the project (preserving data)

```bash
make down
```

This stops and removes the containers. All data stored in volumes (`/home/ravazque/data/`) is preserved and will be available when the project is started again.

### Pause and resume (without removing containers)

```bash
make stop    # pause all containers
make start   # resume paused containers
```

### View live logs

```bash
make logs
```

Press `Ctrl+C` to stop following logs.

---

## 3. Accessing the Website and Administration Panel

### Prerequisites

Before accessing the site, the domain must be mapped to your local machine. Verify this is in your `/etc/hosts` file:

```bash
grep ravazque /etc/hosts
# Expected output: 127.0.0.1 ravazque.42.fr
```

If the line is missing:

```bash
echo "127.0.0.1 ravazque.42.fr" | sudo tee -a /etc/hosts
```

### Access the WordPress site

Open a browser and navigate to:

```
https://ravazque.42.fr
```

**Certificate warning:** Your browser will display a security warning because the TLS certificate is self-signed. This is expected. Click **Advanced** → **Accept the Risk and Continue** (Firefox) or **Proceed anyway** (Chrome/Chromium). The connection is still encrypted with TLS 1.2/1.3.

### Access the WordPress administration panel

```
https://ravazque.42.fr/wp-admin
```

Log in with the administrator credentials (see section 4 below).

---

## 4. Locating and Managing Credentials

### Configuration file

Non-sensitive configuration is stored in `srcs/.env`:

```
srcs/.env
```

This file contains: domain name, database name, database username, WordPress site title, admin username, admin email, regular user username, and regular user email.

**This file is not tracked by Git** — it must be created manually on each new environment from the provided template (`srcs/.env.example`).

### Secrets (passwords)

Passwords are stored as plain-text files in the `secrets/` directory at the root of the repository:

| File | Contents |
|---|---|
| `secrets/db_password.txt` | MariaDB user password (used by WordPress) |
| `secrets/db_root_password.txt` | MariaDB root password |
| `secrets/credentials.txt` | WordPress passwords — line 1: admin, line 2: regular user |

**The `secrets/` directory is not tracked by Git** — it must be created and populated manually on each new environment.

Inside running containers, secrets are accessible at `/run/secrets/<n>`. To verify:

```bash
docker exec mariadb cat /run/secrets/db_password
docker exec wordpress cat /run/secrets/credentials
```

### WordPress users

The WordPress installation contains two users:

| Role | Username | Source |
|---|---|---|
| Administrator | Defined in `srcs/.env` as `WP_ADMIN_USER` | Must not contain "admin" |
| Regular user | Defined in `srcs/.env` as `WP_USER` | Author role |

To list WordPress users:

```bash
docker exec wordpress wp user list --allow-root
```

---

## 5. Checking That Services Are Running Correctly

### Container status

```bash
docker compose -f srcs/docker-compose.yml ps
```

All three containers should show `running`. If any shows `exited` or `restarting`, check its logs.

### Container logs

```bash
# All containers
make logs

# Individual containers
docker logs nginx
docker logs wordpress
docker logs mariadb
```

### TLS verification

```bash
openssl s_client -connect ravazque.42.fr:443 2>/dev/null | grep -E "Protocol|Cipher"
```

Expected output contains `TLSv1.2` or `TLSv1.3`.

### Database connectivity

```bash
docker exec mariadb mariadb \
  -u$(grep MYSQL_USER srcs/.env | cut -d= -f2) \
  -p$(cat secrets/db_password.txt) \
  $(grep MYSQL_DATABASE srcs/.env | cut -d= -f2) \
  -e "SHOW TABLES;"
```

This should return a list of WordPress database tables (`wp_posts`, `wp_users`, etc.).

### PHP-FPM status

```bash
docker exec wordpress php-fpm8.2 -t
```

Should return `configuration file /etc/php/8.2/fpm/php-fpm.conf test is successful`.

### Restart resilience test

```bash
docker kill nginx
sleep 5
docker ps | grep nginx
```

The NGINX container should reappear automatically with `Up X seconds` status, demonstrating the `restart: always` policy.

### Data persistence test

```bash
make down
make
# Visit https://ravazque.42.fr — all content should be intact
```

---

## 6. Persistent Data Location

Volume data is stored directly on the host filesystem:

| Data | Host path |
|---|---|
| WordPress files | `/home/ravazque/data/wordpress/` |
| MariaDB database | `/home/ravazque/data/mysql/` |

These directories persist across `make down` / `make up` cycles. They are only wiped by `make fclean`.

```bash
# Verify data is present
ls /home/ravazque/data/wordpress/    # Should list WordPress PHP files
ls /home/ravazque/data/mysql/        # Should list MariaDB data files
```
