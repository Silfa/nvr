#!/bin/bash
# ---------------------------------------------------------
# status_nvr.sh
#   - NVRシステムの全コンポーネントの稼働状況を表示する
# ---------------------------------------------------------

set -euo pipefail

# ---------------------------------------------------------
# 0. 初期化と共通ライブラリの読み込み
# ---------------------------------------------------------
ENV_GATEWAY="/etc/nvr/common_utils_path"
if [ ! -f "$ENV_GATEWAY" ]; then
    echo "Error: $ENV_GATEWAY not found. Please run deploy_nvr.sh first." >&2
    exit 1
fi
source "$ENV_GATEWAY"
source "$COMMON_UTILS"

# ANSI Color Codes
C_GREEN='\033[0;32m'
C_RED='\033[0;31m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'
C_NONE='\033[0m'

# ---------------------------------------------------------
# 1. ヘルパー関数: サービス状態の取得
# ---------------------------------------------------------
get_service_status() {
    local service_name="$1"
    local status_text="inactive"
    local color="${C_NONE}"

    if systemctl is-active --quiet "$service_name"; then
        status_text="active"
        color="${C_GREEN}"
    elif systemctl is-failed --quiet "$service_name"; then
        status_text="failed"
        color="${C_RED}"
    else
        # サービスは存在するが active/failed ではない場合 (inactive, activating など)
        local sub_state
        sub_state=$(systemctl show -p SubState --value "$service_name" 2>/dev/null)
        if [[ -n "$sub_state" && "$sub_state" != "dead" && "$sub_state" != "exited" ]]; then
            status_text="$sub_state"
            color="${C_YELLOW}"
        fi
    fi
    echo -e "${color}${status_text}${C_NONE}"
}

echo -e "## ${C_CYAN}NVR System Status${C_NONE} ##"
echo ""

# ---------------------------------------------------------
# 2. カメラサービスの状況
# ---------------------------------------------------------
echo "--- Camera Services ---"
CAMERAS=$(basename -a "$NVR_CONFIG_CAM_DIR"/*.yaml 2>/dev/null | sed 's/\.yaml$//')

if [ -z "$CAMERAS" ]; then
    echo "No cameras configured in $NVR_CONFIG_CAM_DIR."
else
    for CAM in $CAMERAS; do
        ENABLED=$(get_cam_val "$CAM" '.enabled // "false"')

        echo -n "Camera: ${CAM} (Config: "
        if [ "$ENABLED" == "true" ]; then
            echo -e "${C_GREEN}enabled${C_NONE})"
            
            S_FFMPEG=$(get_service_status "ffmpeg_nvr@${CAM}.service")
            S_MOTION=$(get_service_status "motion_detector@${CAM}.service")
            S_EVENT=$(get_service_status "motion_event_handler@${CAM}.service")

            printf "  ├─ Record Service : %s\n" "$S_FFMPEG"
            printf "  ├─ Detect Service : %s\n" "$S_MOTION"
            printf "  └─ Handle Service : %s\n" "$S_EVENT"

        else
            echo -e "disabled)"
        fi
        echo ""
    done
fi

# ---------------------------------------------------------
# 3. Web APIサービスの状況
# ---------------------------------------------------------
echo "--- Web API Service ---"
S_WEB=$(get_service_status "nvr-web.service")
printf "Service: nvr-web.service -> %s\n" "$S_WEB"
echo ""

# ---------------------------------------------------------
# 4. ストレージの状況
# ---------------------------------------------------------
echo "--- Storage Status ---"
RECORDS_DIR=$(get_main_val ".common.records_dir_base")
EVENTS_DIR=$(get_main_val ".common.events_dir_base")

if [ -d "$RECORDS_DIR" ]; then
    echo "Records Path: $RECORDS_DIR"
    df -h "$RECORDS_DIR" | tail -n +2 | sed 's/^/  /'
else
    echo -e "Records Path: ${C_RED}$RECORDS_DIR (Not Found)${C_NONE}"
fi

if [ -d "$EVENTS_DIR" ]; then
    echo "Events Path: $EVENTS_DIR"
    df -h "$EVENTS_DIR" | tail -n +2 | sed 's/^/  /'
else
    echo -e "Events Path: ${C_RED}$EVENTS_DIR (Not Found)${C_NONE}"
fi
echo ""

