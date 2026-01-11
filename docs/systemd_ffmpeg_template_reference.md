# ffmpeg_nvr@.service — Reference Template (Not Used in Production)

このドキュメントは、NVR の理解を深めるために  
「もし systemd テンプレートで ffmpeg 録画サービスを作るならどうなるか」  
を示した参考用テンプレートである。

実際の NVR では、systemd テンプレートは **使用しない**。  
理由は systemd が `%i` 以外の変数展開をサポートせず、  
カメラ固有の設定（IP、rtsp_port、segment_time など）を扱えないため。

---

# 1. 参考用テンプレート（実際には使用しない）

```
[Unit]
Description=NVR FFmpeg Recorder (%i)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 昼夜設定の適用（本来は %i しか渡せない）
ExecStartPre=/usr/local/bin/nvr/camera_daynight_apply.sh %i

# ffmpeg 実行（本来は IP や rtsp_port を systemd では扱えない）
ExecStart=/usr/local/bin/nvr/run_ffmpeg.sh %i

# カメラ固有の segment_time は systemd では扱えないため、
# setup_nvr.sh が生成時に埋め込む必要がある。
# 例: RuntimeMaxSec=300
RuntimeMaxSec=__SEGMENT_TIME__

Restart=always
RestartSec=5
KillMode=process
TimeoutStopSec=1

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

---

# 2. なぜ systemd テンプレートを採用しないのか

systemd テンプレート（`foo@.service`）は `%i` しか展開できないため、  
以下のようなカメラ固有設定を扱うことができない：

- IP アドレス  
- RTSP ポート  
- segment_time  
- motion_filter  
- day/night 設定  
- 保存先ディレクトリ  
- brightness 判定の有無  

NVR のように **カメラごとに設定が異なるシステム**では、  
systemd テンプレートは根本的に不向きである。

---

# 3. 実際の NVR で採用している方式

NVR では setup_nvr.sh が cameras.yaml を読み取り、  
カメラごとに **個別のユニットファイルを生成**する方式を採用している。

メリット：

- カメラ固有の設定をすべて埋め込める  
- YAML の変更に応じて systemd を自動再構成できる  
- カメラ追加・削除が完全自動化  
- systemd の制約に縛られない柔軟な設計  

---

# 4. まとめ

このテンプレートは **理解のための参考資料**であり、  
実際の NVR では使用しない。

NVR の本番運用では、  
setup_nvr.sh による **個別ユニット生成方式が最適解**である。

---

# End of Document
