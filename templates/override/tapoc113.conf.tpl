[Service]
# RTSP カメラ用の前処理が必要ならここに書く
# ExecStartPre={{NVR_CORE_DIR}}/rtsp/onvif_setup.sh %i
Environment="LIBVA_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/dri"
