local sizing = Var("sizing")
if sizing == nil then sizing = {} end
--[[
    We are expecting the sizing table to be provided on file load.
    It should contain these attributes:
    Width
    Height
]]
-- all elements are placed relative to default valign - 0 halign
-- this means relatively to center vertically and relative to the left end horizontally

local judgeSetting = (PREFSMAN:GetPreference("SortBySSRNormPercent") and 4 or GetTimingDifficulty())
local timingScale = ms.JudgeScalers[judgeSetting]

-- cap the graph to this
local maxOffset = 180
local lineThickness = 2
local lineAlpha = 0.2
local textPadding = 5
local textSize = 0.65

local bgColor = color("0,0,0,0.8")
local positionColor = color("0.7,0.2,0.2,0.7")
local dotAnimationSeconds = 1
local resizeAnimationSeconds = 0.1

-- the dot sizes
-- the "classic" default is 1.0
local dotLineLength = 0.75
local dotLineUpperBound = 1.2
local dotLineLowerBound = 0.7
-- length of the dot lines for the mine X
local mineXSize = 3
local mineXThickness = 1
local mineColor = color("1,0,0,1")

-- judgment windows to display on the plot
local barJudgments = {
    "TapNoteScore_W2",
    "TapNoteScore_W3",
    "TapNoteScore_W4",
    "TapNoteScore_W5",
}

-- convert number to another number out of a given width
-- relative to left side of the graph
local function fitX(x, maxX)
    -- dont let the x go way off the end of the graph
    x = clamp(x, x, maxX)
    return x / maxX * sizing.Width
end

-- convert millisecond values to a y position in the graph
-- relative to vertical center
local function fitY(y, maxY)
    return -1 * y / maxY * sizing.Height / 2 + sizing.Height / 2
end

