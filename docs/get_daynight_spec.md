# get_daynight.sh Specification
NVR System — Day/Night Mode Determination

このドキュメントは、NVR の昼夜判定を担当する
`/usr/local/bin/nvr/get_daynight.sh` の正式仕様をまとめたもの。

get_daynight.sh は、カメラごとの設定に基づき
「現在は昼か夜か」を判定し、
camera_daynight_apply.sh に渡すための結果を返す。

---

# 1. 役割概要

get_daynight.sh は以下のいずれかの方式で昼夜を判定する：

1. **brightness（輝度）方式**
   - OpenCV が出力する yavg.txt の YAVG を参照
   - 一定閾値より明るければ「day」、暗ければ「night」

2. **time（時刻）方式**
   - cameras.yaml に設定された時刻帯で判定
   - 例：day_start=06:00、night_start=18:00

3. **sunrise（日の出・日の入り）方式**
   - 緯度・経度から日の出/日の入りを計算
   - sunwait を使用

---

# 2. 入力

```
get_daynight.sh <camera_name>
```

例：

```
get_daynight.sh frontdoor
```

---

# 3. 読み取る設定ファイル

```
/etc/nvr/cameras.yaml
```

読み取る項目：

- common.daynight_mode  
  - brightness / time / sunrise
- common.brightness_threshold（brightness モード）
- common.day_start（time モード）
- common.night_start（time モード）
- common.latitude（sunrise モード）
- common.longitude（sunrise モード）
- common.motion_tmp_base（brightness モードで参照）

---

# 4. brightness（輝度）方式

## 4.1 参照するファイル

```
/dev/shm/motion_tmp/<CAM>/yavg.txt
```

OpenCV が毎ループ更新する平均輝度値（0〜255）。

例（内容）：

```
123.45
```

## 4.2 判定ロジック

1. yavg.txt を読み取る  
2. brightness_threshold と比較  
3. 結果を出力

例：

```
if YAVG >= threshold → day
else → night
```

## 4.3 フォールバック動作

brightness モードは通常、OpenCV が生成する `yavg.txt` を参照して 昼夜を判定するが、以下の場合は sunrise モードにフォールバックする：
- `yavg.txt` が存在しない（初回起動など）
- `yavg.txt` が空または読み取り不能

### フォールバックの理由

- 初回起動時でも「時刻＋緯度経度」に基づく妥当な判定が可能
- unknown を返すよりも、粗くても利用可能な情報を優先できる
- brightness → sunrise → time の三段階フォールバックにより 過渡状態の揺れを吸収し、安定した判定が行える

### brightness モードの判定フロー
1. `yavg.txt` が存在し、値が取得できる → brightness 判定（day/night）
2. `yavg.txt` が無い／空 → sunrise モードにフォールバック
3. sunrise モードが利用不可（sunwait 非搭載） → time モードにフォールバック
4. それでも判定不能 → `unknown`

---

# 5. time（時刻）方式

## 5.1 設定例

```yaml
daynight:
  mode: time
  day_start: "06:00"
  night_start: "18:00"
```

## 5.2 判定ロジック

- 現在時刻が day_start〜night_start の間 → day  
- それ以外 → night  

※ 24 時間をまたぐ場合も正しく処理する。

---

# 6. sunrise（日の出・日の入り）方式

設定例：

```yaml
daynight:
  mode: sunrise
  latitude: 35.423
  longitude: 136.863
```

sunwait を使用して日の出/日の入りを判定する。

例：

```
sunwait poll up LAT LON → day
sunwait poll down LAT LON → night
```

---

# 7. 出力

標準出力に以下のいずれかを返す：

```
day
night
unknown
```

camera_daynight_apply.sh がこの結果を受け取り、
ESP32-CAM の設定（露出・ゲイン・フレームレートなど）を切り替える。

---

# 8. エラー処理

- yavg.txt が存在しない  
  → brightness モードでは `"unknown"` を返す  
- YAML の設定が不正  
  → `"unknown"`  
- 引数なし  
  → エラー終了  
- sunwait が利用できない  
  → sunrise モードでは `"unknown"`

---

# 9. 備考

- brightness モードはリアルタイム性が高く、屋外カメラに最適  
- time モードは安定性が高く、室内カメラに向く  
- sunrise モードは季節変動に強い  
- 判定結果は camera_daynight_apply.sh によって即時反映される  

---

# End of Document
