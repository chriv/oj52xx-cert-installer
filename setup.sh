#!/bin/bash
set -u

SERVICE_NAME="oj52xx-cert"
SCRIPT_NAME="oj52xx-cert.sh"
ENV_FILE="config.env"

# Target Locations
BIN_DIR="/usr/local/bin"
CONF_DIR="/etc/oj52xx-cert"
SYSTEMD_DIR="/etc/systemd/system"
OLD_SYSTEMD_DIR="/lib/systemd/system"
OLD_SERVICE_NAME="installhpcert"

# Root Check
if [[ "$EUID" -ne 0 ]]; then
   echo "CRITICAL: Run as root."
   exit 1
fi

# Files Check
if [[ ! -f "./$SCRIPT_NAME" ]] || [[ ! -f "./$ENV_FILE" ]]; then
    echo "CRITICAL: Script or Env file missing."
    exit 1
fi

echo "--- Step 1: Initial Certificate Installation ---"
echo "Forcing INSECURE=1 to bypass potential bad/expired certs on printer."
echo "Performing FULL installation run..."
echo "----------------------------------------------------"

# Force insecure for this run only
export INSECURE=1

# Run the script. If it fails, we abort immediately.
if ./$SCRIPT_NAME; then
    echo "----------------------------------------------------"
    echo "SUCCESS: Certificate installed successfully."
else
    echo "----------------------------------------------------"
    echo "FAILURE: The script failed to install the certificate."
    echo "Aborting installation to prevent broken service deployment."
    exit 1
fi
unset INSECURE

echo "--- Step 2: Cleanup Old Install ---"
# Stop old service if active
systemctl stop "$OLD_SERVICE_NAME.timer" 2>/dev/null || true
systemctl disable "$OLD_SERVICE_NAME.timer" 2>/dev/null || true

if [[ -f "$OLD_SYSTEMD_DIR/$OLD_SERVICE_NAME.service" ]]; then
    echo "Removing legacy unit: $OLD_SYSTEMD_DIR/$OLD_SERVICE_NAME.service"
    rm "$OLD_SYSTEMD_DIR/$OLD_SERVICE_NAME.service"
fi
if [[ -f "$OLD_SYSTEMD_DIR/$OLD_SERVICE_NAME.timer" ]]; then
    echo "Removing legacy timer: $OLD_SYSTEMD_DIR/$OLD_SERVICE_NAME.timer"
    rm "$OLD_SYSTEMD_DIR/$OLD_SERVICE_NAME.timer"
fi

echo "--- Step 3: Installation ---"
# Install Config
mkdir -p "$CONF_DIR"
cp "./$ENV_FILE" "$CONF_DIR/config.env"
chmod 600 "$CONF_DIR/config.env"
echo "[*] Config installed to $CONF_DIR/config.env"

# Install Script
cp "./$SCRIPT_NAME" "$BIN_DIR/oj52xx-cert"
chmod 700 "$BIN_DIR/oj52xx-cert"
echo "[*] Script installed to $BIN_DIR/oj52xx-cert"

# Install Systemd Units
cp "./$SERVICE_NAME.service" "$SYSTEMD_DIR/"
cp "./$SERVICE_NAME.timer" "$SYSTEMD_DIR/"
systemctl daemon-reload

echo "--- Step 4: Activation ---"
systemctl enable --now "$SERVICE_NAME.timer"
systemctl list-timers --no-pager | grep "$SERVICE_NAME"
echo "Done."
