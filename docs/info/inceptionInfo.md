# Inception -- Documentacion Tecnica del Sistema

Referencia tecnica completa de la infraestructura web Dockerizada: NGINX + WordPress + MariaDB.

---

## Tabla de Contenidos

1. [Arquitectura del Sistema](#1-arquitectura-del-sistema)
2. [Contenedores e Imagenes Docker](#2-contenedores-e-imagenes-docker)
3. [NGINX -- Proxy Inverso y TLS](#3-nginx----proxy-inverso-y-tls)
4. [WordPress y PHP-FPM](#4-wordpress-y-php-fpm)
5. [MariaDB](#5-mariadb)
6. [Docker Compose y Orquestacion](#6-docker-compose-y-orquestacion)
7. [Red Docker (Docker Network)](#7-red-docker-docker-network)
8. [Volumenes y Persistencia](#8-volumenes-y-persistencia)
9. [Docker Secrets](#9-docker-secrets)
10. [PID 1 y Gestion de Procesos](#10-pid-1-y-gestion-de-procesos)
11. [Secuencia de Arranque](#11-secuencia-de-arranque)
12. [Makefile](#12-makefile)
13. [Seguridad](#13-seguridad)
14. [Diferencias entre Entornos](#14-diferencias-entre-entornos)

---

## 1. Arquitectura del Sistema

### Diagrama de Arquitectura (tres niveles)

```
                         Internet / Host
                              |
                         puerto 443
                              |
                   +----------v----------+
                   |       NGINX         |
                   |   (Proxy Inverso)   |
                   |   TLS termination   |
                   |   Archivos estaticos|
                   +----+----------+-----+
                        |          |
           FastCGI :9000|          | Archivos estaticos
           (solo .php)  |          | servidos directamente
                        |          | desde volumen compartido
                   +----v-----+   |
                   | WordPress |   |
                   | PHP-FPM   |   |
                   | :9000     |   |
                   +----+------+
                        |
                   TCP :3306
                        |
                   +----v------+
                   |  MariaDB  |
                   |  :3306    |
                   +-----------+

    [wordpress_data]  <-- volumen compartido entre NGINX y WordPress
    [mariadb_data]    <-- volumen exclusivo de MariaDB
```

### Flujo de Datos Completo

Una peticion HTTP sigue este recorrido:

```
Navegador
  --> HTTPS (puerto 443, TLS 1.2/1.3)
    --> NGINX recibe la peticion
      --> Si es un archivo estatico (.css, .js, .jpg):
            NGINX lo sirve directamente desde /var/www/html
      --> Si es un archivo .php:
            NGINX lo envia via FastCGI a wordpress:9000
              --> PHP-FPM procesa el PHP
                --> WordPress consulta MariaDB via TCP :3306
                --> MariaDB devuelve los datos
              --> PHP-FPM devuelve el HTML renderizado a NGINX
            --> NGINX envia la respuesta al navegador
```

### Justificacion de esta Arquitectura

**Separacion de responsabilidades (separation of concerns):** Cada contenedor tiene una unica funcion. NGINX maneja conexiones de red y TLS. PHP-FPM ejecuta codigo PHP. MariaDB gestiona datos persistentes. Esto permite escalar, actualizar o depurar cada capa de forma independiente.

**Fronteras de seguridad:** Solo NGINX esta expuesto al exterior (puerto 443). WordPress y MariaDB son accesibles unicamente a traves de la red interna Docker. Un atacante que comprometa NGINX no tiene acceso directo a la base de datos; tendria que atravesar primero el contenedor de WordPress.

**Rendimiento:** NGINX es extraordinariamente eficiente sirviendo archivos estaticos. Al separarlo de PHP-FPM, los archivos estaticos (CSS, JS, imagenes) nunca pasan por el interprete PHP, reduciendo la carga en el proceso de WordPress.

---

## 2. Contenedores e Imagenes Docker

### Imagen Base: debian:bookworm

Todos los Dockerfiles usan `debian:bookworm` como imagen base:

```dockerfile
FROM debian:bookworm
```

Se usa **bookworm** (Debian 12) porque es la penultima version estable de Debian. El subject del proyecto exige que la imagen base sea la penultima version estable de Alpine o Debian. Bookworm fue la version estable de Debian durante el desarrollo de este proyecto, por lo que cumple con este requisito.

Razones para elegir Debian sobre Alpine:
- Mejor compatibilidad con paquetes como PHP-FPM y MariaDB
- `glibc` en lugar de `musl`, evitando incompatibilidades sutiles
- Documentacion mas extensa y comunidad mas grande para depuracion

### Buenas Practicas en los Dockerfiles

**Agrupacion de comandos RUN y limpieza de cache:**

```dockerfile
RUN apt-get update && apt-get install -y \
    nginx \
    openssl \
    && rm -rf /var/lib/apt/lists/*
```

Esto crea una unica capa de imagen en lugar de multiples. El `rm -rf /var/lib/apt/lists/*` al final elimina la cache de paquetes descargada por `apt-get update`, reduciendo el tamano de la imagen final. Si `apt-get update` y `apt-get install` estuvieran en capas separadas, Docker podria cachear la capa de `update` y usar una lista de paquetes obsoleta en builds futuros.

**Orden de instrucciones para cache de capas:**

Los Dockerfiles colocan las instrucciones que cambian con menos frecuencia primero (instalacion de paquetes) y las que cambian mas a menudo despues (COPY de archivos de configuracion y scripts). Esto maximiza el aprovechamiento de la cache de capas de Docker, evitando reinstalar paquetes cuando solo se modifica un archivo de configuracion.

**Imagenes minimas:**

Solo se instalan los paquetes estrictamente necesarios. No hay `vim`, `nano`, `curl` (excepto en WordPress donde es necesario para WP-CLI), ni herramientas de depuracion. Esto reduce la superficie de ataque y el tamano de la imagen.

### Nomenclatura de Imagenes

Cada imagen se nombra con la directiva `image:` en `docker-compose.yml`:

```yaml
services:
  nginx:
    image: nginx
  wordpress:
    image: wordpress
  mariadb:
    image: mariadb
```

El nombre de la imagen coincide con el nombre del servicio que ejecuta. Esto es un requisito del subject: cada imagen Docker debe llevar el nombre de su servicio correspondiente.

### .dockerignore

Cada servicio incluye un archivo `.dockerignore`:

```
.git
.gitignore
README.md
```

El proposito del `.dockerignore` es excluir archivos del contexto de build de Docker. Cuando se ejecuta `docker build`, Docker envia el contenido del directorio de contexto al daemon. Sin `.dockerignore`, archivos irrelevantes como `.git`, documentacion o archivos temporales se incluirian en este contexto, aumentando el tiempo de build y potencialmente filtrando informacion sensible a la imagen.

---

## 3. NGINX -- Proxy Inverso y TLS

### Rol en el Sistema

NGINX actua como el unico punto de entrada a la infraestructura. Es el unico contenedor con un puerto publicado al host:

```yaml
ports:
  - "443:443"
```

No hay puerto 80 expuesto. Todas las conexiones deben ser HTTPS. No se implementa redireccion HTTP-->HTTPS porque el puerto 80 ni siquiera esta abierto.

### Generacion del Certificado TLS

El script `setup.sh` de NGINX genera un certificado autofirmado si no existe:

```bash
#!/bin/bash

if [ ! -f /etc/ssl/certs/nginx.crt ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/nginx.key \
        -out /etc/ssl/certs/nginx.crt \
        -subj "/C=ES/ST=Madrid/L=Madrid/O=42Madrid/CN=ravazque.42.fr"
fi

exec "$@"
```

Desglose de los parametros de `openssl`:

| Parametro | Significado |
|-----------|-------------|
| `req -x509` | Genera un certificado autofirmado directamente (sin CSR intermedio) |
| `-nodes` | No cifra la clave privada con passphrase (necesario para que NGINX arranque sin intervencion) |
| `-days 365` | Validez de un ano |
| `-newkey rsa:2048` | Genera una nueva clave RSA de 2048 bits |
| `-keyout` | Ruta donde guardar la clave privada |
| `-out` | Ruta donde guardar el certificado |
| `-subj` | Datos del certificado sin prompt interactivo. CN (Common Name) debe coincidir con el dominio |

La comprobacion `if [ ! -f ... ]` asegura **idempotencia**: si el contenedor se reinicia, no regenera el certificado. Esto es importante porque en un entorno real, regenerar certificados podria causar errores de confianza en los clientes.

### Configuracion TLS

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
```

Se permiten TLS 1.2 y TLS 1.3 exclusivamente. Las versiones anteriores (TLS 1.0 y 1.1) estan excluidas porque:

- **TLS 1.0** (1999): Vulnerable a BEAST, POODLE, y otros ataques. Obsoleto por RFC 8996.
- **TLS 1.1** (2006): Sin mejoras de seguridad significativas sobre 1.0. Tambien obsoleto por RFC 8996.
- **TLS 1.2** (2008): Soporta AEAD (cifrado autenticado), eliminando ataques de padding oracle. Sigue siendo seguro con configuracion adecuada.
- **TLS 1.3** (2018): Handshake simplificado (1-RTT vs 2-RTT), elimina algoritmos inseguros por diseno, soporte para 0-RTT.

El subject del proyecto exige explicitamente TLSv1.2 o TLSv1.3.

### Proxy FastCGI a WordPress

La configuracion de NGINX enruta las peticiones PHP al contenedor de WordPress:

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

**Analisis bloque por bloque:**

- `listen 443 ssl` / `listen [::]:443 ssl`: Escucha en IPv4 e IPv6 en el puerto 443 con SSL habilitado.

- `root /var/www/html`: Raiz del sistema de archivos web. Este directorio esta montado como volumen compartido con WordPress, por lo que NGINX tiene acceso a todos los archivos de WordPress.

- `index index.php index.html`: Orden de prioridad para archivos por defecto.

- `location /`: El bloque `try_files $uri $uri/ /index.php$is_args$args` intenta servir el archivo solicitado directamente. Si no existe, intenta como directorio. Si tampoco, reescribe la peticion a `index.php` (patron necesario para las URLs "bonitas" de WordPress).

- `location ~ \.php$`: Captura todas las peticiones que terminan en `.php`. El `try_files $uri =404` previene que PHP procese archivos inexistentes (proteccion contra ataques de inyeccion de path). `fastcgi_pass wordpress:9000` envia la peticion al contenedor de WordPress via protocolo FastCGI en el puerto 9000. Docker resuelve el nombre `wordpress` a la IP del contenedor automaticamente.

- `fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name`: Dice a PHP-FPM cual es la ruta completa del archivo .php a ejecutar. Sin esto, PHP-FPM no sabria que archivo procesar.

- `fastcgi_read_timeout 300`: Timeout de 300 segundos para respuestas de PHP-FPM. Util para operaciones largas como la instalacion inicial de WordPress.

### Servicio de Archivos Estaticos

NGINX sirve archivos estaticos (.css, .js, .jpg, .png, etc.) directamente desde el volumen compartido `/var/www/html` sin pasar por PHP-FPM. Cuando un navegador solicita `/wp-content/themes/style.css`, la directiva `try_files $uri` lo encuentra en el sistema de archivos y lo devuelve inmediatamente. Solo las peticiones `.php` se envian a WordPress.

### Patron ENTRYPOINT + CMD

```dockerfile
ENTRYPOINT ["/usr/local/bin/setup.sh"]
CMD ["nginx", "-g", "daemon off;"]
```

El ENTRYPOINT ejecuta el script de inicializacion. El CMD proporciona los argumentos por defecto. Dentro de `setup.sh`, la linea `exec "$@"` reemplaza el proceso del shell con el comando especificado en CMD. El flujo es:

```
PID 1: /usr/local/bin/setup.sh nginx -g "daemon off;"
  --> genera certificado si falta
  --> exec "$@"
  --> PID 1: nginx -g "daemon off;"  (el shell ya no existe)
```

---

## 4. WordPress y PHP-FPM

### PHP-FPM como Gestor de Procesos FastCGI

PHP-FPM (FastCGI Process Manager) es la forma estandar de ejecutar PHP detras de un servidor web como NGINX. Las alternativas y por que no se usan:

- **mod_php**: Modulo de Apache que ejecuta PHP dentro del proceso de Apache. Requiere Apache, que aqui no se usa. Cada peticion consume un proceso de Apache completo.
- **Apache + mod_php**: Haria que NGINX fuera redundante y violaria la separacion de responsabilidades.
- **PHP CLI server**: Solo para desarrollo, un unico hilo, sin capacidad de produccion.

PHP-FPM mantiene un pool de procesos PHP listos para atender peticiones. Un proceso maestro gestiona los workers y los recicla cuando consumen demasiada memoria.

### Configuracion del Pool (www.conf)

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

**`listen = 0.0.0.0:9000`** -- Se usa un socket TCP en lugar de un socket Unix. La razon es que NGINX y PHP-FPM estan en contenedores diferentes. Los sockets Unix (`/var/run/php/php-fpm.sock`) solo funcionan cuando los procesos comparten el mismo sistema de archivos. Los contenedores Docker tienen sistemas de archivos aislados, asi que la comunicacion debe ser por red TCP.

`0.0.0.0` (todas las interfaces) es necesario porque dentro de un contenedor, la interfaz de red tiene una IP asignada por Docker que puede cambiar. Escuchar en todas las interfaces garantiza que PHP-FPM acepte conexiones sin importar la IP asignada.

**`pm = dynamic`** -- Modo de gestion de procesos. Los tres modos son:
- `static`: Numero fijo de workers siempre activos
- `dynamic`: Workers se crean/destruyen segun demanda (equilibrio entre rendimiento y recursos)
- `ondemand`: Workers se crean solo cuando llega una peticion (minimo uso de memoria, mayor latencia)

Los parametros `pm.max_children = 5`, `pm.start_servers = 2`, `pm.min_spare_servers = 1`, `pm.max_spare_servers = 3` definen que al arrancar habra 2 workers, se mantendran entre 1 y 3 workers libres, y nunca habra mas de 5 simultaneos.

**`clear_env = no`** -- Esta directiva es critica. Por defecto, PHP-FPM limpia todas las variables de entorno antes de pasar el control a los scripts PHP. Esto significa que las variables definidas en `env_file` del docker-compose (como `DOMAIN_NAME`, `MYSQL_DATABASE`, etc.) no serian accesibles desde PHP. Con `clear_env = no`, las variables de entorno del proceso padre se heredan a los workers PHP, permitiendo que `setup.sh` y los scripts PHP accedan a las variables de configuracion.

### Dockerfile de WordPress

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

**Paquetes PHP instalados:**
- `php8.2-fpm`: El gestor de procesos FastCGI
- `php8.2-mysqli`: Extension para conectar con MySQL/MariaDB
- `php8.2-curl`: Peticiones HTTP desde PHP (necesario para actualizaciones de plugins)
- `php8.2-dom`: Manipulacion de XML/HTML
- `php8.2-exif`: Lectura de metadatos de imagenes
- `php8.2-mbstring`: Soporte de strings multibyte (UTF-8)
- `php8.2-xml`: Parser XML
- `php8.2-zip`: Compresion/descompresion (necesario para plugins)
- `php8.2-imagick`: Procesamiento de imagenes
- `curl`: Necesario para descargar WP-CLI
- `mariadb-client`: Proporciona el comando `mariadb` usado en `setup.sh` para comprobar la disponibilidad de la base de datos

**WP-CLI:** Se descarga como archivo `.phar` (PHP Archive) y se instala como comando global `/usr/local/bin/wp`. WP-CLI permite administrar WordPress completamente desde la linea de comandos, sin necesidad de un navegador web. Esto hace posible la instalacion automatizada y no interactiva.

**`mkdir -p /run/php`**: PHP-FPM necesita este directorio para su archivo PID. Sin el, PHP-FPM falla al arrancar.

**`WORKDIR /var/www/html`**: Establece el directorio de trabajo para los comandos siguientes y para el ENTRYPOINT. Los comandos `wp` en `setup.sh` operan sobre este directorio.

Notar que no hay CMD. El ENTRYPOINT es `setup.sh`, que termina con `exec php-fpm8.2 -F`, por lo que el proceso final se especifica directamente en el script.

### Script de Inicializacion (setup.sh)

```bash
#!/bin/bash

# Leer contrasenas de Docker secrets
MYSQL_PASSWORD=$(cat /run/secrets/db_password)
WP_ADMIN_PASSWORD=$(head -n 1 /run/secrets/credentials)
WP_USER_PASSWORD=$(sed -n '2p' /run/secrets/credentials)

# Esperar a que MariaDB este lista
echo "Esperando a MariaDB..."
while ! mariadb -h mariadb -u${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE} -e "SELECT 1" &>/dev/null; do
    sleep 2
done
echo "MariaDB lista!"

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

**Flujo detallado:**

1. **Lectura de secrets:** Las contrasenas se leen de archivos en `/run/secrets/`. `cat` lee el archivo completo, `head -n 1` la primera linea, y `sed -n '2p'` la segunda linea. Esto evita que las contrasenas aparezcan en variables de entorno del contenedor (que serian visibles con `docker inspect`).

2. **Espera de MariaDB:** El bucle `while ! mariadb ... sleep 2` intenta conectarse a MariaDB cada 2 segundos hasta que tiene exito. Esto es necesario porque `depends_on` de Docker Compose solo garantiza que el contenedor de MariaDB se haya **iniciado**, no que el servicio de base de datos este listo para aceptar conexiones. El comando `mariadb -h mariadb -u... -p... database -e "SELECT 1"` verifica una conexion real a la base de datos con las credenciales correctas.

   Este bucle **no es un bucle infinito prohibido**. Tiene una condicion de salida clara: la conexion a MariaDB tiene exito y el bucle termina. Un bucle infinito prohibido seria algo como `while true; do sleep 1; done` como PID 1, donde no hay proceso util ejecutandose.

3. **Idempotencia:** La comprobacion `if [ ! -f /var/www/html/wp-config.php ]` asegura que WordPress solo se instala una vez. Si el contenedor se reinicia y los datos persisten en el volumen, el script salta directamente a `exec php-fpm8.2 -F`.

4. **Instalacion de WordPress con WP-CLI:**
   - `wp core download`: Descarga los archivos core de WordPress en `/var/www/html`
   - `wp config create`: Genera `wp-config.php` con los datos de conexion a la base de datos. `--dbhost=mariadb` usa el nombre del contenedor, que Docker resuelve via DNS interno
   - `wp core install`: Ejecuta la instalacion de WordPress (crea tablas en la base de datos, configura el sitio). `--skip-email` evita intentar enviar un email de notificacion
   - `wp user create`: Crea un segundo usuario con rol de autor. El usuario administrador no puede llamarse "admin" (requisito del subject)

   El flag `--allow-root` es necesario porque el script se ejecuta como root dentro del contenedor. WP-CLI normalmente se niega a ejecutarse como root por seguridad, pero en un contenedor es el unico usuario disponible antes de configurar los permisos.

5. **Permisos:** `chown -R www-data:www-data /var/www/html` asigna propiedad de todos los archivos al usuario `www-data`, que es el usuario bajo el que corren los workers de PHP-FPM (configurado en `www.conf`).

6. **Proceso final:** `exec php-fpm8.2 -F` reemplaza el shell con PHP-FPM en modo foreground. El flag `-F` fuerza el modo primer plano, necesario para que PHP-FPM sea PID 1 y el contenedor permanezca activo.

---

## 5. MariaDB

### Rol en el Sistema

MariaDB es el servidor de base de datos relacional. Almacena todo el contenido de WordPress: posts, usuarios, configuracion, comentarios, etc. Solo es accesible desde la red interna Docker, nunca desde el host.

### Dockerfile

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

- `mariadb-server`: El servidor de base de datos
- `mariadb-client`: Herramientas cliente (`mysql`, `mysqladmin`) usadas en el script de setup
- `/var/run/mysqld`: Directorio para el socket Unix y archivo PID de MariaDB. Debe existir y ser propiedad del usuario `mysql`

### Configuracion (50-server.cnf)

```ini
[mysqld]
datadir         = /var/lib/mysql
socket          = /var/run/mysqld/mysqld.sock
port            = 3306
bind-address    = 0.0.0.0
```

**`bind-address = 0.0.0.0`** -- Por defecto, MariaDB solo escucha en `127.0.0.1` (localhost). Dentro de un contenedor, localhost significa "dentro de este mismo contenedor". El contenedor de WordPress necesita conectarse desde una IP diferente (la que Docker le asigna en la red `inception`). Con `0.0.0.0`, MariaDB acepta conexiones en todas las interfaces de red, incluyendo la interfaz virtual de la red Docker.

**`datadir = /var/lib/mysql`** -- Este directorio esta respaldado por el volumen `mariadb_data`, asi que los datos persisten entre reinicios del contenedor.

**`socket = /var/run/mysqld/mysqld.sock`** -- Socket Unix para conexiones locales (usado por el script de setup). No es accesible desde otros contenedores; la comunicacion entre contenedores usa TCP en el puerto 3306.

### Script de Inicializacion (setup.sh)

```bash
#!/bin/bash

# Leer contrasenas de Docker secrets
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

**Flujo detallado:**

1. **Lectura de secrets:** Dos contrasenas se leen desde archivos en `/run/secrets/`:
   - `db_password`: Contrasena del usuario de la base de datos (usado por WordPress para conectarse)
   - `db_root_password`: Contrasena del usuario root de MariaDB

2. **Instancia temporal:** `mysqld_safe &` arranca MariaDB en segundo plano. El `sleep 5` da tiempo a que el servidor este listo para aceptar conexiones. Esta instancia temporal permite ejecutar comandos SQL para configurar la base de datos.

3. **Idempotencia:** `if ! mysql -e "USE ${MYSQL_DATABASE}"` comprueba si la base de datos ya existe. Si ya existe (por ejemplo, porque los datos persisten en el volumen desde un arranque anterior), todo el bloque de creacion se salta. Esto evita errores por intentar crear recursos duplicados y hace el script seguro para reinicios.

4. **Configuracion de la base de datos:**
   - `CREATE DATABASE`: Crea la base de datos de WordPress
   - `CREATE USER ... '@'%'`: Crea el usuario con acceso desde cualquier host (`%`). Esto es necesario porque WordPress se conecta desde la IP del contenedor, que puede variar
   - `GRANT ALL PRIVILEGES`: Da al usuario permisos completos sobre la base de datos de WordPress (y solo esa base de datos)
   - `FLUSH PRIVILEGES`: Recarga la tabla de permisos para que los cambios surtan efecto inmediatamente
   - `ALTER USER 'root'@'localhost'`: Establece la contrasena de root, que por defecto esta vacia en MariaDB de Debian

5. **Cierre de instancia temporal:** `mysqladmin shutdown` detiene la instancia temporal de forma limpia.

6. **Proceso final:** `exec mysqld_safe` reemplaza el shell con MariaDB como proceso permanente. `mysqld_safe` es un wrapper que reinicia el servidor si este se cae inesperadamente, proporcionando una capa adicional de resiliencia.

---

## 6. Docker Compose y Orquestacion

### Archivo docker-compose.yml Completo

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

### Ausencia de la Clave `version:`

El archivo no incluye la directiva `version: "3.x"` que aparece en ejemplos antiguos. Desde Docker Compose V2, la clave `version` esta obsoleta y se ignora. Compose V2 (el que se invoca con `docker compose` en lugar de `docker-compose`) determina automaticamente las funciones disponibles. Incluir `version:` genera un warning de deprecacion.

### Definicion de Servicios

**`container_name`**: Fija el nombre del contenedor. Sin esto, Docker Compose generaria nombres como `srcs-nginx-1`. Nombres fijos facilitan la depuracion y la resolucion DNS interna.

**`build`**: Ruta relativa al directorio que contiene el Dockerfile. Docker Compose construye la imagen desde ahi.

**`image`**: Nombre que se asigna a la imagen construida. Combinar `build` e `image` hace que Docker Compose construya la imagen y le asigne el nombre especificado.

### depends_on

```yaml
nginx:
  depends_on:
    - wordpress

wordpress:
  depends_on:
    - mariadb
```

Esto crea una cadena de dependencias: mariadb --> wordpress --> nginx. Docker Compose arrancara los contenedores en este orden. Sin embargo, `depends_on` solo controla el **orden de inicio de los contenedores**, no espera a que el servicio dentro del contenedor este listo. Por eso el script de WordPress incluye su propio bucle de espera para MariaDB.

### env_file vs environment vs secrets

Tres mecanismos diferentes para pasar configuracion a los contenedores:

**`env_file: .env`** -- Carga variables de entorno desde un archivo. Se usa para datos no sensibles como nombres de dominio, nombres de bases de datos, emails, etc. Estas variables son visibles con `docker inspect`.

```
DOMAIN_NAME=ravazque.42.fr
MYSQL_DATABASE=ravazquedb
MYSQL_USER=ravazque
WP_TITLE=RavazquePage
WP_ADMIN_USER=ravazque_wp
WP_ADMIN_EMAIL=ravazque@student.42madrid.fr
WP_USER=ravazque
WP_USER_EMAIL=rk.raul1306@gmail.com
SECRETS_DIR=../secrets
```

**`environment:`** -- Variables de entorno definidas directamente en el compose. No se usa en este proyecto para evitar mezclar datos de configuracion entre el archivo .env y el compose.

**`secrets:`** -- Mecanismo seguro para datos sensibles. Los secrets se montan como archivos en `/run/secrets/` dentro del contenedor, no como variables de entorno. Detallado en la seccion 9.

### restart: always

```yaml
restart: always
```

Politica de reinicio `always` significa:
- Si el contenedor se detiene por cualquier razon (crash, error, OOM kill), Docker lo reinicia automaticamente
- Tambien se reinicia cuando el daemon de Docker arranca (por ejemplo, tras un reinicio del sistema)
- La unica forma de detenerlo permanentemente es ejecutar `docker stop` explicitamente

Otras politicas de reinicio (no usadas aqui):
- `no`: Nunca reiniciar (defecto)
- `on-failure`: Solo reiniciar si el proceso sale con codigo de error no-cero
- `unless-stopped`: Como `always`, pero no reinicia si fue detenido manualmente antes de que Docker se reiniciara

---

## 7. Red Docker (Docker Network)

### Red Bridge Definida por el Usuario

```yaml
networks:
  inception:
    driver: bridge
```

Se crea una red bridge personalizada llamada `inception`. Todos los contenedores se conectan a esta red:

```yaml
services:
  nginx:
    networks:
      - inception
  wordpress:
    networks:
      - inception
  mariadb:
    networks:
      - inception
```

### Resolucion DNS Interna

En una red bridge definida por el usuario, Docker proporciona un servidor DNS embebido que resuelve nombres de contenedor a direcciones IP. Esto permite que:

- NGINX se conecte a `wordpress:9000` (el `fastcgi_pass wordpress:9000` en nginx.conf)
- WordPress se conecte a `mariadb:3306` (el `--dbhost=mariadb` en wp-config.php)

No es necesario conocer ni hardcodear direcciones IP. Si Docker reasigna una IP diferente a un contenedor tras un reinicio, la resolucion DNS se actualiza automaticamente.

### Por que NO se usa Host Network

```yaml
# INCORRECTO - no usar:
network_mode: host
```

La red `host` elimina el aislamiento de red del contenedor. El contenedor comparte la pila de red del host directamente. Esto es problematico porque:

1. **Sin aislamiento:** Todos los puertos del contenedor son accesibles directamente en el host. MariaDB (3306) quedaria expuesta al exterior.
2. **Conflictos de puertos:** Si el host ya tiene un servicio en el puerto 443 o 3306, habria conflicto.
3. **Sin DNS interno:** Los contenedores no pueden resolverse entre si por nombre.
4. **Viola el principio de minimo privilegio:** Solo el puerto 443 debe ser accesible desde fuera.

### Por que NO se usa `links:`

```yaml
# OBSOLETO - no usar:
links:
  - mariadb
```

La directiva `links:` es una funcionalidad heredada de Docker Compose V1 que esta deprecada. En redes bridge definidas por el usuario, la resolucion DNS es automatica y `links:` es completamente innecesario. Ademas, `links:` solo funciona de forma unidireccional y no proporciona ninguna funcionalidad que las redes definidas por el usuario no ofrezcan ya.

### Unico Puerto Expuesto

```yaml
nginx:
  ports:
    - "443:443"
```

Solo NGINX publica un puerto al host. Los contenedores de WordPress y MariaDB no tienen directiva `ports:`, por lo que son accesibles unicamente desde dentro de la red `inception`. Aunque declaran `EXPOSE 9000` y `EXPOSE 3306` en sus Dockerfiles, la instruccion `EXPOSE` es puramente documentativa; no abre puertos. Solo `ports:` en el compose realmente mapea puertos al host.

---

## 8. Volumenes y Persistencia

### Volumenes Nombrados vs Bind Mounts

Docker ofrece dos mecanismos principales de persistencia:

**Volumenes nombrados (`docker volume create`):** Gestionados por Docker. Se almacenan en `/var/lib/docker/volumes/`. Docker controla su ciclo de vida.

**Bind mounts (`-v /host/path:/container/path`):** Montan un directorio del host directamente en el contenedor. El host controla su ciclo de vida.

### Enfoque Hibrido con driver_opts

Este proyecto usa un enfoque hibrido: volumenes nombrados con driver local configurados para montar un directorio del host:

```yaml
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
```

Este enfoque combina las ventajas de ambos:
- **Es un volumen nombrado:** Docker lo gestiona como volumen, puede listarse con `docker volume ls`, tiene nombre fijo
- **Los datos estan en un directorio conocido del host:** Los archivos viven en `/home/ravazque/data/`, no en las profundidades de `/var/lib/docker/volumes/`

Los `driver_opts` especifican:
- `type: none` -- No usar un sistema de archivos especial (como NFS o CIFS); usar el sistema de archivos local
- `device: /home/ravazque/data/wordpress` -- Ruta del directorio en el host
- `o: bind` -- Operacion de montaje: bind mount

### Volumen wordpress_data

```yaml
nginx:
  volumes:
    - wordpress_data:/var/www/html

wordpress:
  volumes:
    - wordpress_data:/var/www/html
```

Este volumen es **compartido** entre NGINX y WordPress. Ambos contenedores ven el mismo contenido en `/var/www/html`. Esto es necesario porque:
- WordPress escribe los archivos PHP, temas y plugins en este directorio
- NGINX necesita acceso a estos archivos para servir contenido estatico directamente y para encontrar los archivos .php que envia a PHP-FPM

En el host, los datos residen en `/home/ravazque/data/wordpress`.

### Volumen mariadb_data

```yaml
mariadb:
  volumes:
    - mariadb_data:/var/lib/mysql
```

Este volumen es **exclusivo** de MariaDB. Contiene los archivos binarios de la base de datos (tablas InnoDB, logs de transacciones, etc.). En el host, los datos residen en `/home/ravazque/data/mysql`.

### Ciclo de Vida de los Datos

| Operacion | Efecto en los datos |
|-----------|-------------------|
| `docker compose down` | Contenedores destruidos, volumenes **persisten** |
| `docker compose up` | Nuevos contenedores, montan los volumenes existentes con los datos anteriores |
| `docker compose down -v` | Contenedores destruidos, volumenes **eliminados** |
| `make clean` | `down` + prune + elimina volumenes Docker |
| `make fclean` | `clean` + elimina contenido de `/home/ravazque/data/` |

Solo `make fclean` (o eliminar manualmente los directorios en `/home/ravazque/data/`) borra los datos completamente. Esto significa que se puede detener y reiniciar la infraestructura sin perder el contenido de WordPress ni la base de datos.

---

## 9. Docker Secrets

### Que Son los Docker Secrets

Los Docker secrets son un mecanismo para pasar datos sensibles a los contenedores de forma segura. En Docker Compose (sin Swarm mode), los secrets se implementan como archivos montados en `/run/secrets/` dentro del contenedor. El directorio `/run/secrets/` es un sistema de archivos tmpfs (en memoria), lo que significa que los secrets **nunca se escriben en disco** dentro del contenedor.

### Diferencia con Variables de Entorno

| Caracteristica | Variables de Entorno | Docker Secrets |
|---------------|---------------------|----------------|
| Visibilidad | `docker inspect` las muestra | No aparecen en `docker inspect` |
| Herencia | Procesos hijos las heredan | Solo accesibles leyendo el archivo |
| Almacenamiento | En la metadata del contenedor | En tmpfs (memoria) |
| Logs | Pueden filtrarse en logs de error | Solo accesibles explicitamente |
| Acceso | `$VARIABLE` o `getenv()` | Leer archivo `/run/secrets/nombre` |

### Declaracion en docker-compose.yml

Primero se declaran a nivel global con la ruta al archivo fuente:

```yaml
secrets:
  db_password:
    file: ../secrets/db_password.txt
  db_root_password:
    file: ../secrets/db_root_password.txt
  credentials:
    file: ../secrets/credentials.txt
```

Luego, cada servicio indica que secrets necesita:

```yaml
wordpress:
  secrets:
    - db_password
    - credentials

mariadb:
  secrets:
    - db_password
    - db_root_password
```

Notar que cada servicio solo recibe los secrets que necesita. WordPress no tiene acceso a `db_root_password` porque no lo necesita. Este es el principio de minimo privilegio aplicado a los secrets.

### Archivos de Secrets

Tres archivos en el directorio `secrets/`:

**`db_password.txt`** -- Contiene la contrasena del usuario de la base de datos (una sola linea). Usado por WordPress para conectarse a MariaDB y por MariaDB para crear el usuario.

**`db_root_password.txt`** -- Contiene la contrasena de root de MariaDB (una sola linea). Solo usado por MariaDB durante la inicializacion.

**`credentials.txt`** -- Contiene dos lineas:
- Linea 1: Contrasena del administrador de WordPress
- Linea 2: Contrasena del usuario regular de WordPress

### Consumo en los Scripts

En el setup.sh de MariaDB:
```bash
MYSQL_PASSWORD=$(cat /run/secrets/db_password)
MYSQL_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)
```

En el setup.sh de WordPress:
```bash
MYSQL_PASSWORD=$(cat /run/secrets/db_password)
WP_ADMIN_PASSWORD=$(head -n 1 /run/secrets/credentials)
WP_USER_PASSWORD=$(sed -n '2p' /run/secrets/credentials)
```

Los secrets se leen una vez al inicio del script y se almacenan en variables locales del shell. Estas variables solo existen durante la ejecucion del script y desaparecen cuando `exec` reemplaza el shell con el proceso final (PHP-FPM o mysqld_safe).

---

## 10. PID 1 y Gestion de Procesos

### Por que PID 1 es Especial en Contenedores

En un sistema Linux, el proceso con PID 1 tiene responsabilidades especiales:

1. **Manejo de senales:** Cuando Docker ejecuta `docker stop`, envia SIGTERM al PID 1. Si PID 1 no maneja SIGTERM, Docker espera un timeout (por defecto 10 segundos) y luego envia SIGKILL, causando un cierre abrupto. Un cierre limpio es critico para MariaDB (para que complete las transacciones pendientes) y para PHP-FPM (para que termine las peticiones en curso).

2. **Reaping de procesos zombie:** Cuando un proceso hijo termina, su entrada en la tabla de procesos permanece hasta que el proceso padre llama a `wait()`. Si PID 1 no implementa `wait()`, los procesos zombie se acumulan. `nginx`, `php-fpm` y `mysqld_safe` manejan correctamente sus procesos hijos. Un shell bash como PID 1 **no** reapea zombies de forma predeterminada.

3. **Terminacion del contenedor:** Si PID 1 muere, el contenedor se detiene. Por eso el proceso principal debe ejecutarse en primer plano, no como daemon.

### El Operador `exec` en Bash

Todos los scripts de setup terminan con `exec`:

```bash
# NGINX
exec "$@"

# WordPress
exec php-fpm8.2 -F

# MariaDB
exec mysqld_safe
```

El comando `exec` en bash **reemplaza** el proceso del shell con el nuevo proceso. Sin `exec`:

```
PID 1: bash setup.sh
  PID 2: nginx -g "daemon off;"
```

El shell permaneceria como PID 1 y nginx seria un proceso hijo. Las senales de Docker irian al shell, no a nginx. Con `exec`:

```
PID 1: nginx -g "daemon off;"
```

El shell ya no existe. nginx es PID 1 directamente y recibe las senales de Docker.

### NGINX: ENTRYPOINT + CMD con exec "$@"

```dockerfile
ENTRYPOINT ["/usr/local/bin/setup.sh"]
CMD ["nginx", "-g", "daemon off;"]
```

Docker combina ENTRYPOINT y CMD en un unico comando: `/usr/local/bin/setup.sh nginx -g "daemon off;"`. Dentro de `setup.sh`, `$@` contiene `nginx -g "daemon off;"`. La linea `exec "$@"` se expande a `exec nginx -g "daemon off;"`, reemplazando el shell con NGINX.

`daemon off;` es la directiva de NGINX que le indica ejecutarse en primer plano. Sin ella, NGINX se demoniza (se bifurca al background y el proceso padre termina), lo que haria que el contenedor se detenga inmediatamente.

### WordPress: exec php-fpm8.2 -F

```bash
exec php-fpm8.2 -F
```

El flag `-F` (foreground) de PHP-FPM tiene el mismo efecto que `daemon off;` en NGINX: ejecuta el proceso en primer plano. Sin `-F`, PHP-FPM se demonizaria y el contenedor terminaria.

### MariaDB: exec mysqld_safe

```bash
exec mysqld_safe
```

`mysqld_safe` es un wrapper de MariaDB que:
- Ejecuta `mysqld` (el servidor real) como proceso hijo
- Monitoriza el proceso y lo reinicia si se cae
- Registra errores en el log
- Se ejecuta en primer plano por defecto

### Patrones Prohibidos

Los siguientes patrones no deben usarse como PID 1 porque no manejan senales, no reapean zombies, o no realizan trabajo util:

```bash
# NO HACER:
tail -f /dev/null          # Proceso inutil, no maneja senales
bash                       # Shell interactivo como PID 1
sleep infinity             # No hace nada util
while true; do sleep 1; done  # Bucle infinito sin proposito
```

Estos patrones son "hacks" para mantener un contenedor vivo sin un proceso principal real. El proceso PID 1 debe ser el servicio que el contenedor proporciona.

---

## 11. Secuencia de Arranque

### Paso a Paso: Que Sucede al Ejecutar `make`

```
$ make
```

equivale a `make all`, que equivale a `make up`.

**Paso 1: Creacion de directorios del host**

```makefile
@mkdir -p /home/ravazque/data/wordpress
@mkdir -p /home/ravazque/data/mysql
```

Se crean los directorios donde los volumenes almacenaran datos. `-p` evita errores si ya existen. Estos directorios deben existir antes de que Docker intente montar los volumenes.

**Paso 2: Docker Compose build y start**

```makefile
@docker compose -f srcs/docker-compose.yml --env-file srcs/.env up -d --build
```

- `-f srcs/docker-compose.yml`: Ruta al archivo compose
- `--env-file srcs/.env`: Carga las variables de entorno
- `up`: Crea y arranca los contenedores
- `-d`: Modo detached (devuelve el control a la terminal)
- `--build`: Fuerza la reconstruccion de las imagenes

**Paso 3: Build de imagenes (si necesario)**

Docker Compose construye las tres imagenes en paralelo si es posible:
1. `nginx` desde `srcs/requirements/nginx/Dockerfile`
2. `wordpress` desde `srcs/requirements/wordpress/Dockerfile`
3. `mariadb` desde `srcs/requirements/mariadb/Dockerfile`

Si las imagenes ya existen y el contexto no ha cambiado, Docker usa las capas cacheadas.

**Paso 4: MariaDB arranca (sin dependencias)**

MariaDB no tiene `depends_on`, asi que arranca inmediatamente.

```
mariadb setup.sh:
  1. Lee secrets de /run/secrets/
  2. Arranca instancia temporal (mysqld_safe &)
  3. Espera 5 segundos
  4. Si la DB no existe: CREATE DATABASE, CREATE USER, GRANT, ALTER root
  5. Cierra instancia temporal
  6. exec mysqld_safe (proceso final, PID 1)
```

**Paso 5: WordPress espera a MariaDB, luego instala**

WordPress depende de MariaDB (`depends_on: mariadb`), asi que Docker espera a que el contenedor de MariaDB se haya **creado** antes de crear el de WordPress.

```
wordpress setup.sh:
  1. Lee secrets de /run/secrets/
  2. Bucle: intenta conectar a mariadb:3306 cada 2 segundos
  3. Cuando MariaDB responde: sale del bucle
  4. Si wp-config.php no existe:
     a. wp core download
     b. wp config create (genera wp-config.php)
     c. wp core install (crea tablas, configura sitio)
     d. wp user create (crea usuario adicional)
  5. chown -R www-data:www-data /var/www/html
  6. exec php-fpm8.2 -F (proceso final, PID 1)
```

**Paso 6: NGINX arranca tras WordPress**

NGINX depende de WordPress (`depends_on: wordpress`), asi que Docker espera a que el contenedor de WordPress se haya creado.

```
nginx setup.sh:
  1. Si el certificado TLS no existe: genera uno con openssl
  2. exec "$@" --> exec nginx -g "daemon off;" (proceso final, PID 1)
```

### Diagrama Temporal

```
t=0s    docker compose up --build
        |
t=1s    [MariaDB]  setup.sh comienza
        [Build]    Imagenes se construyen si necesario
        |
t=2s    [MariaDB]  mysqld_safe & (instancia temporal)
        |
t=7s    [MariaDB]  CREATE DATABASE, CREATE USER, etc.
        [MariaDB]  shutdown instancia temporal
        [MariaDB]  exec mysqld_safe (servicio listo)
        |
t=8s    [WordPress] setup.sh comienza
        [WordPress] Esperando a MariaDB...
        |
t=10s   [WordPress] MariaDB lista!
        [WordPress] wp core download...
        |
t=20s   [WordPress] wp config create, wp core install...
        |
t=30s   [WordPress] exec php-fpm8.2 -F (servicio listo)
        |
t=31s   [NGINX]     setup.sh comienza
        [NGINX]     Genera certificado TLS (si necesario)
        [NGINX]     exec nginx -g "daemon off;" (servicio listo)
        |
t=32s   Sistema completamente operativo
        https://ravazque.42.fr accesible
```

Los tiempos son aproximados y varian segun el hardware y la red.

---

## 12. Makefile

### Archivo Completo

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

### Targets Explicados

| Target | Descripcion |
|--------|-------------|
| `all` | Target por defecto. Llama a `up` |
| `up` | Crea directorios de datos, construye imagenes y arranca contenedores |
| `down` | Detiene y elimina contenedores, redes. Los volumenes persisten |
| `stop` | Detiene contenedores sin eliminarlos. Se pueden reanudar con `start` |
| `start` | Reanuda contenedores previamente detenidos con `stop` |
| `logs` | Muestra logs en tiempo real de todos los contenedores (`-f` = follow) |
| `clean` | Ejecuta `down`, luego elimina todas las imagenes no usadas y todos los volumenes Docker |
| `fclean` | Ejecuta `clean`, luego elimina los datos persistidos en el host |
| `re` | Rebuild completo: `fclean` seguido de `all` |

### Prefijo `@` en los Comandos

```makefile
@docker compose -f srcs/docker-compose.yml --env-file srcs/.env up -d --build
```

El `@` al inicio suprime el echo del comando. Por defecto, Make imprime cada comando antes de ejecutarlo. Con `@`, solo se muestra la salida del comando, no el comando en si. Esto produce una salida mas limpia.

### `sudo` en fclean

```makefile
@sudo rm -rf /home/ravazque/data/wordpress/*
@sudo rm -rf /home/ravazque/data/mysql/*
```

Los archivos dentro de los directorios de datos pueden ser propiedad de usuarios del contenedor (como `www-data` o `mysql`). Estos usuarios son mapeados a UIDs especificos (como 33 para www-data, 999 para mysql) que el usuario actual del host puede no tener permiso para eliminar. `sudo` garantiza los permisos necesarios.

### `$$` en la Variable de Shell

```makefile
@docker volume rm $$(docker volume ls -q) 2>/dev/null || true
```

En Makefiles, `$` tiene significado especial (referencia a variables de Make). Para pasar un `$` literal al shell, se escribe `$$`. Asi, `$$(docker volume ls -q)` se traduce a `$(docker volume ls -q)` en el shell, que es una sustitucion de comando. El `2>/dev/null || true` ignora errores si no hay volumenes que eliminar.

### `.PHONY`

```makefile
.PHONY: all up down stop start logs clean fclean re
```

Declara que estos targets no son archivos. Sin `.PHONY`, si existiera un archivo llamado `clean` en el directorio, Make pensaria que el target ya esta actualizado y no ejecutaria las recetas.

---

## 13. Seguridad

### Contrasenas Fuera de los Dockerfiles

Ningun Dockerfile contiene contrasenas, tokens, o datos sensibles. Las contrasenas se pasan exclusivamente a traves del mecanismo de Docker secrets. Esto significa que:
- Las imagenes Docker pueden compartirse sin exponer credenciales
- El historial de Git no contiene contrasenas (con la excepcion del directorio `secrets/`, que en un entorno real deberia estar en `.gitignore`)
- `docker inspect` no revela contrasenas

### Contrasenas Fuera de Variables de Entorno

El archivo `.env` contiene solo datos no sensibles:

```
DOMAIN_NAME=ravazque.42.fr
MYSQL_DATABASE=ravazquedb
MYSQL_USER=ravazque
WP_TITLE=RavazquePage
WP_ADMIN_USER=ravazque_wp
WP_ADMIN_EMAIL=ravazque@student.42madrid.fr
WP_USER=ravazque
WP_USER_EMAIL=rk.raul1306@gmail.com
SECRETS_DIR=../secrets
```

Ninguna contrasena aparece aqui. Las contrasenas estan exclusivamente en los archivos de secrets, que se montan como archivos en `/run/secrets/` dentro de los contenedores.

### TLS 1.2+ Exclusivamente

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
```

Se rechazan conexiones con TLS 1.0 y 1.1, que tienen vulnerabilidades conocidas. Esto cumple con el requisito del subject y con las buenas practicas de la industria (PCI DSS, por ejemplo, requiere TLS 1.2 minimo).

### Aislamiento de Red

Solo el puerto 443 de NGINX es accesible desde el host. WordPress (9000) y MariaDB (3306) son inaccesibles desde fuera de la red Docker `inception`. Un atacante externo solo puede interactuar con NGINX.

### Username del Admin

```
WP_ADMIN_USER=ravazque_wp
```

El nombre de usuario del administrador de WordPress no contiene la palabra "admin". Esto es un requisito del subject, pero tambien una practica de seguridad razonable: los ataques de fuerza bruta comunmente prueban "admin" como nombre de usuario.

### .gitignore

```
docs/subject.pdf
.vscode/
.idea/
*.swp
*.swo
*~
.DS_Store
*.log
```

Excluye archivos de editores, sistema operativo, y logs que podrian contener informacion sensible.

---

## 14. Diferencias entre Entornos

### CachyOS (Entorno de Desarrollo)

El desarrollo de este proyecto se realiza en **CachyOS**, una distribucion basada en Arch Linux con kernel optimizado (linux-cachyos-lts). Particularidades:

**Sistema de archivos Btrfs y Copy-on-Write (CoW):**

Btrfs usa CoW por defecto, lo que significa que cada escritura crea una nueva copia del bloque de datos. Esto es problematico para bases de datos como MariaDB que realizan muchas escrituras pequenas y aleatorias, causando fragmentacion severa y degradacion del rendimiento.

Solucion:
```bash
chattr +C /home/ravazque/data/mysql
```

El atributo `+C` (NoCow) desactiva Copy-on-Write para ese directorio. Los archivos creados dentro heredan este atributo. Esto debe hacerse **antes** de que MariaDB escriba datos, idealmente cuando el directorio esta vacio.

Para verificar:
```bash
lsattr /home/ravazque/data/
```

La salida debe mostrar `C` para el directorio mysql:
```
---------------C-- /home/ravazque/data/mysql
```

**IP Forwarding:**

Docker necesita IP forwarding habilitado para enrutar paquetes entre contenedores y hacia el exterior:

```bash
sudo sysctl net.ipv4.ip_forward=1
```

Para hacerlo persistente:
```bash
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-docker.conf
sudo sysctl --system
```

En CachyOS/Arch, esto no siempre esta habilitado por defecto, a diferencia de distribuciones como Ubuntu donde Docker lo configura automaticamente.

**Resolucion DNS del dominio:**

El dominio `ravazque.42.fr` debe resolver a la maquina local. En `/etc/hosts`:

```
127.0.0.1   ravazque.42.fr
```

### Arch VM (Entorno de Despliegue/Evaluacion)

Para la evaluacion, el proyecto se despliega en una maquina virtual con Arch Linux:

**Sistema de archivos ext4:**

ext4 no usa CoW, asi que no es necesario el `chattr +C`. El rendimiento de MariaDB es normal sin configuracion adicional.

**Docker setup identico:**

La instalacion y configuracion de Docker es la misma que en CachyOS:
```bash
sudo pacman -S docker docker-compose
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```

### Que es Portable y Que Necesita Configuracion Local

**Portable (funciona en cualquier entorno sin cambios):**
- Todos los Dockerfiles (`srcs/requirements/*/Dockerfile`)
- Archivos de configuracion (`nginx.conf`, `www.conf`, `50-server.cnf`)
- Scripts de setup (`tools/setup.sh` de cada servicio)
- `docker-compose.yml`
- `Makefile`

**Requiere configuracion local:**
- `/etc/hosts`: Agregar la entrada `127.0.0.1 ravazque.42.fr`
- Directorios de datos: `mkdir -p /home/ravazque/data/{wordpress,mysql}` (el Makefile lo hace automaticamente)
- Archivo `.env`: Ya incluido en el repositorio con valores del proyecto
- Archivos de secrets: Deben existir en `secrets/` con las contrasenas deseadas
- En Btrfs: `chattr +C` en el directorio de datos de MySQL
- IP forwarding: Puede necesitar habilitarse manualmente en algunas distribuciones

---

## Referencia Rapida de Puertos y Protocolos

| Servicio | Puerto | Protocolo | Accesible desde |
|----------|--------|-----------|-----------------|
| NGINX | 443 | HTTPS (TLS 1.2/1.3) | Host y red externa |
| WordPress (PHP-FPM) | 9000 | FastCGI (TCP) | Solo red Docker interna |
| MariaDB | 3306 | MySQL/TCP | Solo red Docker interna |

## Referencia Rapida de Rutas

| Ruta | Contenedor | Descripcion |
|------|------------|-------------|
| `/var/www/html` | nginx, wordpress | Archivos de WordPress (volumen compartido) |
| `/var/lib/mysql` | mariadb | Datos de la base de datos |
| `/run/secrets/` | wordpress, mariadb | Archivos de secrets (tmpfs) |
| `/etc/ssl/certs/nginx.crt` | nginx | Certificado TLS |
| `/etc/ssl/private/nginx.key` | nginx | Clave privada TLS |
| `/etc/nginx/sites-enabled/default` | nginx | Configuracion de NGINX |
| `/etc/php/8.2/fpm/pool.d/www.conf` | wordpress | Configuracion del pool PHP-FPM |
| `/etc/mysql/mariadb.conf.d/50-server.cnf` | mariadb | Configuracion de MariaDB |

## Referencia Rapida de Archivos del Proyecto

```
inception/
├── Makefile                                    # Automatizacion de build y gestion
├── secrets/
│   ├── credentials.txt                         # L1: admin pw, L2: user pw
│   ├── db_password.txt                         # Contrasena del usuario de DB
│   └── db_root_password.txt                    # Contrasena root de MariaDB
└── srcs/
    ├── .env                                    # Variables de entorno no sensibles
    ├── docker-compose.yml                      # Orquestacion de servicios
    └── requirements/
        ├── mariadb/
        │   ├── .dockerignore
        │   ├── Dockerfile
        │   ├── conf/
        │   │   └── 50-server.cnf               # bind-address = 0.0.0.0
        │   └── tools/
        │       └── setup.sh                    # Init: temp instance -> create DB -> exec mysqld_safe
        ├── nginx/
        │   ├── .dockerignore
        │   ├── Dockerfile
        │   ├── conf/
        │   │   └── nginx.conf                  # TLS + FastCGI proxy
        │   └── tools/
        │       └── setup.sh                    # Init: gen cert -> exec nginx
        └── wordpress/
            ├── .dockerignore
            ├── Dockerfile
            ├── conf/
            │   └── www.conf                    # PHP-FPM pool: TCP 9000, clear_env=no
            └── tools/
                └── setup.sh                    # Init: wait DB -> WP-CLI install -> exec php-fpm
```
