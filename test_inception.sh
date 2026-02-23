#!/bin/bash
# =============================================================================
# test_inception.sh — Inception verification script for CachyOS/Arch
# Run from the root of the inception repository: bash test_inception.sh
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARN++)); }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
section() { echo -e "\n${BLUE}══════════════════════════════════════${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}══════════════════════════════════════${NC}"; }

# =============================================================================
section "1. Pre-flight checks"
# =============================================================================

# Docker available
if docker info &>/dev/null; then
    pass "Docker daemon is running"
else
    fail "Docker daemon is NOT running — run: sudo systemctl start docker"
fi

# Docker Compose v2
if docker compose version &>/dev/null; then
    pass "Docker Compose v2 available: $(docker compose version --short)"
else
    fail "Docker Compose v2 not found"
fi

# Required files exist
for f in Makefile srcs/docker-compose.yml srcs/.env.example; do
    [ -f "$f" ] && pass "File exists: $f" || fail "Missing: $f"
done

# .env exists (not .env.example only)
if [ -f "srcs/.env" ]; then
    pass "srcs/.env exists"
else
    fail "srcs/.env missing — create it from srcs/.env.example"
fi

# Secrets exist
for f in secrets/db_password.txt secrets/db_root_password.txt secrets/credentials.txt; do
    if [ -f "$f" ] && [ -s "$f" ]; then
        pass "Secret file present and non-empty: $f"
    else
        fail "Secret file missing or empty: $f"
    fi
done

# Host data directories
for d in /home/ravazque/data/wordpress /home/ravazque/data/mysql; do
    [ -d "$d" ] && pass "Host data directory exists: $d" || fail "Missing host directory: $d — run: sudo mkdir -p $d"
done

# /etc/hosts entry
if grep -q "ravazque.42.fr" /etc/hosts; then
    pass "/etc/hosts has ravazque.42.fr entry"
else
    fail "/etc/hosts missing ravazque.42.fr — run: echo '127.0.0.1 ravazque.42.fr' | sudo tee -a /etc/hosts"
fi

# IP forwarding
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = "1" ]; then
    pass "IP forwarding enabled"
else
    warn "IP forwarding disabled — Docker networking may fail. Run: sudo sysctl -w net.ipv4.ip_forward=1"
fi

# Docker DNS config
if [ -f /etc/docker/daemon.json ] && grep -q "dns" /etc/docker/daemon.json; then
    pass "/etc/docker/daemon.json has DNS configuration"
else
    warn "/etc/docker/daemon.json missing or has no DNS config — container builds may fail on Arch/CachyOS"
fi

# Git security check
if git ls-files --error-unmatch secrets/ &>/dev/null 2>&1; then
    fail "SECURITY: secrets/ is tracked by Git! Run: git rm -r --cached secrets/"
else
    pass "secrets/ is NOT tracked by Git (correct)"
fi

if git ls-files --error-unmatch srcs/.env &>/dev/null 2>&1; then
    fail "SECURITY: srcs/.env is tracked by Git! Run: git rm --cached srcs/.env"
else
    pass "srcs/.env is NOT tracked by Git (correct)"
fi

# Dockerfile checks
for svc in nginx wordpress mariadb; do
    df="srcs/requirements/$svc/Dockerfile"
    if [ -f "$df" ]; then
        # No 'latest' tag
        if grep -q ":latest" "$df"; then
            fail "$df uses 'latest' tag (prohibited)"
        else
            pass "$df: no 'latest' tag"
        fi
        # No passwords hardcoded
        if grep -qi "password\|passwd\|secret" "$df"; then
            fail "$df may contain hardcoded password/secret"
        else
            pass "$df: no hardcoded credentials"
        fi
        # Starts from debian or alpine (not a service image)
        if grep -q "^FROM debian\|^FROM alpine" "$df"; then
            pass "$df: uses debian/alpine base"
        else
            warn "$df: check FROM line — should be debian:bookworm or alpine"
        fi
    else
        fail "Missing: $df"
    fi
done

# =============================================================================
section "2. Build check"
# =============================================================================

