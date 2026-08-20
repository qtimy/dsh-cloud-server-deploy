import { describe, expect, it, vi } from 'vitest'
import {
  childFailureCanRetry,
  classifyChildTask,
  createChildRouteState,
  markChildFailure,
  pickChildModel,
  shouldReplaceChildRoute,
} from '../src/subagent-router.js'
import type { RankedChildModel } from '../src/deployment-catalog.js'

const candidates: RankedChildModel[] = [
  { provider: 'opencode-go', model: 'deepseek-v4-flash', priority: 1, billing: 'subscription', custom: false, fit: 0 },
  { provider: 'qwen-token-plan-cn', model: 'deepseek-v4-flash', priority: 2, billing: 'subscription', custom: false, fit: 0 },
  { provider: 'deepseek-official', model: 'deepseek-v4-flash', priority: 3, billing: 'payg', custom: false, fit: 0 },
]

describe('child judge and model routing', () => {
  it('walks the judge chain and preserves the six-tier result', async () => {
    const failed = vi.fn()
    const call = vi.fn()
      .mockResolvedValueOnce({ ok: false, code: 'AUTH' })
      .mockResolvedValueOnce({ ok: true, tier: 'code' })
    const tier = await classifyChildTask(
      'implement a parser',
      [
        { provider: 'a', model: 'judge-a', priority: 1 },
        { provider: 'b', model: 'judge-b', priority: 2 },
      ],
      call,
      1000,
      failed,
    )
    expect(tier).toBe('code')
    expect(failed).toHaveBeenCalledWith('a', 'judge-a', 'AUTH')
  })

  it('falls back to fast when every judge route fails', async () => {
    const tier = await classifyChildTask(
      'ordinary task',
      [{ provider: 'a', model: 'm', priority: 1 }],
      async () => ({ ok: false, code: null }),
      1000,
    )
    expect(tier).toBe('fast')
  })

  it('fails over an AUTH error at provider scope, then reaches PAYG', () => {
    const state = createChildRouteState('fast', candidates)
    expect(pickChildModel(state)?.provider).toBe('opencode-go')
    state.lastRequestProvider = 'opencode-go'
    state.lastRequestModel = 'deepseek-v4-flash'
    markChildFailure(state, { code: 'AUTH' })
    expect(pickChildModel(state)?.provider).toBe('qwen-token-plan-cn')
    state.lastRequestProvider = 'qwen-token-plan-cn'
    state.lastRequestModel = 'deepseek-v4-flash'
    markChildFailure(state, { code: 'AUTH' })
    expect(pickChildModel(state)).toMatchObject({ provider: 'deepseek-official', billing: 'payg' })
  })

  it('uses model-scoped failover for transient errors and never retries cancellation', () => {
    const state = createChildRouteState('fast', candidates)
    state.lastRequestProvider = 'opencode-go'
    state.lastRequestModel = 'deepseek-v4-flash'
    markChildFailure(state, { code: 'RATE_LIMIT' })
    expect(state.failedProviders.size).toBe(0)
    expect(state.failedModels.has('opencode-go/deepseek-v4-flash')).toBe(true)
    expect(childFailureCanRetry({ code: 'RATE_LIMIT' })).toBe(true)
    expect(childFailureCanRetry({ code: 'ABORTED' })).toBe(false)
  })

  it('treats provider quota exhaustion as provider-wide', () => {
    const state = createChildRouteState('tiny', candidates)
    state.lastRequestProvider = 'opencode-go'
    state.lastRequestModel = 'deepseek-v4-flash'
    markChildFailure(state, { code: 'QUOTA' })
    expect(pickChildModel(state)?.provider).toBe('qwen-token-plan-cn')
  })

  it('replaces inherited and previously routed defaults but preserves an explicit pin', () => {
    const state = createChildRouteState('fast', candidates)
    const parent = { provider: 'deepseek-official', model: 'deepseek-v4-flash' }
    expect(shouldReplaceChildRoute(parent, parent, state)).toBe(true)

    state.lastRequestProvider = 'opencode-go'
    state.lastRequestModel = 'deepseek-v4-flash'
    expect(shouldReplaceChildRoute({ provider: 'opencode-go', model: 'deepseek-v4-flash' }, parent, state)).toBe(true)
    expect(shouldReplaceChildRoute({ provider: 'custom', model: 'explicit' }, parent, state)).toBe(false)
  })
})
