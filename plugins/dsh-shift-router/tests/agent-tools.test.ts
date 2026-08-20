import { describe, expect, it, vi } from 'vitest'
import { agentHasSubagentTool } from '../src/index.js'

describe('agent-scoped tool lookup', () => {
  it('checks the agent preset context rather than the host plugin context', () => {
    const get = vi.fn((name: string) => name === 'subagent' ? { name } : undefined)
    const agent = { ctx: { tools: { get } } }

    expect(agentHasSubagentTool(agent as never)).toBe(true)
    expect(get).toHaveBeenCalledWith('subagent', agent)
  })
})
