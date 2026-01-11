#!/bin/bash
echo "send_motion_alert.sh called: $1"

EVENT_DIR="$1"

ENV_GATEWAY="/etc/nvr/common_utils_path"
if [ ! -f "$ENV_GATEWAY" ]; then
    echo "Error: $ENV_GATEWAY not found. Please run deploy_nvr.sh first." >&2
    exit 1
fi
source "$ENV_GATEWAY"
source "$COMMON_UTILS"

# メールアドレス取得
MAIL_ADDRESS=$(get_main_val '.common.mail_address')

if [ -z "$MAIL_ADDRESS" ]; then
    echo "[NVR SendAlert]No mail address configured. Exiting."
    exit 1
fi

# イベント開始時刻（フォルダ名から取得）
EVENT_NAME=$(basename "$EVENT_DIR")
EVENT_TIME=${EVENT_NAME#event_}

# 最初のJPEGを取得
FIRST_JPEG=$(ls "$EVENT_DIR" | sort | head -n 1)
FIRST_JPEG_PATH="$EVENT_DIR/$FIRST_JPEG"

# メール本文
BODY="Motion detected at $EVENT_TIME

Event folder:
$EVENT_DIR

First image:
$FIRST_JPEG_PATH
"

# メール送信
echo "[NVR SendAlert] Sending motion alert email to $MAIL_ADDRESS for event at $EVENT_TIME"
echo "$BODY" | mail -s "NVR Motion Alert: $EVENT_TIME" -A "$FIRST_JPEG_PATH" "$MAIL_ADDRESS"