-- 4 xyz coordinates are given to make up the 4 corners of a quad to draw
local function placeDotVertices(vertList, x, y, color)
    vertList[#vertList + 1] = {{x - dotLineLength, y + dotLineLength, 0}, color}
    vertList[#vertList + 1] = {{x + dotLineLength, y + dotLineLength, 0}, color}
    vertList[#vertList + 1] = {{x + dotLineLength, y - dotLineLength, 0}, color}
    vertList[#vertList + 1] = {{x - dotLineLength, y - dotLineLength, 0}, color}
end

-- 2 pairs of 4 coordinates to draw a big X
local function placeMineVertices(vertList, x, y, color)
    vertList[#vertList + 1] = {{x - mineXSize - mineXThickness / 2, y - mineXSize, 0}, color}
    vertList[#vertList + 1] = {{x + mineXSize - mineXThickness / 2, y + mineXSize, 0}, color}
    vertList[#vertList + 1] = {{x - mineXSize + mineXThickness / 2, y - mineXSize, 0}, color}
    vertList[#vertList + 1] = {{x + mineXSize + mineXThickness / 2, y + mineXSize, 0}, color}

    vertList[#vertList + 1] = {{x + mineXSize + mineXThickness / 2, y - mineXSize, 0}, color}
    vertList[#vertList + 1] = {{x - mineXSize + mineXThickness / 2, y + mineXSize, 0}, color}
    vertList[#vertList + 1] = {{x + mineXSize - mineXThickness / 2, y - mineXSize, 0}, color}
    vertList[#vertList + 1] = {{x - mineXSize - mineXThickness / 2, y + mineXSize, 0}, color}
end

local t = Def.ActorFrame {
    Name = "OffsetPlotFile",
    InitCommand = function(self)
        self:SetUpdateFunction(function()
            local bg = self:GetChild("BG")
            if isOver(bg) then
                local top = SCREENMAN:GetTopScreen()
                -- dont break if it will break (we can only do this from the eval screen)
                if not top.GetReplaySnapshotJudgmentsForNoterow or not top.GetReplaySnapshotWifePercentForNoterow then
                    return
                end

                TOOLTIP:Show()

                local x, y = bg:GetLocalMousePos(INPUTFILTER:GetMouseX(), INPUTFILTER:GetMouseY(), 0)
                local percent = clamp(x / bg:GetZoomedWidth(), 0, 1)
                -- 48 rows per beat, multiply the current beat by 48 to get the current row
                local td = GAMESTATE:GetCurrentSteps():GetTimingData()
                local lastsec = GAMESTATE:GetCurrentSteps():GetLastSecond()
                local row = td:GetBeatFromElapsedTime(percent * lastsec) * 48

                local judgments = top:GetReplaySnapshotJudgmentsForNoterow(row)
                local wifescore = top:GetReplaySnapshotWifePercentForNoterow(row) * 100
                local time = SecondsToHHMMSS(td:GetElapsedTimeFromNoteRow(row))

                local marvCount = judgments[10]
                local perfCount = judgments[9]
                local greatCount = judgments[8]
                local goodCount = judgments[7]
                local badCount = judgments[6]
                local missCount = judgments[5]

                -- excessively long string format for translation support
                local txt = string.format(
                    "%5.6f%%\n%s: %d\n%s: %d\n%s: %d\n%s: %d\n%s: %d\n%s: %d\n%s: %s",
                    wifescore,
                    "Marvelous", marvCount,
                    "Perfect", perfCount,
                    "Great", greatCount,
                    "Good", goodCount,
                    "Bad", badCount,
                    "Miss", missCount,
                    "Time", time
                )

                local mp = self:GetChild("MousePosition")
                mp:visible(true)
                mp:x(x)
                TOOLTIP:SetText(txt)
            else
                self:GetChild("MousePosition"):visible(false)
                TOOLTIP:Hide()
            end
        end)
    end,
    UpdateSizingCommand = function(self, params)
        if params.sizing ~= nil then
            sizing = params.sizing
        end
        if params.judgeSetting ~= nil then
            judgeSetting = params.judgeSetting
            timingScale = ms.JudgeScalers[judgeSetting]
        end
    end
}

t[#t+1] = Def.Quad {
    Name = "BG",
    InitCommand = function(self)
        self:halign(0)
        self:diffuse(bgColor)
        self:playcommand("UpdateSizing")
        self:finishtweening()
    end,
    UpdateSizingCommand = function(self)
        self:finishtweening()
        self:smooth(resizeAnimationSeconds)
        self:y(sizing.Height / 2)
        self:zoomto(sizing.Width, sizing.Height)
    end
}

t[#t+1] = Def.Quad {
    Name = "MousePosition",
    InitCommand = function(self)
        self:valign(0)
        self:diffuse(positionColor)
        self:zoomx(lineThickness)
        self:playcommand("UpdateSizing")
        self:finishtweening()
    end,
    UpdateSizingCommand = function(self)
        self:finishtweening()
        self:smooth(resizeAnimationSeconds)
        self:zoomy(sizing.Height)
    end
}

t[#t+1] = Def.Quad {
    Name = "CenterLine",
    InitCommand = function(self)
        self:halign(0)
        self:diffuse(byJudgment("TapNoteScore_W1"))
        self:diffusealpha(lineAlpha)
        self:playcommand("UpdateSizing")
        self:finishtweening()
    end,
    UpdateSizingCommand = function(self)
        self:finishtweening()
        self:smooth(resizeAnimationSeconds)
        self:y(sizing.Height / 2)
        self:zoomto(sizing.Width, lineThickness)
    end
}

for i, j in ipairs(barJudgments) do
    t[#t+1] = Def.Quad {
        Name = j.."_Late",
        InitCommand = function(self)
            self:halign(0)
            self:diffuse(byJudgment(j))
            self:diffusealpha(lineAlpha)
            self:playcommand("UpdateSizing")
            self:finishtweening()
        end,
        UpdateSizingCommand = function(self)
            self:finishtweening()
            self:smooth(resizeAnimationSeconds)
            local window = ms.getLowerWindowForJudgment(j, timingScale)
            self:y(fitY(window, maxOffset))
            self:zoomto(sizing.Width, lineThickness)
        end
    }
    t[#t+1] = Def.Quad {
        Name = j.."_Early",
        InitCommand = function(self)
            self:halign(0)
            self:diffuse(byJudgment(j))
            self:diffusealpha(lineAlpha)
            self:playcommand("UpdateSizing")
            self:finishtweening()
        end,
        UpdateSizingCommand = function(self)
            self:finishtweening()
            self:smooth(resizeAnimationSeconds)
            local window = ms.getLowerWindowForJudgment(j, timingScale)
            self:y(fitY(-window, maxOffset))
            self:zoomto(sizing.Width, lineThickness)
        end
    }
end

t[#t+1] = LoadFont("Common Normal") .. {
    Name = "LateText",
    InitCommand = function(self)
        self:halign(0):valign(0)
        self:zoom(textSize)
        self:playcommand("UpdateSizing")
        self:finishtweening()
    end,
    UpdateSizingCommand = function(self)
        self:finishtweening()
        self:smooth(resizeAnimationSeconds)
        local bound = ms.getUpperWindowForJudgment(barJudgments[#barJudgments], timingScale)
        self:xy(textPadding, textPadding)
        self:settextf("Late (+%dms)", bound)
    end
}

t[#t+1] = LoadFont("Common Normal") .. {
    Name = "EarlyText",
    InitCommand = function(self)
        self:halign(0):valign(1)
        self:zoom(textSize)
        self:playcommand("UpdateSizing")
        self:finishtweening()
    end,
    UpdateSizingCommand = function(self)
        self:finishtweening()
        self:smooth(resizeAnimationSeconds)
        local bound = ms.getUpperWindowForJudgment(barJudgments[#barJudgments], timingScale)
        self:xy(textPadding, sizing.Height - textPadding)
        self:settextf("Early (-%dms)", bound)
    end
}

t[#t+1] = LoadFont("Common Normal") .. {
    Name = "InstructionText",
    InitCommand = function(self)
        self:valign(1)
        self:zoom(textSize)
        self:settext("")
        self:playcommand("UpdateSizing")
        self:finishtweening()
    end,
    UpdateSizingCommand = function(self)
        self:finishtweening()
        self:smooth(resizeAnimationSeconds)
        self:xy(sizing.Width / 2, sizing.Height - textPadding)
    end
}

t[#t+1] = Def.ActorMultiVertex {
    Name = "Dots",
    InitCommand = function(self)
        --self:zoomto(0, 0)
        self:playcommand("UpdateSizing")
    end,
    UpdateSizingCommand = function(self)

    end,
    LoadOffsetsCommand = function(self, params)
        -- makes sure all sizes are updated
        self:GetParent():playcommand("UpdateSizing", params)
        local vertices = {}
        local offsets = params.offsetVector
        local tracks = params.trackVector
        local timing = params.timingVector
        local types = params.typeVector
        local maxTime = params.maxTime

        if offsets == nil or #offsets == 0 then
            self:SetVertices(vertices)
            return
        end

        -- dynamically change the dot size depending on the number of dots
        -- for clarity on ultra dense scores
        dotLineLength = clamp(scale(#offsets, 1000, 5000, dotLineUpperBound, dotLineLowerBound), dotLineLowerBound, dotLineUpperBound)

        for i, offset in ipairs(offsets) do
            local x = fitX(timing[i], maxTime)
            local y = fitY(offset, maxOffset)

            local cappedY = math.max(maxOffset, (maxOffset) * timingScale)
            if y < 0 or y > sizing.Height then
                y = fitY(cappedY, maxOffset)
            end

            local dotColor = offsetToJudgeColor(offset, timingScale)
            dotColor[4] = 1

            if types[i] ~= "TapNoteType_Mine" then
                placeDotVertices(vertices, x, y, dotColor)
            else
                placeMineVertices(vertices, x, fitY(-maxOffset, maxOffset), mineColor)
            end

        end
        -- animation breaks if we start from nothing
        if self:GetNumVertices() ~= 0 then
            self:finishtweening()
            self:smooth(dotAnimationSeconds)
        end
        self:SetVertices(vertices)
        self:SetDrawState {Mode = "DrawMode_Quads", First = 1, Num = #vertices}
    end
}



return t