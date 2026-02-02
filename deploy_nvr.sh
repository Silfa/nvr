#!/bin/bash
set -euo pipefail

# ==============================================================================
# NVR System Deployment Script
#
# This script deploys the NVR (Network Video Recorder) application and its
# components to the local system. It handles user creation, directory setup,
# script installation, configuration, and systemd service setup.
# Must be run with root privileges.
# ==============================================================================

# ---------------------------------------------------------
# Ensure script is run as root
# ---------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use sudo." >&2
    exit 1
fi

# ---------------------------------------------------------
# Load deployment configuration
# ---------------------------------------------------------
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_CONF="$REPO_DIR/deploy_nvr.conf"

if [ -f "$DEPLOY_CONF" ]; then
    echo "[deploy] Loading configuration from $DEPLOY_CONF"
    source "$DEPLOY_CONF"
else
    echo "[deploy] Error: Configuration file not found: $DEPLOY_CONF" >&2
    exit 1
fi

# ---------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------
UPDATE_CONFIG=false
WEB_ONLY=false
USAGE="Usage: $0 [--web-only] [--update-config]"

while [[ $# -gt 0 ]]; do
    case $1 in
        --web-only|-w)
            WEB_ONLY=true
            shift
            ;;
        --update-config|-u)
            UPDATE_CONFIG=true
            shift
            ;;
        --help|-h)
            echo "$USAGE"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            echo "$USAGE"
            exit 1
            ;;
    esac
done

if [ "$WEB_ONLY" = true ]; then
    echo "[deploy] Mode: Web UI Only"
fi


# ---------------------------------------------------------
# Paths
# ---------------------------------------------------------
VENV_DIR="/usr/local/nvr-venv"
WEB_BACKEND_SRC="$REPO_DIR/web/backend"

# Destination paths (NVR_USER, NVR_GROUP, NVR_BASE_DIR, NVR_LIB_DIR, DAYNIGHT_FILE_DIR are loaded from deploy_nvr.conf)
NVR_CORE_DIR="${NVR_BASE_DIR}/core"
NVR_COMMON_DIR="${NVR_BASE_DIR}/common"
SYSTEMD_DIR="/etc/systemd/system"
ETC_NVR_DIR="/etc/nvr"

# Source paths from repository
UNIT_TPL_DIR="$REPO_DIR/templates/unit"
OVERRIDE_TPL_DIR="$REPO_DIR/templates/override"
CONFIG_DIR="$REPO_DIR/config"
CORE_SCRIPTS_DIR="$REPO_DIR/core"
COMMON_SCRIPTS_DIR="$REPO_DIR/common"

# ---------------------------------------------------------
# Pre-flight Checks
# ---------------------------------------------------------
echo "[check] Running pre-flight checks..."

# 4. Check for NVR source code directories
echo "[check] Verifying source code directories..."
REQUIRED_DIRS=(
    "$CORE_SCRIPTS_DIR"
    "$COMMON_SCRIPTS_DIR"
    "$WEB_BACKEND_SRC"
    "$CONFIG_DIR"
)
for dir in "${REQUIRED_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        echo "[check] Error: Required source directory not found: $dir" >&2
        exit 1
    fi
done

# 8. Setup Python virtual environment
echo "[deploy] Verifying Python virtual environment at $VENV_DIR..."

if ! command -v python3 >/dev/null 2>&1; then
    echo "[deploy] Error: python3 is not installed." >&2
    exit 1
fi

if [ ! -d "$VENV_DIR" ] || [ ! -x "$VENV_DIR/bin/python" ]; then
    echo "[deploy] Creating Python virtual environment..."
    if ! python3 -m venv "$VENV_DIR"; then
        echo "[deploy] Error: Failed to create virtual environment." >&2
        echo "  Ensure 'python3-venv' is installed (e.g., sudo apt install python3-venv)." >&2
        exit 1
    fi
    echo "  - Created venv at $VENV_DIR"
fi

# 9. Verify/Install dependencies
echo "[deploy] Verifying Python dependencies..."
if ! "$VENV_DIR/bin/python" -c "import yaml" >/dev/null 2>&1; then
    echo "[deploy] 'pyyaml' not found. Installing requirements..."
    if [ -f "$WEB_BACKEND_SRC/requirements.txt" ]; then
        "$VENV_DIR/bin/pip" install -r "$WEB_BACKEND_SRC/requirements.txt"
    else
        echo "[deploy] Error: requirements.txt not found at $WEB_BACKEND_SRC" >&2
        exit 1
    fi
