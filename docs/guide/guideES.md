# 42 Inception — Guía Completa para CachyOS + Migración a VirtualBox/Arch

> **Login:** `ravazque` — reemplaza `ravazque` por tu login en CADA ruta, comando y archivo de configuración donde aparezca.

---

## Tabla de contenidos

- [42 Inception — Guía Completa para CachyOS + Migración a VirtualBox/Arch](#42-inception--guía-completa-para-cachyos--migración-a-virtualboxarch)
  - [Tabla de contenidos](#tabla-de-contenidos)
  - [1. Qué es Inception y qué pide el subject](#1-qué-es-inception-y-qué-pide-el-subject)
  - [2. Docker y Docker Compose explicados desde cero](#2-docker-y-docker-compose-explicados-desde-cero)
  - [3. Instalar Docker en CachyOS](#3-instalar-docker-en-cachyos)
  - [4. Estructura de directorios del proyecto](#4-estructura-de-directorios-del-proyecto)
  - [5. El hostname: ravazque.42.fr](#5-el-hostname-ravazque42fr)
  - [6. El archivo .env y los secrets](#6-el-archivo-env-y-los-secrets)
    - [El fichero `.env`](#el-fichero-env)
    - [El directorio secrets](#el-directorio-secrets)
    - [El `.gitignore`](#el-gitignore)
  - [7. Contenedor MariaDB](#7-contenedor-mariadb)
    - [`srcs/requirements/mariadb/Dockerfile`](#srcsrequirementsmariadbdockerfile)
    - [`srcs/requirements/mariadb/conf/50-server.cnf`](#srcsrequirementsmariadbconf50-servercnf)
    - [`srcs/requirements/mariadb/tools/setup.sh`](#srcsrequirementsmariadbtoolssetupsh)
  - [8. Contenedor WordPress](#8-contenedor-wordpress)
    - [`srcs/requirements/wordpress/Dockerfile`](#srcsrequirementswordpressdockerfile)
    - [`srcs/requirements/wordpress/conf/www.conf`](#srcsrequirementswordpressconfwwwconf)
    - [`srcs/requirements/wordpress/tools/setup.sh`](#srcsrequirementswordpresstoolssetupsh)
  - [9. Contenedor NGINX](#9-contenedor-nginx)
    - [`srcs/requirements/nginx/Dockerfile`](#srcsrequirementsnginxdockerfile)
    - [`srcs/requirements/nginx/conf/nginx.conf`](#srcsrequirementsnginxconfnginxconf)
    - [`srcs/requirements/nginx/tools/setup.sh`](#srcsrequirementsnginxtoolssetupsh)
  - [10. El docker-compose.yml](#10-el-docker-composeyml)
  - [11. El Makefile](#11-el-makefile)
  - [12. Cómo funcionan los volúmenes y la red](#12-cómo-funcionan-los-volúmenes-y-la-red)
  - [13. Arrancar, probar y validar el proyecto](#13-arrancar-probar-y-validar-el-proyecto)
    - [Primer arranque](#primer-arranque)
    - [Verificar los contenedores](#verificar-los-contenedores)
    - [Probar el sitio web](#probar-el-sitio-web)
  - [14. Archivos de documentación obligatorios (README, USER\_DOC, DEV\_DOC)](#14-archivos-de-documentación-obligatorios-readme-user_doc-dev_doc)
    - [`README.md`](#readmemd)
    - [`USER_DOC.md`](#user_docmd)
    - [`DEV_DOC.md`](#dev_docmd)
  - [15. Checklist de corrección](#15-checklist-de-corrección)
  - [16. Errores frecuentes en Arch/CachyOS](#16-errores-frecuentes-en-archcachyos)
  - [17. Migración a VirtualBox con Arch + i3 en Ubuntu](#17-migración-a-virtualbox-con-arch--i3-en-ubuntu)
    - [Idea general](#idea-general)
  - [0. Arquitectura de despliegue — Qué va dónde](#0-arquitectura-de-despliegue--qué-va-dónde)
    - [Qué necesita la máquina host Ubuntu](#qué-necesita-la-máquina-host-ubuntu)
    - [Qué necesita la VM Arch](#qué-necesita-la-vm-arch)
    - [Qué está y qué no está en tu repositorio Git](#qué-está-y-qué-no-está-en-tu-repositorio-git)
  - [17. Migración a VirtualBox con Arch + i3 en Ubuntu (Guía Completa)](#17-migración-a-virtualbox-con-arch--i3-en-ubuntu-guía-completa)
    - [Paso 1 — Sube tu código a Git (en CachyOS, antes de todo)](#paso-1--sube-tu-código-a-git-en-cachyos-antes-de-todo)
    - [Paso 2 — Instala VirtualBox en Ubuntu](#paso-2--instala-virtualbox-en-ubuntu)
    - [Paso 3 — Crea y configura la VM Arch Linux](#paso-3--crea-y-configura-la-vm-arch-linux)
    - [Paso 4 — Instala Arch Linux en la VM](#paso-4--instala-arch-linux-en-la-vm)
    - [Paso 5 — Instala el entorno gráfico i3 en la VM](#paso-5--instala-el-entorno-gráfico-i3-en-la-vm)
    - [Paso 6 — Instala Docker dentro de la VM](#paso-6--instala-docker-dentro-de-la-vm)
    - [Paso 7 — Configuración SSH (opcional pero recomendado)](#paso-7--configuración-ssh-opcional-pero-recomendado)
    - [Paso 8 — Clona el proyecto dentro de la VM](#paso-8--clona-el-proyecto-dentro-de-la-vm)
    - [Paso 9 — Crea los directorios de datos del host en la VM](#paso-9--crea-los-directorios-de-datos-del-host-en-la-vm)
    - [Paso 10 — Crea .env y secrets en la VM](#paso-10--crea-env-y-secrets-en-la-vm)
    - [Paso 11 — Configura el dominio en la VM](#paso-11--configura-el-dominio-en-la-vm)
    - [Paso 12 — Arranca y prueba el proyecto en la VM](#paso-12--arranca-y-prueba-el-proyecto-en-la-vm)
    - [Diferencias: CachyOS vs VM Arch](#diferencias-cachyos-vs-vm-arch)
    - [Script de preparación rápida de la VM](#script-de-preparación-rápida-de-la-vm)
    - [Checklist del día de la evaluación](#checklist-del-día-de-la-evaluación)

---

## 1. Qué es Inception y qué pide el subject

Inception es un proyecto de administración de sistemas de 42 en el que construyes una infraestructura web completa usando Docker: un servidor NGINX con cifrado TLS, un sitio WordPress con php-fpm y una base de datos MariaDB, cada uno en su propio contenedor, todos orquestados por Docker Compose.

**Lo que el subject exige en la parte obligatoria** (sin bonus):

- **Tres contenedores construidos desde cero.** Está **prohibido** usar imágenes pre-construidas de Docker Hub como `nginx:latest` o `wordpress:latest`. Debes partir de la **penúltima versión estable de Debian o Alpine** e instalar todo tú mismo en el Dockerfile. A febrero de 2026, Debian 13 (Trixie) es la estable actual, así que la penúltima es **Debian 12 (Bookworm)**.
- **El tag `latest` está explícitamente prohibido.** Usa siempre un tag de versión específico (ej: `debian:bookworm`).
- **Contenedor NGINX** — único punto de entrada a la infraestructura. Escucha **solo en el puerto 443** con **TLSv1.2 o TLSv1.3**. Hace proxy de las peticiones PHP al contenedor WordPress.
- **Contenedor WordPress + php-fpm** — corre WordPress con php-fpm (sin NGINX dentro). Escucha internamente en el puerto 9000.
- **Contenedor MariaDB** — la base de datos. Escucha internamente en el puerto 3306.
- **Dos volúmenes Docker con nombre** — uno para los ficheros de la BD (`/var/lib/mysql`) y otro para los del sitio web (`/var/www/html`). Ambos deben estar en el host en `/home/ravazque/data/`. Los bind mounts **no están permitidos** para estos volúmenes.
- **Una red Docker** de tipo bridge definida por el usuario. Usar `network: host`, `--link` o `links:` está **prohibido**.
- **Un `.env`** en `srcs/` con las variables de entorno. Ninguna contraseña en los Dockerfiles.
- **Docker secrets** están fuertemente recomendados para almacenar contraseñas. Un directorio `secrets/` en la raíz del proyecto contiene los ficheros de secretos. **Cualquier credencial encontrada en tu repositorio Git fuera de secrets correctamente configurados resultará en fallo del proyecto.**
- **Un Makefile** en la raíz del proyecto que construya todo con docker-compose.
- **Dominio** `ravazque.42.fr` apuntando a la IP local de tu máquina.
- **Dos usuarios WordPress** — un administrador (cuyo nombre NO puede contener "admin") y un usuario normal.
- Los contenedores deben **reiniciarse automáticamente** si se caen.
- **Sin bucles infinitos** (`tail -f`, `sleep infinity`, `while true`) en los entrypoints.
- Cada imagen Docker debe tener el **mismo nombre que su servicio** en el compose.
- **Un `.dockerignore`** en cada directorio de servicio.
- **Tres ficheros de documentación** en la raíz del repo: `README.md`, `USER_DOC.md`, `DEV_DOC.md`.

---

## 2. Docker y Docker Compose explicados desde cero

**Docker** es una herramienta que permite ejecutar aplicaciones dentro de "contenedores" aislados. Piensa en un contenedor como un mini-ordenador ligero que corre dentro de tu máquina real. Cada contenedor tiene sus propios ficheros de sistema operativo, programas instalados y red, pero comparte el kernel de tu máquina, así que arranca en segundos (a diferencia de una VM completa). Un **Dockerfile** es la receta que le dice a Docker cómo construir la imagen de un contenedor: empezar desde un SO base, instalar paquetes, copiar ficheros de configuración, definir qué se ejecuta al arrancar.

**Docker Compose** es una herramienta complementaria para definir y ejecutar **varios contenedores juntos** usando un único fichero YAML (`docker-compose.yml`). En lugar de tres comandos `docker build` y `docker run` separados, describes los tres servicios, sus redes y sus volúmenes en un fichero y escribes `docker compose up`. Compose lo gestiona todo: construir imágenes, crear redes, arrancar contenedores en el orden correcto.

**Vocabulario clave para Inception:**

- **Image (imagen)** — plantilla/snapshot de un contenedor (construida desde un Dockerfile)
- **Container (contenedor)** — una instancia en ejecución de una imagen
- **Volume (volumen)** — almacenamiento persistente que sobrevive a reinicios y reconstrucciones del contenedor
- **Network (red)** — red virtual que conecta contenedores para que se comuniquen por nombre
- **Port mapping (mapeo de puertos)** — reenviar un puerto de tu host al contenedor (ej: `443:443`)
- **Secret (secreto)** — un fichero con datos sensibles (contraseñas) montado como solo lectura en `/run/secrets/` dentro de los contenedores

---

## 3. Instalar Docker en CachyOS

CachyOS está basado en Arch y tiene Docker en sus repositorios. Ejecuta estos comandos en orden:

```bash
# Paso 1: Actualiza el sistema (crítico en distros rolling-release)
sudo pacman -Syu

# Paso 2: Instala Docker, Docker Compose y Buildx
sudo pacman -S docker docker-compose docker-buildx

# Paso 3: Habilita Docker para que arranque en el boot Y arrancarlo ahora
sudo systemctl enable --now docker.service

# Paso 4: Añade tu usuario al grupo docker (para no usar sudo en cada comando docker)
sudo usermod -aG docker ${USER}

# Paso 5: Aplica el cambio de grupo (cierra sesión y vuelve a entrar, o ejecuta:)
newgrp docker
```

Ahora configura dos cosas que los sistemas basados en Arch necesitan para el networking de Docker:

```bash
# Paso 6: Habilitar IP forwarding (Docker lo necesita para la red de contenedores)
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-docker.conf
sudo sysctl --system

# Paso 7: Arreglar DNS para contenedores
# systemd-resolved de Arch usa 127.0.0.53 que los contenedores no pueden alcanzar
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<'EOF'
{
  "dns": ["1.1.1.1", "8.8.8.8"]
}
EOF
sudo systemctl restart docker
```

**Verificar que todo funciona:**

```bash
docker --version          # Debe mostrar Docker 27.x o superior
docker compose version    # Debe mostrar Docker Compose v2.x o superior
docker run hello-world    # Debe imprimir "Hello from Docker!"
```

Si `docker run hello-world` falla con "permission denied", cierra sesión completamente y vuelve a entrar para que el cambio de grupo surta efecto.

---

## 4. Estructura de directorios del proyecto

El subject especifica una estructura exacta. **Importante: la carpeta se llama `srcs` (con 's'), no `src`.** Créala ahora:

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

Crear todos los directorios de golpe:

```bash
mkdir -p inception/srcs/requirements/nginx/{conf,tools}
mkdir -p inception/srcs/requirements/wordpress/{conf,tools}
mkdir -p inception/srcs/requirements/mariadb/{conf,tools}
mkdir -p inception/secrets
```

Crear los directorios del host donde los volúmenes Docker almacenarán datos persistentes:

```bash
sudo mkdir -p /home/ravazque/data/wordpress
sudo mkdir -p /home/ravazque/data/mysql
sudo chown -R ravazque:ravazque /home/ravazque/data
```

> **Btrfs (CachyOS lo usa por defecto):** Si tu `/home` usa Btrfs, deshabilita Copy-on-Write en estos directorios ANTES de almacenar datos. Las bases de datos funcionan muy mal con CoW activado:
>
> ```bash
> sudo chattr +C /home/ravazque/data/mysql
> sudo chattr +C /home/ravazque/data/wordpress
> ```

Crea un fichero `.dockerignore` en cada directorio de servicio para mantener limpios los contextos de build:

```bash
# Mismo contenido para los tres — ejecuta desde inception/
for service in nginx wordpress mariadb; do
cat > srcs/requirements/$service/.dockerignore <<'EOF'
.git
.gitignore
README.md
EOF
done
```

---

## 5. El hostname: ravazque.42.fr

El subject requiere que el dominio `ravazque.42.fr` resuelva a tu IP local. Edita `/etc/hosts`:

```bash
echo "127.0.0.1 ravazque.42.fr" | sudo tee -a /etc/hosts
```

Verifica con:

```bash
ping -c 1 ravazque.42.fr
# Debe mostrar respuestas desde 127.0.0.1
```

---

## 6. El archivo .env y los secrets

### El fichero `.env`

Crea `inception/srcs/.env`. Este fichero contiene las variables de configuración (no las contraseñas). Docker Compose lo lee automáticamente.

```env
# Dominio
DOMAIN_NAME=ravazque.42.fr

# MariaDB
MYSQL_DATABASE=wordpress
MYSQL_USER=wpuser

# Admin de WordPress (el nombre NO puede contener "admin")
WP_TITLE=Inception
WP_ADMIN_USER=boss
WP_ADMIN_EMAIL=boss@student.42.fr

# Usuario normal de WordPress
WP_USER=editor
WP_USER_EMAIL=editor@student.42.fr

# Ruta a los secrets (usada por Docker Compose)
SECRETS_DIR=../secrets
```

### El directorio secrets

Crea los ficheros de contraseñas en `inception/secrets/`. Cada fichero contiene solo la contraseña, sin salto de línea final:

```bash
cd inception

printf 'wppass123' > secrets/db_password.txt
printf 'rootpass123' > secrets/db_root_password.txt
printf 'bosspass123\neditorpass123' > secrets/credentials.txt
```

> `credentials.txt` almacena las contraseñas de WordPress — línea 1 es la del admin, línea 2 la del usuario normal.

### El `.gitignore`

Crea `inception/.gitignore` para mantener los secretos fuera de Git:

```gitignore
srcs/.env
secrets/
```

**Reglas importantes:**
- `WP_ADMIN_USER` **no puede** contener la palabra "admin" (ni "Admin", "administrator", etc.).
- Usa tus propias contraseñas — las de arriba son solo ejemplos.
- **Nunca subas `.env` ni `secrets/` a un repositorio público.**

---

## 7. Contenedor MariaDB

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

**Explicación línea a línea:**
- `FROM debian:bookworm` — parte de Debian 12 (penúltima versión estable a feb 2026; Debian 13 Trixie es la actual). Sin MariaDB instalado aún.
- `RUN apt-get update && apt-get install -y ...` — instala el servidor y cliente MariaDB. El `rm` limpia la caché de paquetes para mantener la imagen pequeña.
- `COPY conf/50-server.cnf ...` — copia tu configuración personalizada de MariaDB, reemplazando la de por defecto.
- `RUN mkdir -p /var/run/mysqld ...` — crea el directorio de runtime que MariaDB necesita para su socket y PID, con los permisos correctos.
- `EXPOSE 3306` — documenta que el contenedor usa el puerto 3306 (informativo, la red Docker gestiona la conectividad).
- `ENTRYPOINT` — ejecuta el script de configuración al arrancar el contenedor.

### `srcs/requirements/mariadb/conf/50-server.cnf`

```ini
[mysqld]
datadir         = /var/lib/mysql
socket          = /var/run/mysqld/mysqld.sock
port            = 3306
bind-address    = 0.0.0.0
```

- `bind-address = 0.0.0.0` — **línea crítica**. El valor por defecto es `127.0.0.1` (solo acepta conexiones locales). Cambiarlo a `0.0.0.0` permite conexiones desde otros contenedores de la red Docker (WordPress necesita conectarse a MariaDB).

### `srcs/requirements/mariadb/tools/setup.sh`

```bash
#!/bin/bash

# Leer contraseñas de Docker secrets
MYSQL_PASSWORD=$(cat /run/secrets/db_password)
MYSQL_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)

# Arrancar MariaDB temporalmente para ejecutar comandos SQL
mysqld_safe &
sleep 5

# Solo ejecutar setup si la base de datos no existe ya
if ! mysql -e "USE ${MYSQL_DATABASE}" 2>/dev/null; then
    mysql -e "CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;"
    mysql -e "CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    mysql -e "GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';"
    mysql -e "FLUSH PRIVILEGES;"
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
fi

# Parar la instancia temporal
mysqladmin -u root -p${MYSQL_ROOT_PASSWORD} shutdown

# Arrancar MariaDB en primer plano (mantiene el contenedor vivo)
exec mysqld_safe
```

**Puntos clave:**
- Las contraseñas se leen de Docker secrets (`/run/secrets/`), no de variables de entorno. Es el enfoque recomendado.
- El `if` comprueba si la BD ya existe — hace el script seguro para ejecutarse múltiples veces (idempotente).
- `'%'` en el CREATE USER significa que el usuario puede conectarse desde cualquier host.
- `exec mysqld_safe` — reemplaza el proceso shell con MariaDB, haciéndolo PID 1 del contenedor. Esto es lo que mantiene el contenedor vivo y permite que Docker lo gestione correctamente.

---

## 8. Contenedor WordPress

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

**Puntos clave:**
- Se instala `php8.2-fpm` (FastCGI Process Manager) y las extensiones PHP que WordPress necesita. Debian 12 Bookworm trae PHP 8.2.
- `mariadb-client` se incluye para que WP-CLI pueda verificar la conexión a la base de datos.
- WP-CLI se descarga durante el build, no en el entrypoint, para que no se repita en cada arranque.

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

**Puntos clave:**
- `listen = 0.0.0.0:9000` — por defecto PHP-FPM escucha en un Unix socket. Lo cambiamos a TCP puerto 9000 para que NGINX (en un contenedor diferente) pueda alcanzarlo por la red Docker.
- `clear_env = no` — **crítico para Inception**. Por defecto PHP-FPM limpia todas las variables de entorno por seguridad. Con `no`, las variables del `.env` (credenciales de BD, etc.) se pasan a WordPress.

### `srcs/requirements/wordpress/tools/setup.sh`

```bash
#!/bin/bash

# Leer contraseñas de Docker secrets
MYSQL_PASSWORD=$(cat /run/secrets/db_password)
WP_ADMIN_PASSWORD=$(head -n 1 /run/secrets/credentials)
WP_USER_PASSWORD=$(sed -n '2p' /run/secrets/credentials)

# Esperar a que MariaDB esté lista
echo "Esperando a MariaDB..."
while ! mariadb -h mariadb -u${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE} -e "SELECT 1" &>/dev/null; do
    sleep 2
done
echo "¡MariaDB lista!"

# Solo instalar WordPress si no existe ya wp-config.php
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

**Puntos clave:**
- Las contraseñas se leen de ficheros Docker secrets. `credentials` tiene la contraseña del admin en la línea 1 y la del usuario normal en la línea 2.
- El `while` espera a que MariaDB acepte conexiones. El hostname `mariadb` se resuelve automáticamente gracias al DNS interno de Docker en nuestra red personalizada. **Esto no es un bucle infinito prohibido** — tiene una condición de salida clara (MariaDB disponible) y es un patrón estándar de comprobación de disponibilidad.
- `--dbhost=mariadb` — dice a WordPress que se conecte al contenedor MariaDB usando el nombre DNS de Docker.
- `exec php-fpm8.2 -F` — arranca PHP-FPM en primer plano (`-F`), convirtiéndolo en PID 1.

---

## 9. Contenedor NGINX

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

**Puntos clave:**
- `openssl` se instala para generar el certificado TLS autofirmado.
- `CMD ["nginx", "-g", "daemon off;"]` — arranca NGINX en primer plano. `daemon off;` evita que NGINX haga fork al fondo (requerido por Docker). El script del ENTRYPOINT se ejecuta primero y luego pasa la ejecución a este CMD.

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

**Puntos clave:**
- `listen 443 ssl` — solo HTTPS, solo puerto 443. El subject lo exige explícitamente.
- `ssl_protocols TLSv1.2 TLSv1.3` — el subject prohíbe TLS 1.0 y 1.1.
- `fastcgi_pass wordpress:9000` — reenvía peticiones PHP al contenedor WordPress. Docker resuelve automáticamente `wordpress` a la IP del contenedor.
- `fastcgi_read_timeout 300` — evita timeouts durante la instalación inicial de WordPress.

### `srcs/requirements/nginx/tools/setup.sh`

```bash
#!/bin/bash

# Generar certificado TLS autofirmado si no existe todavía
if [ ! -f /etc/ssl/certs/nginx.crt ]; then
    echo "Generando certificado SSL autofirmado..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/nginx.key \
        -out /etc/ssl/certs/nginx.crt \
        -subj "/C=ES/ST=Madrid/L=Madrid/O=42Madrid/CN=ravazque.42.fr"
    echo "¡Certificado SSL generado!"
fi

# Ejecutar el CMD del Dockerfile (nginx -g 'daemon off;')
exec "$@"
```

**Puntos clave:**
- `-x509 -nodes` — certificado autofirmado sin passphrase en la clave privada (NGINX necesita leerla sin intervención humana).
- `-newkey rsa:2048` — genera un nuevo par de claves RSA de 2048 bits.
- `CN=ravazque.42.fr` — el Common Name debe coincidir con el `server_name` en nginx.conf.
- `exec "$@"` — la magia que conecta ENTRYPOINT y CMD. `"$@"` se expande al CMD del Dockerfile. `exec` reemplaza el shell con NGINX, convirtiéndolo en PID 1.

---

## 10. El docker-compose.yml

Crea `inception/srcs/docker-compose.yml`:

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

**Puntos clave:**
- **Sin clave `version:`** — la clave `version` está deprecated en Docker Compose v2 moderno y genera avisos. Omitirla es correcto.
- Solo NGINX tiene `ports:` (`443:443`). MariaDB y WordPress no exponen puertos al host — solo son accesibles dentro de la red Docker.
- NGINX y WordPress montan el **mismo volumen** `wordpress_data` en `/var/www/html`. WordPress escribe ficheros, NGINX los lee.
- `env_file: - .env` — inyecta las variables no secretas del `.env` como variables de entorno en el contenedor.
- `secrets:` — cada servicio lista qué secretos necesita. Docker Compose los monta como solo lectura en `/run/secrets/<nombre_secreto>` dentro del contenedor.
- `restart: always` — si el contenedor se cae, Docker lo reinicia automáticamente.
- Los volúmenes usan `driver_opts type: none, o: bind` con `driver: local` — esto crea volúmenes Docker con nombre que almacenan datos en la ruta del host especificada. Esto cumple con el requisito del subject de volúmenes con nombre (no bind mounts directos).
- La red `inception` de tipo `bridge` crea una red virtual aislada con DNS interno de Docker.
- El bloque `secrets:` al final mapea nombres de secretos a ficheros relativos a la ubicación del docker-compose.yml.

---

## 11. El Makefile

Crea `inception/Makefile`:

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

> **Importante:** Las líneas de receta en Makefiles deben estar indentadas con **tabulaciones**, no con espacios. Si usas espacios el Makefile dará error.

**Comandos disponibles:**
- `make` o `make up` — construye y arranca todo.
- `make down` — para y elimina los contenedores (los datos en volúmenes persisten).
- `make logs` — muestra los logs en tiempo real de todos los contenedores. Muy útil para depurar.
- `make clean` — elimina contenedores e imágenes Docker sin usar.
- `make fclean` — limpieza total: también borra los datos persistentes del host.
- `make re` — limpieza total y reconstrucción desde cero.

---

## 12. Cómo funcionan los volúmenes y la red

**Los volúmenes** son la forma que tiene Docker de persistir datos más allá de la vida de un contenedor. Cuando haces `docker compose down`, los contenedores se destruyen pero los volúmenes sobreviven. Cuando haces `docker compose up` de nuevo, los nuevos contenedores montan los mismos volúmenes y encuentran todos sus datos intactos.

`wordpress_data` mapea a `/home/ravazque/data/wordpress` en tu host. Tanto NGINX como WordPress montan este volumen en `/var/www/html` — por eso NGINX puede servir ficheros que WordPress crea. `mariadb_data` mapea a `/home/ravazque/data/mysql` y solo lo monta MariaDB en `/var/lib/mysql`.

**La red bridge** (`inception`) crea una red virtual aislada. Docker ejecuta un servidor DNS interno en esta red, así los contenedores se alcanzan por nombre — WordPress se conecta a `mariadb` en el puerto 3306, y NGINX envía peticiones PHP a `wordpress` en el puerto 9000. Ningún contenedor necesita conocer la IP de otro. Solo el puerto 443 de NGINX está expuesto al host; MariaDB y WordPress están completamente ocultos del exterior.

---

## 13. Arrancar, probar y validar el proyecto

### Primer arranque

Desde el directorio `inception/`:

```bash
make
```

La primera construcción tarda varios minutos mientras descarga paquetes Debian. Mira los logs:

```bash
make logs
```

Cuando veas `NOTICE: ready to handle connections` de PHP-FPM y `¡MariaDB lista!`, todo está arriba.

### Verificar los contenedores

```bash
docker compose -f srcs/docker-compose.yml ps
```

Debes ver tres contenedores con estado `Up`.

### Probar el sitio web

Abre el navegador en:
```
https://ravazque.42.fr
```

El navegador avisará del certificado autofirmado — es normal y esperado. Haz clic en "Avanzado" → "Aceptar el riesgo". Debe aparecer tu sitio WordPress.

---

## 14. Archivos de documentación obligatorios (README, USER_DOC, DEV_DOC)

El subject requiere tres ficheros markdown en la raíz del repositorio. **Son obligatorios para la validación.**

### `README.md`

Debe incluir:
- **Primera línea** (en cursiva): `*This project has been created as part of the 42 curriculum by ravazque.*`
- Sección **Description**: qué es el proyecto, su objetivo, visión general.
- Sección **Instructions**: cómo instalar y ejecutar el proyecto.
- Sección **Resources**: referencias (docs de Docker, tutoriales, etc.) y descripción de cómo se usó la IA — para qué tareas y qué partes.
- Sección **Project description** con comparaciones:
  - Virtual Machines vs Docker
  - Secrets vs Environment Variables
  - Docker Network vs Host Network
  - Docker Volumes vs Bind Mounts
- Debe estar escrito en **inglés**.

### `USER_DOC.md`

Documentación de usuario explicando:
- Qué servicios proporciona el stack.
- Cómo arrancar y parar el proyecto.
- Cómo acceder al sitio web y al panel de administración de WordPress.
- Dónde encontrar y gestionar las credenciales.
- Cómo comprobar que los servicios funcionan correctamente.

### `DEV_DOC.md`

Documentación de desarrollador explicando:
- Cómo montar el entorno desde cero (requisitos previos, ficheros de configuración, secrets).
- Cómo construir y arrancar con el Makefile y Docker Compose.
- Comandos útiles para gestionar contenedores y volúmenes.
- Dónde se almacenan los datos del proyecto y cómo persisten.

---

## 15. Checklist de corrección

Repasa cada punto antes de la evaluación:

```bash
# TLS funciona correctamente
openssl s_client -connect ravazque.42.fr:443 2>/dev/null | grep -i "protocol\|cipher"
# Debe mostrar TLSv1.2 o TLSv1.3

# La red Docker personalizada existe
docker network ls | grep inception

# Los tres contenedores están en la red
docker network inspect inception --format '{{range .Containers}}{{.Name}} {{end}}'
# Debe listar: nginx wordpress mariadb

# Los volúmenes existen y tienen datos
docker volume ls
ls /home/ravazque/data/wordpress/    # Debe contener ficheros WordPress
ls /home/ravazque/data/mysql/        # Debe contener ficheros de BD

# La BD tiene las tablas de WordPress
docker exec -it mariadb mariadb -u wpuser -p$(cat secrets/db_password.txt) wordpress -e "SHOW TABLES;"

# Existen dos usuarios WordPress
docker exec -it wordpress wp user list --allow-root
# Debe mostrar el admin (sin "admin" en el nombre) y el usuario normal

# El contenedor se reinicia tras un crash
docker kill nginx
# Espera unos segundos
docker ps    # nginx debe aparecer de nuevo con status "Up"

# Los datos persisten tras reinicio
make down && make up
# Visita https://ravazque.42.fr — el sitio debe seguir igual

# El puerto 80 NO está accesible (solo debe funcionar el 443)
curl -v http://ravazque.42.fr 2>&1 | head -5
# Debe fallar con "Connection refused"

# Los secrets están montados correctamente
docker exec -it mariadb cat /run/secrets/db_password
# Debe imprimir la contraseña

# No hay contraseñas en los Dockerfiles
grep -r "password\|pass" srcs/requirements/*/Dockerfile
# No debe devolver nada

# No se usa el tag "latest"
grep -r "latest" srcs/requirements/*/Dockerfile
# No debe devolver nada

# Los archivos de documentación existen
ls README.md USER_DOC.md DEV_DOC.md
```

---

## 16. Errores frecuentes en Arch/CachyOS

**"Cannot connect to the Docker daemon"**
El servicio Docker no está corriendo o no estás en el grupo docker. Ejecuta `sudo systemctl start docker` y asegúrate de haber ejecutado `sudo usermod -aG docker ${USER}` y haber cerrado/abierto sesión.

**DNS dentro de los contenedores falla (los paquetes no se descargan al construir)**
Arch usa `systemd-resolved` al que los contenedores no pueden acceder. Asegúrate de haber creado `/etc/docker/daemon.json` con los DNS explícitos (`1.1.1.1`, `8.8.8.8`) y reiniciado Docker.

**El contenedor MariaDB se reinicia continuamente**
Comprueba los logs con `docker logs mariadb`. Causas comunes: el directorio `/home/ravazque/data/mysql` no existe, o tiene datos corruptos de un intento anterior (limpia con `make fclean` y reconstruye). En Btrfs, ejecuta `chattr +C` en el directorio.

**WordPress muestra la página de instalación en lugar del sitio**
El script de setup no se ejecutó correctamente. Comprueba `docker logs wordpress`. Causa habitual: MariaDB no estaba lista cuando WordPress intentó conectarse. Asegúrate de que el bucle `while` en `setup.sh` funciona y que las variables de entorno se están pasando (comprueba con `docker exec wordpress env`).

**"bind: address already in use" en el puerto 443**
Otro servicio en tu host está usando el puerto 443. Para el que sea: `sudo systemctl stop nginx` o `sudo systemctl stop apache2`. Comprueba qué usa el puerto con `sudo ss -tlnp | grep 443`.

**Errores de permisos en los directorios de volúmenes**
Asegúrate de que el propietario de los directorios del host eres tú: `sudo chown -R ravazque:ravazque /home/ravazque/data`. En Btrfs, ejecuta también `sudo chattr +C` en los dos directorios de datos.

**Conflictos de nftables/iptables**
CachyOS puede usar nftables. Si el networking de Docker está roto, instala la capa de compatibilidad: `sudo pacman -S iptables-nft` y reinicia Docker.

**NGINX devuelve "502 Bad Gateway"**
NGINX no puede alcanzar PHP-FPM. Comprueba que el contenedor WordPress está corriendo (`docker ps`), que `www.conf` tiene `listen = 0.0.0.0:9000`, y que nginx.conf tiene `fastcgi_pass wordpress:9000`. También revisa `docker logs wordpress` para errores de arranque de PHP-FPM.

---

## 17. Migración a VirtualBox con Arch + i3 en Ubuntu

El subject de 42 Madrid requiere que la corrección se haga en una máquina virtual. Tú desarrollas en CachyOS pero la evaluación ocurre en una VM con Arch + i3 corriendo sobre Ubuntu con VirtualBox. Esta sección te guía para que la migración sea perfecta y no haya sorpresas el día de la corrección.

### Idea general

El código fuente de Inception (todos los Dockerfiles, configs, scripts y el Makefile) es completamente portable — no depende de nada específico de CachyOS. Lo que cambia entre entornos es: la instalación de Docker, la configuración local de DNS (`/etc/hosts`), los directorios de datos del host y algunos ajustes del sistema.

## 0. Arquitectura de despliegue — Qué va dónde

Antes de hacer cualquier cosa, entiende bien el entorno de dos capas que se usa en la evaluación de 42:

```
┌─────────────────────────────────────────────────────────────┐
│  MÁQUINA HOST UBUNTU (máquina del evaluador o la tuya)      │
│                                                             │
│  Solo tiene: VirtualBox instalado                           │
│  NO tiene: Docker, el proyecto, secrets, .env               │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  MÁQUINA VIRTUAL ARCH LINUX (dentro de VirtualBox)    │  │
│  │                                                       │  │
│  │  Tiene todo:                                          │  │
│  │  ├── Arch Linux + gestor de ventanas i3               │  │
│  │  ├── Docker + Docker Compose                          │  │
│  │  ├── El repositorio Git clonado (Dockerfiles, etc.)   │  │
│  │  ├── srcs/.env (creado manualmente, NO de Git)        │  │
│  │  ├── secrets/ (creado manualmente, NO de Git)         │  │
│  │  ├── /home/ravazque/data/ (directorios de datos)      │  │
│  │  ├── Entrada en /etc/hosts para ravazque.42.fr        │  │
│  │  └── Firefox (para acceder al sitio WordPress)        │  │
│  │                                                       │  │
│  │  Red Docker (bridge):                                 │  │
│  │  ├── Contenedor: nginx      (puerto 443 ← único abierto) │
│  │  ├── Contenedor: wordpress  (puerto 9000 interno)     │  │
│  │  └── Contenedor: mariadb    (puerto 3306 interno)     │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Qué necesita la máquina host Ubuntu

| Elemento | ¿Necesario en Ubuntu host? | Notas |
|---|---|---|
| VirtualBox | ✅ Sí | `sudo apt install virtualbox` |
| Docker | ❌ No | Docker corre DENTRO de la VM |
| El repositorio Git | ❌ No | El clone se hace DENTRO de la VM |
| El directorio secrets/ | ❌ No | Se crea DENTRO de la VM |
| El archivo srcs/.env | ❌ No | Se crea DENTRO de la VM |
| Firefox / navegador | Opcional | Solo si quieres probar desde el host (no es necesario) |
| Cliente SSH | Opcional | Solo si prefieres trabajar vía SSH en vez de directamente en la VM |

### Qué necesita la VM Arch

| Elemento | ¿Necesario en la VM? | Cómo conseguirlo |
|---|---|---|
| Docker + Compose | ✅ Sí | `sudo pacman -S docker docker-compose docker-buildx` |
| Git | ✅ Sí | `sudo pacman -S git` |
| El repositorio del proyecto | ✅ Sí | `git clone <url-de-tu-repo-42>` |
| srcs/.env | ✅ Sí | Crear manualmente (ver sección 6) |
| El directorio secrets/ | ✅ Sí | Crear manualmente (ver sección 6) |
| /home/ravazque/data/ | ✅ Sí | `sudo mkdir -p /home/ravazque/data/{wordpress,mysql}` |
| Entrada en /etc/hosts | ✅ Sí | `echo "127.0.0.1 ravazque.42.fr" \| sudo tee -a /etc/hosts` |
| Firefox | ✅ Sí | `sudo pacman -S firefox` — para demostrar el sitio en la VM |
| i3 + Xorg | ✅ Sí | Entorno gráfico de la VM |
| openssh (servidor) | ⚠️ Opcional | Solo si quieres acceder vía SSH desde Ubuntu |

### Qué está y qué no está en tu repositorio Git

| Archivo/Directorio | ¿En Git? | Motivo |
|---|---|---|
| `Makefile` | ✅ Sí | Sin credenciales |
| `srcs/docker-compose.yml` | ✅ Sí | Referencia secrets pero no los contiene |
| `srcs/.env.example` | ✅ Sí | Solo plantilla, sin valores reales |
| `srcs/requirements/*/Dockerfile` | ✅ Sí | Sin contraseñas |
| `srcs/requirements/*/conf/*` | ✅ Sí | Archivos de configuración seguros |
| `srcs/requirements/*/tools/setup.sh` | ✅ Sí | Lee contraseñas de secrets, no las hardcodea |
| `README.md`, `USER_DOC.md`, `DEV_DOC.md` | ✅ Sí | Requeridos por el subject |
| `docs/guide/guideEN.md`, `guideES.md` | ✅ Sí | Documentación |
| `srcs/.env` | ❌ NO en Git | Contiene valores reales, excluido por .gitignore |
| `secrets/` | ❌ NO en Git | Contiene contraseñas, excluido por .gitignore |

> **Crítico:** El `.gitignore` debe contener `srcs/.env` y `secrets/`. Verifica antes de cada push:
> ```bash
> git status   # srcs/.env y secrets/ NO deben aparecer en la salida
> ```

---

## 17. Migración a VirtualBox con Arch + i3 en Ubuntu (Guía Completa)

Esta sección cubre el flujo completo para pasar de desarrollar en CachyOS a ejecutar la evaluación en una VM Arch limpia dentro de VirtualBox sobre Ubuntu. Lee la sección 0 primero para entender qué va dónde.

### Paso 1 — Sube tu código a Git (en CachyOS, antes de todo)

```bash
cd inception

# Verifica que secrets y .env están excluidos
git status   # Ni srcs/.env ni secrets/ deben aparecer

# Commit y push
git add .
git commit -m "inception: parte obligatoria completa"
git push
```

### Paso 2 — Instala VirtualBox en Ubuntu

En la máquina host Ubuntu:

```bash
sudo apt update
sudo apt install -y virtualbox virtualbox-ext-pack
```

Reinicia si se solicita.

### Paso 3 — Crea y configura la VM Arch Linux

Descarga la ISO de Arch Linux desde [archlinux.org/download](https://archlinux.org/download/).

En VirtualBox, crea una nueva VM:
- **Tipo:** Linux → Arch Linux (64-bit)
- **RAM:** mínimo 4 GB (2 GB si el espacio es limitado)
- **Disco:** 25 GB VDI dinámico
- **Procesadores:** 2 vCPUs mínimo
- **Adaptador de red:**
  - **Adaptador puente (Bridge)** — la VM obtiene su propia IP en tu red local. Úsalo si quieres que la VM sea accesible desde Ubuntu (por SSH o navegador en Ubuntu).
  - **NAT + Reenvío de puertos** — más simple, sin IP de red local. Configura: Host 443 → Guest 443, Host 2222 → Guest 22 (para SSH si quieres).

Monta la ISO de Arch en la unidad óptica de la VM y arranca.

### Paso 4 — Instala Arch Linux en la VM

Dentro de la VM, en el live environment de la ISO:

```bash
# 1. Distribución de teclado (si es necesario)
loadkeys es    # teclado español

# 2. Conectividad a internet (cable suele funcionar automáticamente en VM)
ping -c 1 archlinux.org

# 3. Particionar el disco (disposición simple para VM)
fdisk /dev/sda
# Crea: /dev/sda1 (1M, BIOS boot) y /dev/sda2 (resto, Linux filesystem)

mkfs.ext4 /dev/sda2
mount /dev/sda2 /mnt

# 4. Instalar sistema base
pacstrap /mnt base base-devel linux linux-firmware networkmanager sudo nano git openssh

# 5. Generar fstab
genfstab -U /mnt >> /mnt/etc/fstab

# 6. Entrar al nuevo sistema
arch-chroot /mnt

# 7. Configuración básica
ln -sf /usr/share/zoneinfo/Europe/Madrid /etc/localtime
hwclock --systohc
echo "es_ES.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=es_ES.UTF-8" > /etc/locale.conf
echo "archvm" > /etc/hostname

# 8. Contraseña root y usuario
passwd
useradd -m -G wheel ravazque
passwd ravazque

# 9. Habilitar sudo para el grupo wheel
EDITOR=nano visudo   # Descomenta: %wheel ALL=(ALL:ALL) ALL

# 10. Habilitar red y SSH en el arranque
systemctl enable NetworkManager
systemctl enable sshd    # opcional, solo si quieres acceso SSH

# 11. Instalar gestor de arranque
pacman -S grub
grub-install /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg

# 12. Salir y reiniciar
exit
umount /mnt
reboot
```

Expulsa la ISO de la unidad óptica antes de que la VM reinicie.

### Paso 5 — Instala el entorno gráfico i3 en la VM

Inicia sesión como `ravazque` tras el reinicio:

```bash
sudo pacman -Syu
sudo pacman -S xorg xorg-xinit i3 i3status dmenu alacritty firefox ttf-dejavu noto-fonts

# Configura startx para lanzar i3
echo "exec i3" > ~/.xinitrc

# (Opcional) Arranque automático del entorno gráfico al login
cat >> ~/.bash_profile <<'EOF'
if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" -eq 1 ]; then
    exec startx
fi
EOF

# Arranca i3 manualmente ahora
startx
```

Dentro de i3: `$mod+Enter` abre terminal (alacritty), `$mod+d` abre el lanzador dmenu.

### Paso 6 — Instala Docker dentro de la VM

Abre una terminal en i3 (`$mod+Enter`) y ejecuta:

```bash
sudo pacman -S docker docker-compose docker-buildx
sudo systemctl enable --now docker.service
sudo usermod -aG docker ravazque

# Aplica el cambio de grupo en la sesión actual
newgrp docker

# Arreglar IP forwarding (necesario para la red Docker en Arch)
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-docker.conf

# Arreglar DNS para builds de contenedores (problema de systemd-resolved en Arch)
sudo mkdir -p /etc/docker
echo '{"dns": ["1.1.1.1", "8.8.8.8"]}' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker

# Verificar
docker run hello-world
```

### Paso 7 — Configuración SSH (opcional pero recomendado)

SSH te permite trabajar desde el terminal del host Ubuntu en lugar del escritorio de la VM. Es opcional — también puedes trabajar directamente dentro de i3.

**Si usas NAT + Reenvío de puertos (Host 2222 → Guest 22):**

Dentro de la VM:
```bash
sudo systemctl enable --now sshd
```

Desde el host Ubuntu:
```bash
ssh -p 2222 ravazque@127.0.0.1
```

**Si usas Adaptador puente (Bridge):**

Obtén la IP de la VM desde dentro de ella:
```bash
ip addr show | grep "inet " | grep -v 127
```

Desde el host Ubuntu:
```bash
ssh ravazque@<ip-de-la-vm>
```

**Copiar archivos desde Ubuntu a la VM por SSH (si es necesario):**

```bash
# Copiar .env o secrets a la VM
scp -P 2222 mi_env_local ravazque@127.0.0.1:/home/ravazque/inception/srcs/.env
scp -P 2222 -r mis_secrets/ ravazque@127.0.0.1:/home/ravazque/inception/secrets/
```

> **Nota:** También puedes escribir el `.env` y `secrets/` directamente dentro de la VM sin SSH. El SSH es pura comodidad para quienes prefieren trabajar desde el terminal de Ubuntu.

### Paso 8 — Clona el proyecto dentro de la VM

Dentro de la VM (en un terminal de i3 o vía SSH):

```bash
cd ~
git clone https://git.42madrid.com/ravazque/inception.git
# Sustituye por la URL real de tu repositorio de 42
```

### Paso 9 — Crea los directorios de datos del host en la VM

```bash
sudo mkdir -p /home/ravazque/data/wordpress
sudo mkdir -p /home/ravazque/data/mysql
sudo chown -R ravazque:ravazque /home/ravazque/data
```

> La VM usa ext4 por defecto — no hay problema de CoW con Btrfs. El paso `chattr +C` de la guía de CachyOS NO es necesario aquí.

### Paso 10 — Crea .env y secrets en la VM

Estos archivos **NO están en Git** y deben crearse manualmente en cada entorno nuevo:

```bash
# Crear .env
cat > ~/inception/srcs/.env <<'EOF'
DOMAIN_NAME=ravazque.42.fr
MYSQL_DATABASE=ravazquedb
MYSQL_USER=ravazque
WP_TITLE=RavazquePage
WP_ADMIN_USER=ravazque_wp
WP_ADMIN_EMAIL=ravazque@student.42madrid.fr
WP_USER=ravazque
WP_USER_EMAIL=tu@email.com
SECRETS_DIR=../secrets
EOF

# Crear secrets
mkdir -p ~/inception/secrets
printf 'tu_contraseña_db'   > ~/inception/secrets/db_password.txt
printf 'tu_contraseña_root' > ~/inception/secrets/db_root_password.txt
printf 'pw_admin\npw_user'  > ~/inception/secrets/credentials.txt
```

### Paso 11 — Configura el dominio en la VM

```bash
echo "127.0.0.1 ravazque.42.fr" | sudo tee -a /etc/hosts
ping -c 1 ravazque.42.fr   # Debe responder desde 127.0.0.1
```

> **Importante:** Esta entrada de `/etc/hosts` debe estar en la VM, NO en el host Ubuntu. El sitio WordPress corre dentro de la VM y se prueba desde dentro de la VM (usando Firefox en i3).

### Paso 12 — Arranca y prueba el proyecto en la VM

```bash
cd ~/inception
make
make logs   # Observa la secuencia de arranque
```

Abre Firefox dentro de i3 y navega a `https://ravazque.42.fr`. Acepta el aviso del certificado. El sitio WordPress debe aparecer.

### Diferencias: CachyOS vs VM Arch

| Aspecto | CachyOS (desarrollo) | Arch Linux VM (evaluación) |
|---|---|---|
| Kernel | linux-cachyos (optimizado) | linux (estándar) |
| Filesystem `/home` | Btrfs (problema CoW → usar chattr +C) | ext4 (sin problema CoW) |
| Gestor de paquetes | pacman + yay | pacman solo |
| Entorno gráfico | KDE/GNOME típicamente | i3 (minimalista) |
| Paquetes Docker | Mismos que Arch | Mismos que Arch |
| Arreglo IP forwarding | Necesario | Necesario |
| Arreglo DNS | Necesario | Necesario |
| Paso chattr Btrfs | Necesario | No hace falta |
| secrets/ y .env | Creados localmente (no en Git) | Deben recrearse en la VM |
| Servidor SSH | Opcional | Opcional |

### Script de preparación rápida de la VM

Guarda esto en tu repositorio como `vm_setup.sh` y ejecútalo dentro de la VM tras clonar el proyecto:

```bash
#!/bin/bash
# Ejecutar dentro de la VM Arch tras clonar el repositorio
# Uso: bash vm_setup.sh
set -e

LOGIN="ravazque"

echo "=== Instalando Docker ==="
sudo pacman -S --noconfirm docker docker-compose docker-buildx
sudo systemctl enable --now docker.service
sudo usermod -aG docker ${LOGIN}

echo "=== Configurando IP forwarding ==="
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-docker.conf

echo "=== Configurando DNS de Docker ==="
sudo mkdir -p /etc/docker
echo '{"dns": ["1.1.1.1", "8.8.8.8"]}' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker

echo "=== Creando directorios de datos ==="
sudo mkdir -p /home/${LOGIN}/data/wordpress
sudo mkdir -p /home/${LOGIN}/data/mysql
sudo chown -R ${LOGIN}:${LOGIN} /home/${LOGIN}/data

echo "=== Configurando dominio local ==="
echo "127.0.0.1 ${LOGIN}.42.fr" | sudo tee -a /etc/hosts

echo ""
echo "=== ¡Setup completo! Próximos pasos: ==="
echo "1. Cierra sesión y vuelve a entrar (o ejecuta: newgrp docker)"
echo "2. Crea srcs/.env con tus valores"
echo "3. Crea secrets/ con tus contraseñas"
echo "4. Ejecuta: make"
```

### Checklist del día de la evaluación

Antes de que llegue el evaluador:

```bash
# 1. Reconstrucción completa para demostrar que funciona desde cero
make re

# 2. Sigue los logs hasta que todos los contenedores estén listos
make logs

# 3. Abre Firefox en i3 y verifica el sitio
# https://ravazque.42.fr — el sitio debe cargar
# https://ravazque.42.fr/wp-admin — el panel de admin debe cargar

# 4. Ejecuta el checklist de corrección (sección 15)
docker compose -f srcs/docker-compose.yml ps
openssl s_client -connect ravazque.42.fr:443 2>/dev/null | grep Protocol
docker network inspect inception --format '{{range .Containers}}{{.Name}} {{end}}'
docker exec wordpress wp user list --allow-root
docker kill nginx && sleep 5 && docker ps | grep nginx  # Prueba de reinicio
```