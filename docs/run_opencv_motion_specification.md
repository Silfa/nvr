# run_opencv_motion.sh Specification  
NVR System — OpenCV Motion Detector Launcher

本スクリプトは systemd（`opencv_motion@.service`）から呼び出され、  
指定されたカメラ名に対して OpenCV 動体検知プロセス  
`opencv_motion.py` を起動するためのランチャーである。

本スクリプトは **OpenCV をシステム Python ではなく  
専用の仮想環境（venv）上で実行することを前提とする。**

---

# 1. 役割概要

run_opencv_motion.sh は以下を行う：

1. systemd テンプレートユニットから渡されたカメラ名（%i）を受け取る  
2. **venv を activate し、OpenCV 実行環境を構築する**  
3. cameras.yaml を読み取り、TMP_DIR を作成  
4. opencv_motion.py を exec で起動（systemd Restart と整合）  
5. ログは systemd journal に出力される  

本スクリプトは OpenCV の実行環境を整えるだけであり、  
動体検知ロジックは opencv_motion.py が担当する。

---

# 2. 実行環境（venv 前提）

OpenCV / numpy / pyyaml などの依存ライブラリは  
以下の専用仮想環境にインストールされていることを前提とする：

```
/usr/local/nvr-venv/
```

systemd から直接 Python を呼ぶのではなく、  
本スクリプト内で以下を実行して環境を整える：

```
source /usr/local/nvr-venv/bin/activate
```

これにより：

- OS アップデートの影響を受けない  
- OpenCV のバージョンを固定できる  
- systemd からの起動でも安定した環境が保証される  

---

# 3. 入力

```
run_opencv_motion.sh <camera_name>
```

例：

```
run_opencv_motion.sh frontdoor
```

systemd の `%i` がそのまま渡される。

---

# 4. 読み取る設定ファイル

```
/etc/nvr/cameras.yaml
```

読み取る項目：

- common.motion_tmp_base  

OpenCV の閾値設定は opencv_motion.py 側で読み取る。

---

# 5. TMP_DIR の作成

```
<common.motion_tmp_base>/<CAM>/
```

例：

```
/dev/shm/motion_tmp/frontdoor/
```

存在しない場合は自動作成する。

---

# 6. 起動するスクリプト

```
/usr/local/bin/nvr/opencv_motion.py <CAM>
```

exec を使用してシェルを置き換えることで、  
systemd の Restart=always と整合する。

---

# 7. エラー処理

- venv の activate に失敗した場合 → エラーを出して終了  
- cameras.yaml が読めない場合 → エラー  
- TMP_DIR 作成失敗 → エラー  
- opencv_motion.py の例外は systemd が再起動を担当  

---

# 8. systemd との連携

```
opencv_motion@<CAM>.service
```

- ffmpeg_nvr_<CAM>.service に依存  
- motion_event_handler@<CAM>.service と並列動作  
- Restart=always により自動復帰  

---

# End of Document
