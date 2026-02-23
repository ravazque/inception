#!/bin/bash
# =============================================================================
# test_eval.sh — Verification script for Arch VM
# Run from the root of the inception repository:
#   bash docs/test/test_eval.sh
#
# Usage:
#   bash docs/test/test_eval.sh          — Full test (includes make re build)
#   bash docs/test/test_eval.sh --quick  — Skip build, only test running state
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0
QUICK=false

[ "$1" = "--quick" ] && QUICK=true

pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARN++)); }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
section() { echo -e "\n${CYAN}══════════════════════════════════════${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}══════════════════════════════════════${NC}"; }

LOGIN="ravazque"
DOMAIN="${LOGIN}.42.fr"

# =============================================================================
section "1. Requisitos del sistema (Arch VM)"
# =============================================================================

if systemd-detect-virt 2>/dev/null | grep -qi "oracle\|kvm\|vmware\|qemu"; then
    pass "Ejecutandose dentro de una maquina virtual ($(systemd-detect-virt))"
else
    warn "No se detecta VM — verifica que estas dentro de VirtualBox"
fi

if docker info &>/dev/null; then
    pass "Docker daemon activo: $(docker --version | cut -d' ' -f3 | tr -d ',')"
else
    fail "Docker daemon NO activo"
    echo -e "${RED}  Ejecuta: sudo systemctl start docker${NC}"
    echo -e "${RED}  Si no esta instalado: sudo pacman -S docker docker-compose docker-buildx${NC}"
fi

if docker compose version &>/dev/null; then
    pass "Docker Compose v2: $(docker compose version --short)"
else
    fail "Docker Compose v2 no encontrado"
fi

if groups | grep -q docker; then
    pass "Usuario '$USER' en grupo docker"
else
    fail "Usuario '$USER' NO en grupo docker — ejecuta: sudo usermod -aG docker $USER && newgrp docker"
fi

if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = "1" ]; then
    pass "IP forwarding habilitado"
else
    fail "IP forwarding deshabilitado"
    echo -e "${RED}  Ejecuta: sudo sysctl -w net.ipv4.ip_forward=1${NC}"
fi

if [ -f /etc/docker/daemon.json ] && grep -q "dns" /etc/docker/daemon.json; then
    pass "Docker DNS configurado en daemon.json"
else
    warn "Docker DNS no configurado — puede causar fallos en builds"
    echo -e "${YELLOW}  Ejecuta: echo '{\"dns\": [\"1.1.1.1\", \"8.8.8.8\"]}' | sudo tee /etc/docker/daemon.json${NC}"
fi

if grep -q "${DOMAIN}" /etc/hosts; then
    pass "/etc/hosts tiene entrada ${DOMAIN}"
else
    fail "/etc/hosts sin ${DOMAIN}"
    echo -e "${RED}  Ejecuta: echo '127.0.0.1 ${DOMAIN}' | sudo tee -a /etc/hosts${NC}"
fi

for d in /home/${LOGIN}/data/wordpress /home/${LOGIN}/data/mysql; do
    [ -d "$d" ] && pass "Directorio existe: $d" || fail "Falta: $d — ejecuta: sudo mkdir -p $d"
done

# =============================================================================
section "2. Estructura del repositorio"
# =============================================================================

info "Verificando archivos en la raiz del repo..."

# --- Root level files ---
[ -f "Makefile" ] && pass "Makefile en raiz" || fail "Falta: Makefile"

if [ -f "README.md" ] && [ -s "README.md" ]; then
    FIRST_LINE=$(head -1 README.md)
    if echo "$FIRST_LINE" | grep -q "^\*This project has been created as part of the 42 curriculum"; then
        pass "README.md en raiz con primera linea correcta"
    else
        fail "README.md primera linea incorrecta: '$FIRST_LINE'"
        echo -e "${RED}  Debe empezar con: *This project has been created as part of the 42 curriculum by ${LOGIN}.*${NC}"
    fi
else
    fail "Falta o vacio: README.md"
fi

if [ -f "USER_DOC.md" ] && [ -s "USER_DOC.md" ]; then
    pass "USER_DOC.md en raiz ($(wc -l < "USER_DOC.md") lineas)"
else
    fail "Falta: USER_DOC.md en la raiz del repo"
fi

if [ -f "DEV_DOC.md" ] && [ -s "DEV_DOC.md" ]; then
    pass "DEV_DOC.md en raiz ($(wc -l < "DEV_DOC.md") lineas)"
