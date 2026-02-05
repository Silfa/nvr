#!/bin/bash
EVENT_DIR="$1"
if [ -z "$EVENT_DIR" ]; then
    echo "[NVR SendAlert] Error: Event directory not provided."
    exit 1
fi

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

# イベントID（フォルダ名）から時刻とカメラ名を抽出
EVENT_ID=$(basename "$EVENT_DIR")
# パス構造: .../<CAM>/<YEAR>/<MONTH>/<EVENT_ID>
CAM_DIR=$(dirname "$(dirname "$(dirname "$EVENT_DIR")")")
CAM_NAME=$(basename "$CAM_DIR")

# 時刻整形 (YYYYMMDD_HHMMSS -> YYYY-MM-DD HH:MM:SS)
if [[ "$EVENT_ID" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})_([0-9]{2})([0-9]{2})([0-9]{2})$ ]]; then
    EVENT_TIME="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}"
else
    EVENT_TIME="$EVENT_ID"
fi

# 添付するJPEGを取得 (0002.jpgを優先、なければ2番目、それでもなければ最初の画像を添付)
ATTACH_JPEG_PATH="$EVENT_DIR/0002.jpg"
if [ ! -f "$ATTACH_JPEG_PATH" ]; then
    # 0002.jpg がなければ ls の結果から探す
    ATTACH_JPEG=$(ls "$EVENT_DIR"/*.jpg 2>/dev/null | sort | sed -n '2p') # 2番目のファイルを取得
    if [ -z "$ATTACH_JPEG" ]; then
        # 2番目のファイルもなければ、最初のファイルを取得 (フォールバック)
        ATTACH_JPEG=$(ls "$EVENT_DIR"/*.jpg 2>/dev/null | sort | sed -n '1p')
    fi

    if [ -n "$ATTACH_JPEG" ]; then
        ATTACH_JPEG_PATH="$ATTACH_JPEG"
    else
        echo "[NVR SendAlert] No JPEG images found in $EVENT_DIR"
        exit 0
    fi
fi

# メール本文
BODY="Motion detected!

Camera: $CAM_NAME
Time:   $EVENT_TIME
Event:  $EVENT_ID

Event folder:
$EVENT_DIR
"

# メール送信
echo "[NVR SendAlert] Sending email to $MAIL_ADDRESS (Cam: $CAM_NAME, Time: $EVENT_TIME)"
echo "$BODY" | mail -s "NVR Motion Alert: $CAM_NAME at $EVENT_TIME" -A "$ATTACH_JPEG_PATH" "$MAIL_ADDRESS"
