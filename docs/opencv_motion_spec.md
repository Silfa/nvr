# OpenCV Motion Detection Script Specification  
NVR System — opencv_motion.py

このドキュメントは、ESP32‑CAM の latest.jpg を読み取り、  
OpenCV による動体検知を行い、motion_event_handler に対して  
「動体あり／なし」のトリガーを提供する  
`opencv_motion.py` の正式仕様をまとめたもの。

本スクリプトは **イベント管理を行わない**。  
イベントの開始・終了・JPEG 保存はすべて  
`motion_event_handler.sh` が担当する。

---

# 0. 実行環境

opencv_motion.py は、システム Python ではなく  
専用の仮想環境（venv）上で動作することを前提とする。

- venv 例：`/usr/local/nvr-venv/`  
- OpenCV / numpy / pyyaml などは venv にインストールする  
- systemd からは `run_opencv_motion.sh` を経由して起動し、  
  その中で venv を activate してから本スクリプトを実行する

本スクリプトが依存する Python ライブラリ：
- opencv-python-headless
- numpy
- pyyaml
これらは venv 内にインストールされていることを前提とする。
---

# 1. 役割概要

opencv_motion.py は以下を行う：

1. ffmpeg が生成する latest.jpg を監視  
2. OpenCV による動体検知（差分・輪郭抽出）  
3. 動体あり → motion.flag を作成  
4. 動体なし → motion.flag を削除  
5. YAVG（平均輝度）を計算し yavg.txt に保存  
6. RTSP には接続しない（ESP32‑CAM は単一接続制約のため）

---

# 2. 入力

```
opencv_motion.py <camera_name>
```

例：

```
opencv_motion.py frontdoor
```

---

# 3. 読み取る設定ファイル

```
/etc/nvr/cameras.yaml
```

読み取る項目：

- cameras[].motion.threshold  
- cameras[].motion.min_area  
- cameras[].motion.blur  
- cameras[].motion.debug（任意）  
- common.motion_tmp_base  

---

# 4. 入出力ファイル

TMP_DIR は cameras.yaml  の設定に従う：

---
<common.motion_tmp_base>/<CAM>/
---

## 4.1 入力（ffmpeg が生成）

```
<common.motion_tmp_base>/<CAM>/latest.jpg
```

## 4.2 出力（OpenCV が生成）

### ✔ 動体フラグ  
```
<common.motion_tmp_base>/<CAM>/motion.flag
```
- 動体あり → 作成  
- 動体なし → 削除  
- 内容は空でよい（存在がフラグ）

### ✔ 平均輝度（YAVG）  
```
<common.motion_tmp_base>/<CAM>/yavg.txt
```
- 0〜255 の整数値  
- get_daynight.sh の brightness モードで使用

---

# 5. 動体検知アルゴリズム

## 5.1 前処理
- latest.jpg を読み込み  
- グレースケール化  
- ガウシアンブラー（設定値 blur）  

## 5.2 差分
- 前フレームとの差分を計算  
- 閾値（threshold）で二値化  

## 5.3 輪郭抽出
- 輪郭を抽出  
- 面積が min_area 以上のものがあれば「動体あり」

## 5.4 動体判定
- 動体あり → motion.flag を作成  
- 動体なし → motion.flag を削除  

---

# 6. 平均輝度（YAVG）の計算

- グレースケール画像の平均値を算出  
- 整数に丸めて yavg.txt に保存  
- get_daynight.sh が参照する

---

# 7. 動作ループ

1. latest.jpg の mtime が更新されるまで待機  
2. 更新されたらフレームを読み込み  
3. 動体検知  
4. motion.flag の作成／削除  
5. YAVG の計算  
6. 次の更新を待つ

※ handler のループの方が高速なため、  
   OpenCV 側は 2fps 程度の更新で十分。

---

# 8. エラー処理

- latest.jpg が読めない場合 → スキップして次ループ  
- OpenCV 読み込みエラー → スキップ  
- motion.flag の作成／削除失敗 → ログ出力のみ  
- スクリプトは常に成功終了（常駐プロセス）

---

# 9. systemd との連携

```
opencv_motion@<CAM>.service
```

- ffmpeg_nvr@CAM.service より先に起動  
- motion_event_handler@CAM.service と並列動作  
- RTSP には接続しないため競合なし

---

# 10. 備考

- 記録用 JPEG は OpenCV が生成しない  
- 記録用 JPEG は motion_event_handler が latest.jpg を保存する  
- OpenCV は「動体あり／なし」の判定だけを担当  
- ESP32‑CAM の単一接続制約を完全に回避できる  

---

# End of Document