else
    fail "Falta: DEV_DOC.md en la raiz del repo"
fi

if [ -f ".gitignore" ]; then
    pass ".gitignore existe"
else
    fail "Falta: .gitignore"
fi

# --- srcs/ directory ---
info "Verificando srcs/..."
for f in srcs/docker-compose.yml srcs/.env; do
    [ -f "$f" ] && pass "Existe: $f" || fail "Falta: $f"
done

# --- secrets/ directory ---
info "Verificando secrets/..."
for f in secrets/db_password.txt secrets/db_root_password.txt secrets/credentials.txt; do
    if [ -f "$f" ] && [ -s "$f" ]; then
        pass "Secret: $f"
    else
        fail "Falta o vacio: $f"
    fi
done

# --- Dockerfiles ---
for svc in nginx wordpress mariadb; do
    df="srcs/requirements/$svc/Dockerfile"
    if [ -f "$df" ]; then
        pass "Dockerfile: $df"
        if grep -q ":latest" "$df"; then
            fail "$df: usa tag 'latest' (prohibido)"
        else
            pass "$df: sin tag 'latest'"
        fi
        if grep -qi "password\|passwd\|secret" "$df"; then
            fail "$df: posible credencial hardcoded"
        else
            pass "$df: sin credenciales"
        fi
        if grep -q "^FROM debian\|^FROM alpine" "$df"; then
            pass "$df: base debian/alpine"
        else
            warn "$df: revisa FROM — debe ser debian:bookworm o alpine"
        fi
    else
        fail "Falta: $df"
    fi
done

# --- docker-compose.yml checks ---
COMPOSE="srcs/docker-compose.yml"
if grep -q "links:" "$COMPOSE" 2>/dev/null; then
    fail "docker-compose.yml usa links: (prohibido)"
else
    pass "docker-compose.yml: sin links:"
fi
if grep -qi "network_mode.*host\|network:.*host" "$COMPOSE" 2>/dev/null; then
    fail "docker-compose.yml usa network: host (prohibido)"
else
    pass "docker-compose.yml: sin network host"
fi

# Admin username
ADMIN_USER=$(grep WP_ADMIN_USER srcs/.env 2>/dev/null | cut -d= -f2)
if [ -n "$ADMIN_USER" ]; then
    if echo "$ADMIN_USER" | grep -qi "admin"; then
        fail "WP_ADMIN_USER '$ADMIN_USER' contiene 'admin' (prohibido)"
    else
        pass "WP_ADMIN_USER '$ADMIN_USER' no contiene 'admin'"
    fi
else
    fail "WP_ADMIN_USER no definido en srcs/.env"
fi

# =============================================================================
section "3. .gitignore"
# =============================================================================
info "Verificando que .gitignore excluye archivos sensibles..."

if [ -f ".gitignore" ]; then
    if grep -qE "^secrets/?$" .gitignore; then
        pass ".gitignore excluye secrets/"
    else
        fail ".gitignore NO excluye secrets/ — DEBE incluir la linea: secrets/"
    fi
    if grep -qE "^srcs/\.env$" .gitignore; then
        pass ".gitignore excluye srcs/.env"
    else
        fail ".gitignore NO excluye srcs/.env — DEBE incluir la linea: srcs/.env"
    fi
    info "Contenido actual de .gitignore:"
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        info "  $line"
    done < .gitignore
fi

# =============================================================================
section "4. Build"
# =============================================================================

if [ "$QUICK" = true ]; then
    info "Modo --quick: saltando build (make re)"
else
    info "Ejecutando: make re (rebuild completo desde cero)"
    info "Esto puede tardar 3-8 minutos dependiendo de la conexion..."
    if make re 2>&1 | tail -10; then
        pass "make re completado"
    else
        fail "make re fallo — revisa los logs con: make logs"
    fi
fi

# =============================================================================
section "5. Contenedores"
# =============================================================================

sleep 10

for ctr in nginx wordpress mariadb; do
    STATUS=$(docker inspect --format='{{.State.Status}}' "$ctr" 2>/dev/null)
    if [ "$STATUS" = "running" ]; then
        pass "Contenedor corriendo: $ctr"
    else
        fail "Contenedor NO corriendo: $ctr (estado: ${STATUS:-no encontrado})"
    fi
done

