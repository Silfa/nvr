# Home NVR System
ESP32-CAM + ffmpeg + OpenCV + Bash Scripts

このリポジトリは、家庭用に構築した NVR（Network Video Recorder）システムの
設定ファイル・スクリプト・仕様書をまとめたものです。

---

## 📂 ディレクトリ構成

```
nvr/
  docs/        - 詳細仕様書（cameras.yaml, event.json, setup_nvr など）
  core/        - NVR のコア実行スクリプト群 (setup_nvr.sh, start_nvr.sh, ffmpeg_runner 等)
  common/      - 共通ユーティリティ (common_utils.sh)
  config/      - 設定ファイル（cameras.yaml, event.schema.json, main.yaml）
  templates/   - Systemd ユニットテンプレート
```

---

## 📄 主な仕様書

### システム管理
- docs/setup_nvr_spec.md
- docs/start_nvr_spec.md
- docs/stop_nvr_spec.md

### コンポーネント仕様
- docs/cameras_yaml_spec.md
- docs/event_json_spec.md
- docs/run_ffmpeg_spec.md (FFmpeg Runner)
- docs/opencv_motion_spec.md (Motion Detector)

---

## 🎯 概要

- ESP32-CAM から RTSP で映像取得 (MJPEG over TCP)
- ffmpeg による録画（セグメント化）
- OpenCV による動体検知
- motion.flag によるイベント管理
- event.json にメタデータ保存
- 昼夜自動切り替え（brightness / sunrise）
- multi-camera 対応設計 (systemd override.conf 方式)

---

## 🔧 今後の予定

- Web UI（イベント一覧・再生）
- AI 物体検知 (OpenCV DNN / Yolo 等) 連携
