# setup_nvr.sh Specification (Complete Edition)
NVR System — Systemd Unit Generator & Service Orchestrator

このドキュメントは、NVR の systemd ユニット生成と構成管理を担当する  
`scripts/setup_nvr.sh` の正式仕様をまとめたもの。

setup_nvr.sh は cameras.yaml を読み取り、  
カメラごとに systemd ユニットを自動生成し、  
NVR 全体のサービス構成を正規化する。

**本スクリプトは初回セットアップおよび再構成専用であり、  
起動処理は start_nvr.sh が担当する。**

---

# 1. 役割概要

setup_nvr.sh は以下を行う：

- cameras.yaml を読み込む  
- YAML に存在するカメラ名一覧を取得  
- systemd に存在する NVR 関連ユニットを列挙  
- **YAML に無いカメラのユニットを削除**  
- **YAML に無いカメラの TMP_DIR を削除**  
- enabled=false のカメラを disable＋ユニット削除  
- enabled=true のカメラについて ffmpeg_nvr_<CAM>.service を生成  
- motion_event_handler@ / opencv_motion@ を enable  
- systemctl daemon-reload  
- 起動は start_nvr.sh に委譲  

setup_nvr.sh は NVR の「systemd 構成の唯一の正規化ポイント」である。

---

# 2. 入力

```
setup_nvr.sh
```

引数なしで実行する。

---

# 3. 読み取る設定ファイル

```
/etc/nvr/cameras.yaml
```

読み取る項目：

- cameras[].name  
- cameras[].enabled  
- cameras[].segment_time  
- cameras[].ip  
- cameras[].rtsp_port  
- cameras[].daynight_mode  
- common.save_dir_base  
- common.motion_tmp_base  
- その他、ffmpeg / opencv_motion / motion_event_handler が必要とする値  

---

# 4. systemd ユニット生成方式

## 4.1 使用するユニット

### ffmpeg 録画ユニット（テンプレート）

```
/etc/systemd/system/ffmpeg_nvr@.service
```

### motion_event_handler ユニット（テンプレート）

```
/etc/systemd/system/motion_event_handler@.service
```

### opencv_motion ユニット（テンプレート）

```
/etc/systemd/system/motion_detector@.service
```
(※旧: opencv_motion@.service. 現在は motion_detector@.service を使用)

---

# 5. カメラごとの設定反映 (override.conf)

setup_nvr.sh は cameras.yaml を読み取り、  
**テンプレートユニットへの override ファイルを生成する**ことで各カメラの設定を反映する。

生成先：
```
/etc/systemd/system/ffmpeg_nvr@<CAM>.service.d/override.conf
```

例：
```ini
[Service]
Environment="SEGMENT_TIME=300"
```

この override.conf は、テンプレート内のプレースホルダーや環境変数を上書きするために使用される。
テンプレートの `ExecStart` は共通化されており、カメラごとの違いは環境変数や引数 (`%i`) で吸収する設計となっている。

---

# 6. 個別ユニット生成の廃止

以前は `ffmpeg_nvr_<CAM>.service` という個別ファイルを生成していたが、
現在は **systemd テンプレート (`ffmpeg_nvr@.service`) + `override.conf`** 方式に統一された。

理由：
- ユニットファイルの管理を簡素化するため
- 共通部分の修正を容易にするため

---

# 7. motion_event_handler@.service の扱い

motion_event_handler はテンプレートユニットをそのまま使用する。
カメラごとの設定（タイムアウト等）はスクリプト実行時に `cameras.yaml` から直接読み込むため、systemd 側の override は不要である。

---

# 8. motion_detector@.service の扱い

motion_detector (旧 opencv_motion) もテンプレートユニットを使用する。
動体検知パラメータは `cameras.yaml` から読み込まれる。

---

# 9. 不要ユニットの削除（YAML に無いカメラ）

setup_nvr.sh は systemd に登録されている NVR 関連ユニットを走査し、  
**cameras.yaml に存在しないカメラのユニット設定を削除する。**

対象：
- `ffmpeg_nvr@<CAM>.service.d/` (override ディレクトリ)
- `motion_tmp_base/<CAM>/` (一時ディレクトリ)

削除内容：
- systemctl stop
- systemctl disable
- override ディレクトリの削除
- TMP_DIR の削除

---

# 10. enabled=false のカメラの扱い

enabled=false のカメラは以下を行う：
- systemctl stop
- systemctl disable
- override ディレクトリを削除
- TMP_DIR を削除

これにより、start_nvr.sh が誤って起動することを防ぐ。

---

# 11. setup_nvr.sh の処理フロー（完全版）

```
1. cameras.yaml を読み込む
2. YAML に存在するカメラ名一覧を取得
3. systemd に存在する NVR 関連ユニットを列挙
4. YAML に無いカメラのユニット設定/TMP_DIR を削除
5. enabled=false のカメラのユニット設定/TMP_DIR を削除
6. enabled=true のカメラについて override.conf を生成
7. systemctl daemon-reload
8. 各ユニットを enable
   - ffmpeg_nvr@<CAM>
   - motion_detector@<CAM>
   - motion_event_handler@<CAM>
9. 起動は start_nvr.sh に委譲（setup_nvr.sh は起動しない）
```

---

# 12. 出力

- systemd ユニットファイル  
- 不要ユニットの削除ログ  
- 不要 TMP_DIR の削除ログ  
- systemd の enable 状態  

---

# 13. 備考

- cameras.yaml の enabled=false のカメラはスキップ  
- 生成されたユニットは手動編集しない（setup_nvr.sh が上書きする）  
- cameras.yaml を変更したら setup_nvr.sh を再実行する  
- 起動は start_nvr.sh を使用する（責務分離）  

---

# End of Document
