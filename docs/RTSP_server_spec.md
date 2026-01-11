# ESP32-CAM RTSP Server Specification  
Firmware for ESP32-CAM — JPEG/RTP over RTSP + HTTP Config API

このドキュメントは、ESP32-CAM 上で動作する  
`RTSP_server.ino` の正式仕様をまとめたもの。

NVR システムの「映像入力デバイス」として、  
RTSP ストリーミングと HTTP 設定 API を提供する。

---

# 1. 機能概要

ESP32-CAM は以下の機能を提供する：

- JPEG/RTP over RTSP (TCP interleaved)
- HTTP 設定 API（GET /config, POST /config）
- SPIFFS による config.json 保存
- カメラ設定の即時反映（brightness, contrast, vflip など）
- 再起動が必要な設定の自動判定（frame_size, fb_count など）
- WiFi 設定の保存と再起動
- RTP/JPEG フラグメント送信（RFC2435 準拠）
- RTSP OPTIONS / DESCRIBE / SETUP / PLAY の実装

---

# 2. 設定ファイル構造（SPIFFS: /config.json）

```json
{
  "wifi": {
    "ssid": "",
    "password": ""
  },
  "rtsp": {
    "port": 8554
  },
  "camera": {
    "frame_size": "SVGA",
    "jpeg_quality": 14,
    "fb_count": 2,
    "vflip": true,
    "hmirror": true,
    "brightness": 0,
    "contrast": 0,
    "saturation": 0,
    "awb": true,
    "awb_mode": 0,
    "aec": true,
    "aec2": true,
    "gain_ctrl": true,
    "denoise": true,
    "sharpness": 0,
    "lenc": true
  },
  "stream": {
    "fps": 10,
    "max_payload": 1400,
    "ssrc": "auto"
  }
}
```

---

# 3. HTTP API

## 3.1 GET /config  
現在の設定を JSON で返す。

## 3.2 POST /config  
設定を更新する。  
以下の項目は **即時反映**：

- vflip / hmirror  
- brightness / contrast / saturation  
- awb / awb_mode  
- aec / aec2 / gain_ctrl  
- denoise / sharpness / lenc  

以下は **再起動が必要**：

- wifi.ssid / wifi.password  
- rtsp.port  
- camera.frame_size  
- camera.fb_count  
- camera.jpeg_quality（fb_count=1 の場合）

---

# 4. RTSP 実装

## 4.1 対応コマンド

- OPTIONS  
- DESCRIBE  
- SETUP（TCP のみ、UDP は 461 Unsupported）  
- PLAY  

## 4.2 RTP/JPEG 送信

- RFC2435 準拠の JPEG ヘッダ  
- RTP timestamp = 90000 / FPS  
- max_payload に応じて分割送信  
- TCP interleaved（$ + channel + length + payload）

---

# 5. カメラ設定

`applyCameraSettings()` にて以下を反映：

- vflip / hmirror  
- brightness / contrast / saturation  
- awb / awb_mode  
- aec / aec2 / gain_ctrl  
- denoise / sharpness / lenc  

frame_size / jpeg_quality / fb_count は  
カメラ初期化時にのみ適用される。

---

# 6. WiFi

- config.json の値を使用  
- 設定変更時は再起動  
- WiFi.setSleep(false) でスリープ無効化

---

# 7. スレッド安全性

- カメラアクセスは `camera_mutex` で保護  
- fb_get / fb_return を排他制御

---

# 8. 今後の拡張予定

- RTP SSRC の固定値対応  
- UDP 対応（現在は拒否）  
- マルチクライアント対応  
- JPEG QTable の送信（RFC2435 Section 3.1.8）

---

# End of Document
