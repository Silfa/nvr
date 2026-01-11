# NVR System — Setup Guide
（リポジトリから実行環境を構築する手順）

このドキュメントは、本リポジトリから  
NVR 実行環境を構築するための正式な手順をまとめたもの。

本システムは以下の 3 層構造で動作する：

- ffmpeg 層：ESP32‑CAM の RTSP を録画し latest.jpg を生成
- OpenCV 層：latest.jpg を解析し motion.flag / yavg.txt を生成
- イベント層：motion.flag を監視し event.json と JPEG 保存を行う

設定は cameras.yaml が唯一のソース・オブ・トゥルースであり、  
systemd によるサービス管理を前提とする。

---

# 1. リポジトリの取得

```
git clone <your-repo>
cd <your-repo>
```

---

# 2. スクリプトの配置

```
sudo mkdir -p /usr/local/bin/nvr
sudo cp scripts/*.sh /usr/local/bin/nvr/
sudo cp scripts/*.py /usr/local/bin/nvr/
sudo chmod 755 /usr/local/bin/nvr/*
```

すべての実行スクリプトは  
`/usr/local/bin/nvr/` に集約される。

---

# 3. 設定ファイルの配置

```
sudo mkdir -p /etc/nvr
sudo cp cameras.yaml /etc/nvr/
sudo chmod 644 /etc/nvr/cameras.yaml
```

cameras.yaml は唯一の設定ファイルであり、  
setup_nvr.sh がこれを読み取って systemd を正規化する。

---

# 4. systemd ユニニットの配置

```
sudo cp units/*.service /etc/systemd/system/
sudo systemctl daemon-reload
```

配置されるユニット：

- ffmpeg_nvr.service.template（setup_nvr.sh が使用）
- opencv_motion@.service
- motion_event_handler@.service

---

# 5. OpenCV 用 venv の構築

OpenCV 層はシステム Python ではなく  
専用の仮想環境（venv）で動作する。

```
sudo python3 -m venv /usr/local/nvr-venv
sudo /usr/local/nvr-venv/bin/pip install --upgrade pip setuptools wheel
sudo /usr/local/nvr-venv/bin/pip install opencv-python-headless numpy pyyaml
```

依存ライブラリはすべて venv に隔離される。

---

# 6. NVR の初期化（setup_nvr.sh）

```
sudo /usr/local/bin/nvr/setup_nvr.sh
```

このスクリプトは以下を行う：

- cameras.yaml を読み取り
- ffmpeg_nvr_<CAM>.service を生成
- 不要なユニットを削除
- TMP_DIR を作成
- systemd を正規化

本システムの「初期化フェーズ」に相当する。

---

# 7. NVR の起動

```
sudo /usr/local/bin/nvr/start_nvr.sh
```

起動されるサービス：

- ffmpeg_nvr_<CAM>.service
- opencv_motion@<CAM>.service
- motion_event_handler@<CAM>.service

依存関係により正しい順序で起動される。

---

# 8. 動作確認

## ffmpeg のログ
```
journalctl -u ffmpeg_nvr_<CAM>.service -f
```

## OpenCV のログ
```
journalctl -u opencv_motion@<CAM>.service -f
```

## イベントハンドラのログ
```
journalctl -u motion_event_handler@<CAM>.service -f
```

---

# 9. 停止

```
sudo /usr/local/bin/nvr/stop_nvr.sh
```

ffmpeg → OpenCV → handler の逆順で停止する。

---

# 10. 再構築（設定変更時）

cameras.yaml を変更した場合は、  
必ず setup_nvr.sh を再実行する。

```
sudo /usr/local/bin/nvr/setup_nvr.sh
sudo /usr/local/bin/nvr/start_nvr.sh
```

---

# 11. ディレクトリ構造（参考）

```
/usr/local/bin/nvr/
    run_ffmpeg.sh
    run_opencv_motion.sh
    motion_event_handler.sh
    setup_nvr.sh
    start_nvr.sh
    stop_nvr.sh
    opencv_motion.py

/usr/local/nvr-venv/
    （OpenCV 専用仮想環境）

/etc/nvr/
    cameras.yaml

/etc/systemd/system/
    ffmpeg_nvr_<CAM>.service
    opencv_motion@.service
    motion_event_handler@.service

<common.motion_tmp_base>/<CAM>/
    latest.jpg
    motion.flag
    yavg.txt
```

---

# End of Document
