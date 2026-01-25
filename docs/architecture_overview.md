# NVR Architecture Overview

このドキュメントは、NVR システム全体の構造と、  
systemd・スクリプト・生成ファイルの関係を視覚的に示すものです。

NVR は以下の 3 層で構成されています：

- **systemd services**  
  カメラごとのプロセスを管理し、起動・停止・再起動を統括する

- **core/**  
  実際の処理ロジック（ffmpeg、OpenCV、イベント処理など）

- **generated files**  
  各スクリプトが生成する最新画像・フラグ・イベント情報

---

## 📊 全体構造（Mermaid 図）

```mermaid
flowchart TD

    subgraph Systemd["systemd services"]
        FF[ffmpeg_nvr@CAM.service]
        MD[motion_detector@CAM.service]
        EH[motion_event_handler@CAM.service]
    end

    subgraph Core["core/"]
        FN[ffmpeg_nvr.sh]
        RMD[run_motion_detector.sh]
        MEH[motion_event_handler.sh]
        PY[motion_detector.py]
        GDN[get_daynight.sh]
        CDA[camera_daynight_apply.sh]
    end

    subgraph Files["Generated files"]
        LJ[latest.jpg]
        MF[motion.flag]
        YA[yavg.txt]
        EJ[event.json]
    end

    FF --> FN --> LJ
    MD --> RMD --> PY
    PY -.-> LJ
    PY --> MF
    PY --> YA

    EH --> MEH
    MEH --> MF
    MEH --> LJ
    MEH --> EJ

    CDA --> GDN
```

---

## 🧩 コンポーネント説明

### systemd services
| Service | 役割 |
|--------|------|
| `ffmpeg_nvr@CAM.service` | カメラ映像を取得し、最新画像 `latest.jpg` を生成 |
| `motion_detector@CAM.service` | OpenCV による動体検知。`motion.flag` と `yavg.txt` を生成 |
| `motion_event_handler@CAM.service` | 動体検知イベントを処理し、`event.json` を生成 |

---

### core/
| Script | 役割 |
|--------|------|
| `ffmpeg_nvr.sh` | ffmpeg ランナーを呼び出し最新画像を生成 |
| `run_motion_detector.sh` | OpenCV スクリプトを起動し動体検知を実行 |
| `motion_detector.py` | 動体検知ロジック本体 |
| `motion_event_handler.sh` | motion.flag を監視しイベントを JSON 化 |
| `camera_daynight_apply.sh` | 昼夜設定の適用 |
| `get_daynight.sh` | 昼夜判定ロジック |

---

### Generated files
| File | 内容 |
|------|------|
| `latest.jpg` | 最新のカメラ画像 |
| `motion.flag` | 動体検知の有無 |
| `yavg.txt` | 画像の輝度情報 |
| `event.json` | 動体検知イベントの詳細 |

---

## 🔄 データフロー概要

1. **ffmpeg** が最新画像を生成  
2. **OpenCV** が最新画像を解析し、動体検知フラグを生成  
3. **イベントハンドラ** がフラグを読み取り、イベント JSON を生成  
4. 必要に応じて昼夜判定スクリプトが設定を適用  

---

## 📝 備考

- cameras.yaml が **唯一のソース（source of truth）**  
- start_nvr.sh は cameras.yaml ベースで起動  
- stop_nvr.sh は systemd の状態ベースで停止  
- core/ は主要なロジックを含む  
- Mermaid 図は GitHub 上でそのまま表示可能
