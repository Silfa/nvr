# NVR System — Systemd Units Specification (Unified Edition)

このドキュメントは、NVR システムを構成する systemd ユニット  
**ffmpeg_nvr_<CAM>.service / opencv_motion@.service / motion_event_handler@.service**  
の仕様を統合的にまとめたものである。

NVR は systemd によって以下の3層構造で動作する：

1. **ffmpeg_nvr_<CAM>.service**  
   └ RTSP を録画し JPEG を生成する「映像入力層」

2. **opencv_motion@<CAM>.service**  
   └ JPEG を解析し motion.flag / yavg.txt を生成する「動体検知層」

3. **motion_event_handler@<CAM>.service**  
   └ motion.flag の変化を監視し event.json を生成する「イベント処理層」

本仕様書は、これら3つのユニットの役割・依存関係・生成方式・  
テンプレート利用方針・再構成時の扱いを統一的に定義する。

---

# 1. systemd ユニット構成の全体像

NVR の systemd ユニットは以下の2種類に分類される：

## 1.1 個別生成ユニット（カメラ固有）
```
/etc/systemd/system/ffmpeg_nvr_<CAM>.service
```

## 1.2 テンプレートユニット（カメラ名のみ可変）
```
/etc/systemd/system/opencv_motion@.service
/etc/systemd/system/motion_event_handler@.service
```

---

# 2. 役割と依存関係

## 2.1 ffmpeg_nvr_<CAM>.service（映像入力層）

- RTSP ストリームを ffmpeg で録画  
- JPEG を生成し OpenCV が参照する  
- 録画セグメントを保存する  
- day/night 設定を適用する  

### 依存関係
- OpenCV → ffmpeg の JPEG を参照するため **ffmpeg が先に起動している必要がある**

---

## 2.2 opencv_motion@<CAM>.service（動体検知層）

- ffmpeg が生成した JPEG を監視  
- motion.flag と yavg.txt を生成  
- 動体検知ロジックを実行  

### 依存関係
- handler → OpenCV の出力を参照するため **OpenCV が先に起動している必要がある**

---

## 2.3 motion_event_handler@<CAM>.service（イベント処理層）

- motion.flag の変化を監視  
- event.json を生成  
- ESP32-CAM などへの通知を行う  

### 依存関係
- handler は OpenCV の出力に依存するため **最後に起動する**

---

# 3. ffmpeg_nvr_<CAM>.service の仕様（個別生成）

ffmpeg_nvr は systemd テンプレートを使用せず、  
**setup_nvr.sh が cameras.yaml を読み取り、カメラごとに個別生成する。**

理由：

- systemd テンプレートでは `%i` しか扱えず  
  IP / RTSP ポート / segment_time / 保存先 / daynight_mode など  
  **カメラ固有の設定を渡せないため**

### 生成されるユニット例

```
[Unit]
Description=NVR FFmpeg Recorder (<CAM>)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=/usr/local/bin/nvr/camera_daynight_apply.sh <CAM>
ExecStart=/usr/local/bin/nvr/run_ffmpeg.sh <CAM>
Restart=always
RestartSec=5
RuntimeMaxSec=<SEGMENT_TIME>
KillMode=process
TimeoutStopSec=1
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

---

# 4. opencv_motion@.service の仕様（テンプレート）

opencv_motion はテンプレートユニットを使用する。

理由：

- カメラ名以外の設定は YAML からスクリプト側で読み取る  
- systemd 側に複雑な設定を持たせる必要がない  
- `%i` でカメラ名だけ渡せば十分  

### 呼び出し例

```
systemctl start opencv_motion@frontdoor.service
```

---

# 5. motion_event_handler@.service の仕様（テンプレート）

motion_event_handler もテンプレートユニットを使用する。

理由：

- handler は motion.flag の変化を監視するだけで  
  systemd 側にカメラ固有設定を持たせる必要がない  
- `%i` でカメラ名だけ渡せば十分  

---

# 6. 起動順序（start_nvr.sh が保証）

NVR の正しい起動順序は以下：

1. **ffmpeg_nvr_<CAM>.service**  
2. **opencv_motion@<CAM>.service**  
3. **motion_event_handler@<CAM>.service**

stop_nvr.sh はこの逆順で停止する。

---

# 7. 再構成時の扱い（setup_nvr.sh が保証）

setup_nvr.sh は systemd の正規化ポイントとして以下を行う：

### 7.1 YAML に無いカメラのユニット削除
- ffmpeg_nvr_<CAM>.service  
- opencv_motion@<CAM>.service  
- motion_event_handler@<CAM>.service  

### 7.2 YAML に無い TMP_DIR の削除

### 7.3 enabled=false のカメラの disable＋削除

### 7.4 enabled=true のカメラのユニット生成＋enable

---

# 8. systemd ユニットの配置

```
/etc/systemd/system/
  ├── ffmpeg_nvr_frontdoor.service
  ├── ffmpeg_nvr_garden.service
  ├── opencv_motion@.service
  └── motion_event_handler@.service
```

---

# 9. 備考

- cameras.yaml が唯一の真実のソース  
- systemd の状態は setup_nvr.sh によって正規化される  
- start_nvr.sh / stop_nvr.sh は運用フェーズ専用  
- ffmpeg_nvr は個別生成、他はテンプレートという構造は  
  NVR の柔軟性と拡張性を最大化するための設計  

---

# End of Document
