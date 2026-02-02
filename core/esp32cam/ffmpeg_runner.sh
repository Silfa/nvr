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
# 5. ffmpeg 実行 & 終了処理（シグナル制御）
# ---------------------------------------------------------

# systemd からの停止信号に応答し、ffmpeg を止めてからリネーム処理を行うための仕組み
cleanup() {
    echo "[esp32cam] Received termination signal. Stopping ffmpeg..."
    if [ -n "${FFMPEG_PID:-}" ]; then
        kill -TERM "$FFMPEG_PID" 2>/dev/null || true
        wait "$FFMPEG_PID" 2>/dev/null || true
    fi
    
    # 録画終了後のリネームをバックグラウンドで切り離して実行
    (finalize_recording "$OUTFILE" >/dev/null 2>&1 &)
    exit 0
}

# 録画ファイルを計測して正確な開始時刻にリネームする関数
finalize_recording() {
    local target_file="${1:-$OUTFILE}"
    if [ -f "$target_file" ]; then
        echo "[esp32cam] Finalizing $target_file..."
        # ffprobe での計測（接続ラグを除去した正確な長さを取得）
        DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$target_file" || echo 0)
        
        if [[ "$DURATION" != "0" && "$DURATION" != "N/A" ]]; then
            END_TS=$(stat -c %Y "$target_file")
            START_TS=$(echo "$END_TS - $DURATION" | bc | cut -d. -f1)
            
            NEW_NAME=$(date -d "@$START_TS" +%Y%m%d_%H%M%S).mkv
            NEW_PATH="${RECORD_DIR}/${NEW_NAME}"
            
            echo "[esp32cam] Sync complete: Actual start at $NEW_NAME (duration ${DURATION}s)"
            mv "$target_file" "$NEW_PATH"
        else
            echo "[esp32cam] Warning: Could not determine duration for $target_file"
        fi
    fi
}

trap cleanup SIGTERM SIGINT

echo "[esp32cam] Starting ffmpeg for ${CAM}"
echo "[esp32cam] RTSP: $RTSP_URL"
echo "[esp32cam] Temporary outfile: $OUTFILE"

# FFmpeg 実行（バックグラウンドで開始し、PIDを記録）
ffmpeg \
    -hide_banner -loglevel warning \
    \
    -timeout 5000000 \
    -rtsp_transport tcp \
    -fflags +igndts+nobuffer+flush_packets \
    -flags low_delay \
    -use_wallclock_as_timestamps 1 \
    -probesize 150k \
    -analyzeduration 150k \
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
    -vsync cfr \
    -forced-idr 1 \
    -max_interleave_delta 0 \
    -reset_timestamps 1 \
    -metadata title="$START_TIME" \
    "$OUTFILE" &

FFMPEG_PID=$!

# FFmpeg の終了を待機
wait "$FFMPEG_PID" || true

# 通常終了（RuntimeMaxSec 到達時など）
# バックグラウンドで実行し、親プロセスは即座に終了して再起動を促す
(finalize_recording "$OUTFILE" >/dev/null 2>&1 &)

exit 0
