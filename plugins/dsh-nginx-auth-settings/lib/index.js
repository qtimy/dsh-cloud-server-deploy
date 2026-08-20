export const name = 'dsh-nginx-auth-settings'
export const inject = []
export function apply(ctx) {
  // Entry-level inject gates are shared by the host and browser trees. The
  // host half has no trust decision to make, but it must release the official
  // no-op host settings entry so profile boot can complete.
  ctx.provide('nginxAuthSettingsReady', { authenticated: false, platform: 'host' })
}
