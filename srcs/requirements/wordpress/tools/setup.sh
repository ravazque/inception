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