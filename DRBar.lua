local DRData = LibStub('DRData-1.0')


DRBar = {}
DRBar.eventHandler = CreateFrame('Frame')
DRBar.eventHandler.events = {}
DRBar.units = {}


DRBar.defaults = {
    profile = {
        trackerSize = { default = 50 },
        testing = false,
        drFactorTextSize = { default = 10 },
        x = {},
        y = {},
    }
}

function DRBar:RegisterEvent(event, handler)
    self.eventHandler.events[event] = handler or event
    self.eventHandler:RegisterEvent(event)
end

DRBar.eventHandler:SetScript('OnEvent', function(self, event, ...)
    if event == 'ADDON_LOADED' and ... == 'DRBar' then
        DRBar:OnInitialize()
    elseif event == 'PLAYER_LOGIN' then
        DRBar:OnEnable()
        DRBar.eventHandler:UnregisterEvent('PLAYER_LOGIN')
    else
        local handler = self.events[event]
        if type(DRBar[handler]) == 'function' then
            DRBar[handler](DRBar, event, ...)
        end
    end
end)

DRBar.eventHandler:RegisterEvent('ADDON_LOADED')
DRBar.eventHandler:RegisterEvent('PLAYER_LOGIN')

-- DRBar.trackedPlayers = { 'player' }
DRBar.trackedPlayers = { 'player', 'raid1', 'raid2', 'raid3', 'raid4', 'raid5', 'target', 'focus' }

function DRBar:OnInitialize()
    self.globalDb = LibStub('AceDB-3.0'):New('DRBarDB', self.defaults)
    self.db = self.globalDb.profile

    -- Metatable qui fait renvoyer table[default] quand
    -- key n'est pas présent
    local defaultMetatable = {
        __index = function(table, key)
            if key:find('^raid[1-5]$') then
                key = 'raid'
            end
            return rawget(table, key) or rawget(table, 'default')
        end
    }
    self.db.trackerSize = setmetatable(self.db.trackerSize, defaultMetatable)
    self.db.drFactorTextSize = setmetatable(self.db.drFactorTextSize, defaultMetatable)

    if self.db.testing then
        print('On Initialize')
    end

    self.bars = {}
    for _, trackedPlayer in pairs(self.trackedPlayers) do
        self:CreateBar(trackedPlayer)
    end
    self:ConfigureOptions()
end

function DRBar:CreateBar(unitId)
    self.bars[unitId] = CreateFrame('Frame', 'DRBarBar', UIParent, 'ActionButtonTemplate')
    local bar = self.bars[unitId]
    bar.drTrackers = {}

    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:SetClampedToScreen(true)
    bar:RegisterForDrag('LeftButton')
    bar:SetScript('OnDragStart', bar.StartMoving)
    bar:SetScript('OnDragStop', function(frame)
        frame:StopMovingOrSizing()
        self.db.x[unitId] = frame:GetLeft()
        self.db.y[unitId] = frame:GetTop()
    end)

    --[[bar.texture = bar:CreateTexture(bar:GetName()..'Texture', 'BACKGROUND')
    bar.texture:SetAllPoints()
    bar.texture:SetColorTexture(0, 0, 0, 0.3)]]
    self:SetBarSize(unitId)
    self:SetBarPosition(unitId)
end

function DRBar:SetBarSize(unitId)
    local bar = self.bars[unitId]
    local width = 0
    for drCategory, tracker in pairs(bar.drTrackers) do
        if tracker.active then
            width = width + tracker:GetWidth()
        end
    end
    bar:SetSize(width, self.db.trackerSize[unitId])

    for drCategory, tracker in pairs(bar.drTrackers) do
        self:ConfigureIcon(unitId, drCategory)
    end
end

function DRBar:SetBarPosition(unitId)
    local bar = self.bars[unitId]
    local trackerSize = self.db.trackerSize[unitId]

    -- print('Setting par positions for '..unitId)
    if not self.db.x[unitId] or not self.db.y[unitId] then
        -- print('Default')
        if unitId == 'player' then
            bar:SetPoint('CENTER', 0, 200)
            -- print('Top : '..bar:GetTop())
            -- print('Left : '..bar:GetLeft())
        elseif unitId:find('^raid[1-5]$') then
            local number = tonumber(string.sub(unitId, -1))
            bar:SetPoint('CENTER', 0, - number * trackerSize)
        elseif unitId == 'target' then
            bar:SetPoint('CENTER', 5 * trackerSize, 200)
        elseif unitId == 'focus' then
            bar:SetPoint('CENTER', 5 * trackerSize, 0)
        end
    else
        -- print('Custom')
        bar:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', self.db.x[unitId], self.db.y[unitId])
    end
