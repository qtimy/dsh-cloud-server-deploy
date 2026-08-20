import { describe, expect, it } from 'vitest'
import {
  buildDeploymentCatalog,
  childModelFit,
  parseChildTier,
  rankChildModels,
  summarizeCatalog,
} from '../src/deployment-catalog.js'

describe('deployment provider/model catalog', () => {
  const providers = [
    { id: 'opencode-go', name: 'OpenCode Go' },
    { id: 'deepseek-official', name: 'DeepSeek' },
    { id: 'my-gateway', name: 'Private gateway' },
  ]
  const models = {
    'opencode-go': [
      { provider: 'opencode-go', id: 'deepseek-v4-flash', name: 'DeepSeek V4 Flash' },
      { provider: 'opencode-go', id: 'kimi-k2.7-code', name: 'Kimi Code' },
    ],
    'deepseek-official': [
      { provider: 'deepseek-official', id: 'deepseek-v4-pro', name: 'DeepSeek V4 Pro' },
    ],
    'my-gateway': [
      { provider: 'my-gateway', id: 'claude-fable-5', name: 'Claude Fable 5' },
      { provider: 'my-gateway', id: 'wan-image', name: 'Wan Image' },
    ],
  }

  const directory = [
    { provider: 'opencode-go', displayName: 'OpenCode Go', declared: false },
    { provider: 'deepseek-official', displayName: 'DeepSeek' },
    { provider: 'anthropic', displayName: 'Anthropic', declared: false },
    { provider: 'my-gateway', displayName: 'Private gateway', declared: true },
  ]

  it('classifies every custom provider as PAYG', () => {
    const catalog = buildDeploymentCatalog(providers, directory, models)
    expect(catalog.providers.find((p) => p.id === 'opencode-go')).toMatchObject({ active: true, billing: 'subscription', custom: false })
    expect(catalog.providers.find((p) => p.id === 'deepseek-official')).toMatchObject({ active: true, billing: 'payg', custom: false })
    expect(catalog.providers.find((p) => p.id === 'my-gateway')).toMatchObject({ active: true, billing: 'payg', custom: true })
    expect(summarizeCatalog(catalog)).toContain('my-gateway [PAYG custom; active]')
  })

  it('custom status overrides a subscription-looking provider id', () => {
    const catalog = buildDeploymentCatalog(
      [{ id: 'opencode-go' }],
      [{ provider: 'opencode-go', declared: true }],
      { 'opencode-go': models['opencode-go'] },
    )
    expect(catalog.providers[0]).toMatchObject({ custom: true, billing: 'payg' })
  })

  it('includes dormant directory providers but never routes to them', () => {
    const catalog = buildDeploymentCatalog(providers, directory, {
      ...models,
      anthropic: [{ provider: 'anthropic', id: 'claude-opus-4', name: 'Claude Opus 4' }],
    })
    expect(catalog.providers.find((p) => p.id === 'anthropic')).toMatchObject({ active: false, custom: false, models: [] })
    expect(summarizeCatalog(catalog)).toContain('anthropic [PAYG built-in; dormant]')
    expect(rankChildModels('heavy', catalog).some((candidate) => candidate.provider === 'anthropic')).toBe(false)
  })

  it('prefers subscription within the same capability band', () => {
    const catalog = buildDeploymentCatalog(providers, directory, models)
    const ranked = rankChildModels('fast', catalog)
    expect(ranked[0]).toMatchObject({ provider: 'opencode-go', model: 'deepseek-v4-flash', billing: 'subscription' })
  })

  it('lets capability outrank billing for heavy work and excludes response-only models', () => {
    const catalog = buildDeploymentCatalog(providers, directory, models)
    const ranked = rankChildModels('heavy', catalog)
    expect(ranked[0]).toMatchObject({ provider: 'my-gateway', model: 'claude-fable-5', billing: 'payg', custom: true })
    expect(ranked.some((candidate) => candidate.model === 'wan-image')).toBe(false)
    expect(childModelFit('heavy', 'deepseek-v4-flash')).toBeGreaterThan(childModelFit('heavy', 'claude-fable-5'))
  })

  it('parses all six child tiers tolerantly', () => {
    expect(parseChildTier('{"tier":"code"}')).toBe('code')
    expect(parseChildTier('SMART')).toBe('smart')
    expect(parseChildTier('unknown')).toBeNull()
  })
})
