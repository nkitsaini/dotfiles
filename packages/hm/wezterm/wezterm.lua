local wezterm = require "wezterm"

-- https://github.com/wez/wezterm/issues/1742#issuecomment-1075333507
local xcursor_size = nil
local xcursor_theme = nil

local success, stdout, stderr =
    wezterm.run_child_process({"gsettings", "get", "org.gnome.desktop.interface", "cursor-theme"})
if success then
    xcursor_theme = stdout:gsub("'(.+)'\n", "%1")
end

local success, stdout, stderr =
    wezterm.run_child_process({"gsettings", "get", "org.gnome.desktop.interface", "cursor-size"})
if success then
    xcursor_size = tonumber(stdout)
end

return {

    -- launches very slow (200-300ms) if wayland is enabled, not sure why. 40-50ms when it is disabled
    -- But keyboard lags (only in some windows) when wayland is enabled
    enable_wayland = true,

    front_end = "WebGpu", -- For some reason opengl breaks rendering (started happening after nixpkgs update)
    xcursor_theme = xcursor_theme,
    xcursor_size = xcursor_size,
    -- colors = {

    --    -- solarized from ghostty themes with two modifications
    --    -- 1. bright colors are same as normal colors
    --    -- 2. background is the average of gruvbox background and solarized background (a bit darker then solrazied)
       
    --     foreground = "#657b83",
    --     background = "#fcf4d5", -- '#fbf1c7', '#fdf6e3'
    --     cursor_bg = "#657b83",
    --     cursor_fg = "#fdf6e3",
    --     cursor_border = "#657b83",
    --     selection_fg = "#586e75",
    --     selection_bg = "#eee8d5",
    --     ansi = {
    --         "#073642", -- black
    --         "#dc322f", -- red
    --         "#859900", -- green
    --         "#b58900", -- yellow
    --         "#268bd2", -- blue
    --         "#d33682", -- magenta
    --         "#2aa198", -- cyan
    --         "#eee8d5" -- white
    --     },
    --     brights = {
    --         "#073642", -- black
    --         "#dc322f", -- red
    --         "#859900", -- green
    --         "#b58900", -- yellow
    --         "#268bd2", -- blue
    --         "#d33682", -- magenta
    --         "#2aa198", -- cyan
    --         "#eee8d5" -- white
    --     },
    --     indexed = {
    --         [16] = "#cb4b16", -- orange
    --         [17] = "#d33682", -- magenta
    --         [18] = "#073642", -- base02
    --         [19] = "#586e75", -- base01
    --         [20] = "#657b83", -- base00
    --         [21] = "#839496", -- base0
    --         [22] = "#93a1a1", -- base1
    --         [23] = "#eee8d5" -- base2
    --     }
    -- },
    -- color_scheme = "Solarized (dark) (terminal.sexy)",
    -- color_scheme = "Gruvbox Dark (Gogh)",
    -- color_scheme = "Gruvbox Dark (Gogh)",
    -- 
    -- 
    -- NOTE: Some wisdom about color themes
    -- ANSI color codes define white, black, blue, ..., and their bright versions
    -- Some tools will use ansi.white to show text, while others will use ansi.black
    -- Some are 'smart' and will check the terminal theme and adjust accordingly
    -- Some tools that you can test your any new theme with
    --   --- taskwarrior (atleast 3 task items) = `task list`
    --   --- bottom (process monitor) = `btm`
    --   --- nmtui-connect = `nmtui-connect`
    --   --- fish = Notice fish autocomplete color
    --   --- ls = Notice folder colors (should be blue)
    --   
    --   GruvboxLight - `task list` has bad contract (with solarized theme) and nmtui-connect is visible but not pleasant
    --                - everything else is good
    --   A "solution" to this is iterm's contrast setting https://www.reddit.com/r/wezterm/comments/1df0e4d/contrast_settings/
    --   Hopefully wezterm will have that some day https://github.com/wez/wezterm/issues/6225
    color_scheme = "GruvboxLight",
    hide_tab_bar_if_only_one_tab = true,
    -- font_hinting = "None",
    --
    font = wezterm.font("Noto Sans Mono"),
    -- font = wezterm.font("ProggyCleanTT"),
    font_size = 14.0,
    -- font = wezterm.font("CozetteHiDpi"),
    -- font_size = 17.0,
    -- line_height = 1.15,

    -- timeout_milliseconds defaults to 1000 and can be omitted
    -- leader = { key="a", mods="CTRL", timeout_milliseconds=1000 },
    -- keys = {
    --   {key="|", mods="LEADER|SHIFT", action=wezterm.action{SplitHorizontal={domain="CurrentPaneDomain"}}},
    --   {key="-", mods="LEADER", action=wezterm.action{SplitVertical={domain="CurrentPaneDomain"}}},
    --   -- Send "CTRL-A" to the terminal when pressing CTRL-A, CTRL-A
    --   {key="a", mods="LEADER|CTRL", action=wezterm.action{SendString="\x01"}},
    -- },

    window_padding = {
        left = 0,
        right = 0,
        top = 0,
        bottom = 0
    }
    -- window_frame = {
    --   -- The font used in the tab bar.
    --   -- Roboto Bold is the default; this font is bundled
    --   -- with wezterm.
    --   -- Whatever font is selected here, it will have the
    --   -- main font setting appended to it to pick up any
    --   -- fallback fonts you may have used there.
    --   font = wezterm.font({family="Inter"}),
    --   font_size = 11.0,

    --   active_titlebar_bg = "#281733",
    -- },

    -- color_scheme = "BirdsOfParadise",
    -- colors = {
    --   -- The default text color
    --   -- foreground = "#ebeafa",
    --   foreground = "#cccccc",
    --   -- The default background color
    --   background = "#3b224c",

    --   -- Overrides the cell background color when the current cell is occupied by the
    --   -- cursor and the cursor style is set to Block
    --   cursor_bg = "#c5c8c6",
    --   -- Overrides the text color when the current cell is occupied by the cursor
    --   cursor_fg = "#1d1f21",
    --   -- Specifies the border color of the cursor when the cursor style is set to Block,
    --   -- of the color of the vertical or horizontal bar when the cursor style is set to
    --   -- Bar or Underline.
    --   cursor_border = "#c5c8c6",

    --   -- the foreground color of selected text
    --   selection_fg = "#ffffff",
    --   -- the background color of selected text
    --   selection_bg = "#404040",

    --   -- The color of the scrollbar "thumb"; the portion that represents the current viewport
    --   scrollbar_thumb = "#222222",

    --   -- The color of the split lines between panes
    --   split = "#444444",

    --   ansi = {"#3b224c", "#f47868", "#9ff28f", "#efba5d", "#a4a0e8", "#dbbfef", "#6acdca", "#ebeafa"},
    --   brights = {"#697c81", "#f47868", "#9ff28f", "#efba5d", "#a4a0e8", "#dbbfef", "#6acdca", "#ebeafa"},

    --   tab_bar = {
    --     active_tab =  {
    --       bg_color = "#3b224c",
    --       -- fg_color = "#ebeafa",
    --       fg_color = "#ffffff",
    --     },

    --     inactive_tab =  {
    --       bg_color = "#3b224c",
    --       fg_color = "#a4a0e8",
    --     },

    --     new_tab = {
    --       bg_color = "#5a5977",
    --       fg_color = "#ebeafa",
    --     },
    --   },
    -- }
}

