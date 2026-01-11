#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------
# Define user and group
# ---------------------------------------------------------
NVR_USER="nvruser"
NVR_GROUP="nvruser"


# ---------------------------------------------------------
# Paths
# ---------------------------------------------------------
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

NVR_BASE_DIR="/usr/local/bin/nvr"
NVR_CORE_DIR="${NVR_BASE_DIR}/core"
NVR_COMMON_DIR="${NVR_BASE_DIR}/common"
NVR_LIB_DIR="/usr/local/lib/nvr"
SYSTEMD_DIR="/etc/systemd/system"
ETC_NVR_DIR="/etc/nvr"
DAYNIGHT_FILE_DIR="/dev/shm/nvr/daynight_files.d"

UNIT_TPL_DIR="$REPO_DIR/templates/unit"
OVERRIDE_TPL_DIR="$REPO_DIR/templates/override"
CONFIG_DIR="$REPO_DIR/config"
CORE_SCRIPTS_DIR="$REPO_DIR/core"
COMMON_SCRIPTS_DIR="$REPO_DIR/common"

# ---------------------------------------------------------
# Create user and group if they don't exist
# ---------------------------------------------------------
if ! id -u "$NVR_USER" >/dev/null 2>&1; then
    echo "[deploy] Creating user and group: $NVR_USER"
    groupadd --system "$NVR_GROUP"
    useradd --system --gid "$NVR_GROUP" --shell /usr/sbin/nologin --no-create-home "$NVR_USER"
fi

# ---------------------------------------------------------
# Backup directory
# ---------------------------------------------------------
BACKUP_DIR="/var/backups/nvr_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "[deploy] Backup directory: $BACKUP_DIR"

# ---------------------------------------------------------
# Backup existing installation
# ---------------------------------------------------------
backup_if_exists() {
    local path="$1"
    if [ -e "$path" ]; then
        echo "[deploy] Backing up $path"
        mkdir -p "$BACKUP_DIR$(dirname "$path")"
        cp -a "$path" "$BACKUP_DIR$path"
    fi
}

backup_if_exists "$NVR_BASE_DIR"
backup_if_exists "$NVR_LIB_DIR"
backup_if_exists "$ETC_NVR_DIR"
backup_if_exists "$SYSTEMD_DIR/ffmpeg_nvr@.service"
backup_if_exists "$SYSTEMD_DIR/motion_detector@.service"
backup_if_exists "$SYSTEMD_DIR/motion_event_handler@.service"

# ---------------------------------------------------------
# Create directories
# ---------------------------------------------------------
mkdir -p "$NVR_CORE_DIR"
mkdir -p "$NVR_COMMON_DIR"
mkdir -p "$NVR_LIB_DIR/templates/override"
mkdir -p "$NVR_LIB_DIR/schema"
mkdir -p "$ETC_NVR_DIR/cameras"
mkdir -p "$ETC_NVR_DIR/secrets/cameras"
mkdir -p "$DAYNIGHT_FILE_DIR"

chown -R "$NVR_USER":"$NVR_GROUP" "$DAYNIGHT_FILE_DIR"
chmod -R 755 "$NVR_BASE_DIR"
chmod -R 755 "$NVR_BASE_DIR/core"
chmod -R 755 "$NVR_BASE_DIR/common"

echo "[deploy] Deploying NVR system..."

# ---------------------------------------------------------
# 1. Deploy scripts → $NVR_BASE_DIR(/usr/local/bin/nvr)
# ---------------------------------------------------------
echo "[deploy] Installing scripts to $NVR_BASE_DIR"
cp -r "$CORE_SCRIPTS_DIR/"* "$NVR_BASE_DIR/core/"
cp -r "$COMMON_SCRIPTS_DIR/"* "$NVR_BASE_DIR/common/"

