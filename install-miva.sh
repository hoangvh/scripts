#!/usr/bin/env bash
set -Eeuo pipefail

UPSTREAM_REPO="https://github.com/smatecvn/miva.git"
MIVA_HOME="/home/miva"
SETUP_DIR="$MIVA_HOME/setup"
DOCKER_DIR="$MIVA_HOME/docker"
STATE_DIR="/var/lib/miva-firstboot"

MIVA_INSTALL="${MIVA_INSTALL:-yes}"
MIVA_TAG="${MIVA_TAG:-${TAG:-latest}}"
MIVA_BRANCH="${MIVA_BRANCH:-master}"
FEATURE_DISPLAY="${FEATURE_DISPLAY:-yes}"
FEATURE_MPV="${FEATURE_MPV:-yes}"
FEATURE_HDMI_HOTPLUG="${FEATURE_HDMI_HOTPLUG:-yes}"
MIVA_NETWORK="${MIVA_NETWORK:-yes}"

log()  { printf '[miva-app] %s\n' "$*"; }
warn() { printf '[miva-app] WARNING: %s\n' "$*" >&2; }
die()  { printf '[miva-app] ERROR: %s\n' "$*" >&2; exit 1; }

done_stage() { [[ -f "$STATE_DIR/$1.done" ]]; }
mark_stage() { mkdir -p "$STATE_DIR"; touch "$STATE_DIR/$1.done"; }
yesno() { [[ "${1,,}" == "yes" ]]; }

require_root() {
    [[ $EUID -eq 0 ]] || die "Run as root"
}

install_common_packages() {
    done_stage packages && return 0
    log "Installing common host packages"

    mkdir -p /etc/apt/apt.conf.d
    cat > /etc/apt/apt.conf.d/99miva-force-ipv4 <<'APT'
Acquire::ForceIPv4 "true";
APT

    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        git curl wget ca-certificates inotify-tools cron jq net-tools
    systemctl enable --now cron.service 2>/dev/null || true
    mark_stage packages
}

install_display() {
    yesno "$FEATURE_DISPLAY" || return 0
    done_stage display && return 0

    log "Installing Xorg + Openbox display stack"
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        xserver-xorg xinit openbox mesa-utils wmctrl x11-utils x11-xserver-utils fonts-cantarell

    cat > /etc/systemd/system/xorg-openbox.service <<'UNIT'
[Unit]
Description=Start Xorg with Openbox (as root)
After=network.target

[Service]
User=root
Environment=DISPLAY=:0
Environment=XDG_RUNTIME_DIR=/run/user/0
WorkingDirectory=/root
ExecStart=/usr/bin/X :0 vt1 -nolisten tcp
ExecStartPost=/bin/bash -c 'sleep 1 && openbox-session &'
Restart=always
RestartSec=2
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

    systemctl daemon-reload
    systemctl enable xorg-openbox.service
    mark_stage display
}

install_mpv() {
    yesno "$FEATURE_MPV" || return 0
    done_stage mpv && return 0

    if ! yesno "$FEATURE_DISPLAY"; then
        warn "FEATURE_MPV=yes requires display; enabling/installing display stack"
        FEATURE_DISPLAY=yes
        install_display
    fi

    log "Installing MPV + FFmpeg"

    # Preserve the previously used MIVA DRM-capable package source when available.
    if wget -q http://apt.undo.it:7242/apt.undo.it.asc -O /etc/apt/trusted.gpg.d/apt.undo.it.asc; then
        . /etc/os-release
        echo "deb http://apt.undo.it:7242 $VERSION_CODENAME main" > /etc/apt/sources.list.d/apt.undo.it.list
        cat > /etc/apt/preferences.d/apt-undo-it <<'PREF'
Package: *
Pin: release o=apt.undo.it
Pin-Priority: 600
PREF
        apt-get update
    else
        warn "apt.undo.it unavailable; using distro MPV/FFmpeg packages"
        rm -f /etc/apt/trusted.gpg.d/apt.undo.it.asc /etc/apt/sources.list.d/apt.undo.it.list /etc/apt/preferences.d/apt-undo-it
    fi

    DEBIAN_FRONTEND=noninteractive apt-get install -y mpv ffmpeg

    mkdir -p /etc/mpv
    cat > /etc/mpv/mpv.conf <<'EOFMPV'
hwdec=drm
drm-drmprime-video-plane=primary
drm-draw-plane=overlay
audio-device=alsa/hw:2,0
EOFMPV

    usermod -aG render root 2>/dev/null || true
    usermod -aG video root 2>/dev/null || true
    mark_stage mpv
}

