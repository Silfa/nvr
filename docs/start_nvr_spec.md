# start_nvr.sh Specification
NVR System — Service Start Controller (Updated)

このドキュメントは、NVR の全コンポーネントを安全に起動するための  
`/usr/local/bin/nvr/start_nvr.sh` の正式仕様をまとめたもの。

start_nvr.sh は systemd 管理下の NVR サービス群を  
**正しい順序で、安全に、確実に起動する**ための制御スクリプトである。

本仕様書は stop_nvr.sh と対になるものであり、  
停止と起動の対称性を保つことを目的とする。

---

# 1. 役割概要

start_nvr.sh は以下の NVR コンポーネントを起動する：

1. **ffmpeg_nvr@<cam>.service**
2. **motion_detector@<cam>.service**
3. **motion_event_handler@<cam>.service**

ただし、起動対象は cameras.yaml ではなく
**systemd に登録されている NVR 関連ユニットを動的に検出して決定する**。

起動順序は以下の通り：

- ffmpeg → motion_detector → handler

理由：

- ffmpeg が映像ストリームを生成しないと Motion Detector (OpenCV) が動作できない
- Motion Detector が動作しないと handler がイベント処理できない
- 依存関係を満たすため、下層から順に起動する

---

# 2. 入力

```
start_nvr.sh
```

引数は不要。

---

# 3. 起動対象サービスの検出方式

stop_nvr.sh と同様、
**systemd のユニット一覧から NVR 関連サービスを検出する**。

## 3.1 検出対象

```
ffmpeg_nvr@*.service
motion_detector@*.service
motion_event_handler@*.service
```

## 3.2 検出方法

```
systemctl list-unit-files --type=service
```

から上記パターンに一致するユニットを抽出する。

## 3.3 カメラ名の抽出

サービス名の `@<cam>.service` 部分から `<cam>` を抽出し、
**カメラ単位でグループ化**する。

---

# 4. 起動プロセス

start_nvr.sh は検出された各カメラについて、以下の順序でサービスを起動（`systemctl start`）する。
起動ごとに `is-active` をポーリングし、起動完了を待機する。

1. **ffmpeg_nvr@<cam>.service**
   - 起動後、Active になるまで待機（最大10秒）
2. **motion_detector@<cam>.service**
   - 起動後、Active になるまで待機（最大10秒）
3. **motion_event_handler@<cam>.service**
   - 起動後、Active になるまで待機（最大10秒）

いずれかのサービス起動に失敗しても、ログを出力して次のステップまた次のカメラの処理へ進む。

---

# 5. エラー処理

- systemctl start が失敗した場合
  → エラーを表示しつつ次のサービスへ進む
- systemd に NVR 関連ユニットが 1 つも存在しない場合
  → エラー終了

---

# 6. ログ出力

start_nvr.sh は以下の形式でログを出力する：

```
[start_nvr] Starting camera: <CAM>
[start_nvr] Waiting for ffmpeg_nvr@<CAM> to become active... OK
[start_nvr] Waiting for motion_detector@<CAM> to become active... OK
[start_nvr] Waiting for motion_event_handler@<CAM> to become active... OK
```

---

# 7. 備考

- 本仕様は **systemd の状態が壊れていても誤起動を防ぐ**
- cameras.yaml と systemd のズレがあっても安全に動作する
- stop_nvr.sh と対になる運用スクリプト
- setup_nvr.sh は初回セットアップ専用とし、
  start_nvr.sh は運用フェーズで使用する

---

# End of Document
