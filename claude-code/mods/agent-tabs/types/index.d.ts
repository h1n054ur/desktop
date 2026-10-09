export type TabState = 'starting' | 'running' | 'waiting' | 'done' | 'failed'

export type TabAgent = {
  id: string
  description: string
  state: TabState
  startedAt: number
  // Set once the agent finishes: the time stops there and the tab drops off a while later
  endedAt?: number
  // Tokens of the agent's latest model call: its context plus what it wrote
  tokens: number
}

declare module 'claude-code' {
  interface PluginState {
    'agent-tabs': {
      agents: TabAgent[]
      now: number
    }
  }
}
