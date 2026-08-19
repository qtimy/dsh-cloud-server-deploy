# DSH 部署模板 —— profile web 的 pnpm-workspace.yaml
packages:
  - .

nodeLinker: hoisted
autoInstallPeers: false
allowBuilds:
  cloudflared: true
  cpu-features: true
  ssh2: true
minimumReleaseAgeExclude:
  - '@linxin666/dsh-client-ui-aionui-panel@${WEB_UI_ALL_VERSION}'
  - '@linxin666/dsh-client-ui-git-graph@${WEB_UI_ALL_VERSION}'
  - '@linxin666/dsh-client-ui-skin-center@${WEB_UI_ALL_VERSION}'
  - '@linxin666/dsh-client-ui-task-board@${WEB_UI_ALL_VERSION}'
  - '@linxin666/dsh-client-ui-web-ui-settings@${WEB_UI_ALL_VERSION}'
  - '@linxin666/dsh-live-stats@${WEB_UI_ALL_VERSION}'
  - '@linxin666/dsh-pet@${WEB_UI_ALL_VERSION}'
  - '@linxin666/dsh-remote-web-ui@${WEB_UI_ALL_VERSION}'
  - '@linxin666/dsh-skins@${WEB_UI_ALL_VERSION}'
  - '@linxin666/dsh-ssh@${WEB_UI_ALL_VERSION}'
  - '@linxin666/dsh-web-ui-all@${WEB_UI_ALL_VERSION}'