fi

# 10. Check for ffmpeg
echo "[check] Verifying 'ffmpeg' installation..."
if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "[check] Error: 'ffmpeg' is not installed." >&2
    echo "  Please install it (e.g., sudo apt install ffmpeg) before deploying." >&2
    exit 1
fi

echo "[check] All checks passed."


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

if [ "$WEB_ONLY" = false ]; then
    backup_if_exists "$NVR_BASE_DIR"
    backup_if_exists "$NVR_LIB_DIR"
    backup_if_exists "$ETC_NVR_DIR"
    backup_if_exists "$SYSTEMD_DIR/ffmpeg_nvr@.service"
    backup_if_exists "$SYSTEMD_DIR/motion_detector@.service"
    backup_if_exists "$SYSTEMD_DIR/motion_event_handler@.service"
fi

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

chown -R "$NVR_USER":"$NVR_GROUP" "$DAYNIGHT_FILE_DIR" "$ETC_NVR_DIR"
chmod -R 755 "$NVR_BASE_DIR"
chmod -R 755 "$NVR_BASE_DIR/core"
chmod -R 755 "$NVR_BASE_DIR/common"
chmod -R 755 "$ETC_NVR_DIR"

echo "[deploy] Deploying NVR system..."

# ---------------------------------------------------------
# 1. Deploy core and common scripts → $NVR_CORE_DIR, $NVR_COMMON_DIR
# ---------------------------------------------------------
if [ "$WEB_ONLY" = false ]; then
    echo "[deploy] Installing scripts to $NVR_BASE_DIR"
    cp -r "$CORE_SCRIPTS_DIR/"* "$NVR_BASE_DIR/core/"
    cp -r "$COMMON_SCRIPTS_DIR/"* "$NVR_BASE_DIR/common/"
fi

# ---------------------------------------------------------
# 2. Deploy override templates → $NVR_LIB_DIR/templates/override
# ---------------------------------------------------------
replace_placeholder() {
    sed -e "s#{{NVR_CORE_DIR}}#${NVR_CORE_DIR}#g" \
        -e "s#{{NVR_USER}}#${NVR_USER}#g" \
        -e "s#{{NVR_GROUP}}#${NVR_GROUP}#g" \
        -e "s#{{NVR_BASE_DIR}}#${NVR_BASE_DIR}#g" \
        -e "s#{{ETC_NVR_DIR}}#${ETC_NVR_DIR}#g" \
        -e "s#{{VENV_DIR}}#${VENV_DIR}#g" "$1"
}

