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

# Install dependencies (full Xorg + Openbox)
log "Cài đặt các gói dependency cần thiết (full Xorg + Openbox)..."
retry_cmd "apt-get update -y" "apt-get update"
retry_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y \
    git curl wget unzip xz-utils ca-certificates \
    xorg openbox x11-utils x11-xserver-utils xinit dbus-x11" "Cài đặt Xorg + Openbox"

log "✅ Cài đặt Xorg và Openbox hoàn tất."

# Clone or update repositoryuzi    
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

# Download hw_test
log "Tải hw_test..."
retry_cmd "curl -fsSL https://raw.githubusercontent.com/hoangvh/miva-hw-test/refs/heads/main/hw_test -o /usr/local/bin/hw_test && chmod +x /usr/local/bin/hw_test" "Download hw_test"

# Kiểm tra thời gian hệ thống so với RTC
log "Kiểm tra thời gian hệ thống và RTC..."
if hwclock --verbose >/dev/null 2>&1; then
    SYS_TIME=$(date '+%s')
    RTC_TIME=$(hwclock --get | xargs -I{} date -d "{}" '+%s')
    DIFF=$(( SYS_TIME - RTC_TIME ))
    if [ ${DIFF#-} -gt 30 ]; then
        log "⏱ Thời gian lệch > 30s, thực hiện đồng bộ..."
        retry_cmd "hwclock --hctosys" "Đồng bộ RTC -> system time"
        retry_cmd "chronyc makestep" "Đồng bộ NTP tức thì"
    else
        log "✅ Thời gian hệ thống và RTC gần đúng, bỏ qua đồng bộ."
    fi
else
    log "⚠️ Không phát hiện RTC hoặc hwclock lỗi, bỏ qua đồng bộ."
fi

# Run setup script
cd /home/miva/setup || { log "❌ Không thể cd vào setup"; exit 1; }
chmod +x setup_miva.sh
retry_cmd "./setup_miva.sh" "setup_miva.sh"

# Docker compose
cd /home/miva/docker || { log "❌ Không thể cd vào docker"; exit 1; }
export TAG=latest
retry_cmd "docker compose up -d" "docker compose up"

# Mark setup done
touch /home/miva/.setup_done
log "=== Miva setup hoàn tất ==="
echo "🎉 Miva setup completed! Xorg + Openbox ready, video display và window management có thể sử dụng."
