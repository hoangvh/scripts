#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================================
# MIVA application installer
#
# Architecture:
#   Phase 1: Host preparation
#     - Display / Xorg / Openbox
#     - MPV / FFmpeg
#     - HDMI hotplug
#
#   Phase 2: MIVA upstream
#     - Clone/update smatecvn/miva
#     - 4G initialization
#     - netcfg-watcher
#     - MPV integration
#     - MIVA network configuration
#     - Docker Compose
#
# Manual:
#
#   MIVA_TAG=latest bash <(
#       curl -4 -fsSL \
#       https://raw.githubusercontent.com/hoangvh/scripts/refs/heads/main/install-miva.sh
#   )
#
# ============================================================================

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------

FEATURE_DISPLAY="${FEATURE_DISPLAY:-yes}"
FEATURE_MPV="${FEATURE_MPV:-yes}"
FEATURE_HDMI_HOTPLUG="${FEATURE_HDMI_HOTPLUG:-yes}"

MIVA_INSTALL="${MIVA_INSTALL:-yes}"
MIVA_TAG="${MIVA_TAG:-${TAG:-latest}}"
MIVA_BRANCH="${MIVA_BRANCH:-master}"
MIVA_NETWORK="${MIVA_NETWORK:-yes}"

MIVA_REPO="https://github.com/smatecvn/miva.git"
MIVA_DIR="/home/miva"

STATE_DIR="/var/lib/miva-firstboot"

APT_UPDATED=no


# ----------------------------------------------------------------------------
# Logging
# ----------------------------------------------------------------------------

log() {
    echo "[miva-install] $*"
}

warn() {
    echo "[miva-install] WARNING: $*" >&2
}

die() {
    echo "[miva-install] ERROR: $*" >&2
    exit 1
}


# ----------------------------------------------------------------------------
# Error handler
# ----------------------------------------------------------------------------

on_error() {
    local rc=$?
    local line="${BASH_LINENO[0]:-unknown}"

    echo "[miva-install] ERROR at line ${line}, exit=${rc}" >&2
    exit "$rc"
}

trap on_error ERR


# ----------------------------------------------------------------------------
# Root
# ----------------------------------------------------------------------------

[[ "$(id -u)" -eq 0 ]] || die "This installer must run as root"


# ----------------------------------------------------------------------------
# Boolean validation
# ----------------------------------------------------------------------------

validate_bool() {
    local name="$1"
    local value="$2"

    case "$value" in
        yes|no)
            ;;
        *)
            die "${name} must be 'yes' or 'no', got '${value}'"
            ;;
    esac
}

validate_bool FEATURE_DISPLAY "$FEATURE_DISPLAY"
validate_bool FEATURE_MPV "$FEATURE_MPV"
validate_bool FEATURE_HDMI_HOTPLUG "$FEATURE_HDMI_HOTPLUG"
validate_bool MIVA_INSTALL "$MIVA_INSTALL"
validate_bool MIVA_NETWORK "$MIVA_NETWORK"


# ----------------------------------------------------------------------------
# Feature dependency resolution
# ----------------------------------------------------------------------------

if [[ "$FEATURE_MPV" == "yes" && "$FEATURE_DISPLAY" != "yes" ]]; then
    log "FEATURE_MPV requires DISPLAY; enabling FEATURE_DISPLAY"
    FEATURE_DISPLAY=yes
fi

if [[ "$FEATURE_HDMI_HOTPLUG" == "yes" && "$FEATURE_DISPLAY" != "yes" ]]; then
    log "FEATURE_HDMI_HOTPLUG requires DISPLAY; enabling FEATURE_DISPLAY"
    FEATURE_DISPLAY=yes
fi


# ----------------------------------------------------------------------------
# State
# ----------------------------------------------------------------------------

mkdir -p "$STATE_DIR"


mark_done() {
    touch "${STATE_DIR}/$1.done"
}


is_done() {
    [[ -f "${STATE_DIR}/$1.done" ]]
}


# ============================================================================
# APT
# ============================================================================

configure_apt_network() {

    log "Configuring APT to use IPv4"

    mkdir -p /etc/apt/apt.conf.d

    cat >/etc/apt/apt.conf.d/99miva-force-ipv4 <<'EOF'
Acquire::ForceIPv4 "true";
EOF
}


