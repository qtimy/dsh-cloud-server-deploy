(() => {
  'use strict'

  const loader = window.__ModuleLoader__
  if (!loader || typeof loader.create !== 'function' || loader.__dshPublicSettingsWrapped) return
  loader.__dshPublicSettingsWrapped = true

  const originalCreate = loader.create
  loader.create = function (...args) {
    const modules = originalCreate.apply(this, args)
    const originalLoad = this.load

    this.load = function (registration) {
      if (
        registration?.id !== '@deepseek-ai/dsh-client-connection' ||
        typeof registration.factory !== 'function'
      ) {
        return originalLoad.call(this, registration)
      }

      const originalFactory = registration.factory
      return originalLoad.call(this, {
        ...registration,
        factory(require) {
          const face = originalFactory(require)
          if (!face || typeof face.apply !== 'function') return face

          const originalApply = face.apply
          face.apply = function (ctx, ...applyArgs) {
            const edgeContext = new Proxy(ctx, {
              get(target, property, receiver) {
                if (property !== 'provide') return Reflect.get(target, property, receiver)
                return (name, value) => {
                  if (name === 'connection' && value && typeof value === 'object') {
                    value.isLoopback = true
                  }
                  return target.provide(name, value)
                }
              },
            })
            return originalApply.call(this, edgeContext, ...applyArgs)
          }
          return face
        },
      })
    }
    return modules
  }
})()
