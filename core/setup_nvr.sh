#!/bin/bash
# ---------------------------------------------------------
# setup_nvr.sh（新構成）
#   - unit 本体はテンプレート（ffmpeg_nvr@.service）
#   - カメラごとの差分は override.conf に書く
#   - cameras/*.yaml を読み、enable/disable を管理
#   - TMP_DIR の作成・削除
# ---------------------------------------------------------

set -euo pipefail

echo "[setup_nvr] setup nvr start."

ENV_GATEWAY="/etc/nvr/common_utils_path"
if [ ! -f "$ENV_GATEWAY" ]; then
    echo "Error: $ENV_GATEWAY not found. Please run deploy_nvr.sh first." >&2
    exit 1
fi
source "$ENV_GATEWAY"
source "$COMMON_UTILS"

echo "[debug] NVR_CONFIG_MAIN_FILE = \"${NVR_CONFIG_MAIN_FILE}\""

SYSTEMD_DIR="/etc/systemd/system"

MOTION_TMP_BASE=$(get_main_val '.common.motion_tmp_base')
echo "[debug] MOTION_TMP_BASE = \"${MOTION_TMP_BASE}\""
RECORDS_DIR_BASE=$(get_main_val '.common.records_dir_base')
EVENTS_DIR_BASE=$(get_main_val ".common.events_dir_base")

if ! command -v yq >/dev/null 2>&1; then
    echo "[setup_nvr] Error: yq is not installed" >&2
    exit 1
fi

if [ ! -d "$NVR_CONFIG_CAM_DIR" ]; then
    echo "[setup_nvr] Error: cameras directory not found: $NVR_CONFIG_CAM_DIR" >&2
    exit 1
fi

OVERRIDE_TPL_DIR="$NVR_LIB_DIR/templates/override"

echo "[setup_nvr] Loading camera configs from $NVR_CONFIG_CAM_DIR"

