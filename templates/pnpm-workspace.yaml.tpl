# DSH 部署模板 —— profile web 的 pnpm-workspace.yaml
packages:
  - .

nodeLinker: hoisted
autoInstallPeers: false
allowBuilds:
  cloudflared: true
  cpu-features: true
  ssh2: true