info "Running: make re (full clean rebuild — this may take several minutes)"
if make re 2>&1 | tail -5; then
    pass "make re completed successfully"
else
    fail "make re failed"
fi

# =============================================================================
section "3. Container status"
# =============================================================================

sleep 5  # Give containers a moment to stabilise

for ctr in nginx wordpress mariadb; do
    STATUS=$(docker inspect --format='{{.State.Status}}' "$ctr" 2>/dev/null)
    if [ "$STATUS" = "running" ]; then
        pass "Container running: $ctr"
    else
        fail "Container NOT running: $ctr (status: ${STATUS:-not found})"
    fi
done

# =============================================================================
section "4. Network checks"
# =============================================================================

# inception network exists
if docker network ls | grep -q inception; then
    pass "Docker network 'inception' exists"
else
    fail "Docker network 'inception' not found"
fi

# All containers on the network
CONTAINERS_ON_NET=$(docker network inspect inception --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null)
for ctr in nginx wordpress mariadb; do
    if echo "$CONTAINERS_ON_NET" | grep -q "$ctr"; then
        pass "Container $ctr is on the inception network"
    else
        fail "Container $ctr is NOT on the inception network"
    fi
done

# No host network used
for ctr in nginx wordpress mariadb; do
    NET=$(docker inspect --format='{{.HostConfig.NetworkMode}}' "$ctr" 2>/dev/null)
    if [ "$NET" = "host" ]; then
        fail "Container $ctr uses host network (prohibited)"
    else
        pass "Container $ctr does not use host network (mode: $NET)"
    fi
done

# Container DNS resolution (containers can reach each other by name)
if docker exec wordpress ping -c 1 -W 2 mariadb &>/dev/null; then
    pass "wordpress can reach mariadb by hostname"
else
    fail "wordpress cannot reach mariadb by hostname"
fi

# =============================================================================
section "5. TLS checks"
# =============================================================================

# Port 443 only (port 80 must NOT be open)
if curl -sk --max-time 3 http://ravazque.42.fr &>/dev/null; then
    fail "Port 80 is responding (should be closed — only 443 allowed)"
else
    pass "Port 80 is NOT accessible (correct)"
fi

# HTTPS works
if curl -sk --max-time 5 https://ravazque.42.fr | grep -q "WordPress\|wp-"; then
    pass "HTTPS site is responding with WordPress content"
else
    fail "HTTPS site is NOT responding or not returning WordPress content"
fi

# TLS version
TLS_PROTO=$(echo | openssl s_client -connect ravazque.42.fr:443 2>/dev/null | grep "Protocol" | awk '{print $3}')
if [[ "$TLS_PROTO" == "TLSv1.2" ]] || [[ "$TLS_PROTO" == "TLSv1.3" ]]; then
    pass "TLS protocol: $TLS_PROTO (correct)"
else
    fail "TLS protocol is '$TLS_PROTO' — expected TLSv1.2 or TLSv1.3"
fi

# =============================================================================
section "6. PID 1 checks"
# =============================================================================

for ctr in nginx wordpress mariadb; do
    PID1=$(docker exec "$ctr" cat /proc/1/cmdline 2>/dev/null | tr '\0' ' ' | sed 's/ $//')
    if echo "$PID1" | grep -qiE "^bash$|^sh$|^tail|sleep|while"; then
        fail "Container $ctr has forbidden PID 1: '$PID1'"
    else
        pass "Container $ctr PID 1: '$PID1'"
    fi
done

# =============================================================================
section "7. Secrets checks"
# =============================================================================

# Secrets mounted inside containers
for f in db_password db_root_password; do
    if docker exec mariadb cat /run/secrets/$f &>/dev/null; then
        pass "mariadb: /run/secrets/$f is accessible"
    else
        fail "mariadb: /run/secrets/$f NOT found"
    fi
done

if docker exec wordpress cat /run/secrets/credentials &>/dev/null; then
    pass "wordpress: /run/secrets/credentials is accessible"
else
    fail "wordpress: /run/secrets/credentials NOT found"
fi

# Secrets NOT in environment variables
if docker exec mariadb env 2>/dev/null | grep -iq "password\|secret"; then
    warn "mariadb: password-like variable found in env — verify it's not an actual secret"
