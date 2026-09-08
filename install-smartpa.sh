#!/usr/bin/env bash
set -Eeuo pipefail

SMARTPA_REPO="${SMARTPA_REPO:-https://gogs.smatec.com.vn/MGW/smartpa-docker.git}"
SMARTPA_HOME="${SMARTPA_HOME:-/home/smartpa}"
SMARTPA_BRANCH="${SMARTPA_BRANCH:-master}"
SMARTPA_TAG="${SMARTPA_TAG:-${MIVA_TAG:-latest}}"
SMARTPA_INSTALL="${SMARTPA_INSTALL:-${MIVA_INSTALL:-yes}}"
SMARTPA_NETWORK="${SMARTPA_NETWORK:-no}"
STATE_DIR="/var/lib/smartpa-app"

log()  { printf '[smartpa-app] %s\n' "$*"; }
warn() { printf '[smartpa-app] WARNING: %s\n' "$*" >&2; }
die()  { printf '[smartpa-app] ERROR: %s\n' "$*" >&2; exit 1; }
yesno() { [[ "${1,,}" == "yes" ]]; }

require_root() {
    [[ $EUID -eq 0 ]] || die "Run as root"
}

install_host_packages() {
    [[ -f "$STATE_DIR/packages.done" ]] && return 0
    log "Installing SmartPA host packages"
    mkdir -p /etc/apt/apt.conf.d "$STATE_DIR"
    cat > /etc/apt/apt.conf.d/99smartpa-force-ipv4 <<'APT'
Acquire::ForceIPv4 "true";
APT
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        git ca-certificates curl inotify-tools cron
    systemctl enable --now cron.service 2>/dev/null || true
    touch "$STATE_DIR/packages.done"
}

sync_source() {
    [[ -f "$STATE_DIR/source.done" ]] && return 0
    if [[ -d "$SMARTPA_HOME/.git" ]]; then
        log "Updating SmartPA source"
        git -C "$SMARTPA_HOME" fetch --prune origin
        git -C "$SMARTPA_HOME" checkout "$SMARTPA_BRANCH"
        git -C "$SMARTPA_HOME" reset --hard "origin/$SMARTPA_BRANCH"
    else
        [[ ! -e "$SMARTPA_HOME" || -z "$(find "$SMARTPA_HOME" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]] \
            || die "$SMARTPA_HOME exists and is not an empty Git checkout"
        log "Cloning SmartPA source"
        git clone --branch "$SMARTPA_BRANCH" --single-branch "$SMARTPA_REPO" "$SMARTPA_HOME"
    fi
    [[ -f "$SMARTPA_HOME/app/docker-compose.yml" ]] || die "Missing SmartPA app compose file"
    [[ -f "$SMARTPA_HOME/app/docker-compose.override.yml" ]] || die "Missing SmartPA device mapping"
    [[ -f "$SMARTPA_HOME/gpio-api/docker-compose.yml" ]] || die "Missing gpio-api compose file"
    [[ -f "$SMARTPA_HOME/mqtt/docker-compose.yml" ]] || die "Missing MQTT compose file"
    touch "$STATE_DIR/source.done"
}

run_source_setup() {
    [[ -f "$STATE_DIR/setup.done" ]] && return 0
    [[ -x "$SMARTPA_HOME/setup/setup_smartpa.sh" ]] || die "Missing source setup script"
    log "Running SmartPA setup script from cloned source"
    ( cd "$SMARTPA_HOME/setup" && bash ./setup_smartpa.sh )
    touch "$STATE_DIR/setup.done"
}

prepare_docker() {
    command -v docker >/dev/null 2>&1 || die "Docker is missing from base firmware"
    docker compose version >/dev/null 2>&1 || die "Docker Compose plugin is missing"
    docker network inspect docker_default >/dev/null 2>&1 || \
        docker network create --driver bridge --subnet 172.18.0.0/16 docker_default >/dev/null
}

start_application() {
    [[ -f "$STATE_DIR/application.done" ]] && return 0
    prepare_docker
    log "Generating MPD configuration from physical USB audio devices"
    ( cd "$SMARTPA_HOME/setup" && bash ./generate-mpd.sh ) || warn "MPD configuration generation failed"

    local app_dir="$SMARTPA_HOME/app"
    local gpio_dir="$SMARTPA_HOME/gpio-api"
    local mqtt_dir="$SMARTPA_HOME/mqtt"

    log "Validating SmartPA Docker Compose files"
    ( cd "$app_dir" && APP_TAG="$SMARTPA_TAG" docker compose config >/dev/null )
    ( cd "$gpio_dir" && GPIO_API_TAG="${GPIO_API_TAG:-latest}" docker compose config >/dev/null )
    ( cd "$mqtt_dir" && MQTT_TAG="${MQTT_TAG:-latest}" docker compose config >/dev/null )

    log "Pulling SmartPA images"
    ( cd "$app_dir" && APP_TAG="$SMARTPA_TAG" docker compose pull )
    ( cd "$gpio_dir" && GPIO_API_TAG="${GPIO_API_TAG:-latest}" docker compose pull )
    ( cd "$mqtt_dir" && MQTT_TAG="${MQTT_TAG:-latest}" docker compose pull )

    log "Starting SmartPA services"
    ( cd "$mqtt_dir" && MQTT_TAG="${MQTT_TAG:-latest}" docker compose up -d )
    ( cd "$gpio_dir" && GPIO_API_TAG="${GPIO_API_TAG:-latest}" docker compose up -d )
    ( cd "$app_dir" && APP_TAG="$SMARTPA_TAG" docker compose up -d )
    docker ps --format '{{.Names}}' | grep -Eq '^(smartpa1|smartpa2|smartpa3|smartpa4|gpio-api|mqtt)$' \
        || die "No SmartPA container is running"
    touch "$STATE_DIR/application.done"
}

main() {
    require_root
    mkdir -p "$STATE_DIR"
    log "Configuration: branch=$SMARTPA_BRANCH tag=$SMARTPA_TAG install=$SMARTPA_INSTALL network=$SMARTPA_NETWORK"
    yesno "$SMARTPA_INSTALL" || { log "SMARTPA_INSTALL=no; nothing to install"; exit 0; }
    install_host_packages
    sync_source
    run_source_setup
    start_application
    log "SmartPA application setup completed"
}

main "$@"