apt_update_once() {

    if [[ "$APT_UPDATED" == "yes" ]]; then
        return 0
    fi

    log "Updating APT package lists"

    apt-get update

    APT_UPDATED=yes
}


install_pkgs() {

    local missing=()
    local pkg

    for pkg in "$@"; do

        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null \
            | grep -q "install ok installed"; then

            missing+=("$pkg")
        fi
    done

    if [[ "${#missing[@]}" -eq 0 ]]; then
        return 0
    fi

    log "Installing packages: ${missing[*]}"

    apt_update_once

    DEBIAN_FRONTEND=noninteractive \
        apt-get install -y --no-install-recommends "${missing[@]}"
}


configure_apt_network


# ============================================================================
# PHASE 1
# ============================================================================

log "========================================"
log "PHASE 1: HOST PREPARATION"
log "========================================"


# ----------------------------------------------------------------------------
# Common dependencies
# ----------------------------------------------------------------------------

install_common() {

    if is_done common; then
        log "Common dependencies already installed"
        return
    fi

    install_pkgs \
        git \
        curl \
        ca-certificates \
        inotify-tools \
        cron

    mark_done common
}


install_common


# ----------------------------------------------------------------------------
# Display
# ----------------------------------------------------------------------------

install_display() {

    if [[ "$FEATURE_DISPLAY" != "yes" ]]; then
        log "FEATURE_DISPLAY=no; skipping display stack"
        return
    fi

    if is_done display; then
        log "Display stack already installed"
        return
    fi

    log "Installing Xorg/Openbox display stack"

    install_pkgs \
        xserver-xorg \
        xinit \
        openbox \
        mesa-utils \
        wmctrl \
        x11-utils \
        x11-xserver-utils \
        fonts-cantarell

    # ------------------------------------------------------------------------
    # Openbox configuration
    # ------------------------------------------------------------------------

    mkdir -p /root/.config/openbox

    if [[ ! -f /root/.config/openbox/autostart ]]; then
        cat >/root/.config/openbox/autostart <<'EOF'
# MIVA Openbox autostart

xset -dpms
xset s off
xset s noblank
EOF
    fi

    chmod +x /root/.config/openbox/autostart


    # ------------------------------------------------------------------------
    # Xorg/Openbox launcher
    # ------------------------------------------------------------------------

    cat >/usr/local/sbin/miva-xorg-openbox <<'EOF'
#!/usr/bin/env bash
set -e

export DISPLAY=:0
export XAUTHORITY=/root/.Xauthority

exec startx /usr/bin/openbox-session -- :0 \
    -nocursor \
    -s 0 \
    -dpms
EOF

    chmod 0755 /usr/local/sbin/miva-xorg-openbox


    # ------------------------------------------------------------------------
    # systemd
    # ------------------------------------------------------------------------

    cat >/etc/systemd/system/xorg-openbox.service <<'EOF'
[Unit]
Description=MIVA Xorg + Openbox
After=systemd-user-sessions.service
Wants=systemd-user-sessions.service

[Service]
Type=simple

Environment=DISPLAY=:0
Environment=XAUTHORITY=/root/.Xauthority

ExecStart=/usr/local/sbin/miva-xorg-openbox

Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable xorg-openbox.service

    mark_done display

    log "Display stack installed"
}


install_display


# ----------------------------------------------------------------------------
# MPV
# ----------------------------------------------------------------------------

install_mpv() {

    if [[ "$FEATURE_MPV" != "yes" ]]; then
        log "FEATURE_MPV=no; skipping MPV"
        return
    fi

    if is_done mpv; then
        log "MPV already installed"
        return
    fi

    log "Installing MPV/FFmpeg"

    install_pkgs \
        mpv \
        ffmpeg

    mark_done mpv
}


install_mpv


# ----------------------------------------------------------------------------
# HDMI hotplug
# ----------------------------------------------------------------------------

