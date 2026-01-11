# Home NVR System  
ESP32-CAM + ffmpeg + OpenCV + Bash Scripts

このリポジトリは、家庭用に構築した NVR（Network Video Recorder）システムの  
設定ファイル・スクリプト・仕様書をまとめたものです。

---

## 📂 ディレクトリ構成

```
nvr/
  docs/        - 仕様書（cameras.yaml, event.json など）
  scripts/     - NVR の実行スクリプト群
  opencv/      - OpenCV テストスクリプト
  config/      - 設定ファイル（cameras.yaml, event.schema.json）
```

---

## 📄 主な仕様書

- docs/cameras_yaml_spec.md  
- docs/event_json_spec.md  
（今後追加予定：OpenCV, ffmpeg, ESP32-CAM 仕様）

---

## 🎯 概要

- ESP32-CAM から RTSP で映像取得  
- ffmpeg による録画（セグメント化）  
- OpenCV による動体検知  
- motion.flag によるイベント管理  
- event.json にメタデータ保存  
- 昼夜自動切り替え（brightness / sunrise）  
- multi-camera 対応設計

---

## 🔧 今後の予定

- OpenCV 仕様書追加  
- ffmpeg パイプライン仕様書追加  
- ESP32-CAM スケッチ仕様書追加  
- Web UI（イベント一覧・再生）  
