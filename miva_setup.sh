#!/bin/bash
set -e

LOG_FILE="/var/log/miva_setup.log"
MAX_RETRIES=3
SLEEP_BETWEEN=5

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

retry_cmd() {
    local cmd="$1"
    local desc="$2"
    local attempt=1
    until eval "$cmd"; do
        if [ $attempt -ge $MAX_RETRIES ]; then
            log "❌ $desc failed after $MAX_RETRIES attempts"
            exit 1
        fi
        log "⚠️ $desc failed (attempt $attempt), retrying in $SLEEP_BETWEEN seconds..."
        attempt=$((attempt+1))
        sleep $SLEEP_BETWEEN
    done
    log "✅ $desc succeeded"
}

log "=== Miva setup started ==="

# Check if already setup
if [ -f "/home/miva/.setup_done" ]; then
    log "Miva đã được setup trước đó. Thoát."
    exit 0
fi

cd /home || { log "❌ Không thể cd vào /home"; exit 1; }

# Clone or update repository
if [ ! -d "/home/miva/.git" ]; then
    log "Repo miva chưa có, tiến hành clone..."
    rm -rf /home/miva
    retry_cmd "git clone https://github.com/smatecvn/miva.git miva" "git clone"
else
    log "Repo miva đã tồn tại, kiểm tra tính hợp lệ..."
    if git -C /home/miva status >/dev/null 2>&1; then
        retry_cmd "git -C /home/miva pull" "git pull"
    else
        log "Repo bị hỏng, xóa và clone lại..."
        rm -rf /home/miva
        retry_cmd "git clone https://github.com/smatecvn/miva.git miva" "git clone"
    fi
fi

# Kiểm tra đồng bộ thời gian
log "Kiểm tra đồng bộ thời gian..."
if ! chronyc tracking | grep -q "Stratum"; then
    log "Khởi động lại chrony..."
    systemctl restart chrony
    sleep 5
fi

if chronyc tracking | grep -q "Not synchronised"; then
    log "Thời gian chưa sync, ép sync ngay..."
    retry_cmd "chronyd -q 'server 0.asia.pool.ntp.org iburst'" "chrony sync"
    sleep 3
fi

if chronyc tracking | grep -q "Not synchronised"; then
    log "❌ Không thể đồng bộ thời gian. Dừng lại."
    exit 1
fi

# Run setup script
cd /home/miva/setup || { log "❌ Không thể cd vào setup"; exit 1; }
chmod +x setup_miva.sh
retry_cmd "./setup_miva.sh" "setup_miva.sh"

# Network config
cd /home/miva/docker || { log "❌ Không thể cd vào docker"; exit 1; }
export TAG=latest

retry_cmd "netplan apply" "netplan apply"
retry_cmd "nmcli connection modify 'netplan-usb0' ipv4.ignore-auto-dns yes" "nmcli modify ignore-auto-dns"
retry_cmd "nmcli connection modify 'netplan-usb0' ipv4.dns '8.8.8.8 8.8.4.4'" "nmcli set DNS"
retry_cmd "nmcli con up 'netplan-usb0'" "nmcli con up"

# Docker compose
retry_cmd "docker compose up -d" "docker compose up"

# Mark setup done
touch /home/miva/.setup_done
log "=== Miva setup hoàn tất ==="
