# event.json Specification  
NVR System — Motion Event Metadata Format

このドキュメントは、NVR が動体検知イベントを記録する際に
イベントディレクトリ内へ保存する `event.json` の正式仕様をまとめたもの。

`event.json` は UI、検索、AI 処理、外部連携の基礎データとなる。

---

# 1. event.json の役割

- イベントの開始・終了時刻
- イベントの継続時間 
- 昼夜判定 
- 明るさ情報（OpenCV） 
- 保存された JPEG の統計 
- AI 推論結果（将来拡張） 

これらを 1 つの JSON に統合して保存する。

---

# 2. 保存場所

```
/mnt/USBHDD/Share/share/NVR/<camera>/<YYYYMMDD>/<HHMMSS_event>/event.json
```

例：

```
/mnt/USBHDD/Share/share/NVR/frontdoor/20250214/183012_event/event.json
```

---

# 3. JSON スキーマ（/etc/nvr/event.schema.json）

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "NVR Motion Event Schema",
  "type": "object",

  "properties": {
    "timestamp":        { "type": "string" },
    "timestamp_end":    { "type": "string" },
    "duration_sec":     { "type": "number", "minimum": 0 },

    "camera":           { "type": "string" },
    "event_timeout":    { "type": "number", "minimum": 0 },

    "daynight":         { "type": "string", "enum": ["day", "night", "unknown"] },

    "brightness_min":   { "type": "number" },
    "brightness_max":   { "type": "number" },

    "jpeg_count":       { "type": "number", "minimum": 1 },
    "first_frame":      { "type": "string" },
    "last_frame":       { "type": "string" },

    "total_size_bytes": { "type": "number", "minimum": 0 },
    
    "ai_tags": {
      "type": "array",
      "items": { "type": "string" }
    },
    "ai_objects": {
      "type": "array",
      "items": { "type": "string" }
    },
    "ai_confidence": {
      "type": "array",
      "items": { "type": "number" }
    }
  },

  "required": [
    "timestamp",
    "timestamp_end",
    "duration_sec",
    "camera",
    "jpeg_count"
  ]
}
```

---

# 4. フィールド仕様

## 4.1 時刻関連

| フィールド | 説明 |
|-----------|------|
| `timestamp` | イベント開始時刻（ISO8601） |
| `timestamp_end` | イベント終了時刻（ISO8601） |
| `duration_sec` | イベント継続時間（秒） |

---

## 4.2 カメラ情報

| フィールド | 説明 |
|-----------|------|
| `camera` | カメラ名（cameras.yaml の name） |
| `event_timeout` | motion.flag が消えてからの終了猶予（秒） |

---

## 4.3 昼夜判定・明るさ情報

| フィールド | 説明 |
|-----------|------|
| `daynight` | "day" / "night" / "unknown" |
| `brightness_min` | イベント中の最小明るさ |
| `brightness_max` | イベント中の最大明るさ |

---

## 4.4 JPEG 情報

| フィールド | 説明 |
|-----------|------|
| `jpeg_count` | 保存された JPEG の枚数 |
| `first_frame` | 最初の JPEG ファイル名 |
| `last_frame` | 最後の JPEG ファイル名 |

---

## 4.5 サイズ情報

| フィールド | 説明 |
|-----------|------|
| `total_size_bytes` | JPEG 合計サイズ |

---

## 4.6 AI 情報（将来拡張）

| フィールド | 説明 |
|-----------|------|
| `ai_tags` | AI が付与したタグ |
| `ai_objects` | 検出された物体名 |
| `ai_confidence` | 信頼度（0〜1） |

---

# 5. 必須フィールド

```
timestamp
timestamp_end
duration_sec
camera
jpeg_count
```

---

# 6. 備考

- event.json は UI のイベント一覧・検索の基礎データ
- OpenCV と ffmpeg の両方の情報を統合
- AI 拡張を見据えたフィールド構造
- multi-camera 対応を前提に設計

---

# End of Document
