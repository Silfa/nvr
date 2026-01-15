#!/bin/bash
# ---------------------------------------------------------
# ffmpeg_nvr.sh
#   - カメラ種別に応じて ffmpeg_runner.sh を呼び出す共通ランチャー
#   - unit テンプレートから呼ばれる
#   - 可変ロジックはすべて scripts/type/ に委譲
# ---------------------------------------------------------

set -euo pipefail

CAM="${1:-}"
if [ -z "$CAM" ]; then
    echo "[ffmpeg_nvr] Error: camera name not provided" >&2
    exit 1
fi

echo "[ffmpeg_nvr] Initializing for camera: $CAM"

ENV_GATEWAY="/etc/nvr/common_utils_path"
if [ ! -f "$ENV_GATEWAY" ]; then
    echo "Error: $ENV_GATEWAY not found. Please run deploy_nvr.sh first." >&2
    exit 1
fi
source "$ENV_GATEWAY"
source "$COMMON_UTILS"

CAMFILE="${NVR_CONFIG_CAM_DIR}/${CAM}.yaml"

if [ ! -f "$CAMFILE" ]; then
    echo "[ffmpeg_nvr] Error: camera config not found: $CAMFILE" >&2
    exit 1
fi

# ---------------------------------------------------------
# 1. カメラ種別を取得
# ---------------------------------------------------------
TYPE=$(get_cam_val "$CAM" '.type')
if [ -z "$TYPE" ] || [ "$TYPE" = "null" ]; then
    echo "[ffmpeg_nvr] Error: .type is missing in $CAMFILE" >&2
    exit 1
fi

RUNNER="${NVR_CORE_DIR}/${TYPE}/ffmpeg_runner.sh"

if [ ! -x "$RUNNER" ]; then
    echo "[ffmpeg_nvr] Error: runner not found: $RUNNER" >&2
    exit 1
fi

echo "[ffmpeg_nvr] Starting camera '${CAM}' (type=${TYPE})"
echo "[ffmpeg_nvr] Runner: $RUNNER"

# ---------------------------------------------------------
# 2. カメラ種別ごとの runner を実行
# ---------------------------------------------------------
exec "$RUNNER" "$CAM"
