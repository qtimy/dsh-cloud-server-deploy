globalThis.window = {
  __ModuleLoader__: {
    load(definition) {
      globalThis.__pluginDefinition = definition
    },
  },
}
globalThis.location = { protocol: 'https:' }
globalThis.fetch = async () => ({
  ok: true,
  json: async () => ({ authenticated: true }),
})

await import('../plugins/dsh-nginx-auth-settings/lib/client.js')
const plugin = globalThis.__pluginDefinition.factory(() => {})
const connection = { isLoopback: false }
await plugin.apply({
  get(name) {
    return name === 'connection' ? connection : undefined
  },
})

if (!connection.isLoopback) {
  throw new Error('authenticated edge did not enable the host settings controller')
}
console.log('authenticated settings client simulation passed')
