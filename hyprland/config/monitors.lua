-- Monitor wiki https://wiki.hypr.land/Configuring/Basics/Monitors/
-- Each machine places its own screens in ../host/<hostname>.lua (loaded before this file).
-- Any screen without a rule there (a TV, a projector) gets its preferred mode, placed automatically.
hl.monitor({
    output    = "",
    mode      = "preferred",
    position  = "auto",
    scale     = "1",
})
