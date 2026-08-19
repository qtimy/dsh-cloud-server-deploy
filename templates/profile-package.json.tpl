{
  "name": "dsh-profile-web",
  "private": true,
  "dsh": {
    "profile": {
      "bundles": [
        "@deepseek-ai/dsh-base",
        "@deepseek-ai/dsh-web-app",
        "@linxin666/dsh-web-ui-all"
      ]
    }
  },
  "pnpm": {
    "onlyBuiltDependencies": [
      "cloudflared",
      "cpu-features",
      "ssh2"
    ]
  },
  "dependencies": {
    "@linxin666/dsh-web-ui-all": "${WEB_UI_ALL_VERSION}"
  }
}