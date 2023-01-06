--- Rebirth Theme Config
-- @module Rebirth_01_theme_config
local defaultConfig = {
    global = {
        TipType = 1, -- 1 = tips, 2 = quotes ...
        ShowVisualizer = true,
        FallbackToAverageColorBG = true, -- wheel bg only
        StaticBackgrounds = false,
        ShowBanners = true, -- globally disable banners from displaying if false
        VideoBanners = true,
        WheelPosition = true, -- true = left, false = right
        WheelBanners = true, -- true = on, false = off
    },
}

themeConfig = create_setting("themeConfig", "themeConfig.lua", defaultConfig, -1)
themeConfig:load()

function getWheelPosition()
    -- true means left, false means right
    return themeConfig:get_data().global.WheelPosition
end
function useWheelBanners()
    return themeConfig:get_data().global.WheelBanners
end
function useVideoBanners()
    return themeConfig:get_data().global.VideoBanners
end
function showBanners()
    return themeConfig:get_data().global.ShowBanners
end