install_hdmi_hotplug() {

    if [[ "$FEATURE_HDMI_HOTPLUG" != "yes" ]]; then
        log "FEATURE_HDMI_HOTPLUG=no; skipping HDMI hotplug"
        return
    fi

    if is_done hdmi; then
        log "HDMI hotplug already installed"
        return
    fi

    log "Installing HDMI hotplug support"

    # ------------------------------------------------------------------------
    # HDMI handler
    # ------------------------------------------------------------------------

    cat >/usr/local/sbin/miva-hdmi-hotplug <<'EOF'
#!/usr/bin/env bash

export DISPLAY=:0
export XAUTHORITY=/root/.Xauthority

sleep 1

if command -v xrandr >/dev/null 2>&1; then
    xrandr --auto || true
fi
EOF

    chmod 0755 /usr/local/sbin/miva-hdmi-hotplug


    # ------------------------------------------------------------------------
    # systemd service
    # ------------------------------------------------------------------------

    cat >/etc/systemd/system/miva-hdmi-hotplug.service <<'EOF'
[Unit]
Description=MIVA HDMI hotplug handler
After=xorg-openbox.service

[Service]
Type=oneshot
Environment=DISPLAY=:0
Environment=XAUTHORITY=/root/.Xauthority
ExecStart=/usr/local/sbin/miva-hdmi-hotplug
EOF


    # ------------------------------------------------------------------------
    # udev
    #
    # Do not assume a board-specific DRM event here.
    # Existing board-specific HDMI rules can be installed separately.
    # ------------------------------------------------------------------------

    systemctl daemon-reload

    mark_done hdmi

    log "HDMI hotplug support installed"
}


install_hdmi_hotplug


log "========================================"
log "PHASE 1: HOST PREPARATION COMPLETE"
log "========================================"


# ============================================================================
# Stop here when MIVA application is disabled
# ============================================================================

if [[ "$MIVA_INSTALL" != "yes" ]]; then

    log "MIVA_INSTALL=no"
    log "Host preparation complete; skipping MIVA application"

    exit 0
fi


# ============================================================================
# PHASE 2
# ============================================================================

log "========================================"
log "PHASE 2: MIVA UPSTREAM INSTALL"
log "========================================"


# ----------------------------------------------------------------------------
# Clone/update upstream
# ----------------------------------------------------------------------------

install_miva_source() {

    log "Preparing MIVA source"

    if [[ -d "$MIVA_DIR/.git" ]]; then

        log "Updating existing MIVA repository"

        git -C "$MIVA_DIR" fetch origin "$MIVA_BRANCH"

        git -C "$MIVA_DIR" checkout -B \
            "$MIVA_BRANCH" \
            "origin/$MIVA_BRANCH"

    else

        if [[ -e "$MIVA_DIR" ]]; then
            die "$MIVA_DIR exists but is not a Git repository"
        fi

        git clone \
            --branch "$MIVA_BRANCH" \
            --single-branch \
            "$MIVA_REPO" \
            "$MIVA_DIR"
    fi

    mark_done miva-source
}


install_miva_source


# ----------------------------------------------------------------------------
# MIVA core
# ----------------------------------------------------------------------------

install_miva_core() {

    log "Installing MIVA core host services"

    local setup="$MIVA_DIR/setup"

    [[ -d "$setup" ]] || die "Missing upstream setup directory"


    # ------------------------------------------------------------------------
    # 4G modem initialization
    # ------------------------------------------------------------------------

    if [[ -f "$setup/init_4g_module.sh" ]]; then

        install -m 0755 \
            "$setup/init_4g_module.sh" \
            /usr/local/bin/init_4g_module.sh
    fi


    # ------------------------------------------------------------------------
    # pre-docker GPIO
    # ------------------------------------------------------------------------

    if [[ -f "$setup/pre-docker-gpio.service" ]]; then

        install -m 0644 \
            "$setup/pre-docker-gpio.service" \
            /etc/systemd/system/pre-docker-gpio.service

        systemctl enable pre-docker-gpio.service
    fi


    # ------------------------------------------------------------------------
    # netcfg watcher
    # ------------------------------------------------------------------------

    if [[ -f "$setup/netcfg-watcher.sh" ]]; then

        install -m 0755 \
            "$setup/netcfg-watcher.sh" \
            /usr/local/bin/netcfg-watcher.sh
    fi


    if [[ -f "$setup/netcfg-watcher.service" ]]; then

        install -m 0644 \
            "$setup/netcfg-watcher.service" \
            /etc/systemd/system/netcfg-watcher.service

        systemctl enable netcfg-watcher.service
    fi


    # ------------------------------------------------------------------------
    # Runtime directories expected by MIVA
    # ------------------------------------------------------------------------

    mkdir -p \
        /root/mgwp/network \
        /root/mgwp/upgrade \
        /root/mgwp/reboot


    touch \
        /root/mgwp/network/netplan.apply \
        /root/mgwp/upgrade/upgrade.tag \
        /root/mgwp/reboot/reboot.apply


    # ------------------------------------------------------------------------
    # MPV integration
    # ------------------------------------------------------------------------

    if [[ "$FEATURE_MPV" == "yes" && -f "$setup/mpv_init.sh" ]]; then

        install -m 0755 \
            "$setup/mpv_init.sh" \
            /usr/local/bin/mpv_init.sh

        CRON_LINE='* * * * * /usr/local/bin/mpv_init.sh >/dev/null 2>&1'

        (
            crontab -l 2>/dev/null \
                | grep -Fv '/usr/local/bin/mpv_init.sh' || true

            echo "$CRON_LINE"

        ) | crontab -
    fi


    systemctl daemon-reload

    mark_done miva-core
}


