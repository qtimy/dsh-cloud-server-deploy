[Unit]
Description=DeepSeek Harness Web (DSH)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=__DSH_USER__
Group=__DSH_USER__
EnvironmentFile=/etc/dsh-web.env
WorkingDirectory=/home/__DSH_USER__
ExecStart=dsh web --no-open --port __DSH_PORT__ --trusted-host ${TRUSTED_HOST}
Restart=on-failure
RestartSec=5
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
