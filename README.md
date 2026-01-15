# Home NVR System  
ESP32-CAM + ffmpeg + OpenCV + Bash Scripts

このリポジトリは、家庭用に構築した NVR（Network Video Recorder）システムの  
設定ファイル・スクリプト・仕様書をまとめたものです。

---

## 📂 ディレクトリ構成

```
nvr/
  core/        - NVR の中核スクリプト群 (ffmpeg, motion_detector, handler)
  common/      - 共通ユーティリティ
  config/      - 設定ファイル (cameras.yaml, main.yaml)
  docs/        - 詳細仕様書
  templates/   - Systemd ユニットおよび設定ファイルのテンプレート
```

---

## 📄 主な仕様書

### システム管理
- Setup Guide
- Architecture Overview
- Setup NVR Spec

### コンポーネント仕様
- Cameras YAML Spec
- Event JSON Spec
- FFmpeg Runner Spec
- OpenCV Motion Spec

---

## 🎯 概要

- ESP32-CAM から RTSP で映像取得 (MJPEG over TCP)
- ffmpeg による録画（セグメント化）  
- OpenCV による動体検知  
- motion.flag によるイベント管理  
- event.json にメタデータ保存  
- 昼夜自動切り替え（brightness / sunrise）  
- multi-camera 対応設計

---

## 🔧 今後の予定

- Web UI（イベント一覧・再生）  