else
    pass "mariadb: no password in environment variables"
fi

# =============================================================================
section "8. Database checks"
# =============================================================================

DB_PASS=$(cat secrets/db_password.txt)
DB_USER=$(grep MYSQL_USER srcs/.env | cut -d= -f2)
DB_NAME=$(grep MYSQL_DATABASE srcs/.env | cut -d= -f2)

if docker exec mariadb mariadb -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SHOW TABLES;" 2>/dev/null | grep -q "wp_"; then
    pass "WordPress tables found in MariaDB"
else
    fail "WordPress tables NOT found in MariaDB"
fi

# =============================================================================
section "9. WordPress users check"
# =============================================================================

USERS=$(docker exec wordpress wp user list --allow-root 2>/dev/null)
USER_COUNT=$(echo "$USERS" | grep -c "author\|administrator" 2>/dev/null || echo 0)

if [ "$USER_COUNT" -ge 2 ]; then
    pass "WordPress has $USER_COUNT users (admin + regular)"
    echo "$USERS" | grep -v "^ID" | while read line; do info "  User: $line"; done
else
    fail "WordPress does not have 2 users (found: $USER_COUNT)"
fi

# Admin username must not contain "admin"
ADMIN_USER=$(grep WP_ADMIN_USER srcs/.env | cut -d= -f2)
if echo "$ADMIN_USER" | grep -qi "admin"; then
    fail "WP_ADMIN_USER '$ADMIN_USER' contains 'admin' (prohibited)"
else
    pass "WP_ADMIN_USER '$ADMIN_USER' does not contain 'admin' (correct)"
fi

# =============================================================================
section "10. Volume and persistence checks"
# =============================================================================

if [ "$(ls /home/ravazque/data/wordpress/ 2>/dev/null | wc -l)" -gt 0 ]; then
    pass "WordPress volume has data at /home/ravazque/data/wordpress/"
else
    fail "WordPress volume is empty"
fi

if [ "$(ls /home/ravazque/data/mysql/ 2>/dev/null | wc -l)" -gt 0 ]; then
    pass "MariaDB volume has data at /home/ravazque/data/mysql/"
else
    fail "MariaDB volume is empty"
fi

# =============================================================================
section "11. Restart policy check"
# =============================================================================

info "Killing nginx container to test restart: always..."
docker kill nginx &>/dev/null
sleep 6
STATUS=$(docker inspect --format='{{.State.Status}}' nginx 2>/dev/null)
if [ "$STATUS" = "running" ]; then
    pass "nginx restarted automatically after being killed (restart: always works)"
else
    fail "nginx did NOT restart after being killed (status: $STATUS)"
fi

# =============================================================================
section "12. Required documentation files"
# =============================================================================

for f in README.md USER_DOC.md DEV_DOC.md; do
    if [ -f "$f" ] && [ -s "$f" ]; then
        LINES=$(wc -l < "$f")
        pass "$f exists ($LINES lines)"
    else
        fail "$f is missing or empty"
    fi
done

# README first line must be italicized 42 line
FIRST_LINE=$(head -1 README.md)
if echo "$FIRST_LINE" | grep -q "^\*This project has been created as part of the 42 curriculum"; then
    pass "README.md first line is the required italicized 42 line"
else
    fail "README.md first line is wrong. Got: '$FIRST_LINE'"
fi

# =============================================================================
section "SUMMARY"
# =============================================================================

TOTAL=$((PASS + FAIL + WARN))
echo ""
echo -e "  ${GREEN}Passed:${NC}   $PASS / $TOTAL"
echo -e "  ${RED}Failed:${NC}   $FAIL / $TOTAL"
echo -e "  ${YELLOW}Warnings:${NC} $WARN / $TOTAL"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}All checks passed. Project is ready for evaluation.${NC}"
elif [ $FAIL -le 2 ]; then
    echo -e "${YELLOW}Minor issues found. Fix the FAIL items above before evaluation.${NC}"
else
    echo -e "${RED}Multiple issues found. Review all FAIL items before evaluation.${NC}"
fi