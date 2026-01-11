[Unit]
Description=NVR Motion Event Handler for %i

[Service]
User={{NVR_USER}}
Group={{NVR_GROUP}}
UMask=000
Type=simple
ExecStart={{NVR_CORE_DIR}}/motion_event_handler.sh %i
Restart=always
RestartSec=1
RuntimeMaxSec=86400
KillMode=process
TimeoutStopSec=1

[Install]
WantedBy=multi-user.target
