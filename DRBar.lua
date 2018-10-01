local DRData = LibStub('DRData-1.0')


DRBar = {}
DRBar.eventHandler = CreateFrame('Frame')
DRBar.eventHandler.events = {}

DRBar.defaults = {
    profile = {
        trackerSize = 50,
        testing = false,
        drFactorTextSize = 10,
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

function DRBar:OnInitialize()
    self.globalDb = LibStub('AceDB-3.0'):New('DRBarDB', self.defaults)
    self.db = self.globalDb.profile

    if self.db.testing then
        print('On Initialize')
    end

    self:CreateBar()
    self:ConfigureOptions()
end

function DRBar:CreateBar()
    self.bar = CreateFrame('Frame', 'DRBarBar', UIParent, 'ActionButtonTemplate')
    self.bar.drTrackers = {}

    self:SetBarSize()

    if not self.db.x or not self.db.y then
        self.bar:SetPoint('CENTER')
    else
        self.bar:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', self.db.x, self.db.y)
    end

    self.bar:SetMovable(true)
    self.bar:EnableMouse(true)
    self.bar:SetClampedToScreen(true)
    self.bar:RegisterForDrag('LeftButton')
    self.bar:SetScript('OnDragStart', self.bar.StartMoving)
    self.bar:SetScript('OnDragStop', function(frame)
        frame:StopMovingOrSizing()
        self.db.x = frame:GetLeft()
        self.db.y = frame:GetTop()
    end)
end

function DRBar:SetBarSize()
    local width = 0
    for drCategory, tracker in pairs(self.bar.drTrackers) do
        if tracker.active then
            width = width + tracker:GetWidth()
        end
    end
    -- print('Bar width : '..self.bar:GetWidth())
    self.bar:SetSize(width, self.db.trackerSize)

    for drCategory, tracker in pairs(self.bar.drTrackers) do
        self:ConfigureIcon(drCategory)
    end
end

function DRBar:OnEnable()
    if self.db.testing then
        print('On Enable')
    end
    self:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
end

function DRBar:COMBAT_LOG_EVENT_UNFILTERED(event)
    self:HandleCombatLogEvent(event, CombatLogGetCurrentEventInfo())
end

function DRBar:HandleCombatLogEvent(event, timestamp, eventType, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellID, spellName, spellSchool, auraType)
    if UnitGUID('player') ~= destGUID then
        return
    end
    -- print(string.format('player event : %s', eventType))

    if eventType == 'SPELL_AURA_REMOVED' or eventType == 'SPELL_AURA_REFRESH' then
        self:HandleFadingAura(spellID)
    end
end

function DRBar:HandleFadingAura(spellID)
    --print(string.format('Handling CC : %d', spellID))
    local drCategory = DRData:GetSpellCategory(spellID)

    if not self.db.testing and not drCategory then
        return
    end

    -- Pour les tests...
    if self.db.testing  and not drCategory then
        if spellID == 21562 then
            drCategory = 'disorient'
        else
            drCategory = 'stun'
        end
    end

    self:ShowTracker(drCategory, spellID)
    self:StartTracker(drCategory)
end

-- SpellID est utilisé pour l'icône, ce serait une bonne
-- idée de trouver un autre moyen de la récuprérer
function DRBar:ShowTracker(drCategory, spellID)
    -- Crée le tracker pour drCategory s'il n'existe pas
    if not self.bar.drTrackers[drCategory] then
        self.bar.drTrackers[drCategory] = CreateFrame('CheckButton', 'DRBarDR'..drCategory, self.bar, 'ActionButtonTemplate')
    end

    -- Configure le tracker
    local tracker = self.bar.drTrackers[drCategory]
    tracker.drCategory = drCategory
    tracker.spellID = spellID
    tracker.active = true
    tracker:Show()
    tracker.resetTime = tracker.resetTime or 0
    if not tracker.drFactor or tracker.resetTime <= GetTime() then
        tracker.drFactor = 1.0
    else
        tracker.drFactor = DRData:NextDR(tracker.drFactor, drCategory)
    end

    self:ConfigureIcon(drCategory)
    self:ConfigureCooldown(drCategory)
    self:ConfigureText(drCategory)
    self:SetBarSize()
    self:SetIconsPositions()

end

function DRBar:ConfigureIcon(drCategory)
    local tracker = self.bar.drTrackers[drCategory]

    tracker:EnableMouse(false)

    local size = self.bar:GetHeight()
    tracker:SetSize(size, size)
    tracker:SetPoint('LEFT')

    if not tracker.texture then
        tracker.texture = tracker:CreateTexture()
        tracker.texture:SetAllPoints()
    end

    local icon = select(3, GetSpellInfo(tracker.spellID))
    tracker.texture:SetTexture(icon)
end

function DRBar:ConfigureCooldown(drCategory)
    local tracker = self.bar.drTrackers[drCategory]

    if not tracker.cooldown.custom then
        tracker.cooldown = CreateFrame('Cooldown', tracker:GetName()..'Cooldown', tracker, 'CooldownFrameTemplate')
        tracker.cooldown.custom = true
        --tracker.cooldown:SetAllPoints()
    end
end

function DRBar:ConfigureText(drCategory)
    local tracker = self.bar.drTrackers[drCategory]
    
    if not tracker.fontString then
        tracker.fontString = tracker:CreateFontString(tracker:GetName()..'FontString', 'OVERLAY')
        tracker.fontString:SetPoint('LEFT')
        tracker.fontString:SetPoint('RIGHT')
        tracker.fontString:SetPoint('BOTTOM', tracker, 0, 3)
    end

    tracker.fontString:SetFont(STANDARD_TEXT_FONT, self.db.drFactorTextSize, 'OUTLINE')

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

function DRBar:SetIconsPositions()
    local relativeTo = self.bar

    for drCategory, tracker in pairs(self.bar.drTrackers) do
        tracker:ClearAllPoints()
        if tracker.active then
            if relativeTo == self.bar then
                tracker:SetPoint('LEFT', relativeTo, 'LEFT')
            else
                tracker:SetPoint('LEFT', relativeTo, 'RIGHT')
            end
            relativeTo = tracker
        end
    end
end

function DRBar:StartTracker(drCategory)
    local tracker = self.bar.drTrackers[drCategory]
    -- Lance le tracker
    tracker.startTime = GetTime()
    tracker.resetTime = tracker.startTime + DRData:GetResetTime()
    -- print(GetTime()..' Start of DR '..tracker.drCategory..' with factor '..tracker.drFactor)
    tracker:SetScript('OnUpdate', function(this, elapsed)
        if GetTime() - this.startTime > DRData:GetResetTime() then
            -- print(GetTime()..' End of DR '..tracker.drCategory)
            this:SetScript('OnUpdate', nil)
            self:HideTracker(drCategory)
        end
    end)
    tracker.cooldown:SetCooldown(GetTime(), DRData:GetResetTime())

end

function DRBar:HideTracker(drCategory)
    local tracker = self.bar.drTrackers[drCategory]
    tracker.active = false
    tracker:Hide()
    self:SetBarSize()
    self:SetIconsPositions()
end

function DRBar:Test()
    self:HandleFadingAura(408)
    self:HandleFadingAura(8122)
    self:HandleFadingAura(8122)
    self:HandleFadingAura(15487)
    self:HandleFadingAura(15487)
    self:HandleFadingAura(15487)
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
                    trackerSize = {
                        type = 'range',
                        name = 'Taille des icônes',
                        desc = 'Taille des icônes',
                        min = 10,
                        max = 200,
                        step = 1,
                        order = 1,
                        get = function()
                            return self.db.trackerSize
                        end,
                        set = function(info, value)
                            --[[print(info)
                            for k, v in pairs(info) do
                                print(k)
                                print(v)
                            end
                            print(value)]]--
                            self.db.trackerSize = value
                            self:SetBarSize()
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
                            return self.db.drFactorTextSize
                        end,
                        set = function(info, value)
                            self.db.drFactorTextSize = value
                            for drCategory, tracker in pairs(self.bar.drTrackers) do
                                self:ConfigureText(drCategory)
                            end
                        end
                    }
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

    LibStub('AceConfig-3.0'):RegisterOptionsTable('DRBar', self.options)
    LibStub('AceConfigDialog-3.0'):AddToBlizOptions('DRBar', 'DRBar')
end


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