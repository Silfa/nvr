[Unit]
Description=NVR Web Interface
After=network.target

[Service]
User={{NVR_USER}}
Group={{NVR_GROUP}}
WorkingDirectory={{NVR_BASE_DIR}}/web/backend
Environment="PATH={{VENV_DIR}}/bin:/usr/local/bin:/usr/bin:/bin"
Environment="NVR_CONFIG_DIR={{ETC_NVR_DIR}}"
Environment="NVR_BASE_DIR={{NVR_BASE_DIR}}"
Environment="PYTHONPATH={{NVR_BASE_DIR}}"

ExecStart={{VENV_DIR}}/bin/python3 run_server.py

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
