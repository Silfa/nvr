import cv2
import os
import time
import sys
import numpy as np
import functools
from common.config_loader import (
    load_camera_config,
    load_main_config
)

print = functools.partial(print, flush=True)

# ----------------------------------------
# 1. 設定ファイルの読み込み
# ----------------------------------------
# （load_main_config と load_camera_config を使用）

# ----------------------------------------
# 2. 平均輝度（YAVG）を計算
# ----------------------------------------
def calc_yavg(frame):
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    return int(np.mean(gray))

# ----------------------------------------
# 4. メイン処理
# ----------------------------------------
def main():
    if len(sys.argv) < 2:
        print("Usage: motion_detector.py <camera_name>")
        sys.exit(1)

    cam = sys.argv[1]

    # カメラ設定を取得
    main_cfg = load_main_config()
    cam_cfg = load_camera_config(cam)

    # motion 設定（個別 → default）
    motion_cfg = cam_cfg.get("motion", {})

    threshold = motion_cfg.get(
        "threshold",
        main_cfg["common"]["default_motion_threshold"]
    )
    # 検知とみなす最小面積（ピクセル）
    min_area = motion_cfg.get( 
        "min_area",
        main_cfg["common"]["default_motion_min_area"]
    )
    # メディアンフィルタのカーネルサイズ（奇数）
    blur = motion_cfg.get(
        "blur",
        main_cfg["common"]["default_motion_blur"]
    )
    # 動体検知の有効/無効
    enabled = motion_cfg.get(
        "enabled",
        main_cfg["common"]["default_motion_enabled"]
    )
    # ノイズ除去用カーネルの高さ（ピクセル）。ノイズの帯より大きく設定。
    noise_v_kernel_height = motion_cfg.get(
        "noise_v_kernel_height",
        main_cfg["common"]["default_motion_noise_v_kernel_height"]
    )
    # 物体の最大アスペクト比（幅 / 高さ）
    max_aspect_ratio = motion_cfg.get(
        "max_aspect_ratio",
        main_cfg["common"]["default_motion_max_aspect_ratio"]
    )

    if not enabled:
        print(f"[motion_detector] Motion detector disabled for {cam}")
        time.sleep(1)
        return

    tmp_base = main_cfg["common"]["motion_tmp_base"]
    tmp_dir = f"{tmp_base}/{cam}"

    latest_jpg = f"{tmp_dir}/latest.jpg"
    motion_flag = f"{tmp_dir}/motion.flag"
    yavg_file = f"{tmp_dir}/yavg.txt"

    print(f"[motion_detector] Starting for camera: {cam}")
    print(f"[motion_detector] threshold={threshold}, min_area={min_area}, blur={blur}, noise_v_kernel_height={noise_v_kernel_height}, max_aspect_ratio={max_aspect_ratio}")
    print(f"[motion_detector] Watching file: {latest_jpg}")
    print(f"[motion_detector] Motion flag file: {motion_flag}")
    print(f"[motion_detector] YAVG file: {yavg_file}")


    # 背景差分法の初期化
    fgbg = cv2.createBackgroundSubtractorMOG2(varThreshold=threshold, detectShadows=False)

    # ノイズ除去用カーネル
    kernel_v = cv2.getStructuringElement(cv2.MORPH_RECT, (1, noise_v_kernel_height))

    last_mtime = 0
    counter = 0

    while True:
        # latest.jpg の更新を待つ
        try:
            mtime = os.path.getmtime(latest_jpg)
        except FileNotFoundError:
            time.sleep(0.1)
            continue

        if mtime == last_mtime:
            time.sleep(0.05)
            continue

        counter += 1
        last_mtime = mtime

        # フレーム読み込み
        frame = cv2.imread(latest_jpg)
        if frame is None:
            continue

        # --- 1. 前処理：メディアンフィルタでざらつきを除去 ---
        # カーネルサイズは奇数。ノイズが酷い場合は 7 や 9 に上げる など調整。
        blurred = cv2.medianBlur(frame, blur)

        # --- 2. 背景差分法による動体検知 ---
        fgmask = fgbg.apply(blurred) 
        
        # --- 3. ノイズ除去：強力な垂直オープニング ---
        fgmask = cv2.morphologyEx(fgmask, cv2.MORPH_OPEN, kernel_v)

# --- 輪郭抽出と判定 ---
        contours, _ = cv2.findContours(fgmask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        motion = False  # ループの前に初期化
        img_w = frame.shape[1]

        for contour in contours:
            area = cv2.contourArea(contour)
            if area < min_area:
                continue  # 小さいものは無視して次の輪郭へ

            x, y, w, h = cv2.boundingRect(contour)
            aspect_ratio = float(w) / h

            # --- 形状フィルタリング ---
            # 横長すぎるもの（帯状ノイズ）を無視
            if aspect_ratio > max_aspect_ratio:
                continue
            # 画像幅の半分を超えるような巨大すぎる横長も無視
            if w > img_w * 0.6:
                continue

            # ここまで到達すれば「本物の動体」とみなす
            motion = True
            break  # 一つでも見つかれば確定なのでループを抜ける

        # motion.flag の更新
        # 起動直後の不安定な時期（最初の25フレーム）を除外
        if motion and counter > 25:
            if not os.path.exists(motion_flag):
                open(motion_flag, "w").close()
        else:
            if os.path.exists(motion_flag):
                try:
                    os.remove(motion_flag)
                except FileNotFoundError:
                    pass

        # YAVG の保存
        yavg = calc_yavg(frame)
        with open(yavg_file, "w") as f:
            f.write(str(yavg))

        # CPU 負荷軽減
        time.sleep(0.1)

# ----------------------------------------
# 実行
# ----------------------------------------
if __name__ == "__main__":
    main()
