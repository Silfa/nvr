#!/bin/bash
# ---------------------------------------------------------
# run_motion_detector.sh <CAM>
#   - OpenCV motion detector launcher
#   - systemd (motion_detector@.service) から呼ばれる
#   - venv を activate して motion_detector.py を実行する
# ---------------------------------------------------------

set -euo pipefail

CAM="$1"
if [ -z "$CAM" ]; then
    echo "[run_motion_detector] Error: CAM argument is required."
    exit 1
fi

ENV_GATEWAY="/etc/nvr/common_utils_path"
if [ ! -f "$ENV_GATEWAY" ]; then
    echo "Error: $ENV_GATEWAY not found. Please run deploy_nvr.sh first." >&2
    exit 1
fi
source "$ENV_GATEWAY"
source "$COMMON_UTILS"

CONFIG="$NVR_CONFIG_MAIN_FILE"
SCRIPT_DIR="$NVR_CORE_DIR"
VENV_DIR=$(get_main_val '.common.python_venv_dir')

# ---------------------------------------------------------
# 1. venv activate
# ---------------------------------------------------------
# systemd は root で動くため sudo は不要
source /usr/local/nvr-venv/bin/activate

# ---------------------------------------------------------
# 2. main.yaml から TMP_DIR を取得して作成
# ---------------------------------------------------------
TMP_BASE=$(get_main_val '.common.motion_tmp_base')
MOTION_TMP_DIR="${TMP_BASE}/${CAM}"

mkdir -p "$MOTION_TMP_DIR"

# ---------------------------------------------------------
# 3. OpenCV motion detector を起動
# ---------------------------------------------------------
echo "[run_motion_detector] Starting motion detector for $CAM"
# PYTHONPATH の設定 (既存のパスも壊さないように追記)
export PYTHONPATH="${NVR_BASE_DIR}:${PYTHONPATH:-}"
VENV_PYTHON="${VENV_DIR}/bin/python3"
SCRIPT_PATH="${NVR_CORE_DIR}/opencv/motion_detector.py"
exec "$VENV_PYTHON" "$SCRIPT_PATH" "$CAM"
