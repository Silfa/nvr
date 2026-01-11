# camera_daynight_apply.sh — Specification  
NVR System — Day/Night Configuration Applier for ESP32‑CAM

このドキュメントは、NVR の昼夜設定を ESP32‑CAM に適用する  
`/usr/local/bin/nvr/camera_daynight_apply.sh` の正式仕様をまとめたもの。

camera_daynight_apply.sh は get_daynight.sh の判定結果をもとに、  
ESP32‑CAM の HTTP API に対して適切な設定（露出・ゲイン・フレームレート等）を送信する。

---

# 1. 目的と役割

camera_daynight_apply.sh は、録画開始前にカメラの昼夜設定を正しく適用するためのスクリプトである。  
主な処理は以下の通り：

1. get_daynight.sh を呼び出して「day/night」を取得  
2. cameras.yaml から対象カメラの設定を読み取る  
3. 昼用・夜用の設定を ESP32‑CAM に HTTP 経由で送信  
4. 前回の判定結果と比較し、変化がある場合のみ設定を適用  
5. ffmpeg 起動前（ExecStartPre）に毎回実行される  

これにより、録画開始時点でカメラが適切なモードに設定される。

---

# 2. 使用方法

```
camera_daynight_apply.sh <camera_name>
```

例：

```
camera_daynight_apply.sh frontdoor
```

---

# 3. 参照する設定ファイル

```
/etc/nvr/cameras.yaml
```

読み取る項目：

- cameras[].ip  
- cameras[].http_port  
- cameras[].day_config  
- cameras[].night_config  
- daynight.mode（brightness / time / fixed）  

---

# 4. 昼夜判定処理

内部で以下を実行：

```
mode=$(get_daynight.sh <CAM>)
```

返り値：

- `day`
- `night`

get_daynight.sh が失敗した場合は安全側として `night` を採用する。

---

# 5. 前回判定結果との比較（DAYNIGHT_FILE）

昼夜設定は、前回の判定結果と異なる場合のみ適用する。

### DAYNIGHT_FILE のパス

```
/dev/shm/daynight_<CAM>.txt
```

### 処理内容

1. 前回の判定結果を読み込む（存在しない場合は初回とみなす）  
2. 今回の判定結果と比較  
3. **変化がなければ何もせず終了**  
4. 変化があれば設定を適用し、DAYNIGHT_FILE を更新  

### 目的

- 不必要な設定再適用を防ぐ  
- 境界時間帯での揺れによる連続適用を防止  
- systemd のログを汚さない  
- 冪等性（idempotency）を保つ  

---

# 6. 適用される設定

## 6.1 昼モード（day_config）

例：

```yaml
day_config:
  exposure: 0
  gain: 0
  brightness: 0
  contrast: 0
  saturation: 0
  denoise: 1
  fps: 25
```

## 6.2 夜モード（night_config）

例：

```yaml
night_config:
  exposure: 1
  gain: 4
  brightness: 2
  contrast: 1
  saturation: 0
  denoise: 2
  fps: 15
```

---

# 7. ESP32‑CAM への設定反映

HTTP API を使用：

```
http://<IP>:<PORT>/control?var=<param>&val=<value>
```

camera_daynight_apply.sh は day/night の設定をループで送信する：

```
for each parameter in config:
    curl -s "http://IP:PORT/control?var=<param>&val=<value>"
```

特徴：

- 設定は 1 パラメータずつ送信  
- 失敗してもスクリプトは停止しない（ログのみ）  
- ffmpeg 起動前に確実に反映される  

---

# 8. systemd との連携

ffmpeg_nvr_<CAM>.service の ExecStartPre で呼ばれる：

```
ExecStartPre=/usr/local/bin/nvr/camera_daynight_apply.sh <CAM>
```

これにより：

- ffmpeg 起動前にカメラ設定が確実に適用される  
- 昼夜切り替えが録画セグメント単位で反映される  
- brightness モードでは環境光に応じて自動調整される  

---

# 9. エラー処理

- get_daynight.sh が失敗 → `night` とみなす  
- HTTP リクエスト失敗 → ログ出力のみ  
- YAML の設定が欠けている → 該当項目をスキップ  
- スクリプト自体は常に成功終了する（ExecStartPre の安定性確保）  

---

# 10. 備考

- ESP32‑CAM の設定は即時反映される  
- 昼夜切り替えは ffmpeg のセグメント周期で自然に行われる  
- brightness モードは signalstats の YAVG に依存  
- time モードは安定性が高く屋内カメラに向く  

---

# End of Document