for svc in nginx wordpress mariadb; do
    IMG=$(docker inspect --format='{{.Config.Image}}' "$svc" 2>/dev/null)
    if [ "$IMG" = "$svc" ]; then
        pass "Imagen '$IMG' = servicio '$svc'"
    else
        warn "Imagen '$IMG' != servicio '$svc'"
    fi
done

# =============================================================================
section "6. Red Docker"
# =============================================================================

if docker network ls | grep -q inception; then
    pass "Red 'inception' existe"
    DRIVER=$(docker network inspect inception --format='{{.Driver}}' 2>/dev/null)
    if [ "$DRIVER" = "bridge" ]; then
        pass "Red inception usa driver bridge"
    else
        warn "Red inception driver: $DRIVER (esperado: bridge)"
    fi
else
    fail "Red 'inception' no encontrada"
fi

CONTAINERS_ON_NET=$(docker network inspect inception --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null)
for ctr in nginx wordpress mariadb; do
    if echo "$CONTAINERS_ON_NET" | grep -q "$ctr"; then
        pass "$ctr conectado a red inception"
    else
        fail "$ctr NO conectado a red inception"
    fi
done

for ctr in nginx wordpress mariadb; do
    NET=$(docker inspect --format='{{.HostConfig.NetworkMode}}' "$ctr" 2>/dev/null)
    if [ "$NET" = "host" ]; then
        fail "$ctr usa red host (prohibido)"
    else
        pass "$ctr: modo red $NET (no host)"
    fi
done

# =============================================================================
section "7. TLS y HTTPS"
# =============================================================================

if curl -sk --max-time 3 http://${DOMAIN} &>/dev/null; then
    fail "Puerto 80 responde (solo 443 permitido)"
else
    pass "Puerto 80 cerrado (correcto)"
fi

