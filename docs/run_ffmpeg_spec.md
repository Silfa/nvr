# run_ffmpeg.sh Specification  
NVR System — Frame Provider & Recorder (OpenCV Integration, MJPEG/MKV)

本ドキュメントは、ESP32‑CAM の RTSP（MJPEG）ストリームを ffmpeg で受信し、  
最新フレーム（latest.jpg）と録画ファイル（MKV）を生成する  
`run_ffmpeg.sh` の正式仕様をまとめたもの。

OpenCV による動体検知を前提とした構成であり、  
ffmpeg は **動体検知を行わず、録画と最新フレーム提供のみを担当する**。

---

# 1. 役割概要

run_ffmpeg.sh は以下を行う：

1. ESP32‑CAM の RTSP（MJPEG）ストリームを受信  
2. latest.jpg を 2fps 程度で常時更新  
3. 録画ファイル（MKV）を生成  
4. 録画ファイルの分割は **ffmpeg ではなく systemd により行われる**  
5. signalstats や motion_filter は使用しない  

---

# 2. 入力

```
run_ffmpeg.sh <camera_name>
```

例：

```
run_ffmpeg.sh frontdoor
```

---

# 3. 読み取る設定ファイル

```
/etc/nvr/cameras.yaml
```

読み取る項目：

- cameras[].rtsp  
- common.motion_tmp_base  
- common.record_base  
- cameras[].record.max_runtime_sec（systemd の RuntimeMaxSec と一致させる）

---

# 4. 入出力ファイル

## 4.1 出力（OpenCV が読む最新フレーム）

```
/dev/shm/motion_tmp_<CAM>/latest.jpg
```

- 2fps 程度で上書き更新  
- OpenCV が動体検知に使用  
- handler が記録用 JPEG として保存する

## 4.2 出力（録画ファイル）

```
/mnt/nvr/record/<CAM>/<YYYYMMDD_HHMMSS>.mkv
```

- コンテナは **MKV（Matroska）**  
- コーデックは **MJPEG を copy**  
- systemd による再起動でファイルが分割される

---

# 5. 動作仕様

## 5.1 latest.jpg の生成

ffmpeg は RTSP を受信し、以下の条件で最新フレームを生成する：

- fps=2（設定可能）  
- JPEG 品質 q:v=5（設定可能）  
- -update 1 により同一ファイル名に上書き  

例：

```
ffmpeg -rtsp_transport tcp -i "$RTSP_URL" \
    -vf fps=2 \
    -q:v 5 \
    -update 1 "$TMP_DIR/latest.jpg"
```

---

## 5.2 録画ファイルの生成（MKV）

録画は以下の条件で行う：

- RTSP（MJPEG）を **copy** で保存（再エンコードなし）  
- コンテナは MKV  
- ファイル名は日時ベース  

例：

```
-c copy "$RECORD_DIR/$(date +%Y%m%d_%H%M%S).mkv"
```

---

## 5.3 録画ファイルの分割（systemd によるライフタイム管理）

本システムでは、録画ファイル（MKV）の分割は  
**ffmpeg の segment 機能を使用しない**。

録画ファイルのローテーションは、以下の systemd の機能により実現される。

### 1. RuntimeMaxSec  
ffmpeg_nvr@.service に `RuntimeMaxSec=<秒>` を設定することで、  
**一定時間経過後に ffmpeg プロセスを強制終了**させる。

### 2. Restart=always  
ffmpeg プロセス終了後、systemd が自動的に再起動することで、  
**新しい MKV ファイルが開始される**。

### ✔ この方式のメリット

- ffmpeg の segment バグに依存しない  
- RTSP の再接続を systemd が確実に行う  
- 長時間録画による MKV の肥大化を防止  
- ESP32‑CAM の RTSP が不安定でも自動復旧  
- 設計がシンプルで堅牢  

---

# 6. コンテナ形式（MKV を採用する理由）

本システムでは録画コンテナとして **MKV（Matroska）** を使用する。

理由：

1. ESP32‑CAM の RTSP ストリームは MJPEG（全フレーム I-frame）であり、  
   MP4 コンテナでは互換性問題が発生する場合がある。

2. MP4 は moov atom の破損に弱く、systemd による強制再起動と相性が悪い。

3. MKV はフレーム単位で柔軟に格納でき、  
   途中でプロセスが終了してもファイルが壊れにくい。

4. 多くのプレイヤー（VLC, mpv, ffplay, Kodi）で高い互換性を持つ。

---

# 7. 削除された機能（OpenCV 版で不要）

以下は **OpenCV 導入により完全に削除**される：

### ❌ motion_filter  
- ffmpeg による動体検知は行わない

### ❌ signalstats  
- brightness 判定は OpenCV の yavg.txt に移行

### ❌ ffmpeg の segment 機能  
- 録画ファイルの分割は systemd が担当する

---

# 8. systemd との連携

```
ffmpeg_nvr@<CAM>.service
```

依存関係：

- After=camera_daynight_apply@%i.service  
- OpenCV とは独立（latest.jpg を提供するだけ）

systemd の RuntimeMaxSec と Restart=always により  
録画ファイルのローテーションが行われる。

---

# 9. 備考

- ffmpeg は「録画し続けるだけ」  
- 動体検知は OpenCV  
- イベント管理は handler  
- 昼夜判定は yavg.txt（OpenCV）  
- ESP32‑CAM の単一接続制約を完全に回避できる  

---

# End of Document
