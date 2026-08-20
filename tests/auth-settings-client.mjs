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
let officialApplyCalls = 0
const plugin = globalThis.__pluginDefinition.factory((id) => {
  if (id !== '@deepseek-ai/dsh-client-ui-settings') {
    throw new Error(`unexpected client dependency: ${id}`)
  }
  return {
    inject: ['connection', 'remote'],
    apply(ctx) {
      officialApplyCalls += 1
      const connection = ctx.get('connection')
      if (!connection.isLoopback) {
        throw new Error('official settings client started before authenticated trust')
      }
    },
  }
})
const connection = { isLoopback: false }
await plugin.apply({
  get(name) {
    return name === 'connection' ? connection : undefined
  },
})

if (!connection.isLoopback) {
  throw new Error('authenticated edge did not enable the host settings controller')
}
if (officialApplyCalls !== 1) {
  throw new Error(`official settings client apply count was ${officialApplyCalls}`)
}
console.log('authenticated settings client simulation passed')
