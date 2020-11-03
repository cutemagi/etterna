--[[
	Note: This is still a WIP
	Feel free to contribute to it
--]]
local find = function(t, x)
    local k = findKeyOf(t, x)
    return k and t[k] or nil
end

local Wheel = {}
local function fillNilTableFieldsFrom(table1, defaultTable)
    for key, value in pairs(defaultTable) do
        if table1[key] == nil then
            table1[key] = defaultTable[key]
        end
    end
end

local function dump(o)
    if type(o) == "table" then
        local s = "{ "
        for k, v in pairs(o) do
            if type(k) ~= "number" then
                k = '"' .. k .. '"'
            end
            s = s .. "[" .. k .. "] = " .. dump(v) .. ","
        end
        return s .. "} "
    else
        return tostring(o)
    end
end

local function print(x)
    SCREENMAN:SystemMessage(dump(x))
end

local function getIndexCircularly(table, idx)
    if idx <= 0 then
        return getIndexCircularly(table, idx + #table)
    elseif idx > #table then
        return getIndexCircularly(table, idx - #table)
    end
    return idx
end

-- false if outside of a group
-- true if inside a group
-- toggles within the move function
-- becomes false if all groups are closed
local crossedGroupBorder = false
local forceGroupCheck = false
local diffSelection = 1 -- index of the selected chart

Wheel.mt = {
    updateMusicFromCurrentItem = function(whee)
        SOUND:StopMusic()

        local top = SCREENMAN:GetTopScreen()
        -- only for ScreenSelectMusic
        if top.PlayCurrentSongSampleMusic then
            if GAMESTATE:GetCurrentSong() ~= nil then
                -- currentItem should be a song
                top:PlayCurrentSongSampleMusic(false)
            end
        end
    end,
    updateGlobalsFromCurrentItem = function(whee)
        -- update Gamestate current song
        local currentItem = whee:getItem(whee.index)
        if currentItem.GetDisplayMainTitle then
            -- currentItem is a SONG
            GAMESTATE:SetCurrentSong(currentItem)
            GAMESTATE:SetPreferredSong(currentItem)

            -- setting diff stuff
            local stepslist = currentItem:GetChartsOfCurrentGameMode()
            if #stepslist == 0 then
                -- this scenario should be impossible but lets prepare for the case
                diffSelection = 1
                GAMESTATE:SetCurrentSteps(PLAYER_1, nil)
            else
                local prefdiff = GAMESTATE:GetPreferredDifficulty()
                diffSelection = clamp(diffSelection, 1, #stepslist)
                for i = 1,#stepslist do
                    if stepslist[i]:GetDifficulty() == prefdiff then
                        diffSelection = i
                        break
                    end
                end
                GAMESTATE:SetPreferredDifficulty(PLAYER_1, stepslist[diffSelection]:GetDifficulty())
                GAMESTATE:SetCurrentSteps(PLAYER_1, stepslist[diffSelection])
            end
        else
            -- currentItem is a GROUP
            GAMESTATE:SetCurrentSong(nil)
            GAMESTATE:SetCurrentSteps(PLAYER_1, nil)
        end
    end,
    move = function(whee, num)
        if whee.moveInterval then
            SCREENMAN:GetTopScreen():clearInterval(whee.moveInterval)
        end
        if num == 0 then
            whee.moveInterval = nil
            return
        end
        whee.floatingOffset = num
        local interval = whee.pollingSeconds / 60
        whee.index = getIndexCircularly(whee.items, whee.index + num)
        MESSAGEMAN:Broadcast("WheelIndexChanged", {index = whee.index, maxIndex = #whee.items})
        whee.moveInterval =
            SCREENMAN:GetTopScreen():setInterval(
            function()
                whee.floatingOffset = whee.floatingOffset - num / (whee.pollingSeconds / interval)
                if num < 0 and whee.floatingOffset >= 0 or num > 0 and whee.floatingOffset <= 0 then
                    SCREENMAN:GetTopScreen():clearInterval(whee.moveInterval)
                    whee.moveInterval = nil
                    whee.floatingOffset = 0
                end
                whee:update()
            end,
            interval
        )

        -- stop the music if moving so we dont leave it playing in a random place
        SOUND:StopMusic()
    end,
    findSong = function(whee, chartkey)
        -- in this case, we want to set based on preferred info
        if chartkey == nil then
            local song = GAMESTATE:GetPreferredSong()

            if song ~= nil then
                local newItems, songgroup, finalIndex = WHEELDATA:GetWheelItemsAndGroupAndIndexForSong(song)

                whee.index = finalIndex
                whee.startIndex = finalIndex
                whee.itemsGetter = function() return newItems end
                whee.items = newItems
                whee.group = songgroup
                GAMESTATE:SetCurrentSong(song)
                GAMESTATE:SetCurrentSteps(PLAYER_1, song:GetChartsOfCurrentGameMode()[1])
                return songgroup
            end
        else
            local song = SONGMAN:GetSongByChartKey(chartkey)
            if song == nil then return nil end

            local newItems, songgroup, finalIndex = WHEELDATA:GetWheelItemsAndGroupAndIndexForSong(song)

            whee.index = finalIndex
            whee.startIndex = finalIndex
            whee.itemsGetter = function() return newItems end
            whee.items = newItems
            whee.group = songgroup
            GAMESTATE:SetCurrentSong(song)
            GAMESTATE:SetCurrentSteps(PLAYER_1, SONGMAN:GetStepsByChartKey(chartkey))
            return songgroup
        end
        return nil
    end,
    findGroup = function(whee, name, openGroup)
        if name == nil then name = whee.group end
        if name == nil then return nil end

        local items = WHEELDATA:GetFilteredFolders()
        local index = WHEELDATA:FindIndexOfFolder(name)

        if index == -1 then return false end
        if openGroup then
            items = WHEELDATA:GetWheelItemsForOpenedFolder(name)
        end
        
        whee.index = index
        whee.startIndex = index
        whee.itemsGetter = function() return items end
        whee.items = items
        whee.group = nil
        GAMESTATE:SetCurrentSong(nil)
        GAMESTATE:SetCurrentSteps(PLAYER_1, nil)
        return true
    end,
    exitGroup = function(whee)
        if whee.group == nil then return end
        crossedGroupBorder = false
        forceGroupCheck = true
        whee:findGroup(whee.group, false)
        whee:updateGlobalsFromCurrentItem()
        whee:updateMusicFromCurrentItem()
        whee:rebuildFrames()
        MESSAGEMAN:Broadcast("ClosedGroup", {group = whee.group})
        MESSAGEMAN:Broadcast("ModifiedGroups", {group = whee.group, index = whee.index, maxIndex = #whee.items})
        MESSAGEMAN:Broadcast("WheelSettled", {song = nil, group = whee.group, hovered = whee:getCurrentItem(), steps = nil, index = whee.index, maxIndex = #whee.items})
    end,
    getItem = function(whee, idx)
        return whee.items[getIndexCircularly(whee.items, idx)]
        -- For some reason i have to +1 here
    end,
    getCurrentItem = function(whee)
        return whee:getItem(whee.index)
    end,
    getFrame = function(whee, idx)
        return whee.frames[getIndexCircularly(whee.frames, idx)]
        -- For some reason i have to +1 here
    end,
    getCurrentFrame = function(whee)
        return whee:getFrame(whee.index)
    end,
    update = function(whee)
        -- this is written so that iteration runs in a specific direction
        -- pretty much to avoid certain texture updating issues
        local direction = whee.floatingOffset >= 0 and 1 or -1
        local startI = direction == 1 and 1 or #whee.frames
        local endI = startI == 1 and #whee.frames or 1

        local numFrames = #(whee.frames)
        local idx = whee.index
        idx = idx - (direction == 1 and math.ceil(numFrames / 2) or -math.floor(numFrames / 2) + 1)

        for i = startI, endI, direction do
            local frame = whee.frames[i]
            local offset = i - math.ceil(numFrames / 2) + whee.floatingOffset
            whee.frameTransformer(frame, offset - 1, i, whee.count)
            whee.frameUpdater(frame, whee:getItem(idx), offset)
            idx = idx + direction
        end

        -- handle scrolling into and out of groups
        if whee.group then
            if whee:getCurrentItem().GetDisplayMainTitle then
                if forceGroupCheck or not crossedGroupBorder then
                    crossedGroupBorder = true
                    forceGroupCheck = false
                    MESSAGEMAN:Broadcast("ScrolledIntoGroup", {group = whee.group})
                end
            else
                if forceGroupCheck or crossedGroupBorder then
                    crossedGroupBorder = false
                    forceGroupCheck = false
                    MESSAGEMAN:Broadcast("ScrolledOutOfGroup", {group = whee.group})
                end
            end

        end

        -- the wheel has settled
        if whee.floatingOffset == 0 and not whee.settled then
            whee:updateGlobalsFromCurrentItem()
            whee:updateMusicFromCurrentItem()
            -- settled brings along the Song, Group, Steps, and HoveredItem
            -- Steps should be set correctly immediately on Move, so no problems should arise.
            MESSAGEMAN:Broadcast("WheelSettled", {song = GAMESTATE:GetCurrentSong(), group = whee.group, hovered = whee:getCurrentItem(), steps = GAMESTATE:GetCurrentSteps(), index = whee.index, maxIndex = #whee.items})
            whee.settled = true
        end
        if whee.floatingOffset ~= 0 then
            whee.settled = false
        end
    end,
    rebuildFrames = function(whee, newIndex)
        whee.items = whee.itemsGetter()
        if whee.sort then
            table.sort(whee.items, whee.sort)
        end
        if not whee.index then
            whee.index = newIndex or whee.startIndex
        end
        whee:update()
    end
}

Wheel.defaultParams = {
    itemsGetter = function()
        -- Should return an array table of elements for the wheel
        -- This is a function so it can be delayed, and rebuilt
        --  with different items using this function
        return SONGMAN:GetAllSongs()
    end,
    count = 20,
    frameBuilder = function()
        return LoadFont("Common Normal") .. {}
    end,
    frameUpdater = function(frame, item) -- Update an frame created with frameBuilder with an item
        frame:settext(item:GetMainTitle())
    end,
    x = 0,
    y = 0,
    highlightBuilder = function()
        return Def.ActorFrame {}
    end,
    buildOnInit = true, -- Build wheel in InitCommand (Will be empty until rebuilt otherwise)
    frameTransformer = function(frame, offsetFromCenter, index, total) -- Handle frame positioning
        frame:y(offsetFromCenter * 30)
    end,
    startIndex = 1,
    speed = 15,
    onSelection = nil, -- function(item)
    sort = nil -- function(a,b) return boolean end
}
function Wheel:new(params)
    params = params or {}
    fillNilTableFieldsFrom(params, Wheel.defaultParams)
    local whee = Def.ActorFrame {Name = "Wheel"}
    setmetatable(whee, {__index = Wheel.mt})
    crossedGroupBorder = false -- reset default
    diffSelection = 1 -- reset default
    whee.settled = false -- leaving this false causes 1 settle message on init
    whee.itemsGetter = params.itemsGetter
    whee.count = params.count
    whee.sort = params.sort
    whee.startIndex = params.startIndex
    whee.frameUpdater = params.frameUpdater
    whee.floatingOffset = 0
    whee.buildOnInit = params.buildOnInit
    whee.frameTransformer = params.frameTransformer
    whee.index = whee.startIndex
    whee.onSelection = params.onSelection
    whee.pollingSeconds = 1 / params.speed
    whee.x = params.x
    whee.y = params.y
    whee.moveHeight = 10
    whee.items = {}
    whee.BeginCommand = function(self)
        local heldButtons = {}
        local interval = nil
        -- the polling interval for button presses to keep moving the wheel
        -- basically replaces the repeat event type for the input stuff
        -- because we want to go faster
        local repeatseconds = 0.097
        SCREENMAN:GetTopScreen():AddInputCallback(
            function(event)
                local gameButton = event.button
                local key = event.DeviceInput.button
                local left = gameButton == "MenuLeft" or gameButton == "Left"
                local enter = gameButton == "Start"
                local right = gameButton == "MenuRight" or gameButton == "Right"
                local exit = gameButton == "Back"
                local up = gameButton == "Up" or gameButton == "MenuUp"
                local down = gameButton == "Down" or gameButton == "MenuDown"

                if left or right then
                    local direction = left and "left" or "right"

                    if event.type == "InputEventType_FirstPress" then
                        heldButtons[direction] = true
                        -- dont move if holding both buttons
                        if (left and heldButtons["right"]) or (right and heldButtons["left"]) then
                            if interval ~= nil then
                                SCREENMAN:GetTopScreen():clearInterval(interval)
                                interval = nil
                            end
                        else
                            -- move on a single press
                            whee:move(right and 1 or -1)

                            if interval ~= nil then
                                SCREENMAN:GetTopScreen():clearInterval(interval)
                                interval = nil
                            end
                            interval = SCREENMAN:GetTopScreen():setInterval(
                                function()
                                    if heldButtons["left"] then
                                        whee:move(-1)
                                    elseif heldButtons["right"] then
                                        whee:move(1)
                                    end
                                end,
                                repeatseconds
                            )
                        end
                    elseif event.type == "InputEventType_Release" then
                        heldButtons[direction] = false
                        if interval ~= nil then
                            SCREENMAN:GetTopScreen():clearInterval(interval)
                            interval = nil
                        end
                    else
                        -- input repeat event
                        -- keep moving
                        -- (movement is handled by the interval function above)
                    end
                elseif enter then
                    if event.type == "InputEventType_FirstPress" then
                        whee.onSelection(whee:getCurrentFrame(), whee:getCurrentItem())
                    end
                elseif exit then
                    if event.type == "InputEventType_FirstPress" then
                        SCREENMAN:set_input_redirected(PLAYER_1, false)
                        SCREENMAN:GetTopScreen():Cancel()
                    end
                elseif up or down then
                    local direction = up and "up" or "down"
                    if event.type == "InputEventType_FirstPress" then
                        heldButtons[direction] = true
                        if heldButtons["up"] and heldButtons["down"] then
                            whee:exitGroup()
                        end
                    elseif event.type == "InputEventType_Release" then
                        heldButtons[direction] = false
                    end
                end
                return false
            end
        )
        SCREENMAN:GetTopScreen():setTimeout(
            function()
                if params.buildOnInit then
                    whee:rebuildFrames()
                end
            end,
            0.1
        )
    end
    whee.InitCommand = function(self)
        whee.actor = self
        local interval = false
        self:x(whee.x):y(whee.y)
    end
    whee.frames = {}
    for i = 1, (params.count) do
        local frame =
            params.frameBuilder() ..
            {
                InitCommand = function(self)
                    whee.frames[i] = self
                    self.index = i
                end
            }
        whee[#whee + 1] = frame
    end
    whee[#whee + 1] =
        params.highlightBuilder() ..
        {
            InitCommand = function(self)
                whee.highlight = self
            end
        }
    return whee
end
MusicWheel = {}
MusicWheel.defaultParams = {
    songActorBuilder = function()
        local s
        s =
            Def.ActorFrame {
            InitCommand = function(self)
                s.actor = self
            end,
            LoadFont("Common Normal") ..
                {
                    BeginCommand = function(self)
                        s.actor.fontActor = self
                    end
                }
        }
        return s
    end,
    groupActorBuilder = function()
        local g
        g =
            Def.ActorFrame {
            InitCommand = function(self)
                g.actor = self
            end,
            LoadFont("Common Normal") ..
                {
                    BeginCommand = function(self)
                        g.actor.fontActor = self
                    end
                }
        }
        return g
    end,
    songActorUpdater = function(self, song)
        (self.fontActor):settext(song:GetMainTitle())
    end,
    groupActorUpdater = function(self, packName)
        (self.fontActor):settext(packName)
    end,
    highlightBuilder = nil,
    frameTransformer = nil --function(frame, offsetFromCenter, index, total) -- Handle frame positioning
}

function MusicWheel:new(params)
    local noOverrideFrameBuilder = false
    local noOverrideFrameUpdater = false
    params = params or {}
    if params.frameBuilder ~= nil then
        noOverrideFrameBuilder = true
    end
    if params.frameUpdater ~= nil then
        noOverrideFrameUpdater = true
    end
    fillNilTableFieldsFrom(params, MusicWheel.defaultParams)
    local groupActorBuilder = params.groupActorBuilder
    local songActorBuilder = params.songActorBuilder
    local songActorUpdater = params.songActorUpdater
    local groupActorUpdater = params.groupActorUpdater

    -- reset all WHEELDATA info, set up stats
    WHEELDATA:Init()

    local w
    w =
        Wheel:new {
        count = params.count,
        buildOnInit = params.buildOnInit,
        frameTransformer = params.frameTransformer,
        x = params.x,
        highlightBuilder = params.highlightBuilder,
        y = params.y,
        frameBuilder = noOverrideFrameBuilder and params.frameBuilder or function()
            local x
            x =
                Def.ActorFrame {
                InitCommand = function(self)
                    x.actor = self
                end,
                groupActorBuilder() ..
                    {
                        BeginCommand = function(self)
                            x.actor.g = self
                        end
                    },
                songActorBuilder() ..
                    {
                        BeginCommand = function(self)
                            x.actor.s = self
                        end
                    }
            }
            return x
        end,
        frameUpdater = noOverrideFrameUpdater and params.frameUpdater or function(frame, songOrPack)
            if songOrPack.GetAllSteps then -- song
                -- Update songActor and make group actor invis
                local s = frame.s
                s:visible(true)
                local g = (frame.g)
                g:visible(false)
                songActorUpdater(s, songOrPack)
            else
                --update group actor and make song actor invis
                local s = frame.s
                s:visible(false)
                local g = (frame.g)
                g:visible(true)
                groupActorUpdater(g, songOrPack)
            end
        end,
        onSelection = function(frame, songOrPack)
            if songOrPack.GetAllSteps then
                -- STARTING SONG
                crossedGroupBorder = true

                SCREENMAN:GetTopScreen():SelectCurrent()
                SCREENMAN:set_input_redirected(PLAYER_1, false)
                MESSAGEMAN:Broadcast("SelectedSong")
            else
                local group = songOrPack
                if w.group and w.group == group then
                    -- CLOSING PACK
                    crossedGroupBorder = false
                    w.group = nil

                    local newItems = WHEELDATA:GetFilteredFolders()

                    w.index = findKeyOf(newItems, group)
                    w.itemsGetter = function()
                        return newItems
                    end

                    MESSAGEMAN:Broadcast("ClosedGroup", {group = group})
                else
                    -- OPENING PACK
                    crossedGroupBorder = false
                    w.group = group

                    local newItems = WHEELDATA:GetWheelItemsForOpenedFolder(group)
                    
                    w.index = findKeyOf(newItems, group)
                    w.itemsGetter = function()
                        return newItems
                    end

                    crossedGroupBorder = true
                    MESSAGEMAN:Broadcast("OpenedGroup", {group = group})
                end
                w:rebuildFrames()
                MESSAGEMAN:Broadcast("ModifiedGroups", {group = w.group, index = w.index, maxIndex = #w.items})
            end
        end,
        itemsGetter = function()
            return WHEELDATA:GetFilteredFolders()
        end
    }

    -- external access to move the wheel in a direction
    -- give either a percentage (musicwheel scrollbar movement) or a distance from current position
    -- params.percent or params.direction
    w.MoveCommand = function(self, params)
        if params and params.direction and tonumber(params.direction) then
            w:move(params.direction)
        elseif params.percent and tonumber(params.percent) >= 0 then
            local now = w.index
            local max = #w.items
            local indexFromPercent = clamp(math.floor(params.percent * max), 0, max)
            local distanceToMove = indexFromPercent - now
            w:move(distanceToMove)
        end
    end

    -- external access command for SelectCurrent with a condition
    w.OpenIfGroupCommand = function(self)
        local i = w:getCurrentItem()
        if i.GetDisplayMainTitle == nil then
            w.onSelection(w:getCurrentFrame(), w:getCurrentItem())
        end
    end

    -- grant external access to the selection function
    w.SelectCurrentCommand = function(self)
        w.onSelection(w:getCurrentFrame(), w:getCurrentItem())
    end

    -- trigger a rebuild on F9 presses in case any specific text uses transliteration
    w.DisplayLanguageChangedMessageCommand = function(self)
        w:rebuildFrames()
    end

    -- building the wheel with startOnPreferred causes init to start on the chart stored in Gamestate
    if params.startOnPreferred then
        w.OnCommand = function(self)
            local group = w:findSong()
            if #w.frames > 0 and group ~= nil then
                -- found the song, set up the group focus and send out the related messages for consistency
                crossedGroupBorder = true
                forceGroupCheck = true
                MESSAGEMAN:Broadcast("OpenedGroup", {group = group})
                w:rebuildFrames()
                MESSAGEMAN:Broadcast("ModifiedGroups", {group = group, index = w.index, maxIndex = #w.items})
            else
                -- if the song was not found or there are no items to refresh, do nothing
                w:rebuildFrames()
            end
        end
    end

    w.FindSongCommand = function(self, params)
        if params.chartkey ~= nil then
            local group = w:findSong(params.chartkey)
            if group ~= nil then
                -- found the song, set up the group focus and send out the related messages for consistency
                crossedGroupBorder = true
                forceGroupCheck = true
                MESSAGEMAN:Broadcast("OpenedGroup", {group = group})
                w:rebuildFrames()
                MESSAGEMAN:Broadcast("ModifiedGroups", {group = group, index = w.index, maxIndex = #w.items})
                w:move(0)
                MESSAGEMAN:Broadcast("WheelSettled", {song = GAMESTATE:GetCurrentSong(), group = w.group, hovered = w:getCurrentItem(), steps = GAMESTATE:GetCurrentSteps(), index = w.index, maxIndex = #w.items})
                w.settled = true
                w:updateMusicFromCurrentItem()
            end
        elseif params.song ~= nil then
            local charts = params.song:GetChartsOfCurrentGameMode()
            if #charts > 0 then
                local group = w:findSong(charts[1]:GetChartKey())
                if group ~= nil then
                    -- found the song, set up the group focus and send out the related messages for consistency
                    crossedGroupBorder = true
                    forceGroupCheck = true
                    MESSAGEMAN:Broadcast("OpenedGroup", {group = group})
                    w:rebuildFrames()
                    MESSAGEMAN:Broadcast("ModifiedGroups", {group = group, index = w.index, maxIndex = #w.items})
                    MESSAGEMAN:Broadcast("WheelSettled", {song = GAMESTATE:GetCurrentSong(), group = w.group, hovered = w:getCurrentItem(), steps = GAMESTATE:GetCurrentSteps(), index = w.index, maxIndex = #w.items})
                    w.settled = true
                    w:updateMusicFromCurrentItem()
                end
            end
        end
    end

    return w
end