end

function DRBar:OnEnable()
    if self.db.testing then
        print('On Enable')
    end
    self:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
    self:RegisterEvent('PLAYER_TARGET_CHANGED')
    self:RegisterEvent('PLAYER_FOCUS_CHANGED')
end

function DRBar:COMBAT_LOG_EVENT_UNFILTERED(event)
    self:HandleCombatLogEvent(event, CombatLogGetCurrentEventInfo())
end

function DRBar:HandleCombatLogEvent(event, timestamp, eventType, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellId, spellName, spellSchool, auraType)
    if eventType ~= 'SPELL_AURA_REMOVED' and eventType ~= 'SPELL_AURA_REFRESH' then
        return
    end
    if not destGUID or not destGUID:find('^Player') then
        return
    end

    self:HandleFadingAura(destGUID, spellId)
end

function DRBar:HandleFadingAura(unitGUID, spellId)
    local drCategory = DRData:GetSpellCategory(spellId)

    if not self.db.testing and not drCategory then
        return
    end
    -- Pour les tests...
    if self.db.testing  and not drCategory then
        if spellId == 21562 then
            drCategory = 'disorient'
        else
            drCategory = 'stun'
        end
    end

    self:ApplyDr(unitGUID, drCategory, spellId)

    for _, trackedPlayer in pairs(self.trackedPlayers) do
        if UnitGUID(trackedPlayer) == unitGUID then
            self:UpdateTracker(trackedPlayer, drCategory)
        end
    end
end

function DRBar:ApplyDr(unitGUID, drCategory, spellId)
    --print('ApplyDr : '..unitGUID)

    if not self.units[unitGUID] then
        self.units[unitGUID] = {}
        self.units[unitGUID].drData = {}
    end
    if not self.units[unitGUID].drData[drCategory] then
        self.units[unitGUID].drData[drCategory] = {}
    end

    local drData = self.units[unitGUID].drData[drCategory]
    drData.spellId = spellId
    if not drData.drFactor or not drData.resetTime or drData.resetTime <= GetTime() then
        drData.drFactor = 1.0
    else
        drData.drFactor = DRData:NextDR(drData.drFactor, drCategory)
    end
    drData.startTime = GetTime()
    drData.resetTime = drData.startTime + DRData:GetResetTime()

    --print(string.format('Time : %f', GetTime()))
    --print(string.format('%s %s %f %f', unitGUID, drCategory, drData.drFactor, drData.resetTime))
end

function DRBar:UpdateTracker(unitId, drCategory)
    --print(string.format('Handling CC : %d', drCategory))
    self:ConfigureTracker(unitId, drCategory)
    self:StartTracker(unitId, drCategory)
end

-- TODO
-- SpellId est utilisé pour l'icône, ce serait une bonne
-- idée de trouver un autre moyen de la récupérer
function DRBar:ConfigureTracker(unitId, drCategory)
    --print('ConfigureTracker : '..unitId..' '..drCategory)
    local unitGUID = UnitGUID(unitId)
    local drData = self.units[unitGUID].drData[drCategory]

    -- Crée le tracker pour drCategory s'il n'existe pas
    local bar = self.bars[unitId]
    if not bar.drTrackers[drCategory] then
        bar.drTrackers[drCategory] = CreateFrame('CheckButton', 'DRBarDR'..drCategory, bar, 'ActionButtonTemplate')
    end

    -- Configure le tracker
    local tracker = bar.drTrackers[drCategory]
    tracker.spellId = drData.spellId
    tracker.drFactor = drData.drFactor
    tracker.startTime = drData.startTime
    tracker.resetTime = drData.resetTime

    if GetTime() <= tracker.resetTime then
        --print('Displaying '..unitId..' '..drCategory)
        tracker.active = true
        tracker:Show()

        self:ConfigureIcon(unitId, drCategory)
        self:CreateCooldown(unitId, drCategory)
        self:ConfigureText(unitId, drCategory)
    else
        tracker.active = false
        tracker:Hide()
    end

    self:SetBarSize(unitId)
    self:SetIconsPositions(unitId)

