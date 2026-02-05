#!/bin/bash
# ---------------------------------------------------------
# motion_event_handler.sh (new YAML version)
#   - Uses:
#       /etc/nvr/main.yaml
#       /etc/nvr/cameras/<CAM>.yaml
#   - Handles event start/end, JPEG saving, brightness stats
# ---------------------------------------------------------

set -euo pipefail

CAM="$1"
if [ -z "$CAM" ]; then
    echo "Usage: motion_event_handler.sh <camera_name>"
    exit 1
fi

# ---------------------------------------------------------
# 0. Define Constants and Load Install Paths
# ---------------------------------------------------------
ENV_GATEWAY="/etc/nvr/common_utils_path"
if [ ! -f "$ENV_GATEWAY" ]; then
    echo "Error: $ENV_GATEWAY not found. Please run deploy_nvr.sh first." >&2
    exit 1
fi
source "$ENV_GATEWAY"
source "$COMMON_UTILS"

# ---------------------------------------------------------
# 1. Load configuration (YAML)
# ---------------------------------------------------------

# event.timeout（個別 → default）
IDLE_SEC=$(get_nvr_val "$CAM" ".event.timeout" ".common.default_event_timeout")

# events_dir_base（main.yaml）
EVENTS_BASE=$(get_main_val ".common.events_dir_base")

# motion_tmp_base（main.yaml）
TMP_BASE=$(get_main_val ".common.motion_tmp_base")

# 一時ディレクトリ
TMP_DIR="$TMP_BASE/$CAM"
LATEST="$TMP_DIR/latest.jpg"
MOTION_FLAG="$TMP_DIR/motion.flag"
YAVG_FILE="$TMP_DIR/yavg.txt"

# ---------------------------------------------------------
# 2. 状態変数
# ---------------------------------------------------------
event_active=0
frame_counter=0
last_saved_mtime=0
event_dir=""
event_id=""
event_start_iso=""
event_start_epoch=0
last_motion_time=0

brightness_min=""
brightness_max=""

echo "[handler] start for $CAM"

# ---------------------------------------------------------
# 3. 終了シグナル処理
# ---------------------------------------------------------
cleanup_handler() {
    echo "[handler] received termination signal for $CAM"

    if [ $event_active -eq 1 ]; then
        echo "[handler] terminating active event $event_id"
        end_event
    fi

    exit 0
}

trap cleanup_handler SIGTERM SIGINT

# ---------------------------------------------------------
# 3.5. JPEG完全性チェック
# ---------------------------------------------------------
validate_jpeg() {
    local file="$1"
    [ ! -f "$file" ] && return 1
    
    # SOI (Start of Image): 0xFF 0xD8
    local soi
    soi=$(xxd -p -l 2 "$file" 2>/dev/null)
    [ "$soi" != "ffd8" ] && return 1
    
    # EOI (End of Image): 0xFF 0xD9
    local eoi
    eoi=$(xxd -p -s -2 "$file" 2>/dev/null)
    [ "$eoi" != "ffd9" ] && return 1
    
    return 0
}

# ---------------------------------------------------------
# 4. brightness 更新
# ---------------------------------------------------------
update_brightness() {
    if [ -f "$YAVG_FILE" ]; then
        local val
        val=$(cat "$YAVG_FILE" 2>/dev/null || echo "")
        if [ -n "$val" ]; then
            if [ -z "$brightness_min" ] || [ -z "$brightness_max" ]; then
                brightness_min="$val"
                brightness_max="$val"
            else
                awk -v v="$val" -v mn="$brightness_min" -v mx="$brightness_max" '
                    BEGIN {
                        if (v < mn) mn = v;
                        if (v > mx) mx = v;
                        printf "%s %s\n", mn, mx;
                    }
                ' | {
                    read new_min new_max
                    brightness_min="$new_min"
                    brightness_max="$new_max"
                }
            fi
        fi
    fi
}

