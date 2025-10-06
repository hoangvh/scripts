#!/bin/bash
# Script: setup_hdmi_hotplug.sh
# Purpose: Tự động cài đặt HDMI hotplug handler và patch mpv_init.sh

set -e

echo "[INFO] === BẮT ĐẦU CẤU HÌNH HDMI HOTPLUG ==="

#######################################
# 1️⃣ Tạo service
#######################################
SERVICE_FILE="/etc/systemd/system/hdmi-hotplug-handler.service"
cat > "$SERVICE_FILE" << 'EOF'
[Unit]
Description=Handle HDMI hotplug event
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hdmi-hotplug-handler.sh

[Install]
WantedBy=multi-user.target
EOF
echo "[OK] Tạo $SERVICE_FILE"

#######################################
# 2️⃣ Tạo script handler
#######################################
HANDLER="/usr/local/bin/hdmi-hotplug-handler.sh"
cat > "$HANDLER" << 'EOF'
#!/bin/bash
STATUS=$(cat /sys/class/drm/card0-HDMI-A-1/status)
if [ "$STATUS" = "connected" ]; then
    logger "HDMI connected, setting resolution and restarting MPV"
    export DISPLAY=:0
    export XAUTHORITY=/root/.Xauthority

    # Set resolution
    xrandr --output HDMI-1 --mode 1920x1080 --primary

    # Restart mpv windows
    /usr/local/bin/mpv_init.sh
fi
EOF
chmod +x "$HANDLER"
echo "[OK] Tạo $HANDLER"

#######################################
# 3️⃣ Tạo udev rule
#######################################
RULE="/etc/udev/rules.d/99-hdmi-hotplug.rules"
cat > "$RULE" << 'EOF'
ACTION=="change", SUBSYSTEM=="drm", RUN+="/bin/systemctl start hdmi-hotplug-handler.service"
EOF
echo "[OK] Tạo $RULE"

#######################################
# 4️⃣ Patch mpv_init.sh
#######################################
MPV_INIT="/usr/local/bin/mpv_init.sh"
BACKUP="${MPV_INIT}.bak"

if [ ! -f "$MPV_INIT" ]; then
    echo "[WARN] Không tìm thấy $MPV_INIT, bỏ qua bước patch!"
else
    cp "$MPV_INIT" "$BACKUP"
    echo "[INFO] Sao lưu: $BACKUP"

    if ! grep -q "Force HDMI output mode" "$MPV_INIT"; then
        sed -i '/UPGRADE=\/root\/mgwp\/upgrade\/upgrade.tag/a \
# Force HDMI output mode if connected\nif DISPLAY=:0 XAUTHORITY=/root/.Xauthority xrandr | grep -q "HDMI-1 connected"; then\n    echo "[INFO] HDMI detected, setting mode 1920x1080..."\n    DISPLAY=:0 XAUTHORITY=/root/.Xauthority xrandr --output HDMI-1 --mode 1920x1080 --primary\nelse\n    echo "[WARN] HDMI not connected!"\nfi\n' "$MPV_INIT"
        echo "[OK] Đã chèn đoạn kiểm tra HDMI vào $MPV_INIT"
    else
        echo "[INFO] Đã có đoạn kiểm tra HDMI, bỏ qua."
    fi
fi

#######################################
# 5️⃣ Reload systemd và udev
#######################################
systemctl daemon-reload
systemctl enable hdmi-hotplug-handler.service
udevadm control --reload-rules
udevadm trigger

echo "[✅] Cấu hình hoàn tất! Vui lòng rút cáp HDMI và cắm lại để thử hoặc reboot."
