#!/usr/bin/env bash
set -euo pipefail

REPO="aliasgharshams/Quilo-cleaner"
BASE_URL="https://github.com/${REPO}/releases/latest/download"
PUBLIC_KEY="RWTtREeNz08jFJCcH7g9BOAMmd4uyjr1N1zstJiK+TFn+BMc1PGwOXrN"

CLI="/usr/local/bin/quilo-cleaner"
APP_DIR="/usr/local/lib/quilo-cleaner"
WORKER="${APP_DIR}/quilo-cleaner-worker"
DATA_DIR="/var/lib/quilo-cleaner"
SERVICE="/etc/systemd/system/quilo-cleaner.service"

if [ "$(id -u)" -ne 0 ]; then
    echo "این نصب‌کننده باید با دسترسی root اجرا شود."
    exit 1
fi

case "$(uname -m)" in
    x86_64|amd64) ;;
    *)
        echo "این نسخه فقط از Linux x86_64 پشتیبانی می‌کند."
        exit 1
        ;;
esac

command -v apt-get >/dev/null 2>&1 || {
    echo "فعلاً فقط Ubuntu و Debian پشتیبانی می‌شوند."
    exit 1
}

export DEBIAN_FRONTEND=noninteractive

echo "نصب ابزارهای موردنیاز..."
apt-get update -qq
apt-get install -y -qq ca-certificates curl minisign

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

echo "دانلود فایل‌های رسمی QUILO Cleaner..."

for FILE in \
    quilo-cleaner \
    quilo-cleaner-worker \
    SHA256SUMS \
    SHA256SUMS.minisig
do
    curl -fL --retry 5 \
        -o "$FILE" \
        "${BASE_URL}/${FILE}"
done

echo "بررسی امضای دیجیتال..."

minisign -V \
    -P "$PUBLIC_KEY" \
    -m SHA256SUMS \
    -x SHA256SUMS.minisig

echo "بررسی سلامت فایل‌ها..."
sha256sum -c SHA256SUMS

echo "نصب QUILO Cleaner..."

systemctl stop quilo-cleaner.service 2>/dev/null || true

install -d -o root -g root -m 755 "$APP_DIR"
install -d -o root -g root -m 700 "$DATA_DIR"

if [ ! -f "$DATA_DIR/bots.json" ]; then
    printf '[]\n' > "$DATA_DIR/bots.json"
fi

chown root:root "$DATA_DIR/bots.json"
chmod 600 "$DATA_DIR/bots.json"

install -o root -g root -m 755 quilo-cleaner "$CLI"
install -o root -g root -m 755 quilo-cleaner-worker "$WORKER"

cat > "$SERVICE" <<'EOF'
[Unit]
Description=QUILO Cleaner Telegram Worker
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
UMask=0077
Environment=QUILO_DATA_DIR=/var/lib/quilo-cleaner
ExecStart=/usr/local/lib/quilo-cleaner/quilo-cleaner-worker
Restart=always
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=/var/lib/quilo-cleaner

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "$SERVICE"

systemctl daemon-reload
systemctl enable --now quilo-cleaner.service

sleep 2

if ! systemctl is-active --quiet quilo-cleaner.service; then
    echo "سرویس اجرا نشد."
    journalctl -u quilo-cleaner.service -n 30 --no-pager
    exit 1
fi

echo
echo "QUILO Cleaner با موفقیت نصب شد."
echo "برای باز کردن منو اجرا کنید:"
echo "sudo quilo-cleaner"