end

function DRBar:ConfigureIcon(unitId, drCategory)
    local bar = self.bars[unitId]
    local tracker = bar.drTrackers[drCategory]

    tracker:EnableMouse(false)

    local size = bar:GetHeight()
    tracker:SetSize(size, size)
    tracker:SetPoint('LEFT')

    if not tracker.texture then
        tracker.texture = tracker:CreateTexture()
        tracker.texture:SetAllPoints()
    end

    local icon = select(3, GetSpellInfo(tracker.spellId))
    tracker.texture:SetTexture(icon)
end

function DRBar:CreateCooldown(unitId, drCategory)
    local tracker = self.bars[unitId].drTrackers[drCategory]

    if not tracker.cooldown.custom then
        tracker.cooldown = CreateFrame('Cooldown', tracker:GetName()..'Cooldown', tracker, 'CooldownFrameTemplate')
        tracker.cooldown.custom = true
        --tracker.cooldown:SetAllPoints()
    end
end

function DRBar:ConfigureText(unitId, drCategory)
    local tracker = self.bars[unitId].drTrackers[drCategory]
    
    if not tracker.fontString then
        tracker.fontString = tracker:CreateFontString(tracker:GetName()..'FontString', 'OVERLAY')
        tracker.fontString:SetPoint('LEFT')
        tracker.fontString:SetPoint('RIGHT')
        tracker.fontString:SetPoint('BOTTOM', tracker, 0, 3)
    end

    tracker.fontString:SetFont(STANDARD_TEXT_FONT, self.db.drFactorTextSize[unitId], 'OUTLINE')

    local text = DRData:NextDR(tracker.drFactor, drCategory)
    tracker.fontString:SetText(text)

    local r, g, b = unpack(self.drFactorFontColors[tracker.drFactor])
    tracker.fontString:SetTextColor(r, g, b)
end

DRBar.drFactorFontColors = {
    [1] = { 0, 1, 0 },
    [0.5] = { 1, 1, 0 },
    [0.25] = { 1, 0, 0 },
    [0] = { 1, 0, 0 },
}

function DRBar:SetIconsPositions(unitId)
    local bar = self.bars[unitId]
    local relativeTo = bar

    for drCategory, tracker in pairs(bar.drTrackers) do
        tracker:ClearAllPoints()
        if tracker.active then
            if relativeTo == bar then
                tracker:SetPoint('LEFT', relativeTo, 'LEFT')
            else
                tracker:SetPoint('LEFT', relativeTo, 'RIGHT')
            end
            relativeTo = tracker
        end
    end
end

function DRBar:StartTracker(unitId, drCategory)
    local tracker = self.bars[unitId].drTrackers[drCategory]
    -- Lance le tracker
    -- print(GetTime()..' Start of DR '..tracker.drCategory..' with factor '..tracker.drFactor)
    tracker:SetScript('OnUpdate', function(this, elapsed)
        if this.resetTime < GetTime() then
            -- print(GetTime()..' End of DR '..tracker.drCategory)
            this:SetScript('OnUpdate', nil)
            self:HideTracker(unitId, drCategory)
        end
    end)
    local duration = tracker.resetTime - tracker.startTime
    tracker.cooldown:SetCooldown(tracker.startTime, duration)
end

function DRBar:HideTracker(unitId, drCategory)
    local tracker = self.bars[unitId].drTrackers[drCategory]
    tracker.active = false
    tracker:Hide()
    self:SetBarSize(unitId)
    self:SetIconsPositions(unitId)
end

function DRBar:PLAYER_TARGET_CHANGED()
    --print('Target changed')
    self:UpdateBar('target')
end

function DRBar:PLAYER_FOCUS_CHANGED()
    self:UpdateBar('focus')
end

function DRBar:UpdateBar(unitId)
    --print('Updating bar '..unitId)

    -- On cache les trackers existants
    for drCategory, _ in pairs(self.bars[unitId].drTrackers) do
        self:HideTracker(unitId, drCategory)
    end

    local unitGUID = UnitGUID(unitId)
    -- Puis on affiche les nouveaux
    if unitGUID and self.units[unitGUID] then
        for drCategory, _ in pairs(self.units[unitGUID].drData) do
            self:UpdateTracker(unitId, drCategory)
        end
    end
end

