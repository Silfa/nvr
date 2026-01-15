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
- enabled=true のカメラについて override.conf を生成  
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

## 4.1 生成されるユニット

### ffmpeg 録画ユニット（テンプレート）

```
/etc/systemd/system/ffmpeg_nvr@.service
```

### ffmpeg 録画ユニット用オーバーライド（カメラごと・個別生成）

```
/etc/systemd/system/ffmpeg_nvr@.service.d/override.conf
```

### motion_event_handler ユニット（テンプレート）

```
/etc/systemd/system/motion_event_handler@.service
```

### motion_detector ユニット（テンプレート）

```
/etc/systemd/system/motion_detector@.service
```

---

# 5. ffmpeg_nvr_<CAM>.service の生成仕様

setup_nvr.sh は cameras.yaml を読み取り、  
**カメラ固有の値を埋め込んだ systemd ユニットを生成する。**

例：

```
[Service]
ExecStartPre=/usr/local/bin/nvr/camera_daynight_apply.sh <CAM>
RuntimeMaxSec=<SEGMENT_TIME>
```

埋め込まれる値：

- `<SEGMENT_TIME>`（録画セグメント時間）


# 6. なぜテンプレート＋オーバーライド方式を採用するのか

`ffmpeg_nvr@.service` という共通のテンプレートユニットを使い、  
カメラごとの可変設定（録画時間など）だけを `override.conf` に分離することで、  
基本ロジックの変更が全カメラに一括で適用できるようになります。

これにより、カメラごとに `.service` ファイルを丸ごと管理する必要がなくなり、  
メンテナンス性が大幅に向上します。

カメラ名（`%i`）以外の固有設定は、各スクリプトが YAML ファイルから直接読み込むため、  
systemd 側で複雑な値を管理する必要はありません。


# 7. motion_event_handler@.service の扱い

motion_event_handler はテンプレートユニットを使用する。

理由：

- カメラ名以外の設定はスクリプト側で YAML から読み取る  
- systemd 側に複雑な設定を持たせる必要がない  


# 8. motion_detector@.service の扱い

motion_detector もテンプレートユニットを使用する。

理由：

- Python スクリプト側もカメラ名以外の設定を YAML から読み取る  


# 9. 不要ユニットの削除（YAML に無いカメラ）

setup_nvr.sh は systemd に登録されている NVR 関連ユニットを走査し、  
**cameras.yaml に存在しないカメラのユニットを削除する。**

対象：

- ffmpeg_nvr@<CAM>.service
- motion_detector@<CAM>.service
- motion_event_handler@<CAM>.service

削除されるケース：

- カメラを撤去した  
- cameras.yaml から削除した  
- カメラ名を変更した  
- 設置場所変更に伴い名称変更した  

削除内容：

- systemctl stop / disable
- TMP_DIR の削除


# 10. enabled=false のカメラの扱い

enabled=false のカメラは以下を行う：

- systemctl stop / disable
- TMP_DIR を削除

これにより、start_nvr.sh が誤って起動することを防ぐ。


# 11. setup_nvr.sh の処理フロー（完全版）

```
1. cameras.yaml を読み込む
2. YAML に存在するカメラ名一覧を取得
3. systemd に存在する NVR 関連ユニットを列挙
4. YAML に無いカメラのユニット/TMP_DIR を削除
5. enabled=false のカメラのユニット/TMP_DIR を削除
6. enabled=true のカメラについて override.conf を生成
7. systemctl daemon-reload
8. motion_event_handler@<CAM> を enable
9. motion_detector@<CAM> を enable
10. ffmpeg_nvr@<CAM>.service を enable
11. 起動は start_nvr.sh に委譲（setup_nvr.sh は起動しない）
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
