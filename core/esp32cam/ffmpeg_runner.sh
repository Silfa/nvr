#!/bin/bash
# ---------------------------------------------------------
# esp32cam/ffmpeg_runner.sh (new YAML version)
#   - ESP32-CAM 専用録画エンジン
#   - MJPEG → MKV copy
#   - latest.jpg を 5fps で更新
#   - 分割は systemd RuntimeMaxSec に任せる
# ---------------------------------------------------------

set -euo pipefail

CAM="$1"
if [ -z "$CAM" ]; then
    echo "[esp32cam] Error: camera name not provided" >&2
    exit 1
fi

ENV_GATEWAY="/etc/nvr/common_utils_path"
if [ ! -f "$ENV_GATEWAY" ]; then
    echo "Error: $ENV_GATEWAY not found. Please run deploy_nvr.sh first." >&2
    exit 1
fi
source "$ENV_GATEWAY"
source "$COMMON_UTILS"

CAMCFG_PUB="${NVR_CONFIG_CAM_DIR}/${CAM}.yaml"

if [ ! -f "$CAMCFG_PUB" ]; then
    echo "[esp32cam] Error: camera config not found: $CAMCFG_PUB" >&2
    exit 1
fi

# ---------------------------------------------------------
# 1. 共通設定読み込み
# ---------------------------------------------------------
MOTION_TMP_BASE=$(get_main_val '.common.motion_tmp_base')
RECORDS_DIR_BASE=$(get_main_val '.common.records_dir_base')

# ---------------------------------------------------------
# 2. ESP32-CAM 接続情報（新 YAML 構造）
# ---------------------------------------------------------
HOST=$(get_cam_val "$CAM" '.connection.host')
RTSP_PORT=$(get_cam_val "$CAM" '.esp32cam.rtsp_port // 8554')

RTSP_URL="rtsp://${HOST}:${RTSP_PORT}/stream"
echo "[esp32cam] RTSP URL: $RTSP_URL"

# ---------------------------------------------------------
# 3. ディレクトリ準備
# ---------------------------------------------------------
MOTION_TMP_DIR="${MOTION_TMP_BASE}/${CAM}"
RECORD_DIR="${RECORDS_DIR_BASE}/${CAM}"
LATEST="${MOTION_TMP_DIR}/latest.jpg"

mkdir -p "$MOTION_TMP_DIR" "$RECORD_DIR"
chmod 777 "$MOTION_TMP_DIR" "$RECORD_DIR"

# ---------------------------------------------------------
# 4. 録画ファイル名（systemd 再起動ごとに新規作成）
# ---------------------------------------------------------
START_TIME=$(date -Is)
OUTFILE="${RECORD_DIR}/$(date +%Y%m%d_%H%M%S).mkv"

echo "[esp32cam] Starting ffmpeg for ${CAM}"
echo "[esp32cam] RTSP: $RTSP_URL"
echo "[esp32cam] OUTFILE: $OUTFILE"

# ---------------------------------------------------------
# 5. ffmpeg 実行
# ---------------------------------------------------------
exec ffmpeg \
    -hide_banner -loglevel warning \
    \
    -stimeout 5000000 \
    -rtsp_transport tcp \
    -i "$RTSP_URL" \
    \
    -y \
    \
    -map 0:v \
    -vf fps=5 \
    -q:v 5 \
    -update 1 "$LATEST" \
    \
    -map 0:v \
    -c:v libx264 \
    -preset veryfast \
    -crf 23 \
    -pix_fmt yuv420p \
    -reset_timestamps 1 \
    -metadata title="$START_TIME" \
    "$OUTFILE"
