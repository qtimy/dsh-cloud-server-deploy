[Unit]
Description=Auto-restart dsh-web after a plugin install/remove
After=network-online.target dsh-web.service
Wants=dsh-web.service

[Service]
Type=simple
User=__DSH_USER__
Group=__DSH_USER__
ExecStart=/bin/bash __DEPLOY_DIR__/scripts/dsh-autorestart.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
