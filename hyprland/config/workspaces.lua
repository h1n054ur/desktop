-- Workspace rules wiki https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
-- Add your workspace rules here. Increment the workspace number as you go. Do not have duplicate workspaces.
hl.workspace_rule({ workspace = "name:gaming", monitor = SIDE_SCREEN })
hl.workspace_rule({ workspace = "1", monitor = MAIN_SCREEN, default = true, persistent = true })
hl.workspace_rule({ workspace = "2", monitor = MAIN_SCREEN, default = true, persistent = true })
hl.workspace_rule({ workspace = "3", monitor = MAIN_SCREEN, default = true, persistent = true })
hl.workspace_rule({ workspace = "4", monitor = MAIN_SCREEN, default = true, persistent = true })
hl.workspace_rule({ workspace = "5", monitor = MAIN_SCREEN, default = true, persistent = true })
hl.workspace_rule({ workspace = "6", monitor = SIDE_SCREEN, default = true, persistent = true })
hl.workspace_rule({ workspace = "7", monitor = SIDE_SCREEN, default = true, persistent = true })
hl.workspace_rule({ workspace = "8", monitor = SIDE_SCREEN, default = true, persistent = true })
hl.workspace_rule({ workspace = "9", monitor = SIDE_SCREEN, default = true, persistent = true })
hl.workspace_rule({ workspace = "10", monitor = SIDE_SCREEN, default = true, persistent = true })

-- For other layouts such as scrolling, see example below
-- hl.workspace_rule({ workspace = "1", monitor = MAIN_SCREEN, default = true, persistent = true, layout = "scrolling" })
