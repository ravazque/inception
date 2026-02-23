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