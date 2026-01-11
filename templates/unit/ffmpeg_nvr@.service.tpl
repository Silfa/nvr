[Unit]
Description=NVR FFmpeg Recorder for %i
After=network-online.target
Wants=network-online.target

[Service]
User={{NVR_USER}}
Group={{NVR_GROUP}}
UMask=000
Type=simple
ExecStart={{NVR_CORE_DIR}}/ffmpeg_nvr.sh %i
Restart=always
RestartSec=5
KillMode=process
TimeoutStopSec=1

[Install]
WantedBy=multi-user.target
