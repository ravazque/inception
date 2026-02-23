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