install_miva_core


# ============================================================================
# Network configuration
# ============================================================================

install_miva_network() {

    if [[ "$MIVA_NETWORK" != "yes" ]]; then

        log "MIVA_NETWORK=no"
        log "Keeping firmware/bootstrap network configuration"

        return
    fi

    log "Staging MIVA upstream network configuration"

    local setup="$MIVA_DIR/setup"

    for file in \
        01-netcfg.yaml \
        02-rndis.yaml \
        03-uqmi.yaml
    do
        [[ -f "$setup/$file" ]] \
            || die "Missing upstream network file: $file"
    done


    # MIVA now becomes owner of Netplan configuration.
    rm -f /etc/netplan/*.yaml


    install -m 0600 \
        "$setup/01-netcfg.yaml" \
        /etc/netplan/01-netcfg.yaml

    install -m 0600 \
        "$setup/02-rndis.yaml" \
        /etc/netplan/02-rndis.yaml

    install -m 0600 \
        "$setup/03-uqmi.yaml" \
        /etc/netplan/03-uqmi.yaml


    # Generate only.
    #
    # IMPORTANT:
    # Do NOT netplan apply here because doing so can remove the Internet
    # connection being used to pull the MIVA Docker image.
    netplan generate

    mark_done miva-network

    log "MIVA network configuration staged"
}


install_miva_network


# ============================================================================
# Docker
# ============================================================================

install_miva_docker() {

    local docker_dir="$MIVA_DIR/docker"

    [[ -d "$docker_dir" ]] \
        || die "Missing MIVA docker directory"


    cd "$docker_dir"


    # ------------------------------------------------------------------------
    # Generate dynamic device mappings
    # ------------------------------------------------------------------------

    if [[ -f ./generate-devices.sh ]]; then

        chmod +x ./generate-devices.sh

        log "Generating Docker device mappings"

        ./generate-devices.sh
    fi


    # ------------------------------------------------------------------------
    # Compose
    # ------------------------------------------------------------------------

    if docker compose version >/dev/null 2>&1; then

        COMPOSE=(docker compose)

    elif command -v docker-compose >/dev/null 2>&1; then

        COMPOSE=(docker-compose)

    else

        die "Docker Compose not found"
    fi


    export TAG="$MIVA_TAG"

    log "Using Docker image tag: $TAG"


    log "Validating Docker Compose configuration"

    "${COMPOSE[@]}" config >/dev/null


    log "Pulling MIVA Docker image"

    "${COMPOSE[@]}" pull


    log "Starting MIVA"

    "${COMPOSE[@]}" up -d


    # ------------------------------------------------------------------------
    # Verify
    # ------------------------------------------------------------------------

    log "Verifying MIVA container"

    local ok=no

    for _ in $(seq 1 10); do

        if docker ps --format '{{.Names}}' \
            | grep -qx 'miva'; then

            ok=yes
            break
        fi

        sleep 2
    done


    "${COMPOSE[@]}" ps || true


    if [[ "$ok" != "yes" ]]; then

        docker ps -a || true

        die "MIVA container is not running"
    fi


    mark_done miva-container
}


install_miva_docker


# ============================================================================
# Final verification
# ============================================================================

log "========================================"
log "MIVA INSTALLATION COMPLETE"
log "========================================"

log "MIVA branch : $MIVA_BRANCH"
log "MIVA tag    : $MIVA_TAG"
log "Network     : $MIVA_NETWORK"

docker ps --filter name=miva || true

exit 0
