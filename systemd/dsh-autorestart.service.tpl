[Unit]
Description=Auto-restart dsh-web after a plugin install/remove
After=network-online.target dsh-web.service
Wants=dsh-web.service

[Service]
Type=simple
User=root
Group=root
Environment=DSH_HOME=/home/__DSH_USER__/.dsh
ExecStart=/bin/bash __DEPLOY_DIR__/dsh-autorestart.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
