#!/bin/bash
# ---------------------------------------------------------
# start_nvr.sh
#   - Start all NVR services based on /etc/nvr/cameras/*.yaml
# ---------------------------------------------------------
set -euo pipefail

ENV_GATEWAY="/etc/nvr/common_utils_path"
if [ ! -f "$ENV_GATEWAY" ]; then
    echo "Error: $ENV_GATEWAY not found. Please run deploy_nvr.sh first." >&2
    exit 1
fi
source "$ENV_GATEWAY"
source "$COMMON_UTILS"

echo "[start_nvr] Reading camera configs from $NVR_CONFIG_CAM_DIR"

# カメラ一覧を取得（ファイル名＝カメラ名）
CAMERAS=$(basename -a "$NVR_CONFIG_CAM_DIR"/*.yaml 2>/dev/null | sed 's/\.yaml$//')

if [ -z "$CAMERAS" ]; then
    echo "[start_nvr] error: No camera YAML files found."
    exit 1
fi

echo "[start_nvr] Cameras: $CAMERAS"

for CAM in $CAMERAS; do
    CAMFILE="$NVR_CONFIG_CAM_DIR/$CAM.yaml"

    # enabled=false のカメラはスキップ
    ENABLED=$(yq -r '.enabled // "false"' "$CAMFILE")
    if [ "$ENABLED" != "true" ]; then
        echo "[start_nvr] Skipping $CAM (enabled=false)"
        continue
    fi

    echo "[start_nvr] Starting camera: $CAM"

    # ffmpeg_nvr サービス
    systemctl start ffmpeg_nvr@"$CAM".service
    echo -n "[start_nvr] Waiting for ffmpeg_nvr@$CAM to become active"
    for i in {1..10}; do
        if systemctl is-active --quiet ffmpeg_nvr@"$CAM".service; then
            echo " OK"
            break
        fi
        echo -n "."
        sleep 1
    done

    # motion_detector サービス
    systemctl start motion_detector@"$CAM".service
    echo -n "[start_nvr] Waiting for motion_detector@$CAM to become active"
    for i in {1..10}; do
        if systemctl is-active --quiet motion_detector@"$CAM".service; then
            echo " OK"
            break
        fi
        echo -n "."
        sleep 1
    done

    # motion_event_handler サービス
    systemctl start motion_event_handler@"$CAM".service
    echo -n "[start_nvr] Waiting for motion_event_handler@$CAM to become active"
    for i in {1..10}; do
        if systemctl is-active --quiet motion_event_handler@"$CAM".service; then
            echo " OK"
            break
        fi
        echo -n "."
        sleep 1
    done

done

echo "[start_nvr] All enabled cameras started."

systemctl start nvr-web.service
echo "[start_nvr] WebUI started."
