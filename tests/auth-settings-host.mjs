const provided = new Map()
const plugin = await import('../plugins/dsh-nginx-auth-settings/lib/index.js')

plugin.apply({
  provide(name, value) {
    provided.set(name, value)
  },
})

if (provided.get('nginxAuthSettingsReady')?.platform !== 'host') {
  throw new Error('host half did not release the shared settings readiness gate')
}
console.log('host settings readiness simulation passed')
