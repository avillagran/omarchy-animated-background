-- omarchy-animated-backgrounds: take over the stock background-switcher bind.
-- Installed by the plugin (see bin/omarchy-parallax-keybind); required from
-- hyprland.lua AFTER Omarchy's defaults, so the unbind + rebind win.
-- Opt out: delete the require("hypr.parallax-backgrounds") line in
-- ~/.config/hypr/hyprland.lua (the stock SUPER+CTRL+SPACE bind returns on the
-- next Hyprland reload).

pcall(function() hl.unbind("SUPER + CTRL + SPACE") end)
o.bind("SUPER + CTRL + SPACE", "Parallax background switcher",
  "omarchy-shell -q io.github.avillagran.omarchy-animated-backgrounds toggle")
