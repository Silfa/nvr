#!/bin/bash
# ---------------------------------------------------------
# get_daynight.sh <camera_name>
#   - main.yaml + cameras/<CAM>.yaml に基づき昼夜を判定
#   - brightness / time / sunrise / fixed の4方式に対応
# ---------------------------------------------------------

set -euo pipefail

CAM="$1"
if [ -z "$CAM" ]; then
    echo "Usage: $0 <camera_name>" >&2
    exit 1
fi

ENV_GATEWAY="/etc/nvr/common_utils_path"
if [ ! -f "$ENV_GATEWAY" ]; then
    echo "Error: $ENV_GATEWAY not found. Please run deploy_nvr.sh first." >&2
    exit 1
fi
source "$ENV_GATEWAY"
source "$COMMON_UTILS"

# ---------------------------------------------------------
# 1. YAML 読み取り（個別 → default）
# ---------------------------------------------------------

# mode
MODE=$(get_nvr_val "$CAM" '.daynight.mode // ""' '.common.default_daynight_mode')

# brightness threshold
THRESH=$(get_nvr_val "$CAM" '.daynight.brightness_threshold // ""' '.common.default_brightness_threshold')

# time mode
DAY_START=$(get_nvr_val "$CAM" '.daynight.day_start // ""' '.common.day_start')
NIGHT_START=$(get_nvr_val "$CAM" '.daynight.night_start // ""' '.common.night_start')

# sunrise mode
LAT=$(get_nvr_val "$CAM" '.daynight.latitude // ""' '.common.latitude')
LON=$(get_nvr_val "$CAM" '.daynight.longitude // ""' '.common.longitude')

# fixed mode
FIXED=$(get_nvr_val '.daynight.fixed_value // ""' '.common.fixed_value // ""')

# tmp base
TMP_BASE=$(get_main_val '.common.motion_tmp_base')

# ---------------------------------------------------------
# 2. brightness モード
# ---------------------------------------------------------
brightness_mode() {
    YAVG_FILE="$TMP_BASE/$CAM/yavg.txt"
    if [ ! -f "$YAVG_FILE" ]; then
        sunrise_mode
        return
    fi

    YAVG=$(cat "$YAVG_FILE" 2>/dev/null || echo "")
    if [ -z "$YAVG" ]; then
        sunrise_mode
        return
    fi

    if (( $(echo "$YAVG >= $THRESH" | bc -l) )); then
        echo "day"
    else
        echo "night"
    fi
}

# ---------------------------------------------------------
# 3. time モード
# ---------------------------------------------------------
time_mode() {
    if [ "$DAY_START" = "null" ] || [ "$NIGHT_START" = "null" ]; then
        echo "unknown"
        return
    fi

    NOW=$(date +%H:%M)

    to_min() { echo "$1" | awk -F: '{print $1*60 + $2}'; }

    NOW_M=$(to_min "$NOW")
    DAY_M=$(to_min "$DAY_START")
    NIGHT_M=$(to_min "$NIGHT_START")

    if [ "$DAY_M" -le "$NIGHT_M" ]; then
        if [ "$NOW_M" -ge "$DAY_M" ] && [ "$NOW_M" -lt "$NIGHT_M" ]; then
            echo "day"
        else
            echo "night"
        fi
    else
        if [ "$NOW_M" -ge "$DAY_M" ] || [ "$NOW_M" -lt "$NIGHT_M" ]; then
            echo "day"
        else
            echo "night"
        fi
    fi
}

# ---------------------------------------------------------
# 4. sunrise モード
# ---------------------------------------------------------
sunrise_mode() {
    if ! command -v sunwait >/dev/null 2>&1; then
        time_mode
        return
    fi

    RESULT=$(sunwait poll "$LAT" "$LON")
    if [ "$RESULT" = "DAY" ]; then
        echo "day"
    else
        echo "night"
    fi
}

# ---------------------------------------------------------
# 5. fixed モード
# ---------------------------------------------------------
fixed_mode() {
    if [ "$FIXED" = "day" ] || [ "$FIXED" = "night" ]; then
        echo "$FIXED"
    else
        echo "unknown"
    fi
}

# ---------------------------------------------------------
# 6. メイン処理
# ---------------------------------------------------------
case "$MODE" in
    brightness) brightness_mode ;;
    time)       time_mode ;;
    sunrise)    sunrise_mode ;;
    fixed)      fixed_mode ;;
    *)          echo "unknown" ;;
esac