if [ "$WEB_ONLY" = false ]; then
    echo "[deploy] Installing override templates"
    for tpl in "$OVERRIDE_TPL_DIR"/*.tpl; do
        out="$NVR_LIB_DIR/templates/override/$(basename "$tpl")"
        replace_placeholder "$tpl" > "$out"
    done
fi

# ---------------------------------------------------------
# 3. Deploy systemd unit files from templates → $SYSTEMD_DIR
# ---------------------------------------------------------
echo "[deploy] Installing systemd unit files"

for tpl in "$UNIT_TPL_DIR"/*.tpl; do
    unit_name="$(basename "$tpl" .tpl)"
    
    # If in WEB_ONLY mode, only install nvr-web.service
    if [ "$WEB_ONLY" = true ]; then
        if [[ "$unit_name" != "nvr-web.service" ]]; then
            continue
        fi
    fi

    out="$SYSTEMD_DIR/$unit_name"

    replace_placeholder "$tpl" > "$out"
    chmod 644 "$out"

    echo "  - Installed $unit_name"
done

# ---------------------------------------------------------
# 4. Deploy JSON schema files → $NVR_LIB_DIR/schema
# ---------------------------------------------------------
if [ "$WEB_ONLY" = false ]; then
    echo "[deploy] Installing schema files"
    shopt -s nullglob
    for SCHEMA in "$CONFIG_DIR"/*.schema.json; do
        cp "$SCHEMA" "$NVR_LIB_DIR/schema/"
        echo "  - $(basename "$SCHEMA")"
    done
fi

# ---------------------------------------------------------
# 5. Deploy YAML configuration files → $ETC_NVR_DIR
# ---------------------------------------------------------
echo "[deploy] Installing YAML configs"

install_yaml() {
    local src="$1"
    local dest="$2"
    if [ -f "$dest" ] && [ "$UPDATE_CONFIG" = false ]; then
        echo "  - Skipping $(basename "$dest") (already exists)"
    else
        cp "$src" "$dest"
        echo "  - Installed $(basename "$dest")"
    fi
}

install_yaml "$CONFIG_DIR/main.yaml" "$ETC_NVR_DIR/main.yaml"

shopt -s nullglob
for cam_yaml in "$CONFIG_DIR/cameras/"*.yaml; do
    install_yaml "$cam_yaml" "$ETC_NVR_DIR/cameras/$(basename "$cam_yaml")"
done

mkdir -p "$ETC_NVR_DIR/masks"
chmod 777 "$ETC_NVR_DIR/masks"

install_yaml "$CONFIG_DIR/secrets/main.yaml" "$ETC_NVR_DIR/secrets/main.yaml"
for cam_secret_yaml in "$CONFIG_DIR/secrets/cameras/"*.yaml; do
    install_yaml "$cam_secret_yaml" "$ETC_NVR_DIR/secrets/cameras/$(basename "$cam_secret_yaml")"
done

# ---------------------------------------------------------
# 6. Reload systemd
# ---------------------------------------------------------
echo "[deploy] Reloading systemd..."
systemctl daemon-reload

# ---------------------------------------------------------
# 7. Write install paths metadata → $ETC_NVR_DIR/install_paths
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
common_utils_path: $NVR_COMMON_DIR/common_utils.sh
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
# 9. Deploy Web UI
# ---------------------------------------------------------
echo "[deploy] Deploying Web UI..."

WEB_FRONTEND_SRC="$REPO_DIR/web/frontend/dist"
WEB_DEST_DIR="$NVR_BASE_DIR/web"

# Create web directories
mkdir -p "$WEB_DEST_DIR"
rm -rf "$WEB_DEST_DIR/frontend" "$WEB_DEST_DIR/backend"

# Copy build artifacts and backend code
if [ -d "$WEB_FRONTEND_SRC" ]; then
    echo "[deploy] Installing Frontend..."
    mkdir -p "$WEB_DEST_DIR/frontend"
    cp -r "$WEB_FRONTEND_SRC"/* "$WEB_DEST_DIR/frontend/"
else
    echo "[deploy] Warning: Frontend build not found at $WEB_FRONTEND_SRC"
fi

echo "[deploy] Installing Backend..."
cp -r "$WEB_BACKEND_SRC" "$WEB_DEST_DIR/"

# Setup Python venv using common config if available, or create new one for web?
# For simplicity, we assume NVR_VENV (python_venv_dir) is managed externally or via separate setup script.
# But here we should probably ensure requirements are installed if we want to run it.
# To keep deploy script idempotent and fast, maybe skip heavy pip install here or check?
# Let's assume the venv at /usr/local/nvr-venv exists and we update it.

if [ -f "$WEB_BACKEND_SRC/requirements.txt" ] && [ -d "$VENV_DIR" ]; then
    echo "[deploy] Installing Python requirements..."
    "$VENV_DIR/bin/pip" install --quiet -r "$WEB_BACKEND_SRC/requirements.txt"
fi

# ---------------------------------------------------------
# 10. Deploy Nginx Template
# ---------------------------------------------------------
echo "[deploy] Installing Nginx template..."
NGINX_TPL_SRC="$REPO_DIR/templates/nvr-web.nginx.conf"
NGINX_TPL_DEST="$NVR_LIB_DIR/templates/nvr-web.nginx.conf"
mkdir -p "$NVR_LIB_DIR/templates"

if [ -f "$NGINX_TPL_SRC" ]; then
    cp "$NGINX_TPL_SRC" "$NGINX_TPL_DEST"
    chmod 644 "$NGINX_TPL_DEST"
    echo "  - Installed nginx template to $NGINX_TPL_DEST"
else
    echo "[deploy] Warning: Nginx template not found at $NGINX_TPL_SRC"
fi

# ---------------------------------------------------------
# Deployment complete
# ---------------------------------------------------------
echo "[deploy] Deployment complete."
echo "[deploy] Backup stored at: $BACKUP_DIR"
