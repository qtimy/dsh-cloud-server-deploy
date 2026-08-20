import type { ModelRef } from './types.js'

/** Child-agent task classes retained from dsh-agent-orchestrator. */
export type ChildTier = 'tiny' | 'fast' | 'code' | 'smart' | 'heavy' | 'image'

export const CHILD_TIERS: readonly ChildTier[] = [
  'tiny',
  'fast',
  'code',
  'smart',
  'heavy',
  'image',
] as const

/** Billing classification used when ranking deployment routes. */
export type ProviderBilling = 'subscription' | 'payg'

export interface CatalogModel {
  provider: string
  id: string
  name: string
  inputModalities?: readonly string[]
}

export interface CatalogProvider {
  id: string
  name: string
  /** True only when DSH currently has a registered adapter for this route. */
  active: boolean
  /** True when the adapter directory says this route was declared by the user. */
  custom: boolean
  /** Custom providers are always pay-as-you-go, even if their id mimics a subscription route. */
  billing: ProviderBilling
  models: CatalogModel[]
}

export interface DeploymentCatalog {
  checkedAt: number
  providers: CatalogProvider[]
}

export interface ProviderInput {
  id: string
  name?: string
}

export interface ConfigurableProviderInput {
  provider: string
  displayName?: string
  /** True means the route was user-declared rather than shipped by the adapter. */
  declared?: boolean
}

export interface ModelInput {
  provider: string
  id: string
  name?: string
  inputModalities?: readonly string[]
}

/** Deployment-owned subscription routes; every other built-in route is PAYG. */
export const SUBSCRIPTION_PROVIDER_IDS = new Set([
  'opencode-go',
  'qwen-token-plan-cn',
])

/**
 * Build a detached snapshot from both DSH provider surfaces.
 *
 * The configurable directory includes every known provider, including dormant
 * routes. The adapter registry includes only routes that can be requested now.
 * Directory order is retained and any non-configurable live routes are appended.
 */
export function buildDeploymentCatalog(
  activeProviders: readonly ProviderInput[],
  configurableProviders: readonly ConfigurableProviderInput[],
  modelsByProvider: Readonly<Record<string, readonly ModelInput[]>>,
  checkedAt = Date.now(),
): DeploymentCatalog {
  const activeById = new Map(activeProviders.map((provider) => [provider.id, provider]))
  const directoryById = new Map(configurableProviders.map((entry) => [entry.provider, entry]))
  const providerIds = [
    ...directoryById.keys(),
    ...activeProviders.map((provider) => provider.id).filter((id) => !directoryById.has(id)),
  ]

  return {
    checkedAt,
    providers: providerIds.map((providerId) => {
      const directory = directoryById.get(providerId)
      const activeProvider = activeById.get(providerId)
      const active = activeProvider !== undefined
      const custom = directory?.declared === true
      return {
        id: providerId,
        name: directory?.displayName ?? activeProvider?.name ?? providerId,
        active,
        custom,
        billing: !custom && SUBSCRIPTION_PROVIDER_IDS.has(providerId) ? 'subscription' : 'payg',
        models: (active ? modelsByProvider[providerId] ?? [] : []).map((model) => ({
          provider: providerId,
          id: model.id,
          name: model.name ?? model.id,
          ...(model.inputModalities === undefined ? {} : { inputModalities: model.inputModalities }),
        })),
      }
    }),
  }
}

