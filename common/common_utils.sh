#!/bin/bash

# --- 1. 看板ファイルの読み込み ---
# これにより、このスクリプト自体の場所や設定ファイルのパスが環境変数に入ります
GATEWAY="/etc/nvr/common_utils_path"
if [ ! -f "$GATEWAY" ]; then
    echo "[Error] Gateway file not found: $GATEWAY" >&2
    return 1 2>/dev/null || exit 1
fi
source "$GATEWAY"

# --- 2. YAML (install_paths) から環境変数を一括展開 ---
# install_paths の中身 (例: user: nvruser) を NVR_USER 等に変換します
if [ -f "/etc/nvr/install_paths" ]; then
    # yqの結果を eval して export する
    # key を大文字にし、先頭に NVR_ を付与
    eval "$(yq -r 'to_entries | .[] | "export NVR_" + (.key | upcase) + "=\"" + .value + "\""' /etc/nvr/install_paths)"
else
    echo "[Error] install_paths not found!" >&2
fi

# --- 3. 設定取得関数 (Main/Global) ---

# マージ済みの Main 設定を出力する内部関数
_get_merged_main() {
    # 両方のファイルが存在する場合
    if [ -f "$NVR_CONFIG_MAIN_FILE" ] && [ -f "$NVR_CONFIG_MAIN_SECRET_FILE" ]; then
        yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$NVR_CONFIG_MAIN_FILE" "$NVR_CONFIG_MAIN_SECRET_FILE"
    # 公開設定のみ存在する場合
    elif [ -f "$NVR_CONFIG_MAIN_FILE" ]; then
        cat "$NVR_CONFIG_MAIN_FILE"
    # 万が一どちらもない場合
    else
        echo "{}"
    fi
}

# 外部から値を1つ取る用: get_main_val ".common.threshold"
get_main_val() {
    _get_merged_main | yq -r "$1"
}

# --- 4. 設定取得関数 (Camera) ---

# マージ済みの Camera 設定を出力する内部関数
_get_merged_cam() {
    local cam=$1
    local pub="$NVR_CONFIG_CAM_DIR/${cam}.yaml"
    local sec="$NVR_CONFIG_CAM_SECRET_DIR/${cam}.yaml"

    if [ -f "$pub" ] && [ -f "$sec" ]; then
        yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$pub" "$sec"
    elif [ -f "$pub" ]; then
        cat "$pub"
    else
        echo "{}"
    fi
}

# 外部から値を1つ取る用: get_cam_val "front" ".motion.threshold"
get_cam_val() {
    _get_merged_cam "$1" | yq -r "$2"
}

# --- 5. 究極のフォールバック関数 ---
# 個別設定を優先し、なければメイン設定を返す
# get_nvr_val "front" ".motion.threshold" ".common.default_threshold"
get_nvr_val() {
    local cam=$1
    local cam_key=$2
    local main_key=$2    
    
    local val
    val=$(get_cam_val "$cam" "$cam_key")
    
    # yq の結果が null または空なら、メインから取得
    if [ "$val" == "null" ] || [ -z "$val" ]; then
        val=$(get_main_val "$main_key")
    fi
    echo "${val}"
}

# --- デバッグ用: source した瞬間に変数が正しく入っているか確認したい場合は
# 以下の echo のコメントを外して確認してください
# echo "DEBUG: NVR_CONFIG_MAIN is $NVR_CONFIG_MAIN"