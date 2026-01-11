[Service]
#Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStartPre={{NVR_CORE_DIR}}/esp32cam/camera_daynight_apply.sh %i
RuntimeMaxSec={{SEGMENT_TIME}}
