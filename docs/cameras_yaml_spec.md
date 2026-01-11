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
  save_dir_base: /mnt/USBHDD/Share/share/NVR
  motion_tmp_base: /dev/shm/motion_tmp

  default_segment_time: 300
  default_event_timeout: 10

  default_motion_filter_day: "tblend=all_mode=average,select='gt(scene,0.05)'"
  default_motion_filter_night: "select='gt(scene,0.05)'"

  daynight_mode: "brightness"
  brightness_threshold: 40

  latitude: 35.423
  longitude: 136.863

cameras:
  - name: frontdoor
    enabled: true
    ip: 192.168.0.59
    rtsp_port: 8554

    segment_time: 300
    event_timeout: 10

    analyze_brightness: true

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
| `save_dir_base` | 録画データ（MKV・イベント）の保存先 |
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

## 3.3 motion filter（ffmpeg の scene 検出）

### 昼
```
tblend=all_mode=average,select='gt(scene,0.05)'
```

### 夜
```
select='gt(scene,0.05)'
```

夜はノイズが多いため tblend を外している。

---

## 3.4 昼夜判定

| キー | 説明 |
|------|------|
| `daynight_mode` | brightness / time / sunrise |
| `brightness_threshold` | 明るさの閾値（40 以上で昼） |

sunrise モード用に緯度経度も設定可能。

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