install_hdmi_hotplug() {
    yesno "$FEATURE_HDMI_HOTPLUG" || return 0
    done_stage hdmi && return 0

    if ! yesno "$FEATURE_DISPLAY"; then
        warn "FEATURE_HDMI_HOTPLUG=yes requires display; enabling/installing display stack"
        FEATURE_DISPLAY=yes
        install_display
    fi

    log "Installing HDMI hotplug handler"

    cat > /usr/local/bin/hdmi-hotplug-handler.sh <<'EOFHDMI'
#!/bin/bash
set -u
STATUS_FILE="/sys/class/drm/card0-HDMI-A-1/status"
[[ -r "$STATUS_FILE" ]] || exit 0
STATUS="$(cat "$STATUS_FILE")"
if [[ "$STATUS" == "connected" ]]; then
    logger "HDMI connected, setting resolution and restarting MPV"
    export DISPLAY=:0
    export XAUTHORITY=/root/.Xauthority
    xrandr --output HDMI-1 --mode 1920x1080 --primary 2>/dev/null || true
    [[ -x /usr/local/bin/mpv_init.sh ]] && /usr/local/bin/mpv_init.sh || true
fi
EOFHDMI
    chmod 0755 /usr/local/bin/hdmi-hotplug-handler.sh

    cat > /etc/systemd/system/hdmi-hotplug-handler.service <<'UNIT'
[Unit]
Description=Handle HDMI hotplug event
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hdmi-hotplug-handler.sh

[Install]
WantedBy=multi-user.target
UNIT

    cat > /etc/udev/rules.d/99-hdmi-hotplug.rules <<'RULE'
ACTION=="change", SUBSYSTEM=="drm", RUN+="/bin/systemctl start hdmi-hotplug-handler.service"
RULE

    systemctl daemon-reload
    systemctl enable hdmi-hotplug-handler.service
    udevadm control --reload-rules
    mark_stage hdmi
}

sync_upstream_source() {
    yesno "$MIVA_INSTALL" || return 0
    done_stage source && return 0

    log "Installing/updating MIVA upstream branch: $MIVA_BRANCH"

    if [[ -d "$MIVA_HOME/.git" ]]; then
        git -C "$MIVA_HOME" fetch --prune origin
        git -C "$MIVA_HOME" checkout "$MIVA_BRANCH"
        git -C "$MIVA_HOME" reset --hard "origin/$MIVA_BRANCH"
    else
        if [[ -e "$MIVA_HOME" ]] && [[ -n "$(ls -A "$MIVA_HOME" 2>/dev/null || true)" ]]; then
            die "$MIVA_HOME exists and is not an upstream Git checkout"
        fi
        rm -rf "$MIVA_HOME"
        git clone --branch "$MIVA_BRANCH" --single-branch "$UPSTREAM_REPO" "$MIVA_HOME"
    fi

    [[ -d "$SETUP_DIR" ]] || die "Missing upstream setup directory"
    [[ -d "$DOCKER_DIR" ]] || die "Missing upstream docker directory"
    mark_stage source
}

