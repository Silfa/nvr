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

# event.post_motion_buffer_sec（個別 → default）
POST_MOTION_BUFFER_SEC=$(get_nvr_val "$CAM" ".event.post_motion_buffer_sec" ".common.default_post_motion_buffer_sec")

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
alert_sent=0
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
    alert_sent=0
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
    # --- [追加] 末尾の無駄な静止画を削除する処理 ---
    # 「最後にモーションがあった時刻 + 余韻」を計算
    local cutoff_time=$((last_motion_time + POST_MOTION_BUFFER_SEC))
    
    # イベントディレクトリ内の全JPEGをチェック
    # (ファイル名順＝時系列順なので、後ろから消すなどの最適化も可能ですが、
    #  数十枚程度なら全走査でも一瞬です)
    for f in "$event_dir"/*.jpg; do
        if [ -f "$f" ]; then
            local fmt
            fmt=$(stat -c %Y "$f" 2>/dev/null || echo 0)
            
            # プレモーション画像(0001.jpg)は絶対に消さない（安全策）
            if [[ "$f" == *"0001.jpg" ]]; then
                continue
            fi

            # カットオフ時刻より新しいファイルは削除
            if [ "$fmt" -gt "$cutoff_time" ]; then
                rm "$f"
            fi
        fi
    done

    # --- [修正] 削除後の正しいファイル数を再カウント ---
    # 削除によってフレーム数が減っているため、ls で数え直す
    frame_counter=$(ls -1 "$event_dir"/*.jpg 2>/dev/null | wc -l)

    # -----------------------------------------------------

    local end_iso end_epoch duration first_frame last_frame total_size

    # 終了時刻は「現在時刻」ではなく「最後のファイルの時間（あるいはcutoff_time）」にするのが自然ですが、
    # シンプルに処理完了時刻とします（または last_motion_time に合わせるのもあり）
    end_iso=$(date -Is)
    
    # duration も「実際に保存された期間」に再計算
    # (開始時刻 〜 最後のファイルの更新時刻)
    local last_file_mtime
    last_file_mtime=$(stat -c %Y "$(ls -t "$event_dir"/*.jpg | head -1)" 2>/dev/null || echo "$event_start_epoch")
    duration=$((last_file_mtime - event_start_epoch))
    if [ $duration -lt 0 ]; then duration=0; fi

    if [ $frame_counter -gt 0 ]; then
        # ファイルリストが変わっているので、first/last を再取得
        first_frame=$(ls "$event_dir"/*.jpg | head -1 | xargs basename)
        last_frame=$(ls "$event_dir"/*.jpg | tail -1 | xargs basename)
        
        total_size=$(du -cb "$event_dir"/*.jpg 2>/dev/null | tail -1 | cut -f1)
        [ -z "$total_size" ] && total_size=0
    else
        first_frame="null"
        last_frame="null"
        total_size=0
    fi

    local bmin bmax
    [ -z "$brightness_min" ] && bmin="null" || bmin="$brightness_min"
    [ -z "$brightness_max" ] && bmax="null" || bmax="$brightness_max"

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
        | .first_frame = (if $ff == "null" then null else $ff end)
        | .last_frame  = (if $lf == "null" then null else $lf end)
        | .total_size_bytes = $size
        | .brightness_min = $bmin
        | .brightness_max = $bmax
      ' "$event_dir/event.json" > "$event_dir/event.json.tmp"

    mv "$event_dir/event.json.tmp" "$event_dir/event.json"

    echo "[handler] EVENT END $event_id (Trimmed to $frame_counter frames, ${duration}s)"

    event_active=0
    frame_counter=0
    brightness_min=""
    brightness_max=""
}

# ---------------------------------------------------------
# 7. メインループ
# ---------------------------------------------------------
while true; do
    # 現在時刻の取得
    now=$(date +%s)

    # =========================================================
    # Phase A: 状態遷移 (開始判定 / タイムアウト判定)
    #   - ここは画像(latest.jpg)の状態に依存させてはいけない
    # =========================================================
    
    if [ -f "$MOTION_FLAG" ]; then
        # --- モーション検知中 ---
        last_motion_time=$now

        if [ $event_active -eq 0 ]; then
            # 新規イベント開始
            # (start_event内で last_saved_mtime=0 にリセットされる)
            start_event
        fi
    else
        # --- モーションフラグ無し（静止中） ---
        if [ $event_active -eq 1 ]; then
            # 最後の動きから IDLE_SEC 経過したかチェック
            diff=$((now - last_motion_time))
            
            if [ $diff -ge $IDLE_SEC ]; then
                # タイムアウト確定 -> 終了処理へ
                # (end_event内で末尾の静止画を削除する)
                end_event
            fi
        fi
    fi

    # =========================================================
    # Phase B: 画像保存 (イベント中のみ実行)
    # =========================================================
    if [ $event_active -eq 1 ]; then
        
        # latest.jpg が存在するか確認
        if [ -f "$LATEST" ]; then
            mtime=$(stat -c %Y "$LATEST" 2>/dev/null || echo 0)

            # 「新しい画像である(前回保存した時刻と違う)」かつ「有効な時刻」なら保存処理
            # ※ start_eventで last_saved_mtime=0 にしているので、
            #    イベント最初の1枚は必ずここで保存される。
            if [ "$mtime" -ne "$last_saved_mtime" ] && [ "$mtime" -ne 0 ]; then
                
                # 完全性チェック（壊れたJPEGを保存しない）
                if validate_jpeg "$LATEST"; then
                    
                    frame_counter=$((frame_counter + 1))
                    printf -v fname "%04d.jpg" "$frame_counter"
                    
                    # コピー実行
                    cp "$LATEST" "$event_dir/$fname"
                    
                    # 保存した時刻を記録（次のループでの重複防止）
                    last_saved_mtime=$mtime 

                    # 初回検知時のアラート送信（非同期）
                    if [ $alert_sent -eq 0 ] && [ -x "$NVR_CORE_DIR/send_motion_alert.sh" ]; then
                         ( "$NVR_CORE_DIR/send_motion_alert.sh" "$event_dir" 2>&1 | logger -t "nvr_alert" ) &
                         alert_sent=1
                    fi

                    # 輝度統計更新
                    update_brightness
                fi
            fi
        fi
    fi

    # CPU負荷軽減のためのウェイト
    sleep 0.05
done
