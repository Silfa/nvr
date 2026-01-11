# motion_event_handler.sh Specification  
NVR System — Event Management Layer (OpenCV Integration)

本ドキュメントは、OpenCV による動体検知を前提とした  
`motion_event_handler.sh` の正式仕様をまとめたもの。

本スクリプトは **イベントの開始・継続・終了を管理する唯一のレイヤー**であり、  
OpenCV は「動体あり／なし」の判定のみを提供する。

---

# 1. 役割概要

motion_event_handler.sh は以下を行う：

1. OpenCV が生成する `motion.flag` を監視  
2. ffmpeg が生成する `latest.jpg` の mtime を監視  
3. イベントの開始・継続・終了を管理  
4. 記録用 JPEG を連番で保存  
5. event.json を生成・更新  
6. idle_sec による終了判定を行う  
7. OpenCV や ffmpeg の内部には干渉しない

---

# 2. 入力

```
motion_event_handler.sh <camera_name>
```

例：

```
motion_event_handler.sh frontdoor
```

---

# 3. 読み取る設定ファイル

```
/etc/nvr/cameras.yaml
```

読み取る項目：

- cameras[].event.idle_sec  
- cameras[].event.max_duration（任意）  
- common.motion_tmp_base  
- common.events_base  

---

# 4. 入出力ファイル

## 4.1 OpenCV が生成するフラグ

### ✔ 動体フラグ  
```
/dev/shm/motion_tmp_<CAM>/motion.flag
```
- 存在 → 動体あり  
- 不在 → 動体なし  
- 内容は空でよい（存在がフラグ）

## 4.2 ffmpeg が生成するフレーム

```
/dev/shm/motion_tmp_<CAM>/latest.jpg
```
- 2fps 程度で更新される  
- 記録用 JPEG の元データとして使用する

## 4.3 handler が生成するイベントデータ

### ✔ JPEG（連番）
```
events/<CAM>/<YYYY>/<MM>/<EVENT_ID>/0001.jpg
events/<CAM>/<YYYY>/<MM>/<EVENT_ID>/0002.jpg
...
```

### ✔ event.json
```
events/<CAM>/<YYYY>/<MM>/<EVENT_ID>/event.json
```

---

# 5. イベント管理ロジック

## 5.1 イベント開始条件

以下の両方を満たしたとき：

1. `motion.flag` が存在する  
2. 現在イベント中でない（event_active=false）

開始時に行う処理：

- EVENT_ID を生成（例：20250101_120305）  
- イベントディレクトリを作成  
- event.json を生成（start_time のみ）  
- event_active=true  
- frame_counter=0

---

## 5.2 イベント継続条件

以下の両方を満たす間：

1. `motion.flag` が存在する  
2. idle_sec が経過していない

継続中に行う処理：

### ✔ latest.jpg の mtime を監視  
- 前回保存時刻より新しければ記録用 JPEG として保存  
- 保存名は 0001.jpg, 0002.jpg … の連番  
- frame_counter をインクリメント

---

## 5.3 イベント終了条件

以下のいずれか：

1. `motion.flag` が消えてから idle_sec 経過  
2. max_duration を超えた（任意）

終了時に行う処理：

- event.json に end_time を追記  
- num_frames を追記  
- event_active=false  
- 次のイベントに備えて内部状態をリセット

---

# 6. 動作ループ

```
loop:
    if motion.flag が存在:
        if イベント中でない:
            → イベント開始
        if latest.jpg の mtime が更新されていれば:
            → JPEG を連番保存
        → イベント継続
    else:
        if イベント中:
            if idle_sec 経過:
                → イベント終了
```

---

# 7. エラー処理

- latest.jpg が存在しない → スキップ  
- motion.flag が読めない → 動体なし扱い  
- JPEG 保存失敗 → ログ出力のみ  
- event.json 書き込み失敗 → ログ出力のみ  
- スクリプトは常に常駐し続ける（systemd restart=always）

---

# 8. systemd との連携

```
motion_event_handler@<CAM>.service
```

依存関係：

- After=opencv_motion@%i.service  
- Wants=opencv_motion@%i.service  

OpenCV → handler → ffmpeg の順で連携する。

---

# 9. 備考

- 記録用 JPEG は OpenCV ではなく handler が保存する  
- OpenCV は動体判定のみ  
- ffmpeg は latest.jpg を生成するだけ  
- ESP32‑CAM の単一接続制約を完全に回避できる  
- handler のロジックは既存の idle_sec ベースをそのまま活かす  

---

# End of Document
