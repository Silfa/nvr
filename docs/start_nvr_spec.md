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
2. **opencv_motion@<cam>.service**
3. **motion_event_handler@<cam>.service**

ただし、起動対象は cameras.yaml ではなく  
**systemd に登録されている NVR 関連ユニットを動的に検出して決定する**。

起動順序は以下の通り：

- ffmpeg → opencv → handler

理由：

- ffmpeg が映像ストリームを生成しないと OpenCV が動作できない  
- OpenCV が動作しないと handler がイベント処理できない  
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
opencv_motion@*.service
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

# 4. 起動前チェック（重要・新規）

start_nvr.sh は、各カメラについて以下の3つのユニットが  
**すべて存在するかを起動前に確認する**：

- ffmpeg_nvr@<cam>.service  
- opencv_motion@<cam>.service  
- motion_event_handler@<cam>.service  

## 4.1 3つすべて存在する場合  
→ 起動処理を実行する。

## 4.2 1つでも欠けている場合  
→ そのカメラは起動対象から除外し、警告を出す。

特に：

### ✔ ffmpeg_nvr が欠けている場合  
→ **そのカメラの起動は中止する（必須ユニットのため）**

例：

```
[start_nvr] error: ffmpeg_nvr@frontdoor.service is missing. Skipping frontdoor.
```

## 4.3 全カメラでユニットが揃っていない場合  
→ start_nvr.sh 全体を停止し、エラー終了する。

---

# 5. 起動順序

各カメラについて以下の順序で起動する：

1. **ffmpeg_nvr@<cam>.service**
2. **opencv_motion@<cam>.service**
3. **motion_event_handler@<cam>.service**

起動対象が存在する場合のみ起動する。

---

# 6. ログ出力

start_nvr.sh は以下の形式でログを出力する：

```
[start_nvr] starting <CAM> (ffmpeg → opencv → handler)
[start_nvr] done <CAM>
```

---

# 7. エラー処理

- 必須ユニットが欠けている場合  
  → そのカメラは起動しない  
- systemctl start が失敗した場合  
  → エラーを表示しつつ次のサービスへ進む  
- systemd に NVR 関連ユニットが 1 つも存在しない場合  
  → エラー終了  

---

# 8. 備考

- 本仕様は **systemd の状態が壊れていても誤起動を防ぐ**  
- cameras.yaml と systemd のズレがあっても安全に動作する  
- stop_nvr.sh と対になる運用スクリプト  
- setup_nvr.sh は初回セットアップ専用とし、  
  start_nvr.sh は運用フェーズで使用する  

---

# End of Document
