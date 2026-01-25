#!/bin/bash
# ---------------------------------------------------------
# stop_nvr.sh
#   - NVR の全コンポーネントを安全に停止する
#   - 停止対象は systemd の実際の稼働状態から動的に検出
#   - 停止順序：handler → opencv → ffmpeg
# ---------------------------------------------------------

set -euo pipefail

echo "[stop_nvr] Scanning running NVR services..."

# ---------------------------------------------------------
# 1. systemd から稼働中の NVR 関連サービスを抽出
# ---------------------------------------------------------
RUNNING_SERVICES=$(
    systemctl list-units --type=service --state=running --no-legend \
        | awk '{print $1}' \
        | grep -E '^(motion_event_handler@|motion_detector@|ffmpeg_nvr@)' || true
)

if [ -z "${RUNNING_SERVICES:-}" ]; then
    echo "[stop_nvr] No running NVR services found."
    exit 0
fi

# ---------------------------------------------------------
# 2. カメラ名を抽出してユニーク化
# ---------------------------------------------------------
CAMERAS=$(echo "$RUNNING_SERVICES" \
    | sed -E 's/^.*@([^.]+)\.service$/\1/' \
    | sort -u)

echo "[stop_nvr] Detected cameras: $CAMERAS"

# ---------------------------------------------------------
# 3. カメラごとに停止処理
# ---------------------------------------------------------
for CAM in $CAMERAS; do
    echo "[stop_nvr] stopping ${CAM} (handler → motion_detector → ffmpeg)"

    # 1. motion event handler
    if systemctl is-active --quiet "motion_event_handler@${CAM}.service" \
        || systemctl is-failed --quiet "motion_event_handler@${CAM}.service"; then
        systemctl stop "motion_event_handler@${CAM}.service" || \
            echo "[stop_nvr] warning: failed to stop handler for ${CAM}"
    else
        echo "[stop_nvr] motion event handler not running for ${CAM}"
    fi

    # 2. motion_detector
    if systemctl is-active --quiet "motion_detector@${CAM}.service" \
        || systemctl is-failed --quiet "motion_detector@${CAM}.service"; then
        systemctl stop "motion_detector@${CAM}.service" || \
            echo "[stop_nvr] warning: failed to stop motion_detector for ${CAM}"
    else
        echo "[stop_nvr] motion_detector not running for ${CAM}"
    fi

    # 3. ffmpeg
    if systemctl is-active --quiet "ffmpeg_nvr@${CAM}.service" \
        || systemctl is-failed --quiet "ffmpeg_nvr@${CAM}.service"; then

        systemctl stop "ffmpeg_nvr@${CAM}.service" || \
            echo "[stop_nvr] warning: failed to stop ffmpeg for ${CAM}"
    else
        echo "[stop_nvr] ffmpeg not running for ${CAM}"
    fi


    echo "[stop_nvr] done ${CAM}"
done

echo "[stop_nvr] All running NVR services stopped."
