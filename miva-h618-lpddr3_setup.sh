#!/usr/bin/env bash
set -Eeuo pipefail

MIVA_REPO="https://github.com/smatecvn/miva.git"
MIVA_DIR="/home/miva"

log() {
    printf '[miva-h618-lpddr3] %s\n' "$*"
}

die() {
    printf '[miva-h618-lpddr3] ERROR: %s\n' "$*" >&2
    exit 1
}

[[ $EUID -eq 0 ]] || die "Hay chay script bang root."
command -v git >/dev/null 2>&1 || die "Thieu git."
command -v docker >/dev/null 2>&1 || die "Thieu docker."
docker compose version >/dev/null 2>&1 || die "Thieu Docker Compose plugin."

log "Clone/cap nhat MIVA vao $MIVA_DIR"
if [[ -d "$MIVA_DIR/.git" ]]; then
    git -C "$MIVA_DIR" pull --ff-only
else
    [[ ! -e "$MIVA_DIR" ]] || die "$MIVA_DIR ton tai nhung khong phai Git checkout."
    git clone "$MIVA_REPO" "$MIVA_DIR"
fi

log "Cap quyen thuc thi cho cac file shell"
find "$MIVA_DIR" -type f -name '*.sh' -exec chmod +x {} +

MPV_INIT="$MIVA_DIR/setup/mpv_init.sh"
SETUP="$MIVA_DIR/setup/setup_miva.sh"
DOCKER_DIR="$MIVA_DIR/docker"
OVERRIDE="$DOCKER_DIR/docker-compose.override.yml"

[[ -f "$MPV_INIT" ]] || die "Khong tim thay $MPV_INIT"
[[ -x "$SETUP" ]] || die "Khong tim thay file setup thuc thi: $SETUP"
[[ -x "$DOCKER_DIR/generate-devices.sh" ]] || die "Khong tim thay generate-devices.sh"

log "Bo tham so --no-audio khoi mpv_init.sh"
sed -i 's/[[:space:]]--no-audio\([[:space:]]\|$\)/\1/g' "$MPV_INIT"

log "Chay setup_miva.sh"
(cd "$MIVA_DIR/setup" && ./setup_miva.sh)

log "Tao docker-compose.override.yml"
(cd "$DOCKER_DIR" && ./generate-devices.sh)
[[ -f "$OVERRIDE" ]] || die "generate-devices.sh khong tao $OVERRIDE"

log "Vo hieu hoa mapping ttyS0 de tranh xung dot"
sed -i -E 's/^([[:space:]]*)- "\/dev\/ttyS0"/\1# - "\/dev\/ttyS0"/' "$OVERRIDE"

log "Pull image MIVA voi TAG=latest"
(cd "$DOCKER_DIR" && export TAG=latest && docker compose pull)

install_to_emmc() {
    local root_source target type

    command -v armbian-install >/dev/null 2>&1 || die "Khong tim thay armbian-install."
    armbian-install --help 2>&1 | grep -q -- '--target' || die "armbian-install qua cu, khong ho tro che do tu dong (--target/--yes)."

    root_source="$(findmnt -n -o SOURCE / || true)"
    target=""
    for device in /sys/block/mmcblk*/device/type; do
        [[ -r "$device" ]] || continue
        type="$(<"$device")"
        if [[ "$type" == "MMC" ]]; then
            target="/dev/$(basename "$(dirname "$(dirname "$device")")")"
            break
        fi
    done

    [[ -b "$target" ]] || die "Khong tu tim thay thiet bi eMMC."
    [[ "$root_source" != "$target" && "$root_source" != "$target"* ]] || die "Tu choi ghi: root dang nam tren $target."

    log "Tu dong cai vao eMMC $target (ext4, boot emmc)"
    armbian-install --target "$target" --boot emmc --fs ext4 --yes
}

log "Chuyen he thong tu SD sang eMMC khong tuong tac"
export http_proxy="http://127.0.0.1:9"
export https_proxy="http://127.0.0.1:9"
install_to_emmc