# ---------------------------------------------------------
# 1. YAML に存在するカメラ一覧
# ---------------------------------------------------------
YAML_CAMERAS=()
for f in "$NVR_CONFIG_CAM_DIR"/*.yaml; do
    CAM=$(basename "$f" .yaml)
    YAML_CAMERAS+=("$CAM")
done

echo "[setup_nvr] Cameras: ${YAML_CAMERAS[*]}"

# ---------------------------------------------------------
# 2. systemd に存在するカメラ一覧
# ---------------------------------------------------------
SYSTEMD_CAMERAS=()

while read -r UNIT; do
    if [[ "$UNIT" =~ ffmpeg_nvr@(.*)\.service ]]; then
        SYSTEMD_CAMERAS+=("${BASH_REMATCH[1]}")
    fi
done <<< "$(systemctl list-unit-files --type=service | awk '{print $1}')"

SYSTEMD_CAMERAS=($(printf "%s\n" "${SYSTEMD_CAMERAS[@]}" | sort -u))

echo "[setup_nvr] Systemd cameras: ${SYSTEMD_CAMERAS[*]}"

# ---------------------------------------------------------
# 3. YAML に無いカメラを削除
# ---------------------------------------------------------
for CAM in "${SYSTEMD_CAMERAS[@]}"; do
    if [[ ! " ${YAML_CAMERAS[*]} " =~ " ${CAM} " ]]; then
        echo "[setup_nvr] Removing obsolete camera: $CAM"

        systemctl stop "ffmpeg_nvr@${CAM}.service" || true
        systemctl stop "motion_detector@${CAM}.service" || true
        systemctl stop "motion_event_handler@${CAM}.service" || true

        systemctl disable "ffmpeg_nvr@${CAM}.service" || true
        systemctl disable "motion_detector@${CAM}.service" || true
        systemctl disable "motion_event_handler@${CAM}.service" || true

        rm -rf "$SYSTEMD_DIR/ffmpeg_nvr@${CAM}.service.d"

        rm -rf "$MOTION_TMP_BASE/$CAM"
    fi
done

# ---------------------------------------------------------
# 4. enabled=false のカメラを disable
# ---------------------------------------------------------
for CAM in "${YAML_CAMERAS[@]}"; do
    ENABLED=$(get_cam_val "$CAM" '.enabled')

    if [ "$ENABLED" != "true" ]; then
        echo "[setup_nvr] Disabling camera: $CAM"

        systemctl stop "ffmpeg_nvr@${CAM}.service" || true
        systemctl stop "motion_detector@${CAM}.service" || true
        systemctl stop "motion_event_handler@${CAM}.service" || true

        systemctl disable "ffmpeg_nvr@${CAM}.service" || true
        systemctl disable "motion_detector@${CAM}.service" || true
        systemctl disable "motion_event_handler@${CAM}.service" || true

        rm -rf "$SYSTEMD_DIR/ffmpeg_nvr@${CAM}.service.d"
        rm -rf "$MOTION_TMP_BASE/$CAM"
    fi
done

# ---------------------------------------------------------
# 5. enabled=true のカメラについて override.conf を生成
# ---------------------------------------------------------
echo "[setup_nvr] Generating override.conf..."

for CAM in "${YAML_CAMERAS[@]}"; do
    CAMFILE="$NVR_CONFIG_CAM_DIR/$CAM.yaml"
    ENABLED=$(yq -r '.enabled' "$CAMFILE")
    TYPE=$(yq -r '.type' "$CAMFILE")

    if [ "$ENABLED" != "true" ]; then
        continue
    fi

    echo "[setup_nvr] Camera $CAM (type=$TYPE)"

    TPL="${OVERRIDE_TPL_DIR}/${TYPE}.conf.tpl"
    OVERRIDE_DIR="$SYSTEMD_DIR/ffmpeg_nvr@${CAM}.service.d"
    mkdir -p "$OVERRIDE_DIR"

    SEG=$(yq -r '.ffmpeg.segment_time // ""' "$CAMFILE")
    if [ -z "$SEG" ] || [ "$SEG" = "null" ]; then
        SEG=$(yq -r '.common.default_segment_time' "$NVR_CONFIG_MAIN_FILE")
    fi

    sed "s/{{SEGMENT_TIME}}/${SEG}/g" "$TPL" > "$OVERRIDE_DIR/override.conf"

done

# ---------------------------------------------------------
# 6. systemd reload
# ---------------------------------------------------------
echo "[setup_nvr] Reloading systemd..."
systemctl daemon-reload

# ---------------------------------------------------------
# 7. enable（start は start_nvr.sh に任せる）
# ---------------------------------------------------------
echo "[setup_nvr] Enabling units..."

for CAM in "${YAML_CAMERAS[@]}"; do
    ENABLED=$(get_cam_val "$CAM" '.enabled')
    if [ "$ENABLED" != "true" ]; then
        continue
    fi
    systemctl enable "ffmpeg_nvr@${CAM}.service"
    systemctl enable "motion_detector@${CAM}.service"
    systemctl enable "motion_event_handler@${CAM}.service"
done

# ---------------------------------------------------------
# 8. set storage directories permissions
# ---------------------------------------------------------
echo "[setup_nvr] Setting permissions for storage directories..."
for directory in "$MOTION_TMP_BASE" "$RECORDS_DIR_BASE" "$EVENTS_DIR_BASE" "$NVR_DAYNIGHT_FILE_DIR"; do
    if [ -d "$directory" ]; then
        chown -R "$NVR_USER":"$NVR_GROUP" "$directory"
        chmod 777 "$directory"
    else
        echo "[setup_nvr] Directory $directory does not exist, creating..."
        mkdir -p "$directory"
        chown -R "$NVR_USER":"$NVR_GROUP" "$directory"
        chmod 777 "$directory"
    fi
done

echo "[setup_nvr] Setup complete."