/** Tolerant child-judge parser. Invalid output falls back at the caller. */
export function parseChildTier(raw: string): ChildTier | null {
  const text = String(raw ?? '').trim().toLowerCase()
  const json = text.match(/\"tier\"\s*:\s*\"(tiny|fast|code|smart|heavy|image)\"/)
  if (json) return json[1] as ChildTier
  const bare = text.match(/\b(tiny|fast|code|smart|heavy|image)\b/)
  return bare ? bare[1] as ChildTier : null
}

const NON_TEXT_MODEL = /(?:^|[-_.])(image|vision|audio|tts|realtime|embedding|rerank)(?:$|[-_.])/i

/**
 * Task-fit score (lower is better). Billing is applied separately so a PAYG
 * model can still win when a high-capability task has no credible subscription
 * equivalent.
 */
export function childModelFit(tier: ChildTier, modelId: string, modelName = ''): number {
  const value = `${modelId} ${modelName}`.toLowerCase()
  if (NON_TEXT_MODEL.test(modelId) || NON_TEXT_MODEL.test(modelName)) return 10_000

  const has = (pattern: RegExp): boolean => pattern.test(value)
  switch (tier) {
    case 'tiny':
      if (has(/mini|max-m[23]|minimax|mimo|nano|lite|small/)) return 0
      if (has(/flash|turbo|fast/)) return 1
      if (has(/plus|glm|kimi/)) return 3
      if (has(/pro|max|claude|grok|opus/)) return 8
      return 5
    case 'fast':
      if (has(/flash|turbo|fast|lite|mini|mimo/)) return 0
      if (has(/plus|glm|kimi|qwen/)) return 2
      if (has(/pro|max|claude|grok|opus/)) return 6
      return 4
    case 'code':
      if (has(/code|coder|codex/)) return 0
      if (has(/kimi|glm|pro|qwen/)) return 2
      if (has(/flash|turbo|mini/)) return 5
      return 4
    case 'smart':
      if (has(/pro|max|claude|opus|fable|grok|kimi-k?3|gpt-?5/)) return 0
      if (has(/plus|glm|kimi|code|coder/)) return 2
      if (has(/flash|turbo|mini|lite/)) return 7
      return 4
    case 'heavy':
      if (has(/opus|fable|claude|gpt-?5|grok|kimi-k?3/)) return 0
      if (has(/pro|max|code|coder/)) return 2
      if (has(/flash|turbo|mini|lite/)) return 9
      return 5
    case 'image':
      // A DSH child is still a text agent. Give it a capable reasoning model;
      // it may call the deployment's image tool instead of being sent to an
      // image-only response model that the agent loop cannot consume.
      if (has(/pro|max|claude|opus|fable|grok|kimi-k?3|gpt-?5/)) return 0
      if (has(/plus|glm|kimi/)) return 2
      if (has(/flash|turbo|mini/)) return 5
      return 4
  }
}

export interface RankedChildModel extends ModelRef {
  billing: ProviderBilling
  custom: boolean
  fit: number
}

/**
 * Rank only routes actually advertised by the running deployment. Explicit
 * top-level tier refs are merged as advisory fallbacks because DSH catalogs may
 * omit accepted model ids. Subscription routes win ties; every custom route is
 * unconditionally PAYG.
 */
export function rankChildModels(
  tier: ChildTier,
  catalog: DeploymentCatalog,
  configuredRefs: readonly ModelRef[] = [],
): RankedChildModel[] {
  const byProvider = new Map(catalog.providers.map((provider) => [provider.id, provider]))
  const candidates = new Map<string, RankedChildModel>()

  const add = (providerId: string, modelId: string, modelName: string, priority: number): void => {
    const provider = byProvider.get(providerId)
    if (!provider?.active) return
    const fit = childModelFit(tier, modelId, modelName)
    if (fit >= 10_000) return
    const key = `${providerId}/${modelId}`
    const candidate: RankedChildModel = {
      provider: providerId,
      model: modelId,
      priority,
      billing: provider.billing,
      custom: provider.custom,
      fit,
    }
    const current = candidates.get(key)
    if (!current || candidate.priority < current.priority) candidates.set(key, candidate)
  }

  for (const provider of catalog.providers) {
    for (let index = 0; index < provider.models.length; index += 1) {
      const model = provider.models[index]!
      add(provider.id, model.id, model.name, index + 1)
    }
  }
  for (const ref of configuredRefs) add(ref.provider, ref.model, ref.model, ref.priority)

  return [...candidates.values()].sort((a, b) => {
    // Capability is primary. Within a close capability band, subscriptions
    // precede PAYG; custom providers can never acquire subscription priority.
    const fit = a.fit - b.fit
    if (fit !== 0) return fit
    const billing = (a.billing === 'subscription' ? 0 : 1) - (b.billing === 'subscription' ? 0 : 1)
    if (billing !== 0) return billing
    const priority = a.priority - b.priority
    if (priority !== 0) return priority
    return `${a.provider}/${a.model}`.localeCompare(`${b.provider}/${b.model}`)
  })
}

export function summarizeCatalog(catalog: DeploymentCatalog): string {
  const lines = catalog.providers.map((provider) => {
    const kind = provider.custom ? 'PAYG custom' : provider.billing === 'subscription' ? 'subscription' : 'PAYG built-in'
    const state = provider.active ? 'active' : 'dormant'
    return `  ${provider.id} [${kind}; ${state}] - ${provider.models.length} models`
  })
  const activeCount = catalog.providers.filter((provider) => provider.active).length
  return [
    `Deployment model/provider catalog (checked ${new Date(catalog.checkedAt).toISOString()}): ${catalog.providers.length} known, ${activeCount} active`,
    ...(lines.length > 0 ? lines : ['  (no known providers)']),
    'Only active providers are eligible for routing; dormant providers are reported for deployment visibility.',
    'Policy: opencode-go and qwen-token-plan-cn are subscription routes; every custom provider is PAYG.',
  ].join('\n')
}
