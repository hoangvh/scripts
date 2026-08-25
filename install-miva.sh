#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================================
# install-miva.sh — one-line MIVA application installer
#
# Chạy trực tiếp trên firmware MIVA DSDZ-H618 (đã boot production):
#
#   sudo -i
#   bash <(curl -fsSL https://raw.githubusercontent.com/hoangvh/scripts/refs/heads/main/install-miva.sh)
#
# Chọn Docker image tag:
#
#   TAG=<tag> bash <(curl -fsSL https://raw.githubusercontent.com/hoangvh/scripts/refs/heads/main/install-miva.sh)
#
# Default: TAG=latest
#
# Script tự clone/update upstream https://github.com/smatecvn/miva (branch
# master) vào /home/miva rồi chạy flow tương đương setup/setup_miva.sh.
# KHÔNG yêu cầu clone repo thủ công trước.
#
# Yêu cầu:
#   - chạy bằng root
#   - base firmware phải có Docker (docker + docker compose)
#   - không phụ thuộc current working directory
#
# LƯU Ý NETWORK OWNERSHIP:
#   - TRƯỚC install: network do firmware bootstrap quản lý
#     (/etc/netplan/20-miva-device.yaml từ init.conf).
#   - SAU install:  network do upstream MIVA quản lý
#     (/etc/netplan/01-netcfg.yaml, 02-rndis.yaml, 03-uqmi.yaml).
#   Script xóa /etc/netplan/*.yaml và copy các YAML upstream (giống
#   setup_miva.sh: rm /etc/netplan/*.yaml; chmod 600; cp *.yaml /etc/netplan).
#   20-miva-device.yaml KHÔNG được tồn tại sau khi cài.
#
# Option:
#   TAG          image tag cho sonnh911/miva (default: latest)
#   INSTALL_MPV  yes/no  cài mpv + x11-xserver-utils + cron mpv_init
#                (default: yes)
# ============================================================================

UPSTREAM_URL="https://github.com/smatecvn/miva.git"
UPSTREAM_BRANCH="master"
APP_DIR="/home/miva"
COMPOSE_DIR="/home/miva/docker"
MGPW_DIR="/root/mgwp"
USB_MM_RULE="/etc/udev/rules.d/99-mm-ignore.rules"
GPIO_4G=204 # upstream 4G reset GPIO (KHÁC LED_GPIO=262 của installer)

TAG="${TAG:-latest}"
INSTALL_MPV="${INSTALL_MPV:-yes}"

# Temporary directory dùng để stage git clone; tự dọn khi thoát.
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

log()  { echo "[miva-install] $*"; }
warn() { echo "[miva-install][WARN] $*" >&2; }
die()  { echo "[miva-install][ERROR] $*" >&2; exit 1; }

if [[ "$(id -u)" -ne 0 ]]; then
    die "must run as root (try: sudo -i, sau do chay lai lenh nay)"
fi

# ---------------------------------------------------------------------------
# 1. Docker phải có sẵn trong base firmware (KHÔNG tự cài lại Docker)
# ---------------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
    die "Base firmware does not contain Docker"
fi
docker --version >/dev/null 2>&1 || die "docker is not functional"

if docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose)
else
    die "Docker Compose not found; base firmware must provide 'docker compose' or 'docker-compose'"
fi
log "Using compose: ${COMPOSE[*]}"