HTTP_CODE=$(curl -sk --max-time 15 -o /dev/null -w '%{http_code}' https://${DOMAIN})
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
    pass "HTTPS responde (codigo: $HTTP_CODE)"
else
    fail "HTTPS no responde (codigo: $HTTP_CODE)"
fi

if curl -sk --max-time 15 https://${DOMAIN} | grep -qi "WordPress\|wp-\|<!DOCTYPE"; then
    pass "Contenido WordPress detectado en HTTPS"
else
    fail "Sin contenido WordPress en HTTPS"
fi

TLS_PROTO=$(echo | openssl s_client -connect ${DOMAIN}:443 2>/dev/null | grep "Protocol" | awk '{print $3}')
if [[ "$TLS_PROTO" == "TLSv1.2" ]] || [[ "$TLS_PROTO" == "TLSv1.3" ]]; then
    pass "Protocolo TLS: $TLS_PROTO"
else
    fail "Protocolo TLS: '$TLS_PROTO' — esperado TLSv1.2 o TLSv1.3"
fi

if echo | openssl s_client -tls1 -connect ${DOMAIN}:443 2>&1 | grep -qi "alert\|error\|wrong version\|no protocols"; then
    pass "TLSv1.0 rechazado correctamente"
else
    warn "No se pudo verificar rechazo de TLSv1.0"
fi

# =============================================================================
section "8. PID 1 (procesos)"
# =============================================================================

for ctr in nginx wordpress mariadb; do
    PID1=$(docker exec "$ctr" cat /proc/1/cmdline 2>/dev/null | tr '\0' ' ' | sed 's/ $//')
    if echo "$PID1" | grep -qiE "^bash |^/bin/bash |^sh |^/bin/sh |^tail |^sleep |^while"; then
        fail "$ctr PID 1 prohibido: '$PID1'"
    else
        pass "$ctr PID 1: '$PID1'"
    fi
done

# =============================================================================
section "9. Docker Secrets"
# =============================================================================

for f in db_password db_root_password; do
    if docker exec mariadb cat /run/secrets/$f &>/dev/null; then
        pass "mariadb: /run/secrets/$f OK"
    else
        fail "mariadb: /run/secrets/$f NO encontrado"
    fi
done

for f in credentials db_password; do
    if docker exec wordpress cat /run/secrets/$f &>/dev/null; then
        pass "wordpress: /run/secrets/$f OK"
    else
        fail "wordpress: /run/secrets/$f NO encontrado"
    fi
done

for ctr in wordpress mariadb; do
    ENV_DUMP=$(docker exec "$ctr" env 2>/dev/null)
    if echo "$ENV_DUMP" | grep -qiE "^.*PASSWORD=|^.*PASSWD=|^.*SECRET="; then
        warn "$ctr: variable tipo PASSWORD encontrada en env — verifica que no sea un secreto real"
    else
        pass "$ctr: sin contraseñas en variables de entorno"
    fi
done

# =============================================================================
section "10. Base de datos MariaDB"
# =============================================================================

DB_PASS=$(cat secrets/db_password.txt 2>/dev/null)
DB_USER=$(grep MYSQL_USER srcs/.env 2>/dev/null | cut -d= -f2)
DB_NAME=$(grep MYSQL_DATABASE srcs/.env 2>/dev/null | cut -d= -f2)

if [ -n "$DB_PASS" ] && [ -n "$DB_USER" ] && [ -n "$DB_NAME" ]; then
    TABLES=$(docker exec mariadb mariadb -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SHOW TABLES;" 2>/dev/null)
    if echo "$TABLES" | grep -q "wp_"; then
        TABLE_COUNT=$(echo "$TABLES" | grep -c "wp_")
        pass "MariaDB: $TABLE_COUNT tablas WordPress encontradas"
    else
        fail "MariaDB: sin tablas WordPress"
    fi
else
    fail "No se pudo leer configuracion de BD de srcs/.env y secrets/"
fi

# =============================================================================
section "11. Usuarios WordPress"
# =============================================================================

USERS=$(docker exec wordpress wp user list --allow-root --format=csv 2>/dev/null)
ADMIN_COUNT=$(echo "$USERS" | grep -c "administrator" 2>/dev/null || echo 0)
TOTAL_USERS=$(echo "$USERS" | tail -n +2 | wc -l)

if [ "$TOTAL_USERS" -ge 2 ]; then
    pass "WordPress: $TOTAL_USERS usuarios encontrados"
else
    fail "WordPress: menos de 2 usuarios (encontrados: $TOTAL_USERS)"
fi

if [ "$ADMIN_COUNT" -ge 1 ]; then
    pass "WordPress: $ADMIN_COUNT administrador(es)"
else
    fail "WordPress: sin administrador"
fi

echo "$USERS" | tail -n +2 | while IFS=, read -r id login name email role; do
    info "  $login ($role)"
done

WP_ADMIN=$(docker exec wordpress wp user list --role=administrator --field=user_login --allow-root 2>/dev/null)
if [ -n "$WP_ADMIN" ]; then
    if echo "$WP_ADMIN" | grep -qi "admin"; then
        fail "Admin WP '$WP_ADMIN' contiene 'admin' (prohibido)"
    else
        pass "Admin WP '$WP_ADMIN' no contiene 'admin'"
    fi
fi

# =============================================================================
section "12. Volumenes y persistencia"
# =============================================================================

WP_FILES=$(ls /home/${LOGIN}/data/wordpress/ 2>/dev/null | wc -l)
DB_FILES=$(ls /home/${LOGIN}/data/mysql/ 2>/dev/null | wc -l)

if [ "$WP_FILES" -gt 0 ]; then
    pass "WordPress: $WP_FILES archivos en /home/${LOGIN}/data/wordpress/"
else
    fail "Volumen WordPress vacio"
fi

if [ "$DB_FILES" -gt 0 ]; then
    pass "MariaDB: $DB_FILES archivos en /home/${LOGIN}/data/mysql/"
else
    fail "Volumen MariaDB vacio"
fi

for vol in wordpress_data mariadb_data; do
    FOUND=$(docker volume ls --format '{{.Name}}' | grep "$vol")
    if [ -n "$FOUND" ]; then
        pass "Volumen nombrado: $FOUND"
    else
        warn "Volumen '$vol' no encontrado con ese nombre exacto"
    fi
done

# =============================================================================
section "13. Reinicio automatico"
# =============================================================================

info "Matando nginx para verificar restart: always..."
docker kill nginx &>/dev/null
sleep 8

STATUS=$(docker inspect --format='{{.State.Status}}' nginx 2>/dev/null)
if [ "$STATUS" = "running" ]; then
    pass "nginx reinicio automaticamente"
else
    fail "nginx NO reinicio (estado: $STATUS)"
fi

for ctr in nginx wordpress mariadb; do
    POLICY=$(docker inspect --format='{{.HostConfig.RestartPolicy.Name}}' "$ctr" 2>/dev/null)
    if [ "$POLICY" = "always" ]; then
        pass "$ctr: restart policy = always"
    else
        fail "$ctr: restart policy = '$POLICY' (esperado: always)"
    fi
done

# =============================================================================
section "14. Persistencia de datos (down + up)"
# =============================================================================

info "Verificando persistencia: make down + make up..."

POST_COUNT_BEFORE=$(docker exec wordpress wp post list --allow-root --format=count 2>/dev/null)

make down 2>/dev/null
sleep 3

if [ "$(ls /home/${LOGIN}/data/wordpress/ 2>/dev/null | wc -l)" -gt 0 ]; then
    pass "Datos WordPress persisten tras make down"
else
    fail "Datos WordPress perdidos tras make down"
fi

if [ "$(ls /home/${LOGIN}/data/mysql/ 2>/dev/null | wc -l)" -gt 0 ]; then
    pass "Datos MariaDB persisten tras make down"
else
    fail "Datos MariaDB perdidos tras make down"
fi

make up 2>/dev/null
sleep 15

if curl -sk --max-time 15 https://${DOMAIN} | grep -qi "WordPress\|wp-\|<!DOCTYPE"; then
    pass "Sitio accesible tras down + up"
else
    fail "Sitio NO accesible tras down + up"
fi

POST_COUNT_AFTER=$(docker exec wordpress wp post list --allow-root --format=count 2>/dev/null)
if [ "$POST_COUNT_BEFORE" = "$POST_COUNT_AFTER" ] && [ -n "$POST_COUNT_BEFORE" ]; then
    pass "Contenido WordPress preservado ($POST_COUNT_AFTER posts)"
else
    warn "No se pudo verificar preservacion de contenido (antes: $POST_COUNT_BEFORE, despues: $POST_COUNT_AFTER)"
fi

# =============================================================================
section "RESUMEN"
# =============================================================================

TOTAL=$((PASS + FAIL + WARN))
echo ""
echo -e "  ${GREEN}Pasados:${NC}  $PASS / $TOTAL"
echo -e "  ${RED}Fallidos:${NC} $FAIL / $TOTAL"
echo -e "  ${YELLOW}Avisos:${NC}   $WARN / $TOTAL"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  TODAS LAS COMPROBACIONES PASADAS${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════${NC}"
elif [ $FAIL -le 3 ]; then
    echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  PROBLEMAS MENORES — corrige los FAIL${NC}"
    echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
else
    echo -e "${RED}══════════════════════════════════════════════${NC}"
    echo -e "${RED}  MULTIPLES PROBLEMAS — revisa todos los FAIL${NC}"
    echo -e "${RED}══════════════════════════════════════════════${NC}"
fi

# =============================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
echo -e "${CYAN}  RECORDATORIO: Configuracion para Git${NC}"
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}Archivos que DEBEN estar en la raiz del repo:${NC}"
echo -e "  - Makefile"
echo -e "  - README.md (primera linea: *This project has been created as part of the 42 curriculum by ${LOGIN}.*)"
echo -e "  - USER_DOC.md"
echo -e "  - DEV_DOC.md"
echo -e "  - .gitignore"
echo ""
echo -e "${BLUE}Carpetas que DEBEN estar en el repo:${NC}"
echo -e "  - srcs/ (con docker-compose.yml y .env)"
echo -e "  - srcs/requirements/ (con nginx/, wordpress/, mariadb/)"
echo ""
echo -e "${BLUE}Carpeta secrets/ — passwords (NO en Git):${NC}"
echo -e "  - secrets/db_password.txt"
echo -e "  - secrets/db_root_password.txt"
echo -e "  - secrets/credentials.txt"
echo -e "  ${YELLOW}Estos archivos DEBEN existir en la VM pero NO deben estar en Git.${NC}"
echo -e "  Crealos manualmente antes de ejecutar make."
echo ""
echo -e "${BLUE}.gitignore DEBE contener estas lineas:${NC}"
echo -e "  secrets/"
echo -e "  srcs/.env"
echo ""
echo -e "${BLUE}.gitignore NO debe excluir:${NC}"
echo -e "  Makefile, README.md, USER_DOC.md, DEV_DOC.md"
echo -e "  srcs/docker-compose.yml"
echo -e "  srcs/requirements/ (Dockerfiles, configs, scripts)"
echo ""
