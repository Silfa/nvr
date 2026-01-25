# stop_nvr.sh Specification
NVR System — Service Stop Controller (Updated)

このドキュメントは、NVR の全コンポーネントを安全に停止するための  
`/usr/local/bin/nvr/stop_nvr.sh` の正式仕様をまとめたもの。

本仕様書は従来の「cameras.yaml に基づく停止方式」から  
**systemd の実際の稼働状態を基準に停止対象を決定する方式**へ更新されている。

stop_nvr.sh は、NVR に関連する systemd サービスを  
**正しい順序で、安全に、確実に停止する**ための制御スクリプトである。

---

# 1. 役割概要

stop_nvr.sh は以下の NVR コンポーネントを停止する：

1. **motion_event_handler@<cam>.service**
2. **motion_detector@<cam>.service**
3. **ffmpeg_nvr@<cam>.service**

ただし、停止対象は cameras.yaml ではなく  
**systemd 上で実際に稼働中のサービスを動的に検出して決定する**。

停止順序は従来通り：

- handler → motion_detector → ffmpeg

理由：

- handler はイベントを閉じる責務があるため、最初に停止する  
- motion_detector は motion.flag と yavg.txt を更新するため、handler 停止後に停止  
- ffmpeg は録画ストリームを生成するため、最後に停止する  

---

# 2. 入力

```
stop_nvr.sh
```

引数は不要。

---

# 3. 停止対象サービスの検出方式（更新点）

従来は cameras.yaml の cameras[].name を基準にしていたが、  
本仕様では **systemd の実際の稼働状態を基準にする**。

## 3.1 検出対象

```
motion_event_handler@*.service
motion_detector@*.service
ffmpeg_nvr@*.service
```

## 3.2 検出方法

```
systemctl list-units --type=service --state=running
```

から上記パターンに一致するサービスを抽出する。

## 3.3 カメラ名の抽出

サービス名の `@<cam>.service` 部分から `<cam>` を抽出し、  
**カメラ単位でグループ化**する。

例：

```
motion_event_handler@frontdoor.service
motion_detector@frontdoor.service
ffmpeg_nvr@frontdoor.service
```

→ カメラ名は `frontdoor`

---

# 4. 停止順序（仕様変更なし）

各カメラについて以下の順序で停止する：

1. **motion_event_handler@<cam>.service**
2. **motion_detector@<cam>.service**
3. **ffmpeg_nvr@<cam>.service**

systemd 側から検出したサービスが存在する場合のみ停止する。

---

# 5. ログ出力

stop_nvr.sh は以下の形式でログを出力する：

```
[stop_nvr] stopping <CAM> (handler → opencv → ffmpeg)
[stop_nvr] done <CAM>
```

---

# 6. エラー処理

- サービスが存在しない場合  
  → 警告を出すが処理は継続  
- systemctl stop が失敗した場合  
  → エラーを表示しつつ次のサービスへ進む  
- systemd 側に NVR 関連サービスが 1 つも存在しない場合  
  → 警告を出して終了  

---

# 7. 備考

- 本仕様は **cameras.yaml と systemd の状態がズレていても安全に停止できる**  
- テスト用ユニットや一時的なサービスも自動的に検出される  
- NVR 全体の安全な停止を保証するための重要なコンポーネント  
- start_nvr.sh とは独立して動作する  

---

# End of Document
