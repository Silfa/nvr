[Unit]
StartLimitIntervalSec=0

[Service]
#Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="LIBVA_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/dri"
ExecStartPre={{NVR_CORE_DIR}}/esp32cam/camera_daynight_apply.sh %i
RuntimeMaxSec={{SEGMENT_TIME}}
