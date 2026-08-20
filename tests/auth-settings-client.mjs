globalThis.window = {
  __ModuleLoader__: {
    load(definition) {
      globalThis.__pluginDefinition = definition
    },
  },
}
globalThis.location = { protocol: 'https:' }
globalThis.AbortSignal = { timeout: () => ({}) }
globalThis.fetch = async () => ({
  ok: true,
  json: async () => ({ authenticated: true }),
})

await import('../plugins/dsh-nginx-auth-settings/lib/client.js')
const plugin = globalThis.__pluginDefinition.factory((id) => {
  throw new Error(`trust plugin must not import another client module: ${id}`)
})
const connection = { isLoopback: false }
const provided = new Map()
await plugin.apply({
  get(name) {
    return name === 'connection' ? connection : undefined
  },
  provide(name, value) {
    provided.set(name, value)
  },
})

if (!connection.isLoopback) {
  throw new Error('authenticated edge did not enable the host settings controller')
}
if (provided.get('nginxAuthSettingsReady')?.authenticated !== true) {
  throw new Error('settings readiness gate was not provided after authentication')
}
console.log('authenticated settings client simulation passed')
