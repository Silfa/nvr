#!/bin/bash
# ---------------------------------------------------------
# tapoc113/ffmpeg_runner.sh (new YAML version)
#   - tapoc113用録画エンジン
#   - RTSP → MKV copy
#   - latest.jpg を 5fps で更新
# ---------------------------------------------------------

set -euo pipefail

CAM="$1"
if [ -z "$CAM" ]; then
    echo "[tapoc113] Error: camera name not provided" >&2
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
    echo "[tapoc113] Error: camera config not found: $CAMCFG_PUB" >&2
    exit 1
fi

# ---------------------------------------------------------
# 1. 共通設定読み込み
# ---------------------------------------------------------
MOTION_TMP_BASE=$(get_main_val '.common.motion_tmp_base')
RECORDS_DIR_BASE=$(get_main_val '.common.records_dir_base')

# ---------------------------------------------------------
# 2. 接続情報
# ---------------------------------------------------------
HOST=$(get_cam_val "$CAM" '.connection.host')
RTSP_PORT=$(get_cam_val "$CAM" '.connection.port // 554')
USERID=$(get_cam_val "$CAM" '.connection.userid')
PASSWD=$(get_cam_val "$CAM" '.connection.passwd')

RTSP_URL1="rtsp://${USERID}:${PASSWD}@${HOST}:${RTSP_PORT}/stream1"
RTSP_URL2="rtsp://${USERID}:${PASSWD}@${HOST}:${RTSP_PORT}/stream2"

# ---------------------------------------------------------
# 3. ディレクトリ準備
# ---------------------------------------------------------
MOTION_TMP_DIR="${MOTION_TMP_BASE}/${CAM}"
RECORD_DIR="${RECORDS_DIR_BASE}/${CAM}"
LATEST="${MOTION_TMP_DIR}/latest.jpg"

mkdir -p "$MOTION_TMP_DIR" "$RECORD_DIR"
chmod 777 "$MOTION_TMP_DIR" "$RECORD_DIR"

# ---------------------------------------------------------
# 4. 録画関係
# ---------------------------------------------------------
SEGMENT_TIME=$(get_cam_val "$CAM" '.ffmpeg.segment_time')
LATEST_FPS=$(get_cam_val "$CAM" '.ffmpeg.latest_fps')

# VAAPIドライバのパス (ESP32の時の成功例を反映)
# export LIBVA_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/dri
VAAPI_DEVICE="/dev/dri/renderD128"

# ---------------------------------------------------------
# 5. ffmpeg 実行
# ---------------------------------------------------------
echo "[tapoc113] Starting ffmpeg for ${CAM}"
echo "[tapoc113] RTSP: ${RTSP_URL1}, ${RTSP_URL2}"
echo "[tapoc113] Record dir: ${RECORD_DIR}"

#exec /opt/ffmpeg/ffmpeg-7.0.2-amd64-static/ffmpeg \
exec ffmpeg \
    -hide_banner -loglevel warning \
    \
    -init_hw_device vaapi=intel:${VAAPI_DEVICE} \
    -filter_hw_device intel \
    \
    -thread_queue_size 2048 \
    -hwaccel vaapi \
    -hwaccel_output_format vaapi \
    -hwaccel_device intel \
    \
    -rtsp_transport udp \
    -reorder_queue_size 4096 \
    -buffer_size 2000000 \
    -timeout 5000000 \
    -i "$RTSP_URL1" \
    \
    -filter_complex "
        [0]split=2[v_rec][v_snap];
        [v_rec]scale_vaapi=format=nv12[v_enc_in];
        [v_snap]scale_vaapi=w=640:h=360:format=nv12,
                hwdownload,
                format=nv12,
                fps=${LATEST_FPS}[v_img_out]
    " \
    \
    -map "[v_enc_in]" \
    -c:v h264_vaapi \
    -qp 28 \
    -g 60 \
    -bf 0 \
    -c:a aac \
    -f segment \
    -segment_time ${SEGMENT_TIME} \
    -segment_format matroska \
    -strftime 1 \
    -reset_timestamps 1 \
    "$RECORD_DIR/%Y%m%d_%H%M%S.mkv" \
    \
    -map "[v_img_out]" \
    -an \
    -f image2 \
    -update 1 \
    -atomic_writing 1 \
    -y \
    "$LATEST"
    