install_miva_core() {
    yesno "$MIVA_INSTALL" || return 0
    done_stage core && return 0

    log "Installing MIVA core host setup following upstream flow"

    install -m 0755 "$SETUP_DIR/init_4g_module.sh" /usr/local/bin/init_4g_module.sh
    install -m 0755 "$SETUP_DIR/netcfg-watcher.sh" /usr/local/bin/netcfg-watcher.sh
    install -m 0755 "$SETUP_DIR/mpv_init.sh" /usr/local/bin/mpv_init.sh

    mkdir -p /root/mgwp/network /root/mgwp/upgrade /root/mgwp/reboot
    touch /root/mgwp/network/netplan.apply
    touch /root/mgwp/upgrade/upgrade.tag
    touch /root/mgwp/reboot/reboot.apply

    install -m 0644 "$SETUP_DIR/netcfg-watcher.service" /etc/systemd/system/netcfg-watcher.service
    install -m 0644 "$SETUP_DIR/pre-docker-gpio.service" /etc/systemd/system/pre-docker-gpio.service

    cat > /etc/udev/rules.d/99-mm-ignore.rules <<'RULE'
KERNEL=="ttyUSB1", ENV{ID_MM_DEVICE_IGNORE}="1"
RULE
    udevadm control --reload-rules
    udevadm trigger || true

    if yesno "$FEATURE_MPV"; then
        local cron_line='*/1 * * * * /usr/local/bin/mpv_init.sh >> /tmp/mpv_init.log 2>&1'
        ( crontab -l 2>/dev/null | grep -Fv '/usr/local/bin/mpv_init.sh' || true; echo "$cron_line" ) | crontab -
    else
        ( crontab -l 2>/dev/null | grep -Fv '/usr/local/bin/mpv_init.sh' || true ) | crontab -
    fi

    systemctl daemon-reload
    systemctl enable netcfg-watcher.service
    systemctl enable pre-docker-gpio.service

    systemctl restart netcfg-watcher.service || warn "netcfg-watcher.service failed to start"
    systemctl restart pre-docker-gpio.service || warn "pre-docker-gpio.service failed; modem may not be ready yet"

    mark_stage core
}

install_miva_network() {
    yesno "$MIVA_INSTALL" || return 0
    yesno "$MIVA_NETWORK" || {
        log "MIVA_NETWORK=no; keeping firmware-provisioned Netplan configuration"
        return 0
    }
    done_stage network && return 0

    log "Installing upstream MIVA Netplan files"
    rm -f /etc/netplan/*.yaml
    cp "$SETUP_DIR/"*.yaml /etc/netplan/
    chmod 0600 /etc/netplan/*.yaml

    # Upstream setup_miva.sh copies the files but does not call netplan apply.
    # Keep the current working connection alive so Docker pull can finish.
    netplan generate
    mark_stage network
}

start_miva_container() {
    yesno "$MIVA_INSTALL" || return 0
    done_stage container && return 0

    command -v docker >/dev/null 2>&1 || die "Docker is missing from base firmware"
    docker compose version >/dev/null 2>&1 || die "Docker Compose plugin is missing"

    log "Generating Docker device mapping"
    cd "$DOCKER_DIR"
    chmod +x generate-devices.sh
    ./generate-devices.sh

    export TAG="$MIVA_TAG"
    log "Validating Docker Compose for sonnh911/miva:${MIVA_TAG}"
    docker compose config >/dev/null

    log "Pulling MIVA image"
    docker compose pull

    log "Starting MIVA container"
    docker compose up -d

    sleep 3
    docker compose ps
    docker ps --format '{{.Names}}' | grep -qx miva || die "MIVA container is not running"
    mark_stage container
}

main() {
    require_root
    mkdir -p "$STATE_DIR"

    log "Configuration: branch=$MIVA_BRANCH tag=$MIVA_TAG display=$FEATURE_DISPLAY mpv=$FEATURE_MPV hdmi=$FEATURE_HDMI_HOTPLUG network=$MIVA_NETWORK"

    install_common_packages
    install_display
    install_mpv
    install_hdmi_hotplug

    if yesno "$MIVA_INSTALL"; then
        sync_upstream_source
        install_miva_core
        install_miva_network
        start_miva_container
    else
        log "MIVA_INSTALL=no; host feature setup only"
    fi

    log "MIVA first-boot application setup completed"
}

main "$@"
