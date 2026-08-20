import type { Context } from '@deepseek-ai/cordis'
import { BlockAssembler, createUserMessage } from '@deepseek-ai/dsh-llm'
import type { LlmFailure } from '@deepseek-ai/dsh-llm'
import type { ModelRef } from './types.js'
import type { ChildTier, RankedChildModel } from './deployment-catalog.js'
import { parseChildTier } from './deployment-catalog.js'

export const CHILD_JUDGE_PROMPT = `You classify a delegated AI-agent task.
Return exactly one JSON object with one tier:
{"tier":"tiny|fast|code|smart|heavy|image"}

tiny: extraction, formatting, short summaries, simple checks
fast: routine Q&A, docs, configuration checks, straightforward debugging
code: implementation, tests, fixes, migrations, refactors
smart: architecture, complex diagnosis, reviews, important trade-offs
heavy: high-risk or unusually difficult cross-module reasoning and implementation
image: planning or executing image-generation work

Classify the delegated task itself, not the parent conversation. No prose.`

export type ChildJudgeOutcome =
  | { ok: true; tier: ChildTier }
  | { ok: false; code: string | null }

export interface ChildJudgeCall {
  (provider: string, model: string, prompt: string, signal: AbortSignal): Promise<ChildJudgeOutcome>
}

/** A single child classifier request through DSH's adapter registry. */
export async function defaultChildJudgeCall(
  ctx: Pick<Context, 'llm'>,
  provider: string,
  model: string,
  prompt: string,
  signal: AbortSignal,
  maxTokens: number,
): Promise<ChildJudgeOutcome> {
  const assembler = new BlockAssembler()
  try {
    const stream = ctx.llm.stream({
      provider,
      model,
      system: CHILD_JUDGE_PROMPT,
      messages: [createUserMessage({
        content: [{ type: 'text', text: prompt }],
        source: { kind: 'user' },
      })],
      temperature: 0,
      maxTokens,
      signal,
    })
    for await (const chunk of stream) assembler.push(chunk)
  } catch {
    return { ok: false, code: null }
  }

  const finish = assembler.finish
  if (finish.kind === 'error' || finish.kind === 'aborted') {
    return { ok: false, code: finish.failure.code ?? null }
  }
  const text = assembler.blocks()
    .filter((block): block is { type: 'text'; text: string } => block.type === 'text')
    .map((block) => block.text)
    .join('')
  const tier = parseChildTier(text)
  return tier ? { ok: true, tier } : { ok: false, code: null }
}

/** Walk the configured Fast chain for a bounded child-task classification. */
export async function classifyChildTask(
  prompt: string,
  judgeChain: readonly ModelRef[],
  call: ChildJudgeCall,
  timeoutMs: number,
  onFailure?: (provider: string, model: string, code: string | null) => void,
  externalSignal?: AbortSignal,
): Promise<ChildTier> {
  const sorted = [...judgeChain].sort((a, b) => a.priority - b.priority)
  for (const ref of sorted) {
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), timeoutMs)
    const signal = externalSignal === undefined
      ? controller.signal
      : AbortSignal.any([controller.signal, externalSignal])
    try {
      const outcome = await call(ref.provider, ref.model, prompt, signal)
      if (outcome.ok) return outcome.tier
      onFailure?.(ref.provider, ref.model, outcome.code)
    } catch {
      onFailure?.(ref.provider, ref.model, null)
    } finally {
      clearTimeout(timer)
    }
  }
  return 'fast'
}

export interface ChildRouteState {
  tier: ChildTier
  candidates: RankedChildModel[]
  failedModels: Set<string>
  failedProviders: Set<string>
  lastRequestProvider: string | null
  lastRequestModel: string | null
}

export function createChildRouteState(tier: ChildTier, candidates: RankedChildModel[]): ChildRouteState {
  return {
    tier,
    candidates,
    failedModels: new Set(),
    failedProviders: new Set(),
    lastRequestProvider: null,
    lastRequestModel: null,
  }
}

export function pickChildModel(state: ChildRouteState): RankedChildModel | null {
  for (const candidate of state.candidates) {
    if (state.failedProviders.has(candidate.provider)) continue
    if (state.failedModels.has(`${candidate.provider}/${candidate.model}`)) continue
    return candidate
  }
  return null
}

/**
 * Replace a worker's inherited parent route and any route previously selected
 * by this plugin. A genuinely different child pin remains explicit.
 */
export function shouldReplaceChildRoute(
  incoming: { provider?: string; model?: string },
  parent: { provider?: string; model?: string } | undefined,
  state: Pick<ChildRouteState, 'lastRequestProvider' | 'lastRequestModel'>,
): boolean {
  if (!incoming.provider && !incoming.model) return true
  const inherited = parent !== undefined
    && incoming.provider === parent.provider
    && incoming.model === parent.model
  const previouslyRouted = incoming.provider === state.lastRequestProvider
    && incoming.model === state.lastRequestModel
  return inherited || previouslyRouted
}

/** Authentication/configuration failures poison a provider; transient failures poison one model. */
export function markChildFailure(state: ChildRouteState, failure: Pick<LlmFailure, 'code'>): void {
  const provider = state.lastRequestProvider
  const model = state.lastRequestModel
  if (!provider || !model) return
  const code = String(failure.code ?? '').toUpperCase()
  if (
    code === 'AUTH'
    || code === 'INVALID_API_KEY'
    || code === 'CONFIG'
    || code === 'NOT_FOUND'
    || code === 'QUOTA'
  ) {
    state.failedProviders.add(provider)
  } else {
    state.failedModels.add(`${provider}/${model}`)
  }
}

/** Cancellation/abort is caller intent; every provider failure may otherwise try a finite next route. */
export function childFailureCanRetry(failure: Pick<LlmFailure, 'code'>): boolean {
  const code = String(failure.code ?? '').toUpperCase()
  return code !== 'ABORTED' && code !== 'CANCELLED' && code !== 'CANCELED'
}