function DRBar:UpdateAllBars()
    for unitId, _ in pairs(self.bars) do
        self:UpdateBar(unitId)
    end
end


-- /drbar

SLASH_DRBAR1 = '/drbar'
SlashCmdList['DRBAR'] = function(message)
    if message == 'testing' then
        DRBar.db.testing = not DRBar.db.testing
    elseif message =='test' then
        DRBar:Test()
    else
        AceConfigDialog = LibStub('AceConfigDialog-3.0')
        AceConfigDialog:Open('DRBar')
    end
end

function DRBar:Test()
    for _, trackedPlayerId in pairs(self.trackedPlayers) do
        local trackedPlayerGUID = UnitGUID(trackedPlayerId)
        if trackedPlayerGUID then
            -- print(trackedPlayerId..' '..trackedPlayerGUID)
            self:HandleFadingAura(trackedPlayerGUID, 408)
            self:HandleFadingAura(trackedPlayerGUID, 8122)
            self:HandleFadingAura(trackedPlayerGUID, 8122)
            self:HandleFadingAura(trackedPlayerGUID, 15487)
            self:HandleFadingAura(trackedPlayerGUID, 15487)
            self:HandleFadingAura(trackedPlayerGUID, 15487)
        end
    end
end

-- Fonctions utilisées pour le menu de configuration

function DRBar:SetDrFactorTextSize(info, value)
    for _, trackedPlayer in pairs(self.trackedPlayers) do
        for drCategory, tracker in pairs(self.bars[trackedPlayer].drTrackers) do
            self:ConfigureText(trackedPlayer, drCategory)
        end
    end
end

function DRBar:ResetBarsPosition()
    self.db.x = {}
    self.db.y = {}
    for _, trackedPlayer in pairs(self.trackedPlayers) do
        self:SetBarPosition(trackedPlayer)
    end
end

function DRBar:ConfigureOptions()
    self.options = {
        type = 'group',
        name = 'DRBar v'..GetAddOnMetadata('DRBar', 'Version'),
        args = {
            parameters = {
                type = 'group',
                name = 'Paramètres',
                desc = 'Paramètres généraux',
                inline = true,
                order = 1,
                args = {
                    resetBarsPosition = {
                        type = 'execute',
                        name = 'Reset les positions',
                        order = 1,
                        func = function()
                            self:ResetBarsPosition()
                        end
                    },
                }
            },
            dev = {
                type = 'group',
                name = 'Développement',
                desc = 'Paramètres de développement',
                inline = true,
                order = 2,
                args = {
                    testing = {
                        type = 'toggle',
                        name = 'Mode Test',
                        desc = 'Simule un DR stun pour chaque buff ou debuff qui fade.',
                        get = function()
                            return self.db.testing
                        end,
                        set = function(info, value)
                            self.db.testing = value
                        end
                    },
                }
            },
        }
    }

    local barSections = {
        player = 'Joueur',
        target = 'Cible',
        focus = 'Focus',
        raid = 'Groupe',
    }

    for sectionId, sectionName in pairs(barSections) do
        local section = {
            type = 'group',
            name = sectionName,
            desc = sectionName,
            inline = true,
            args = {
                trackerSize = {
                    type = 'range',
                    name = 'Taille des icônes',
                    desc = 'Taille des icônes',
                    min = 10,
                    max = 200,
                    step = 1,
                    order = 1,
                    get = function()
                        return self.db.trackerSize[sectionId]
                    end,
                    set = function(info, value)
                        self.db.trackerSize[sectionId] = value
                        self:UpdateAllBars()
                    end
                },
                drFactorTextSize = {
                    type = 'range',
                    name = 'Taille de la force du DR',
                    desc = 'Taille du texte qui indique la force du DR (0.5, 0.25, 0)',
                    min = 2,
                    max = 48,
                    step = 1,
                    order = 2,
                    get = function()
                        return self.db.drFactorTextSize[sectionId]
                    end,
                    set = function(info, value)
                        self.db.drFactorTextSize[sectionId] = value
                        self:SetDrFactorTextSize(info, value)
                    end
                },
            }
        }
        self.options.args.parameters.args[sectionId] = section
    end

    LibStub('AceConfig-3.0'):RegisterOptionsTable('DRBar', self.options)
    LibStub('AceConfigDialog-3.0'):AddToBlizOptions('DRBar', 'DRBar')
end
