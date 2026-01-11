# send_motion_alert.sh Specification  
NVR System — Motion Event Notification Sender

このドキュメントは、動体検知イベント発生時に通知を送信する  
`/usr/local/bin/nvr/send_motion_alert.sh` の正式仕様をまとめたもの。

send_motion_alert.sh は motion_event_handler.sh によって  
イベントが確定したタイミングで呼び出され、  
メールや Webhook などの外部サービスへ通知を送信する。

---

# 1. 役割概要

send_motion_alert.sh は以下を行う：

- イベントディレクトリを受け取り、event.json を読み取る  
- カメラ名・開始時刻・終了時刻・フレーム数などを抽出  
- 通知メッセージを生成  
- 設定された通知手段（メール / Webhook）へ送信  

通知は「イベント終了後」に行われるため、  
誤検知や短時間のノイズによる通知スパムを防止できる。

---

# 2. 入力

```
send_motion_alert.sh <camera_name> <event_dir>
```

例：

```
send_motion_alert.sh frontdoor /var/nvr/events/frontdoor/20250101_120305
```

---

# 3. 読み取る設定ファイル

```
/etc/nvr/cameras.yaml
```

読み取る項目：

- cameras[].alert.enabled  
- cameras[].alert.method（email / webhook）  
- cameras[].alert.to（メールアドレス）  
- cameras[].alert.webhook_url  
- common.event_dir_base  

---

# 4. event.json の読み取り

イベントディレクトリ内の event.json を読み取る：

```json
{
  "camera": "frontdoor",
  "event_id": "20250101_120305",
  "start_time": "2025-01-01T12:03:05+09:00",
  "end_time": "2025-01-01T12:03:12+09:00",
  "num_frames": 7
}
```

抽出する項目：

- camera  
- event_id  
- start_time  
- end_time  
- num_frames  

---

# 5. 通知メッセージの生成

例：

```
[Motion Detected] frontdoor
Event ID: 20250101_120305
Start: 2025-01-01 12:03:05
End:   2025-01-01 12:03:12
Frames: 7
```

---

# 6. 通知方式

## 6.1 メール通知（method: email）

sendmail または mail コマンドを使用：

```
echo "$MESSAGE" | mail -s "[NVR] Motion detected on $CAM" "$TO"
```

特徴：

- シンプルで依存が少ない  
- 家庭内サーバーでも安定して動作  

---

## 6.2 Webhook 通知（method: webhook）

curl を使用：

```
curl -X POST -H "Content-Type: application/json" \
     -d "{\"text\":\"$MESSAGE\"}" \
     "$WEBHOOK_URL"
```

用途：

- Slack  
- Discord  
- LINE Notify  
- Home Assistant  
- 任意の Webhook サービス  

---

# 7. エラー処理

- event.json が存在しない場合 → エラー終了  
- alert.enabled=false → 何もせず終了  
- メール送信失敗 → ログ出力  
- Webhook 失敗 → ログ出力  
- スクリプト自体は成功終了（NVR の動作を止めない）  

---

# 8. 備考

- 通知はイベント終了後に行われるため、誤検知の連続通知を防げる  
- event.json の情報は UI 側でのタイムライン表示にも利用可能  
- 通知方式はカメラごとに独立して設定できる  

---

# End of Document
