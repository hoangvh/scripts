#!/bin/sh
set -eu

COMPOSE_DIR=/home/mira/docker
COMPOSE_FILE=$COMPOSE_DIR/docker-compose.yml
RUNTIME_SCRIPT=/usr/local/sbin/mira-runtime-start.sh
SERVICE_FILE=/etc/systemd/system/mira-runtime.service

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: run this script as root" >&2
    exit 1
fi

if [ ! -f "$COMPOSE_FILE" ]; then
    echo "ERROR: compose file not found: $COMPOSE_FILE" >&2
    exit 1
fi

if ! grep -q '^[[:space:]]*mira:[[:space:]]*$' "$COMPOSE_FILE"; then
    echo "ERROR: service 'mira' not found in $COMPOSE_FILE" >&2
    exit 1
fi

if grep -q '^[[:space:]]*restart:[[:space:]]*unless-stopped[[:space:]]*$' "$COMPOSE_FILE"; then
    backup_file="$COMPOSE_FILE.bak.$(date +%Y%m%d-%H%M%S)"
    cp -a "$COMPOSE_FILE" "$backup_file"
    sed -i '0,/^[[:space:]]*restart:[[:space:]]*unless-stopped[[:space:]]*$/s//    restart: always/' "$COMPOSE_FILE"
    echo "Updated restart policy; backup: $backup_file"
elif grep -q '^[[:space:]]*restart:[[:space:]]*always[[:space:]]*$' "$COMPOSE_FILE"; then
    echo "Compose restart policy is already 'always'"
else
    echo "ERROR: expected restart policy not found; refusing an unsafe edit" >&2
    exit 1
fi

docker compose -f "$COMPOSE_FILE" config >/dev/null

cat >"$RUNTIME_SCRIPT" <<'EOF'
#!/bin/sh
set -u

attempt=1
max_attempts=24

while [ "$attempt" -le "$max_attempts" ]; do
    if docker info >/dev/null 2>&1; then
        if ! docker inspect mira >/dev/null 2>&1; then
            docker compose -f /home/mira/docker/docker-compose.yml up -d mira || true
        else
            docker start mira >/dev/null 2>&1 || true
        fi

        if [ "$(docker inspect -f '{{.State.Running}}' mira 2>/dev/null || true)" = "true" ]; then
            echo "mira is running (attempt $attempt)"
            exit 0
        fi
    fi

    echo "mira is not running yet (attempt $attempt/$max_attempts)" >&2
    attempt=$((attempt + 1))
    sleep 5
done

echo "ERROR: failed to start mira after $max_attempts attempts" >&2
exit 1
EOF
chmod 0755 "$RUNTIME_SCRIPT"

cat >"$SERVICE_FILE" <<'EOF'
[Unit]
Description=Ensure MIRA Docker container is running after boot
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/mira-runtime-start.sh
RemainAfterExit=yes
TimeoutStartSec=150

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mira-runtime.service
docker update --restart always mira >/dev/null 2>&1 || true
systemctl restart mira-runtime.service

echo "Installed mira-runtime.service successfully"
systemctl --no-pager --full status mira-runtime.service
