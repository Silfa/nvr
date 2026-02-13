#!/bin/bash
set -euo pipefail

CAM="$1"
if [ -z "$CAM" ]; then
    echo "Usage: camera_daynight_apply.sh <camera_name>"
    exit 1
fi

# ---------------------------------------------------------
# Define Constants and Load Install Paths
# ---------------------------------------------------------
ENV_GATEWAY="/etc/nvr/common_utils_path"
if [ ! -f "$ENV_GATEWAY" ]; then
    echo "Error: $ENV_GATEWAY not found. Please run deploy_nvr.sh first." >&2
    exit 1
fi
source "$ENV_GATEWAY"
source "$COMMON_UTILS"

DAYNIGHT_FILE="$NVR_DAYNIGHT_FILE_DIR/daynight_${CAM}.txt"

# ---------------------------------------------------------
# 1. 現在の昼夜モード取得
# ---------------------------------------------------------
echo "[DEBUG] Get day/night value."
if ! MODE=$("$NVR_CORE_DIR/get_daynight.sh" "$CAM"); then
    echo "[$CAM] Warning: get_daynight.sh failed, defaulting to night"
    MODE="night"
fi
echo "[DEBUG] ${MODE}"
OLD=$(cat "$DAYNIGHT_FILE" 2>/dev/null || echo "unknown")


# 変化なしなら終了
if [ "$MODE" = "$OLD" ]; then
    exit 0
fi

# ---------------------------------------------------------
# 2. camera/<CAM>.yaml から設定取得
# ---------------------------------------------------------

# esp32cam 固有の JSON 設定
JSON=$(get_cam_val "$CAM" ".esp32cam.camera_config.${MODE} // \"\"")
if [ -z "$JSON" ] || [ "$JSON" = "null" ]; then
    echo "[$CAM] No esp32cam.camera_config.$MODE found"
    exit 0
fi

# ---------------------------------------------------------
# 2. 接続先取得
# ---------------------------------------------------------
# HOST（connection.host）
HOST=$(get_cam_val "$CAM" '.connection.host // ""')
if [ -z "$HOST" ] || [ "$HOST" = "null" ]; then
    echo "[$CAM] ERROR: connection.host not set"
    exit 0
fi
# PORT（connection.port）
PORT=$(get_cam_val "$CAM" '.connection.port // 80')

if [ -n "$PORT" ] && [ "$PORT" != "null" ] && [ "$PORT" != "80" ]; then
    HOST="${HOST}:${PORT}"
fi

echo "[$CAM] Switching to $MODE mode..."

# ---------------------------------------------------------
# 3. POST /config
# ---------------------------------------------------------
echo "[DEBUG] Post json: ${JSON}"
RESP=$(curl -s -X POST "http://${HOST}/config" \
    -H "Content-Type: application/json" \
    -d "$JSON")

if [[ "$RESP" == "Invalid JSON" ]]; then
    echo "[$CAM] ERROR: Invalid JSON"
    exit 0
fi

RESTART_NEEDED=0

if [[ "$RESP" == "OK (Need Restart)" ]]; then
    echo "[$CAM] Camera restarting..."
    RESTART_NEEDED=1
elif [[ "$RESP" != "OK" ]]; then
    echo "[$CAM] Unexpected response: '$RESP'"
    exit 0
fi

# ---------------------------------------------------------
# 3.5 再起動待ち（必要な場合のみ）
# ---------------------------------------------------------
if [ "$RESTART_NEEDED" -eq 1 ]; then
    # 最低限の待ち時間
    sleep 3

    echo -n "[$CAM] Waiting for camera to come back online"
    for i in {1..20}; do
        if curl -s --max-time 1 "http://${HOST}/config" >/dev/null; then
            echo " OK"
            break
        fi
        echo -n "."
        sleep 1
    done
fi

# ---------------------------------------------------------
# 4. GET /config で反映確認
# ---------------------------------------------------------
GET_JSON=$(curl -s "http://${HOST}/config" || echo "")

if [ -z "$GET_JSON" ]; then
    echo "[$CAM] GET /config failed"
    exit 0
fi

POST_CAMERA=$(echo "$JSON" | jq -c '.camera')
GET_CAMERA=$(echo "$GET_JSON" | jq -c '.camera')

MISMATCH=0

# POST したキーだけ比較する
for key in $(echo "$POST_CAMERA" | jq -r 'keys[]'); do
    POST_VAL=$(echo "$POST_CAMERA" | jq -r --arg k "$key" '.[$k]')
    GET_VAL=$(echo "$GET_CAMERA" | jq -r --arg k "$key" '.[$k]')

    if [ "$POST_VAL" != "$GET_VAL" ]; then
        echo "[$CAM] Mismatch: $key (post=$POST_VAL get=$GET_VAL)"
        MISMATCH=1
    fi
done

if [ "$MISMATCH" -eq 1 ]; then
    echo "[$CAM] Config mismatch (but continuing)"
    exit 0
fi

# ---------------------------------------------------------
# 5. 成功したときだけ書き込み
# ---------------------------------------------------------
echo "$MODE" > "$DAYNIGHT_FILE"
echo "[$CAM] Day/Night updated to $MODE"
