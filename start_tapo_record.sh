#!/bin/bash

# ==========================================
# 設定エリア
# ==========================================
TAPO_IP="192.168.0.61"
TAPO_USER="IlfaErhard"          # Tapoアプリで設定した「カメラのアカウント」
TAPO_PASS="TcH9TdK2tnmmd8M"       # Tapoアプリで設定した「カメラのパスワード」

# 入力は Stream1 (720p)
RTSP_URL1="rtsp://${TAPO_USER}:${TAPO_PASS}@${TAPO_IP}:554/stream1"

BASE_DIR="/mnt/WD_Purple/NVR/tapo_data"
RECORD_DIR="${BASE_DIR}/recordings"
LATEST="${BASE_DIR}/latest.jpg"

SEGMENT_TIME="30"
LATEST_FPS="1"

# VAAPIドライバのパス (ESP32の時の成功例を反映)
export LIBVA_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/dri
VAAPI_DEVICE="/dev/dri/renderD128"

echo "--- Tapo Recording Script (VAAPI Transcode Mode) ---"

if [ ! -d "$RECORD_DIR" ]; then
    mkdir -p "$RECORD_DIR" || { echo "Error: Cannot create directory."; exit 1; }
fi

# ==========================================
# FFmpeg 実行
# ==========================================
# 解説:
# -hwaccel vaapi : 入力(デコード)をGPUで処理
# -filter_complex : 映像を2つに分岐
#    [0:v]split=2[v_rec][v_snap] -> 録画用と静止画用に分ける
#    [v_rec] -> h264_vaapi で再圧縮 (QP=28で容量削減)
#    [v_snap] -> scale_vaapi で縮小 -> hwdownload でメモリに戻してJPEG保存

exec /usr/bin/ffmpeg \
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
        [v_snap]scale_vaapi=w=640:h=-1:format=nv12,hwdownload,format=nv12,fps=${LATEST_FPS}[v_img_out]
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