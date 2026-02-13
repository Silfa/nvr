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

# ---------------------------------------------------------
# 5. ffmpeg 実行
# ---------------------------------------------------------
echo "[esp32cam] Starting ffmpeg for ${CAM}"
echo "[esp32cam] RTSP: $RTSP_URL"
echo "[esp32cam] Outfile: $OUTFILE"

exec /usr/bin/ffmpeg \
    -hide_banner -loglevel warning \
    -init_hw_device vaapi=intel:/dev/dri/renderD128 \
    -filter_hw_device intel \
    \
    -rtsp_transport tcp \
    -timeout 15000000 \
    -max_delay 5000000 \
    -reorder_queue_size 4096 \
    -use_wallclock_as_timestamps 1 \
    -fflags +igndts+genpts+discardcorrupt+nobuffer \
    -analyzeduration 1M \
    -probesize 1M \
    -i "$RTSP_URL" \
    \
    -filter_complex "
        [0:v]split=2[v_to_gpu][v_to_img];
        [v_to_gpu]format=nv12,hwupload[v_enc_out];
        [v_to_img]fifo,fps=5,format=yuv420p,setrange=pc[v_img_final]
    " \
    \
    -map "[v_enc_out]" \
    -c:v h264_vaapi \
    -qp 26 \
    -g 100 \
    -fps_mode cfr -r 5 \
    -max_interleave_delta 0 \
    -reset_timestamps 1 \
    -metadata title="$START_TIME" \
    "$OUTFILE" \
    \
    -map "[v_img_final]" \
    -f image2 \
    -q:v 18 \
    -update 1 \
    -atomic_writing 1 \
    -y \
    "$LATEST"