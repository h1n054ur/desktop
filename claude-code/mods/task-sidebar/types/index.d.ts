export type SidebarStatus = 'pending' | 'in_progress' | 'completed'

export type SidebarTask = {
  id: string
  subject: string
  status: SidebarStatus
  owner?: string
  blockedBy: string[]
}

declare module 'claude-code' {
  interface PluginState {
    'task-sidebar': {
      tasks: SidebarTask[]
      autoOpened: boolean
    }
  }
}