# ---------------------------------------------------------
# 2. Deploy override templates → $NVR_LIB_DIR/templates/override(/usr/local/lib/nvr/templates/override)
# ---------------------------------------------------------
replace_placeholder() {
    sed -e "s|{{NVR_CORE_DIR}}|$NVR_CORE_DIR|g" \
        -e "s|{{NVR_USER}}|$NVR_USER|g" \
        -e "s|{{NVR_GROUP}}|$NVR_GROUP|g" "$1"
}

echo "[deploy] Installing override templates"
for tpl in "$OVERRIDE_TPL_DIR"/*.tpl; do
    out="$NVR_LIB_DIR/templates/override/$(basename "$tpl")"
    replace_placeholder "$tpl" > "$out"
done

# ---------------------------------------------------------
# 3. Deploy systemd unit templates (.tpl → .service)
# ---------------------------------------------------------
echo "[deploy] Installing systemd unit files"

for tpl in "$UNIT_TPL_DIR"/*.tpl; do
    unit_name="$(basename "$tpl" .tpl)"
    out="$SYSTEMD_DIR/$unit_name"

    replace_placeholder "$tpl" > "$out"
    chmod 644 "$out"

    echo "  - Installed $unit_name"
done

# ---------------------------------------------------------
# 4. Deploy schema → /usr/local/lib/nvr/schema
# ---------------------------------------------------------
echo "[deploy] Installing schema files"

for SCHEMA in "$CONFIG_DIR"/*.schema.json; do
    [ -f "$SCHEMA" ] || continue
    cp "$SCHEMA" "$NVR_LIB_DIR/schema/"
    echo "  - $(basename "$SCHEMA")"
done

# ---------------------------------------------------------
# 5. Deploy YAML configs → /etc/nvr
# ---------------------------------------------------------
echo "[deploy] Installing YAML configs"
cp "$CONFIG_DIR/main.yaml" "$ETC_NVR_DIR/"
cp "$CONFIG_DIR/cameras/"*.yaml "$ETC_NVR_DIR/cameras/"
cp "$CONFIG_DIR/secrets/main.yaml" "$ETC_NVR_DIR/secrets/"
cp "$CONFIG_DIR/secrets/cameras/"*.yaml "$ETC_NVR_DIR/secrets/cameras/"

# ---------------------------------------------------------
# 6. Reload systemd
# ---------------------------------------------------------
echo "[deploy] Reloading systemd..."
systemctl daemon-reload

# ---------------------------------------------------------
# 7. Write install paths metadata
# ---------------------------------------------------------
echo "[deploy] Writing install paths metadata"
INSTALL_PATHS="/etc/nvr/install_paths"

cat <<EOF > $INSTALL_PATHS
# Install paths for NVR

# 実行ユーザー情報
user: $NVR_USER
group: $NVR_GROUP

# ディレクトリ情報
base_dir: $NVR_BASE_DIR
core_dir: $NVR_BASE_DIR/core
common_dir: $NVR_BASE_DIR/common
lib_dir: $NVR_LIB_DIR
daynight_file_dir: $DAYNIGHT_FILE_DIR

# 設定ファイル情報
config_main_file: $ETC_NVR_DIR/main.yaml
config_main_secret_file: $ETC_NVR_DIR/secrets/main.yaml
config_cam_dir: $ETC_NVR_DIR/cameras
config_cam_secret_dir: $ETC_NVR_DIR/secrets/cameras
EOF

chown root:root $INSTALL_PATHS
chmod 644 $INSTALL_PATHS

# ---------------------------------------------------------
# 8. Write common_utils.sh path metadata
# ---------------------------------------------------------
echo "COMMON_UTILS=\"$NVR_COMMON_DIR/common_utils.sh\"" > "$ETC_NVR_DIR/common_utils_path"

# 権限を root 所有の読み取り専用にする
chown root:root "$ETC_NVR_DIR/common_utils_path"
chmod 644 "$ETC_NVR_DIR/common_utils_path"

# ---------------------------------------------------------
# Deployment complete
# ---------------------------------------------------------
echo "[deploy] Deployment complete."
echo "[deploy] Backup stored at: $BACKUP_DIR"
