let registered
const loader = {
  create() {
    this.load = (registration) => {
      registered = registration
    }
    return { version: 'client' }
  },
  load() {},
}
globalThis.window = { __ModuleLoader__: loader }

await import('../nginx/dsh-public-settings-bootstrap.js')
loader.create({})
loader.load({
  id: '@deepseek-ai/dsh-client-connection',
  factory() {
    return {
      inject: [],
      apply(ctx) {
        ctx.provide('connection', { isLoopback: false })
      },
    }
  },
})

let connection
const face = registered.factory(() => {})
face.apply({
  provide(name, value) {
    if (name === 'connection') connection = value
  },
})

if (connection?.isLoopback !== true) {
  throw new Error('authenticated edge did not adapt connection before publication')
}
console.log('public settings bootstrap simulation passed')
