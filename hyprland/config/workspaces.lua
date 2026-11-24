-- Workspace rules wiki https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
-- Add your workspace rules here. Increment the workspace number as you go. Do not have duplicate workspaces.
hl.workspace_rule({ workspace = "name:gaming", monitor = SIDE_SCREEN })
for i = 1, WORKSPACE_COUNT do
    hl.workspace_rule({
        workspace = tostring(i),
        monitor = i <= NUM_WPM and MAIN_SCREEN or SIDE_SCREEN,
        default = true,
        persistent = true,
    })
end

-- For other layouts such as scrolling, see example below
-- hl.workspace_rule({ workspace = "1", monitor = MAIN_SCREEN, default = true, persistent = true, layout = "scrolling" })