# ---------------------------------------------------------
# 5. イベント開始
# ---------------------------------------------------------
start_event() {
    YEAR=$(date +%Y)
    MONTH=$(date +%m)
    event_id=$(date +%Y%m%d_%H%M%S)

    event_dir="$EVENTS_BASE/$CAM/$YEAR/$MONTH/$event_id"
    mkdir -p "$event_dir"
    chmod 777 "$event_dir"

    event_start_iso=$(date -Is)
    event_start_epoch=$(date +%s)
    last_motion_time=$event_start_epoch
    last_saved_mtime=0
    brightness_min=""
    brightness_max=""

    daynight=$("${NVR_CORE_DIR}/get_daynight.sh" "$CAM" 2>/dev/null || echo "unknown")
    
    # --- 検知前フレーム (Optional) の取り込み ---
    PRE_MOTION="${TMP_DIR}/pre_motion.jpg"
    if [ -f "$PRE_MOTION" ]; then
        mv "$PRE_MOTION" "$event_dir/0001.jpg"
        frame_counter=1
    else
        frame_counter=0
    fi

    # 初期 JSON
    cat <<EOF > "$event_dir/event.json"
{
  "timestamp": "$event_start_iso",
  "timestamp_end": null,
  "duration_sec": 0,

  "camera": "$CAM",
  "event_timeout": $IDLE_SEC,

  "daynight": "$daynight",

  "brightness_min": null,
  "brightness_max": null,

  "jpeg_count": 0,
  "first_frame": null,
  "last_frame": null,

  "total_size_bytes": 0,

  "ai_tags": [],
  "ai_objects": [],
  "ai_confidence": []
}
EOF

    event_active=1
    echo "[handler] EVENT START $event_id"
}

# ---------------------------------------------------------
# 6. イベント終了
# ---------------------------------------------------------
end_event() {
    local end_iso end_epoch duration first_frame last_frame total_size

    end_iso=$(date -Is)
    end_epoch=$(date +%s)
    duration=$((end_epoch - event_start_epoch))

    if [ $frame_counter -gt 0 ]; then
        printf -v first_frame "%04d.jpg" 1
        printf -v last_frame "%04d.jpg" "$frame_counter"
        total_size=$(du -cb "$event_dir"/*.jpg 2>/dev/null | tail -1 | cut -f1)
        [ -z "$total_size" ] && total_size=0
    else
        first_frame=null
        last_frame=null
        total_size=0
    fi

    local bmin bmax
    [ -z "$brightness_min" ] && bmin=null || bmin="$brightness_min"
    [ -z "$brightness_max" ] && bmax=null || bmax="$brightness_max"

    jq \
      --arg end_ts "$end_iso" \
      --argjson dur "$duration" \
      --argjson count "$frame_counter" \
      --arg ff "$first_frame" \
      --arg lf "$last_frame" \
      --argjson size "$total_size" \
      --argjson bmin "$bmin" \
      --argjson bmax "$bmax" \
      '
        .timestamp_end = $end_ts
        | .duration_sec = $dur
        | .jpeg_count = $count
        | .first_frame = ($ff | if . == "null" then null else . end)
        | .last_frame  = ($lf | if . == "null" then null else . end)
        | .total_size_bytes = $size
        | .brightness_min = $bmin
        | .brightness_max = $bmax
      ' "$event_dir/event.json" > "$event_dir/event.json.tmp"

    mv "$event_dir/event.json.tmp" "$event_dir/event.json"

    echo "[handler] EVENT END $event_id ($frame_counter frames, ${duration}s)"

    event_active=0
    frame_counter=0
    last_saved_mtime=0
    brightness_min=""
    brightness_max=""
}

# ---------------------------------------------------------
# 7. メインループ
# ---------------------------------------------------------
while true; do
    if [ -f "$LATEST" ]; then
        mtime=$(stat -c %Y "$LATEST" 2>/dev/null || echo 0)

        if [ "$mtime" -eq "$last_saved_mtime" ] || [ "$mtime" -eq 0 ]; then
            sleep 0.05
            continue
        fi

        last_saved_mtime=$mtime
        now=$(date +%s)

        # 1. motion.flag の状態
        if [ -f "$MOTION_FLAG" ]; then
            last_motion_time=$now

            if [ $event_active -eq 0 ]; then
                start_event
            fi
        else
            if [ $event_active -eq 1 ]; then
                diff=$((now - last_motion_time))
                if [ $diff -ge $IDLE_SEC ]; then
                    end_event
                fi
            fi
        fi

        # 2. イベント中なら JPEG 保存（完全性チェック付き）
        if [ $event_active -eq 1 ]; then
            if validate_jpeg "$LATEST"; then
                frame_counter=$((frame_counter + 1))
                printf -v fname "%04d.jpg" "$frame_counter"
                cp "$LATEST" "$event_dir/$fname"

                # 初回フレーム保存時にアラート送信（非同期）
                if [ $frame_counter -eq 1 ] && [ -x "$NVR_CORE_DIR/send_motion_alert.sh" ]; then
                   # loggerのタグとしてイベントIDを使用し、システムログに記録する
                    ( "$NVR_CORE_DIR/send_motion_alert.sh" "$event_dir" 2>&1 | logger -t "nvr_send_alert[${event_id}]" ) &
                fi

                # 3. brightness 更新
                update_brightness
            fi
        fi
    fi

    sleep 0.05
done
