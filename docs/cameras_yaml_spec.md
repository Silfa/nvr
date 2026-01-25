# cameras.yaml Specification  
NVR System — Camera & Recording Configuration

このドキュメントは `/etc/nvr/cameras.yaml` の正式仕様をまとめたもの。  
NVR のすべてのコンポーネント（ffmpeg、OpenCV、handler、ESP32-CAM 設定）が  
この YAML を基準に動作する。

---

# 1. ファイルの役割

`cameras.yaml` は NVR の **唯一の設定ファイル**であり、以下を制御する。

- 録画ディレクトリ構成  
- ffmpeg の録画設定（セグメント長、motion filter）  
- OpenCV の動体検知パラメータ（昼夜切り替え）  
- ESP32-CAM の昼夜設定（HTTP API）  
- brightness による昼夜判定  
- sunrise モード（将来拡張）  
- RAM ディスクの latest.jpg / motion.flag の配置  

---

# 2. YAML 全体構造

```yaml
common:
  python_venv_dir: /usr/local/nvr-venv
  
  records_dir_base: /mnt/USBHDD/Share/share/NVR/records
  events_dir_base: /mnt/USBHDD/Share/share/NVR/events
  motion_tmp_base: /dev/shm/motion_tmp

  default_segment_time: 300
  default_event_timeout: 10
  default_daynight_mode: "brightness" # brightness / time / sunrise
  
  # brightness mode settings
  default_brightness_threshold: 40
  
  # sunrise mode settings
  latitude: "35.423N"
  longitude: "136.863E"
  
  # time mode settings
  day_start: "06:00"
  night_start: "18:00"

  default_motion_threshold: 50
  default_motion_min_area: 500
  default_motion_blur: 5

cameras:
  - name: frontdoor
    display_name: 玄関
    enabled: true
    type: esp32cam # esp32cam / rtsp / usb
    
    connection:
      host: 192.168.0.59
      port: 80
      rtsp_url: null

    ffmpeg:
      segment_time: 300
    
    event:
      timeout: 10

    daynight:
      mode: brightness
      brightness_threshold: 40
      # lat/lon or time settings can be overridden here
    
    motion:
      enabled: true
      threshold: 64
      min_area: 500

    esp32cam:
      rtsp_port: 8554
      camera_config:
        day: |
          { ... }
        night: |
          { ... }
```

---

# 3. common セクションの仕様

## 3.1 ディレクトリ設定

| キー | 説明 |
|------|------|
| `records_dir_base` | 録画データ（MKV）の保存先ベースディレクトリ |
| `events_dir_base` | イベントデータ（JSON, JPEG）の保存先ベースディレクトリ |
| `motion_tmp_base` | RAM ディスク上の latest.jpg / motion.flag の保存先 |

例：  
`/dev/shm/motion_tmp/frontdoor/latest.jpg`

---

## 3.2 録画設定（ffmpeg）

| キー | 説明 |
|------|------|
| `default_segment_time` | MKV のセグメント長（秒） |
| `default_event_timeout` | motion.flag が消えてからイベント終了までの猶予 |

---

## 3.3 動体検知設定 (OpenCV)

`common` でデフォルト値を設定し、`cameras` 内で override 可能。

| キー | 説明 |
|------|------|
| `default_motion_threshold` | 差分検知の閾値 (0-255) |
| `default_motion_min_area` | 動体とみなす最小面積 (px) |
| `default_motion_blur` | ブラー処理のカーネルサイズ (奇数) |

---

## 3.4 昼夜判定

| キー | 説明 |
|------|------|
| `default_daynight_mode` | brightness / time / sunrise |
| `default_brightness_threshold` | 明るさの閾値（これ以上で昼） |
| `latitude` / `longitude` | sunrise モード用の緯度経度 |
| `day_start` / `night_start` | time モード用の開始時間 ("HH:MM") |

各カメラの設定（`daynight` ブロック）で上書き可能。

---

# 4. cameras セクションの仕様

各カメラは以下の項目を持つ。

| キー | 説明 |
|------|------|
| `name` | カメラ識別名（ディレクトリ名にも使用） |
| `enabled` | true で有効 |
| `ip` | ESP32-CAM の IP |
| `rtsp_port` | RTSP ポート |
| `segment_time` | 個別の録画セグメント長 |
| `event_timeout` | 個別のイベント終了猶予 |
| `analyze_brightness` | OpenCV による明るさ解析を有効化 |

---

# 5. ESP32-CAM 昼夜設定（camera_config）

`camera_config.day` と `camera_config.night` は  
**POST /config** にそのまま送れる JSON。

### 昼設定の特徴
- gain_ctrl