# ---------------------------------------------------------------------------
# 2. Host dependencies
# ---------------------------------------------------------------------------
install_pkgs() {
    local missing=() p
    for p in "$@"; do
        dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
    done
    [[ ${#missing[@]} -eq 0 ]] && return 0
    log "Installing packages: ${missing[*]}"
    apt-get update -y
    apt-get install -y --no-install-recommends "${missing[@]}"
}

install_pkgs git curl ca-certificates inotify-tools cron

if [[ "$INSTALL_MPV" == "yes" ]]; then
    log "INSTALL_MPV=yes: installing mpv + x11-xserver-utils"
    install_pkgs mpv x11-xserver-utils
else
    log "INSTALL_MPV=no: skipping mpv / x11-xserver-utils / mpv_init cron"
fi

# ---------------------------------------------------------------------------
# 3. Runtime directories (idempotent, runtime data preserved)
# ---------------------------------------------------------------------------
log "Creating runtime directories under ${MGPW_DIR}"
mkdir -p "$MGPW_DIR/network" "$MGPW_DIR/upgrade" "$MGPW_DIR/reboot"
touch "$MGPW_DIR/network/netplan.apply"
touch "$MGPW_DIR/upgrade/upgrade.tag"
touch "$MGPW_DIR/reboot/reboot.apply"

mkdir -p /mnt/mmcblk0p1

# ---------------------------------------------------------------------------
# 4. Clone / update upstream MIVA app to /home/miva (self-contained)
# ---------------------------------------------------------------------------
if [[ -d "$APP_DIR/.git" ]]; then
    log "Updating existing MIVA repo at $APP_DIR"
    git -C "$APP_DIR" fetch origin
    git -C "$APP_DIR" checkout master
    git -C "$APP_DIR" reset --hard "origin/$UPSTREAM_BRANCH"
else
    if [[ -e "$APP_DIR" ]] && [[ -n "$(ls -A "$APP_DIR" 2>/dev/null || true)" ]]; then
        die "$APP_DIR exists but is not a git repo; refusing to overwrite"
    fi
    log "Cloning MIVA repo from $UPSTREAM_URL (staged in $WORK_DIR)"
    git clone --branch "$UPSTREAM_BRANCH" "$UPSTREAM_URL" "$WORK_DIR/miva" || die "clone upstream failed"
    rm -rf "$APP_DIR"
    mv "$WORK_DIR/miva" "$APP_DIR"
fi

# ---------------------------------------------------------------------------
# 5. Helper scripts -> /usr/local/bin (theo setup_miva.sh)
# ---------------------------------------------------------------------------
log "Installing helper scripts to /usr/local/bin"
cp -v "$APP_DIR/setup/init_4g_module.sh"    /usr/local/bin/init_4g_module.sh
cp -v "$APP_DIR/setup/netcfg-watcher.sh"    /usr/local/bin/netcfg-watcher.sh
cp -v "$APP_DIR/setup/mpv_init.sh"          /usr/local/bin/mpv_init.sh
chmod 0755 /usr/local/bin/init_4g_module.sh \
           /usr/local/bin/netcfg-watcher.sh \
           /usr/local/bin/mpv_init.sh

# ---------------------------------------------------------------------------
# 6. systemd services (theo setup_miva.sh)
# ---------------------------------------------------------------------------
log "Installing systemd services"
cp -v "$APP_DIR/setup/netcfg-watcher.service" /etc/systemd/system/netcfg-watcher.service
cp -v "$APP_DIR/setup/pre-docker-gpio.service" /etc/systemd/system/pre-docker-gpio.service
systemctl daemon-reload
systemctl enable netcfg-watcher.service
systemctl enable pre-docker-gpio.service

# ---------------------------------------------------------------------------
# 7. ModemManager ignore rule cho /dev/ttyUSB1 (theo setup_miva.sh)
# ---------------------------------------------------------------------------
log "Installing udev rule ${USB_MM_RULE}"
printf 'KERNEL=="ttyUSB1", ENV{ID_MM_DEVICE_IGNORE}="1"\n' > "$USB_MM_RULE"
udevadm control --reload-rules
udevadm trigger

# ---------------------------------------------------------------------------
# 8. MPV cron (idempotent). mpv_init.sh cần X display trên :0.
# ---------------------------------------------------------------------------
if [[ "$INSTALL_MPV" == "yes" ]]; then
    CRON_LINE='*/1 * * * * /usr/local/bin/mpv_init.sh >> /tmp/mpv_init.log 2>&1'
    if ! crontab -l 2>/dev/null | grep -Fq "$CRON_LINE"; then
        log "Adding mpv_init cron entry"
        ( crontab -l 2>/dev/null || true; echo "$CRON_LINE" ) | crontab - || die "failed to install cron entry"
    else
        log "mpv_init cron entry already present"
    fi

    if ! DISPLAY=:0 xrandr >/dev/null 2>&1; then
        warn "no X display on :0; mpv video zones will start once Xorg is running"
    fi
fi

# ---------------------------------------------------------------------------
# 9. NETWORK TAKEOVER — theo setup_miva.sh: rm + copy YAML upstream.
#    20-miva-device.yaml (firmware bootstrap) phải bị xóa.
# ---------------------------------------------------------------------------
log "Taking over production network config (upstream MIVA netplan)"
rm -f /etc/netplan/*.yaml

cp "$APP_DIR/setup/01-netcfg.yaml" /etc/netplan/01-netcfg.yaml
cp "$APP_DIR/setup/02-rndis.yaml"  /etc/netplan/02-rndis.yaml
cp "$APP_DIR/setup/03-uqmi.yaml"   /etc/netplan/03-uqmi.yaml

chmod 600 /etc/netplan/*.yaml

log "Generating netplan"
netplan generate || die "netplan generate failed"

log "Applying netplan"
netplan apply || die "netplan apply failed"

if [[ -f /etc/netplan/20-miva-device.yaml ]]; then
    die "20-miva-device.yaml still exists after network takeover"
fi

# ---------------------------------------------------------------------------
# 10. 4G GPIO (upstream uses GPIO 204, khác LED_GPIO=262 của installer).
#     Hardware optional: failure KHÔNG được làm install abort.
# ---------------------------------------------------------------------------
check_gpio() {
    if [[ ! -e /sys/class/gpio/export ]]; then
        warn "legacy sysfs GPIO not available (/sys/class/gpio/export missing); 4G modem reset via GPIO ${GPIO_4G} may not work"
        return 1
    fi
    if [[ ! -w /sys/class/gpio/export ]]; then
        warn "sysfs GPIO export not writable; 4G modem reset via GPIO ${GPIO_4G} may not work"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# 11. Start services (theo setup_miva.sh: systemctl start)
# ---------------------------------------------------------------------------
log "Starting netcfg-watcher.service"
systemctl restart netcfg-watcher.service \
    || warn "netcfg-watcher failed to start; check: systemctl status netcfg-watcher.service"

if check_gpio; then
    log "Starting pre-docker-gpio.service (4G reset via GPIO ${GPIO_4G})"
    systemctl restart pre-docker-gpio.service \
        || warn "pre-docker-gpio failed to start (4G modem may be absent); check: systemctl status pre-docker-gpio.service"
else
    warn "skipping pre-docker-gpio start (sysfs GPIO not available); will be retried at next boot"
fi

# ---------------------------------------------------------------------------
# 12. Docker compose: dynamic devices + validation + pull + up
# ---------------------------------------------------------------------------
log "Generating device overrides (docker-compose.override.yml)"
cd "$COMPOSE_DIR"
chmod +x generate-devices.sh
./generate-devices.sh || die "generate-devices.sh failed"

log "Validating compose config"
"${COMPOSE[@]}" config >/dev/null || die "docker compose config validation failed"

export TAG
log "Pulling image sonnh911/miva:${TAG}"
"${COMPOSE[@]}" pull || die "docker compose pull failed"

log "Starting MIVA container"
"${COMPOSE[@]}" up -d || die "docker compose up failed"

# ---------------------------------------------------------------------------
# 13. Verification
# ---------------------------------------------------------------------------
log "=== Verification ==="
echo "--- /etc/netplan/ ---"
ls -la /etc/netplan/
echo "--- grep /etc/netplan/ ---"
grep -R . /etc/netplan/ || true

if [[ -f /etc/netplan/20-miva-device.yaml ]]; then
    die "FAIL: 20-miva-device.yaml must not exist after install"
fi
log "OK: 20-miva-device.yaml removed"

netplan generate || die "netplan generate (verify) failed"

log "--- ip -4 addr ---"
ip -4 addr || true
log "--- ip route ---"
ip route || true

cd "$COMPOSE_DIR"
"${COMPOSE[@]}" config >/dev/null || die "docker compose config (verify) failed"
"${COMPOSE[@]}" ps || die "docker compose ps failed"

if docker ps --filter "name=^/miva$" --format '{{.Names}} {{.Status}}' | grep -q .; then
    log "container 'miva' is running"
else
    if docker ps -a --filter "name=^/miva$" --format '{{.Names}}' | grep -q .; then
        warn "container 'miva' exists but is NOT running; check: docker logs miva"
    else
        die "container 'miva' was not created; check: docker compose ps"
    fi
fi

if docker inspect miva >/dev/null 2>&1; then
    log "docker inspect miva: OK"
else
    warn "docker inspect miva failed"
fi

echo
systemctl --no-pager status netcfg-watcher.service || true
systemctl --no-pager status pre-docker-gpio.service || true

# ---------------------------------------------------------------------------
# 14. Done
# ---------------------------------------------------------------------------
DEVICE_IP="$(ip -4 addr show eth0 2>/dev/null | awk '/inet /{gsub(/\/.*/,"",$2); print $2; exit}')"

echo
log "MIVA installation completed"
if [[ -n "$DEVICE_IP" ]]; then
    log "Web:    http://${DEVICE_IP}   (port 80)"
    log "        https://${DEVICE_IP}  (port 443)"
else
    log "Web:    http://<device-ip>    (port 80 / 443)"
fi
log "Status: cd /home/miva/docker && docker compose ps"
log "Logs:   docker logs -f miva"
