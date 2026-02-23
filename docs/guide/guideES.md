# 42 Inception — Guía Completa para CachyOS + Migración a VirtualBox/Arch

> **Login:** `ravazque` — reemplaza `ravazque` por tu login en CADA ruta, comando y archivo de configuración donde aparezca.

---

## Tabla de contenidos

1. [Qué es Inception y qué pide el subject](#1-qué-es-inception-y-qué-pide-el-subject)
2. [Docker y Docker Compose explicados desde cero](#2-docker-y-docker-compose-explicados-desde-cero)
3. [Instalar Docker en CachyOS](#3-instalar-docker-en-cachyos)
4. [Estructura de directorios del proyecto](#4-estructura-de-directorios-del-proyecto)
5. [El hostname: ravazque.42.fr](#5-el-hostname-ravazque42fr)
6. [El archivo .env](#6-el-archivo-env)
7. [Contenedor MariaDB](#7-contenedor-mariadb)
8. [Contenedor WordPress](#8-contenedor-wordpress)
9. [Contenedor NGINX](#9-contenedor-nginx)
10. [El docker-compose.yml](#10-el-docker-composeyml)
11. [El Makefile](#11-el-makefile)
12. [Cómo funcionan los volúmenes y la red](#12-cómo-funcionan-los-volúmenes-y-la-red)
13. [Arrancar, probar y validar el proyecto](#13-arrancar-probar-y-validar-el-proyecto)
14. [Checklist de corrección](#14-checklist-de-corrección)
15. [Errores frecuentes en Arch/CachyOS](#15-errores-frecuentes-en-archcachyos)
16. [Migración a VirtualBox con Arch + i3 en Ubuntu](#16-migración-a-virtualbox-con-arch--i3-en-ubuntu)

---

## 1. Qué es Inception y qué pide el subject

Inception es un proyecto de administración de sistemas de 42 en el que construyes una infraestructura web completa usando Docker: un servidor NGINX con cifrado TLS, un sitio WordPress con php-fpm y una base de datos MariaDB, cada uno en su propio contenedor, todos orquestados por Docker Compose.

**Lo que el subject exige en la parte obligatoria** (sin bonus):

- **Tres contenedores construidos desde cero.** Está **prohibido** usar imágenes pre-construidas de Docker Hub como `nginx:latest` o `wordpress:latest`. Debes partir de la **penúltima versión estable de Debian o Alpine** e instalar todo tú mismo en el Dockerfile.
- **Contenedor NGINX** — único punto de entrada a la infraestructura. Escucha **solo en el puerto 443** con **TLSv1.2 o TLSv1.3**. Hace proxy de las peticiones PHP al contenedor WordPress.
- **Contenedor WordPress + php-fpm** — corre WordPress con php-fpm (sin NGINX dentro). Escucha internamente en el puerto 9000.
- **Contenedor MariaDB** — la base de datos. Escucha internamente en el puerto 3306.
- **Dos volúmenes Docker** — uno para los ficheros de la base de datos (`/var/lib/mysql`) y otro para los ficheros del sitio web (`/var/www/html`). Ambos deben estar en el host en `/home/ravazque/data/`.
- **Una red Docker** de tipo bridge definida por el usuario. Usar `network: host`, `--link` o `links:` está **prohibido**.
- **Un `.env`** en `srcs/` con todas las credenciales. Ninguna contraseña en los Dockerfiles.
- **Un Makefile** en la raíz del proyecto que construya todo con docker-compose.
- **Dominio** `ravazque.42.fr` apuntando a la IP local de tu máquina.
- **Dos usuarios WordPress** — un administrador (cuyo nombre NO puede contener "admin") y un usuario normal.
- Los contenedores deben **reiniciarse automáticamente** si se caen.
- **Sin bucles infinitos** (`tail -f`, `sleep infinity`, `while true`) en los entrypoints.
- Cada imagen Docker debe tener el **mismo nombre que su servicio** en el compose.

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

El subject especifica una estructura exacta. Créala ahora:

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

Crear todos los directorios de golpe:

```bash
mkdir -p inception/srcs/requirements/nginx/{conf,tools}
mkdir -p inception/srcs/requirements/wordpress/{conf,tools}
mkdir -p inception/srcs/requirements/mariadb/{conf,tools}
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

## 6. El archivo .env

Crea `inception/srcs/.env`. Este fichero contiene todas las credenciales y variables de configuración. Docker Compose lo lee automáticamente.

```env
# Dominio
DOMAIN_NAME=ravazque.42.fr

# MariaDB
MYSQL_DATABASE=wordpress
MYSQL_USER=wpuser
MYSQL_PASSWORD=wppass123
MYSQL_ROOT_PASSWORD=rootpass123

# Admin de WordPress (el nombre NO puede contener "admin")
WP_TITLE=Inception
WP_ADMIN_USER=boss
WP_ADMIN_PASSWORD=bosspass123
WP_ADMIN_EMAIL=boss@student.42.fr

# Usuario normal de WordPress
WP_USER=editor
WP_USER_PASSWORD=editorpass123
WP_USER_EMAIL=editor@student.42.fr
```

**Reglas importantes:**
- `WP_ADMIN_USER` **no puede** contener la palabra "admin" (ni "Admin", "administrator", etc.).
- Usa tus propias contraseñas — las de arriba son solo ejemplos.
- **Nunca subas este fichero a un repositorio público.**

---

## 7. Contenedor MariaDB

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

**Explicación línea a línea:**
- `FROM debian:bullseye` — parte del SO base Debian 11 (penúltima versión estable). Sin MariaDB instalado aún.
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
- El `if` comprueba si la BD ya existe — hace el script seguro para ejecutarse múltiples veces (idempotente).
- `'%'` en el CREATE USER significa que el usuario puede conectarse desde cualquier host.
- `exec mysqld_safe` — reemplaza el proceso shell con MariaDB, haciéndolo PID 1 del contenedor. Esto es lo que mantiene el contenedor vivo y permite que Docker lo gestione correctamente.

---

## 8. Contenedor WordPress

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

**Puntos clave:**
- Se instala `php7.4-fpm` (FastCGI Process Manager) y las extensiones PHP que WordPress necesita.
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
- `listen = 0.0.0.0:9000` — por defecto PHP-FPM escucha en un Unix socket (`/run/php/php7.4-fpm.sock`). Lo cambiamos a TCP puerto 9000 para que NGINX (en un contenedor diferente) pueda alcanzarlo por la red Docker.
- `clear_env = no` — **crítico para Inception**. Por defecto PHP-FPM limpia todas las variables de entorno por seguridad. Con `no`, las variables del `.env` (credenciales de BD, etc.) se pasan a WordPress.

### `srcs/requirements/wordpress/tools/setup.sh`

```bash
#!/bin/bash

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

exec php-fpm7.4 -F
```

**Puntos clave:**
- El `while` espera a que MariaDB acepte conexiones. El hostname `mariadb` se resuelve automáticamente gracias al DNS interno de Docker en nuestra red personalizada. **Esto no es un bucle infinito prohibido** — tiene una condición de salida clara (MariaDB disponible) y es un patrón estándar de comprobación de disponibilidad.
- `--dbhost=mariadb` — dice a WordPress que se conecte al contenedor MariaDB usando el nombre DNS de Docker.
- `exec php-fpm7.4 -F` — arranca PHP-FPM en primer plano (`-F`), convirtiéndolo en PID 1.

---

## 9. Contenedor NGINX

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
- `fastcgi_pass wordpress:9000` — reenvía las peticiones PHP al contenedor WordPress. Docker resuelve `wordpress` a la IP del contenedor automáticamente.
- `fastcgi_read_timeout 300` — evita timeouts durante la instalación inicial de WordPress.

### `srcs/requirements/nginx/tools/setup.sh`

```bash
#!/bin/bash

# Generar certificado TLS autofirmado si no existe ya
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
- `-newkey rsa:2048` — genera un par de claves RSA de 2048 bits.
- `CN=ravazque.42.fr` — el Common Name del certificado debe coincidir con el `server_name` de nginx.conf.
- `exec "$@"` — el truco que conecta ENTRYPOINT y CMD. `"$@"` se expande al CMD definido en el Dockerfile. `exec` reemplaza el proceso shell con NGINX.

---

## 10. El docker-compose.yml

Crea `inception/srcs/docker-compose.yml`:

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

**Puntos clave:**
- Solo NGINX tiene `ports:` (`443:443`). MariaDB y WordPress no exponen puertos al host — solo son accesibles dentro de la red Docker.
- NGINX y WordPress montan el **mismo volumen** `wordpress_data` en `/var/www/html`. WordPress escribe ficheros, NGINX los lee.
- `env_file: - .env` — inyecta todas las variables del `.env` como variables de entorno en el contenedor.
- `restart: always` — si el contenedor se cae, Docker lo reinicia automáticamente.
- Los volúmenes usan `driver_opts type: none, o: bind` para hacer un bind mount directo del directorio del host.
- La red `inception` de tipo `bridge` crea una red virtual aislada con DNS interno de Docker.

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

## 14. Checklist de corrección

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
docker exec -it mariadb mariadb -u wpuser -pwppass123 wordpress -e "SHOW TABLES;"

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
```

---

## 15. Errores frecuentes en Arch/CachyOS

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

## 16. Migración a VirtualBox con Arch + i3 en Ubuntu

El subject de 42 Madrid requiere que la corrección se haga en una máquina virtual. Tú desarrollas en CachyOS pero la evaluación ocurre en una VM con Arch + i3 corriendo sobre Ubuntu con VirtualBox. Esta sección te guía para que la migración sea perfecta y no haya sorpresas el día de la corrección.

### Idea general

El código fuente de Inception (todos los Dockerfiles, configs, scripts y el Makefile) es completamente portable — no depende de nada específico de CachyOS. Lo que cambia entre entornos son: la instalación de Docker, la configuración del DNS local (`/etc/hosts`), los directorios de datos del host, y algunos detalles de configuración del sistema.

### Paso 1: Tener el código en Git

Antes de nada, tu proyecto debe estar en tu repositorio de 42:

```bash
cd inception
git init  # si no lo has hecho ya
git add .
git commit -m "inception: mandatory part complete"
git push
```

**No incluyas el fichero `.env` en Git.** Añádelo al `.gitignore`:

```bash
echo "srcs/.env" >> .gitignore
git add .gitignore
git commit -m "inception: add .env to gitignore"
```

### Paso 2: Instalar VirtualBox en Ubuntu

En la máquina Ubuntu (la del evaluador, o la tuya para prepararte):

```bash
sudo apt update
sudo apt install -y virtualbox virtualbox-ext-pack
```

### Paso 3: Crear la VM con Arch Linux

**Configuración recomendada de la VM:**
- **Tipo:** Linux, Arch Linux (64-bit)
- **RAM:** mínimo 2 GB, recomendado 4 GB
- **Disco:** mínimo 20 GB (con expansión dinámica está bien)
- **Red:** Adaptador puente (Bridge) — así la VM obtiene una IP de tu red local. Alternativamente usa NAT con reenvío de puertos (443 → 443).
- **Procesadores:** 2 vCPUs mínimo

**Instalación de Arch Linux en la VM:**

Descarga la ISO de Arch Linux desde [archlinux.org](https://archlinux.org/download/), monta la ISO en la VM y sigue la instalación estándar de Arch. Para Inception no necesitas nada especial — instalación base con:

```bash
# Desde el live environment de Arch
pacstrap /mnt base base-devel linux linux-firmware networkmanager sudo nano git
genfstab -U /mnt >> /mnt/etc/fstab
arch-chroot /mnt
ln -sf /usr/share/zoneinfo/Europe/Madrid /etc/localtime
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "archvm" > /etc/hostname
passwd   # contraseña de root
useradd -m -G wheel ravazque
passwd ravazque
# Edita /etc/sudoers y descomenta la línea %wheel ALL=(ALL) ALL
systemctl enable NetworkManager
```

### Paso 4: Instalar i3 en la VM

i3 es un gestor de ventanas mínimo. Instala un entorno gráfico básico:

```bash
# Como root o con sudo en la VM ya instalada
pacman -Syu
pacman -S xorg xorg-xinit i3 i3status dmenu alacritty \
          firefox ttf-dejavu noto-fonts

# Configura xinit para arrancar i3
echo "exec i3" > ~/.xinitrc

# Arranca el entorno gráfico
startx
```

Para que arranque automáticamente al login, añade a `~/.bash_profile` o `~/.zprofile`:

```bash
if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" -eq 1 ]; then
    exec startx
fi
```

### Paso 5: Instalar Docker en la VM (Arch)

Exactamente igual que en CachyOS — ambos son Arch-based:

```bash
sudo pacman -S docker docker-compose docker-buildx
sudo systemctl enable --now docker.service
sudo usermod -aG docker ravazque
newgrp docker

# Arreglar IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-docker.conf

# Arreglar DNS de Docker
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<'EOF'
{
  "dns": ["1.1.1.1", "8.8.8.8"]
}
EOF
sudo systemctl restart docker
```

### Paso 6: Clonar el proyecto en la VM

```bash
cd ~
git clone https://git.42madrid.com/ravazque/inception.git
# o el URL de tu repositorio de 42
```

### Paso 7: Crear los directorios de datos y el .env en la VM

Los directorios de datos **deben existir en el host de la VM** antes de ejecutar el proyecto:

```bash
sudo mkdir -p /home/ravazque/data/wordpress
sudo mkdir -p /home/ravazque/data/mysql
sudo chown -R ravazque:ravazque /home/ravazque/data

# Si el disco de la VM usa Btrfs (no es lo habitual en una instalación limpia):
# sudo chattr +C /home/ravazque/data/mysql
# sudo chattr +C /home/ravazque/data/wordpress
```

Crea el `.env` manualmente en la VM (no está en Git):

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

### Paso 8: Configurar el hostname en la VM

```bash
echo "127.0.0.1 ravazque.42.fr" | sudo tee -a /etc/hosts
```

### Paso 9: Arrancar el proyecto en la VM

```bash
cd ~/inception
make
```

Verifica que funciona exactamente igual que en CachyOS:

```bash
make logs
# Espera a que los tres contenedores estén listos

# Abre Firefox en la VM
firefox https://ravazque.42.fr
```

### Diferencias entre CachyOS y Arch puro en VM que debes tener en cuenta

| Aspecto | CachyOS | Arch puro en VM |
|---|---|---|
| Kernel | linux-cachyos (optimizado) | linux (estándar) |
| Filesystem `/home` | Btrfs frecuente | ext4 por defecto (no hay problema CoW) |
| Gestor de paquetes | pacman + yay | pacman |
| Entorno gráfico | KDE/GNOME típico | i3 minimalista |
| Tiempo de instalación | más rápido (mirrors pre-configurados) | estándar |
| Docker | Mismos paquetes, misma configuración | Mismos paquetes, misma configuración |

### Consejos para el día de la corrección

- **Haz `make re`** antes de que llegue el evaluador para demostrar que el proyecto se construye desde cero sin errores.
- **Conoce todos los ficheros de memoria** — el evaluador pedirá que expliques cada Dockerfile y el docker-compose.yml.
- **Prueba `docker kill` en vivo** — demuestra que el contenedor se reinicia automáticamente con `restart: always`.
- **Muestra la persistencia** — haz `make down && make up` y muestra que el contenido del sitio WordPress sigue ahí.
- **Ten el checklist a mano** — repasa la sección 14 de esta guía punto por punto antes de la evaluación.
- **Si el evaluador pide ver las contraseñas:** están en `srcs/.env` que no está en Git, lo cual es correcto según el subject.

### Script de preparación rápida para la VM

Guarda este script como `vm_setup.sh` en tu repositorio (pero no lo ejecutes en producción sin revisarlo):

```bash
#!/bin/bash
# Script de preparación de la VM para la corrección de Inception
# Ejecutar como ravazque con sudo disponible

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

echo "=== Configurando hostname ==="
echo "127.0.0.1 ${LOGIN}.42.fr" | sudo tee -a /etc/hosts

echo "=== ¡Setup completado! ==="
echo "Ahora crea el fichero srcs/.env con tus credenciales y ejecuta 'make'"
```

---

*Guía elaborada para el proyecto Inception de 42 Madrid. Login: ravazque.*