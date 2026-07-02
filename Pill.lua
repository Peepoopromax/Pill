-- // PILGRAMMED ORE MINER + AUTO PARRY + MOB FARMER
-- // LocalScript inside StarterPlayerScripts
-- // Restructured: UI always created outside pcall, logic wrapped in pcall
-- // Bug fix: If logic code errors, UI content (sidebar, pages, buttons) still appears

print("[Pilgrammed] Script starting...")

-- // SERVICES
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- // CONFIG
local SWING_INTERVAL = 0.3
local FLY_OFFSET = Vector3.new(0, -3, 0)
local ORES_FOLDER_NAME = "Ores"
local PARRY_RANGE = 40
local PARRY_PRE_BLOCK = 0.08
local PARRY_HOLD_TIME = 0.5
local PARRY_COOLDOWN = 0.2
local MOB_ATTACK_INTERVAL = 0.4
local MOB_FLY_OFFSET = Vector3.new(0, -3, 0)
local MOB_DISTANCE = 5

-- // LAG OPTIMIZATION CONSTANTS
local MOB_REFRESH_DEBOUNCE = 1.5      -- min seconds between mob list refreshes
local NPC_SCAN_INTERVAL = 15          -- fallback NPC scan (now event-driven, this is just backup)
local NOCLIP_REFRESH_INTERVAL = 0.5   -- re-cache character parts every 0.5s
local MOB_NAME_CACHE_TTL = 3          -- cache getAllMobsOfName results for 3s

-- // AUTO DEPOSIT GOLD CONFIG
local AUTO_DEPOSIT_THRESHOLD = 1      -- (deprecated, kept for compat)
local AUTO_DEPOSIT_COOLDOWN = 2       -- min seconds between deposits (adjustable in UI)

-- // ATTACK POSITION CONFIG (for both mob farm and camp farm)
-- Options: "below" | "above" | "behind" | "front" | "custom"
local ATTACK_POSITION = "below"
local BELOW_DISTANCE = 3          -- studs below mob (adjustable in UI)
local ABOVE_DISTANCE = 3          -- studs above mob (adjustable in UI)
local BEHIND_DISTANCE = 4          -- studs behind/front of mob (adjustable in UI)
local CUSTOM_OFFSET = Vector3.new(0, -3, 0)  -- custom offset for "custom" position

-- // MOB BLACKLIST: mobs that will never be detected, targeted, or TP'd to
local MOB_BLACKLIST = {
        ["Museum Guard"] = true,
}

-- // STATE
local State = {
        autoFarming = false,
        selectedOres = {},
        currentOreQueue = {},
        currentOreQueueIndex = 1,
        currentPartIndex = 1,
        currentPart = nil,
        equippedPickaxe = nil,
        swingConnection = nil,
        flyConnection = nil,
        oreWatchConnection = nil,
        respawnConnection = nil,
        noclipConnection = nil,
        toggleSquareMoveable = false,
        autoParry = false,
        parryConnection = nil,
        parryHealthConn = nil,
        npcWatchConn = nil,
        npcScanThread = nil,
        attackWarningConn = nil,
        lastHealth = 0,
        maxHealth = 100,
        isBlocking = false,
        parryCount = 0,
        -- Mob farming
        autoMobFarming = false,
        selectedMobs = {},
        currentMobQueue = {},
        currentMobQueueIndex = 1,
        currentMob = nil,
        mobMainConnection = nil,  -- single Heartbeat for fly+attack+respawn
        mobWatchConnection = nil,
        mobNoclipConn = nil,
        equippedWeapon = nil,
        lastEquippedWeaponName = nil,
        attackTypes = {true, false, false}, -- [1]=light, [2]=heavy, [3]=technique
        currentAttackType = 1,
        -- Optimization caches
        noclipPartsCache = {},
        noclipCacheChar = nil,
        noclipLastRefresh = 0,
        mobCache = {},         -- [mobName] = {time=..., mobs={...}}
        lastMobRefresh = 0,
        -- Auto Deposit Gold
        autoDepositGold = false,
        goldConn = nil,
        lastGoldValue = 0,
        lastDepositTime = 0,
        -- Event-based mob spawn detection for parry
        mobSpawnConns = {},   -- array of ChildAdded connections on mob area folders
        -- Camp Farm
        autoCampFarming = false,
        campPoint = nil,         -- Vector3 of saved position
        campRadius = 30,         -- studs
        campCirclePart = nil,    -- visual Part showing the radius
        campMainConn = nil,      -- single Heartbeat for fly+attack+return
        campNoclipConn = nil,
        campTargetMob = nil,
        campLastAttack = 0,
        campWeaponName = nil,
        -- Spam Parry
        spamParry = false,
        spamParryLength = 0.3,   -- seconds to hold block before toggling
        spamParryThread = nil,
        -- Junkpits: Crono's Challenge Key Collect
        autoCronoKey = false,
        cronoThread = nil,
        -- Junkpits: Auto Delete Enemies/Killbricks
        autoDeleteEnemies = false,
        deleteThread = nil,
        deleteConns = {},       -- ChildAdded connections for auto-delete
        -- Auto Bow Shoot
        autoBow = false,
        bowShootRate = 0.1,     -- seconds between shots
        bowName = "Prism Bow",
        bowThread = nil,
        -- Auto Fishing
        autoFish = false,
        fishDiscovery = false,
        fishRodName = "Rod of Kings",
        fishThread = nil,
        fishConns = {},
        fishLastBite = 0,
        fishWaitSeconds = 1.4,       -- seconds to wait after casting before attempting to catch
        -- Auto Rifts
        autoRifts = false,
        riftsThread = nil,
        riftsConns = {},
        riftsRadius = 1000,
        riftsCurrentIndex = 1,
        riftsMessageConn = nil,
        riftsActivationMode = "mobile",  -- "mobile" (tap screen 2x) or "desktop" (hold G)
}

-- // FORWARD DECLARATIONS (set by logic code inside pcall, used by early UI handlers)
local refreshOreList
local refreshMobList

-- ================================================================
-- // SECTION 1: EARLY UI (NO PCALL — always works even if rest crashes)
-- ================================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "OreMinerGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui

local ToggleButton = Instance.new("TextButton")
ToggleButton.Name = "ToggleButton"
ToggleButton.Size = UDim2.new(0, 50, 0, 50)
ToggleButton.Position = UDim2.new(1, -70, 0, 20)
ToggleButton.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
ToggleButton.BorderSizePixel = 0
ToggleButton.Text = "[M]"
ToggleButton.TextColor3 = Color3.fromRGB(200, 220, 255)
ToggleButton.TextScaled = true
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.AutoButtonColor = false
ToggleButton.ZIndex = 100
ToggleButton.Parent = ScreenGui

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = ToggleButton
end

local ToggleStroke = Instance.new("UIStroke")
ToggleStroke.Color = Color3.fromRGB(100, 180, 255)
ToggleStroke.Thickness = 1.5
ToggleStroke.Parent = ToggleButton

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 420, 0, 480)
MainFrame.Position = UDim2.new(0.5, -210, 0.5, -240)
MainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Visible = false
MainFrame.ZIndex = 50
MainFrame.Parent = ScreenGui

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 12)
        corner.Parent = MainFrame
end

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(80, 140, 255)
MainStroke.Thickness = 1.5
MainStroke.Parent = MainFrame

-- Mobile: Toggle via button click
ToggleButton.MouseButton1Click:Connect(function()
        MainFrame.Visible = not MainFrame.Visible
        if MainFrame.Visible then
                pcall(function() if refreshOreList then refreshOreList() end end)
                pcall(function() if refreshMobList then refreshMobList() end end)
        end
end)

-- Desktop: Toggle via M key
UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == Enum.KeyCode.M then
                MainFrame.Visible = not MainFrame.Visible
                if MainFrame.Visible then
                        pcall(function() if refreshOreList then refreshOreList() end end)
                        pcall(function() if refreshMobList then refreshMobList() end end)
                end
        end
end)

print("[Pilgrammed] Toggle UI ready!")

-- ================================================================
-- // SECTION 2: ALL UI ELEMENTS (NO PCALL — always created)
-- ================================================================

-- Title bar
local TitleBar = Instance.new("Frame")
TitleBar.Name = "TitleBar"
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(25, 25, 38)
TitleBar.BorderSizePixel = 0
TitleBar.ZIndex = 2
TitleBar.Parent = MainFrame

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 12)
        corner.Parent = TitleBar
end

local TitleBarFix = Instance.new("Frame")
TitleBarFix.Size = UDim2.new(1, 0, 0, 12)
TitleBarFix.Position = UDim2.new(0, 0, 1, -12)
TitleBarFix.BackgroundColor3 = Color3.fromRGB(25, 25, 38)
TitleBarFix.BorderSizePixel = 0
TitleBarFix.ZIndex = 2
TitleBarFix.Parent = TitleBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -60, 1, 0)
TitleLabel.Position = UDim2.new(0, 12, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "Pilgrammed Miner V2"
TitleLabel.TextColor3 = Color3.fromRGB(180, 210, 255)
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextSize = 15
TitleLabel.ZIndex = 3
TitleLabel.Parent = TitleBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -34, 0.5, -14)
CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 13
CloseBtn.BorderSizePixel = 0
CloseBtn.ZIndex = 4
CloseBtn.Parent = TitleBar

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = CloseBtn
end

-- Close button handler (always works)
CloseBtn.MouseButton1Click:Connect(function()
        MainFrame.Visible = false
end)

-- LEFT SIDEBAR
local Sidebar = Instance.new("Frame")
Sidebar.Name = "Sidebar"
Sidebar.Size = UDim2.new(0, 90, 1, -36)
Sidebar.Position = UDim2.new(0, 0, 0, 36)
Sidebar.BackgroundColor3 = Color3.fromRGB(22, 22, 32)
Sidebar.BorderSizePixel = 0
Sidebar.Parent = MainFrame

local SidebarLayout = Instance.new("UIListLayout")
SidebarLayout.Padding = UDim.new(0, 6)
SidebarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
SidebarLayout.VerticalAlignment = Enum.VerticalAlignment.Top
SidebarLayout.Parent = Sidebar

local SidebarPadding = Instance.new("UIPadding")
SidebarPadding.PaddingTop = UDim.new(0, 10)
SidebarPadding.Parent = Sidebar

-- CONTENT AREA
local ContentArea = Instance.new("Frame")
ContentArea.Name = "ContentArea"
ContentArea.Size = UDim2.new(1, -90, 1, -36)
ContentArea.Position = UDim2.new(0, 90, 0, 36)
ContentArea.BackgroundTransparency = 1
ContentArea.ClipsDescendants = true
ContentArea.Parent = MainFrame

-- PAGE SYSTEM
local Pages = {}

local function createSidebarButton(name, icon)
        local btn = Instance.new("TextButton")
        btn.Name = name .. "Btn"
        btn.Size = UDim2.new(0, 74, 0, 50)
        btn.BackgroundColor3 = Color3.fromRGB(30, 30, 44)
        btn.BorderSizePixel = 0
        btn.Text = icon .. "\n" .. name
        btn.TextColor3 = Color3.fromRGB(160, 180, 220)
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 10
        btn.AutoButtonColor = false
        btn.Parent = Sidebar
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 8)
        c.Parent = btn
        return btn
end

local function setActiveSidebarBtn(activeBtn, allBtns)
        for _, b in ipairs(allBtns) do
                b.BackgroundColor3 = Color3.fromRGB(30, 30, 44)
                b.TextColor3 = Color3.fromRGB(160, 180, 220)
        end
        activeBtn.BackgroundColor3 = Color3.fromRGB(50, 90, 180)
        activeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
end

local function showPage(pageName)
        for name, frame in pairs(Pages) do
                frame.Visible = (name == pageName)
        end
end

-- DRAGGING (always works)
-- One shared InputChanged listener instead of one per draggable - prevents connection leak
local _dragTargets = {}
UserInputService.InputChanged:Connect(function(input)
        for _, d in ipairs(_dragTargets) do
                if input == d.dragInput and d.dragging then
                        local delta = input.Position - d.dragStart
                        d.targetFrame.Position = UDim2.new(
                                d.startPos.X.Scale, d.startPos.X.Offset + delta.X,
                                d.startPos.Y.Scale, d.startPos.Y.Offset + delta.Y
                        )
                end
        end
end)

local function makeDraggable(dragHandle, targetFrame, canMoveCheck)
        local d = {dragging=false, dragStart=nil, startPos=nil, dragInput=nil, targetFrame=targetFrame}
        table.insert(_dragTargets, d)
        dragHandle.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                        or input.UserInputType == Enum.UserInputType.Touch then
                        if canMoveCheck and not canMoveCheck() then return end
                        d.dragging = true
                        d.dragStart = input.Position
                        d.startPos = targetFrame.Position
                        input.Changed:Connect(function()
                                if input.UserInputState == Enum.UserInputState.End then
                                        d.dragging = false
                                end
                        end)
                end
        end)
        dragHandle.InputChanged:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseMovement
                        or input.UserInputType == Enum.UserInputType.Touch then
                        d.dragInput = input
                end
        end)
end

makeDraggable(TitleBar, MainFrame, nil)

-- Show UI on load
MainFrame.Visible = true

-- // PLAYER PAGE
local PlayerPage = Instance.new("ScrollingFrame")
PlayerPage.Name = "PlayerPage"
PlayerPage.Size = UDim2.new(1, 0, 1, 0)
PlayerPage.BackgroundTransparency = 1
PlayerPage.Visible = true
PlayerPage.ScrollBarThickness = 4
PlayerPage.ScrollBarImageColor3 = Color3.fromRGB(100, 180, 255)
PlayerPage.CanvasSize = UDim2.new(0, 0, 0, 560)
PlayerPage.AutomaticCanvasSize = Enum.AutomaticSize.Y
PlayerPage.Parent = ContentArea
Pages["Player"] = PlayerPage

local PlayerPagePad = Instance.new("UIPadding")
PlayerPagePad.PaddingLeft = UDim.new(0, 14)
PlayerPagePad.PaddingTop = UDim.new(0, 14)
PlayerPagePad.PaddingRight = UDim.new(0, 14)
PlayerPagePad.Parent = PlayerPage

local PlayerTitle = Instance.new("TextLabel")
PlayerTitle.Size = UDim2.new(1, 0, 0, 24)
PlayerTitle.BackgroundTransparency = 1
PlayerTitle.Text = "Player"
PlayerTitle.TextColor3 = Color3.fromRGB(180, 210, 255)
PlayerTitle.TextXAlignment = Enum.TextXAlignment.Left
PlayerTitle.Font = Enum.Font.GothamBold
PlayerTitle.TextSize = 15
PlayerTitle.Parent = PlayerPage

-- Auto Parry Section
local ParryLabel = Instance.new("TextLabel")
ParryLabel.Size = UDim2.new(1, 0, 0, 20)
ParryLabel.Position = UDim2.new(0, 0, 0, 34)
ParryLabel.BackgroundTransparency = 1
ParryLabel.Text = "Auto Parry - blocks enemy attacks automatically"
ParryLabel.TextXAlignment = Enum.TextXAlignment.Left
ParryLabel.Font = Enum.Font.Gotham
ParryLabel.TextSize = 12
ParryLabel.TextWrapped = true
ParryLabel.Parent = PlayerPage

local AutoParryBtn = Instance.new("TextButton")
AutoParryBtn.Size = UDim2.new(1, 0, 0, 36)
AutoParryBtn.Position = UDim2.new(0, 0, 0, 60)
AutoParryBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 180)
AutoParryBtn.BorderSizePixel = 0
AutoParryBtn.Text = "Auto Parry: OFF"
AutoParryBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
AutoParryBtn.Font = Enum.Font.GothamBold
AutoParryBtn.TextSize = 14
AutoParryBtn.AutoButtonColor = false
AutoParryBtn.Parent = PlayerPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = AutoParryBtn
end

local ParryInfo = Instance.new("TextLabel")
ParryInfo.Size = UDim2.new(1, 0, 0, 30)
ParryInfo.Position = UDim2.new(0, 0, 0, 100)
ParryInfo.BackgroundTransparency = 1
ParryInfo.Text = "2-Layer: AttackWarning remote + Animations"
ParryInfo.TextColor3 = Color3.fromRGB(90, 100, 130)
ParryInfo.TextXAlignment = Enum.TextXAlignment.Left
ParryInfo.Font = Enum.Font.Gotham
ParryInfo.TextSize = 10
ParryInfo.TextWrapped = true
ParryInfo.Parent = PlayerPage

local ParryHoldLabel = Instance.new("TextLabel")
ParryHoldLabel.Size = UDim2.new(0, 180, 0, 28)
ParryHoldLabel.Position = UDim2.new(0, 0, 0, 140)
ParryHoldLabel.BackgroundTransparency = 1
ParryHoldLabel.Text = "Hold: 0.5s | Cooldown: 0.2s"
ParryHoldLabel.TextColor3 = Color3.fromRGB(160, 180, 220)
ParryHoldLabel.TextXAlignment = Enum.TextXAlignment.Left
ParryHoldLabel.Font = Enum.Font.Gotham
ParryHoldLabel.TextSize = 13
ParryHoldLabel.Parent = PlayerPage

local ParryStatus = Instance.new("TextLabel")
ParryStatus.Size = UDim2.new(1, 0, 0, 18)
ParryStatus.Position = UDim2.new(0, 0, 0, 170)
ParryStatus.BackgroundTransparency = 1
ParryStatus.Text = "Status: Idle"
ParryStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
ParryStatus.TextXAlignment = Enum.TextXAlignment.Left
ParryStatus.Font = Enum.Font.Gotham
ParryStatus.TextSize = 11
ParryStatus.Parent = PlayerPage

-- Spam Parry section
local SpamParryDivider = Instance.new("Frame")
SpamParryDivider.Size = UDim2.new(1, 0, 0, 1)
SpamParryDivider.Position = UDim2.new(0, 0, 0, 196)
SpamParryDivider.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
SpamParryDivider.BorderSizePixel = 0
SpamParryDivider.Parent = PlayerPage

local SpamParryLabel = Instance.new("TextLabel")
SpamParryLabel.Size = UDim2.new(1, 0, 0, 20)
SpamParryLabel.Position = UDim2.new(0, 0, 0, 202)
SpamParryLabel.BackgroundTransparency = 1
SpamParryLabel.Text = "Spam Parry - holds & releases block in a loop"
SpamParryLabel.TextXAlignment = Enum.TextXAlignment.Left
SpamParryLabel.Font = Enum.Font.Gotham
SpamParryLabel.TextSize = 12
SpamParryLabel.TextWrapped = true
SpamParryLabel.Parent = PlayerPage

local SpamParryBtn = Instance.new("TextButton")
SpamParryBtn.Size = UDim2.new(1, 0, 0, 34)
SpamParryBtn.Position = UDim2.new(0, 0, 0, 226)
SpamParryBtn.BackgroundColor3 = Color3.fromRGB(120, 60, 160)
SpamParryBtn.BorderSizePixel = 0
SpamParryBtn.Text = "Spam Parry: OFF"
SpamParryBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
SpamParryBtn.Font = Enum.Font.GothamBold
SpamParryBtn.TextSize = 14
SpamParryBtn.AutoButtonColor = false
SpamParryBtn.Parent = PlayerPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = SpamParryBtn
end

-- Spam parry length adjuster
local SpamParryLenLabel = Instance.new("TextLabel")
SpamParryLenLabel.Size = UDim2.new(0, 180, 0, 28)
SpamParryLenLabel.Position = UDim2.new(0, 0, 0, 264)
SpamParryLenLabel.BackgroundTransparency = 1
SpamParryLenLabel.Text = "Hold length: 0.3s"
SpamParryLenLabel.TextColor3 = Color3.fromRGB(160, 180, 220)
SpamParryLenLabel.TextXAlignment = Enum.TextXAlignment.Left
SpamParryLenLabel.Font = Enum.Font.Gotham
SpamParryLenLabel.TextSize = 13
SpamParryLenLabel.Parent = PlayerPage

local SpamParryDownBtn = Instance.new("TextButton")
SpamParryDownBtn.Size = UDim2.new(0, 36, 0, 24)
SpamParryDownBtn.Position = UDim2.new(0, 186, 0, 267)
SpamParryDownBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
SpamParryDownBtn.BorderSizePixel = 0
SpamParryDownBtn.Text = "-"
SpamParryDownBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
SpamParryDownBtn.Font = Enum.Font.GothamBold
SpamParryDownBtn.TextSize = 14
SpamParryDownBtn.AutoButtonColor = false
SpamParryDownBtn.Parent = PlayerPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = SpamParryDownBtn
end

local SpamParryUpBtn = Instance.new("TextButton")
SpamParryUpBtn.Size = UDim2.new(0, 36, 0, 24)
SpamParryUpBtn.Position = UDim2.new(0, 228, 0, 267)
SpamParryUpBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
SpamParryUpBtn.BorderSizePixel = 0
SpamParryUpBtn.Text = "+"
SpamParryUpBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
SpamParryUpBtn.Font = Enum.Font.GothamBold
SpamParryUpBtn.TextSize = 14
SpamParryUpBtn.AutoButtonColor = false
SpamParryUpBtn.Parent = PlayerPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = SpamParryUpBtn
end

local SpamParryStatus = Instance.new("TextLabel")
SpamParryStatus.Size = UDim2.new(1, 0, 0, 16)
SpamParryStatus.Position = UDim2.new(0, 0, 0, 296)
SpamParryStatus.BackgroundTransparency = 1
SpamParryStatus.Text = "Idle"
SpamParryStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
SpamParryStatus.TextXAlignment = Enum.TextXAlignment.Left
SpamParryStatus.Font = Enum.Font.Gotham
SpamParryStatus.TextSize = 10
SpamParryStatus.Parent = PlayerPage

-- ===== AUTO FISHING SECTION =====
local FishDivider = Instance.new("Frame")
FishDivider.Size = UDim2.new(1, 0, 0, 1)
FishDivider.Position = UDim2.new(0, 0, 0, 316)
FishDivider.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
FishDivider.BorderSizePixel = 0
FishDivider.Parent = PlayerPage

local FishTitle = Instance.new("TextLabel")
FishTitle.Size = UDim2.new(1, 0, 0, 20)
FishTitle.Position = UDim2.new(0, 0, 0, 322)
FishTitle.BackgroundTransparency = 1
FishTitle.Text = "Auto Fishing"
FishTitle.TextColor3 = Color3.fromRGB(100, 220, 180)
FishTitle.TextXAlignment = Enum.TextXAlignment.Left
FishTitle.Font = Enum.Font.GothamBold
FishTitle.TextSize = 13
FishTitle.Parent = PlayerPage

-- Rod name input
local RodNameBox = Instance.new("TextBox")
RodNameBox.Size = UDim2.new(1, 0, 0, 26)
RodNameBox.Position = UDim2.new(0, 0, 0, 346)
RodNameBox.BackgroundColor3 = Color3.fromRGB(28, 28, 40)
RodNameBox.BorderSizePixel = 0
RodNameBox.PlaceholderText = "Rod name (e.g. Rod of Kings)"
RodNameBox.PlaceholderColor3 = Color3.fromRGB(90, 100, 130)
RodNameBox.Text = "Rod of Kings"
RodNameBox.TextColor3 = Color3.fromRGB(220, 230, 255)
RodNameBox.Font = Enum.Font.Gotham
RodNameBox.TextSize = 12
RodNameBox.ClearTextOnFocus = false
RodNameBox.Parent = PlayerPage
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = RodNameBox end
do local p = Instance.new("UIPadding"); p.PaddingLeft = UDim.new(0,8); p.Parent = RodNameBox end

-- Wait time selector (seconds after cast before attempting to catch)
local FishWaitLabel = Instance.new("TextLabel")
FishWaitLabel.Size = UDim2.new(0, 180, 0, 26)
FishWaitLabel.Position = UDim2.new(0, 0, 0, 406)
FishWaitLabel.BackgroundTransparency = 1
FishWaitLabel.Text = "Wait before reel: 1.40 sec"
FishWaitLabel.TextColor3 = Color3.fromRGB(160, 180, 220)
FishWaitLabel.TextXAlignment = Enum.TextXAlignment.Left
FishWaitLabel.Font = Enum.Font.Gotham
FishWaitLabel.TextSize = 12
FishWaitLabel.Parent = PlayerPage

local FishWaitDownBtn = Instance.new("TextButton")
FishWaitDownBtn.Size = UDim2.new(0, 28, 0, 24)
FishWaitDownBtn.Position = UDim2.new(0, 186, 0, 408)
FishWaitDownBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
FishWaitDownBtn.BorderSizePixel = 0
FishWaitDownBtn.Text = "-"
FishWaitDownBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
FishWaitDownBtn.Font = Enum.Font.GothamBold
FishWaitDownBtn.TextSize = 14
FishWaitDownBtn.AutoButtonColor = false
FishWaitDownBtn.Parent = PlayerPage
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = FishWaitDownBtn end

local FishWaitUpBtn = Instance.new("TextButton")
FishWaitUpBtn.Size = UDim2.new(0, 28, 0, 24)
FishWaitUpBtn.Position = UDim2.new(0, 218, 0, 408)
FishWaitUpBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
FishWaitUpBtn.BorderSizePixel = 0
FishWaitUpBtn.Text = "+"
FishWaitUpBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
FishWaitUpBtn.Font = Enum.Font.GothamBold
FishWaitUpBtn.TextSize = 14
FishWaitUpBtn.AutoButtonColor = false
FishWaitUpBtn.Parent = PlayerPage
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = FishWaitUpBtn end

-- Auto Fish toggle button
local AutoFishBtn = Instance.new("TextButton")
AutoFishBtn.Size = UDim2.new(1, 0, 0, 36)
AutoFishBtn.Position = UDim2.new(0, 0, 0, 440)
AutoFishBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 100)
AutoFishBtn.BorderSizePixel = 0
AutoFishBtn.Text = ">  Start Auto Fish"
AutoFishBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
AutoFishBtn.Font = Enum.Font.GothamBold
AutoFishBtn.TextSize = 14
AutoFishBtn.AutoButtonColor = false
AutoFishBtn.Parent = PlayerPage
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,8); c.Parent = AutoFishBtn end

local FishStatus = Instance.new("TextLabel")
FishStatus.Size = UDim2.new(1, 0, 0, 30)
FishStatus.Position = UDim2.new(0, 0, 0, 480)
FishStatus.BackgroundTransparency = 1
FishStatus.Text = "Status: Idle"
FishStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
FishStatus.TextXAlignment = Enum.TextXAlignment.Left
FishStatus.Font = Enum.Font.Gotham
FishStatus.TextSize = 10
FishStatus.TextWrapped = true
FishStatus.Parent = PlayerPage

-- // AUTO PAGE
local AutoPage = Instance.new("Frame")
AutoPage.Name = "AutoPage"
AutoPage.Size = UDim2.new(1, 0, 1, 0)
AutoPage.BackgroundTransparency = 1
AutoPage.Visible = false
AutoPage.Parent = ContentArea
Pages["Auto"] = AutoPage

local AutoPagePadding = Instance.new("UIPadding")
AutoPagePadding.PaddingLeft = UDim.new(0, 12)
AutoPagePadding.PaddingRight = UDim.new(0, 12)
AutoPagePadding.PaddingTop = UDim.new(0, 8)
AutoPagePadding.Parent = AutoPage

local OreLabel = Instance.new("TextLabel")
OreLabel.Size = UDim2.new(1, 0, 0, 20)
OreLabel.BackgroundTransparency = 1
OreLabel.Text = "Select Ores (click to toggle)"
OreLabel.TextColor3 = Color3.fromRGB(140, 170, 220)
OreLabel.TextXAlignment = Enum.TextXAlignment.Left
OreLabel.Font = Enum.Font.GothamBold
OreLabel.TextSize = 13
OreLabel.Parent = AutoPage

local SearchBox = Instance.new("TextBox")
SearchBox.Size = UDim2.new(0.52, 0, 0, 28)
SearchBox.Position = UDim2.new(0, 0, 0, 24)
SearchBox.BackgroundColor3 = Color3.fromRGB(28, 28, 40)
SearchBox.BorderSizePixel = 0
SearchBox.PlaceholderText = "Filter ores..."
SearchBox.PlaceholderColor3 = Color3.fromRGB(90, 100, 130)
SearchBox.TextColor3 = Color3.fromRGB(220, 230, 255)
SearchBox.Font = Enum.Font.Gotham
SearchBox.TextSize = 12
SearchBox.ClearTextOnFocus = false
SearchBox.Parent = AutoPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = SearchBox
end

local SearchPad = Instance.new("UIPadding")
SearchPad.PaddingLeft = UDim.new(0, 8)
SearchPad.Parent = SearchBox

local SelectAllBtn = Instance.new("TextButton")
SelectAllBtn.Size = UDim2.new(0, 72, 0, 28)
SelectAllBtn.Position = UDim2.new(0.52, 6, 0, 24)
SelectAllBtn.BackgroundColor3 = Color3.fromRGB(40, 80, 140)
SelectAllBtn.BorderSizePixel = 0
SelectAllBtn.Text = "Sel All"
SelectAllBtn.TextColor3 = Color3.fromRGB(200, 220, 255)
SelectAllBtn.Font = Enum.Font.GothamBold
SelectAllBtn.TextSize = 10
SelectAllBtn.AutoButtonColor = false
SelectAllBtn.Parent = AutoPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = SelectAllBtn
end

local DeselectAllBtn = Instance.new("TextButton")
DeselectAllBtn.Size = UDim2.new(0, 72, 0, 28)
DeselectAllBtn.Position = UDim2.new(0.52, 82, 0, 24)
DeselectAllBtn.BackgroundColor3 = Color3.fromRGB(80, 50, 50)
DeselectAllBtn.BorderSizePixel = 0
DeselectAllBtn.Text = "Clr All"
DeselectAllBtn.TextColor3 = Color3.fromRGB(200, 180, 180)
DeselectAllBtn.Font = Enum.Font.GothamBold
DeselectAllBtn.TextSize = 10
DeselectAllBtn.AutoButtonColor = false
DeselectAllBtn.Parent = AutoPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = DeselectAllBtn
end

local OreScroll = Instance.new("ScrollingFrame")
OreScroll.Size = UDim2.new(1, 0, 0, 130)
OreScroll.Position = UDim2.new(0, 0, 0, 58)
OreScroll.BackgroundColor3 = Color3.fromRGB(22, 22, 34)
OreScroll.BorderSizePixel = 0
OreScroll.ScrollBarThickness = 4
OreScroll.ScrollBarImageColor3 = Color3.fromRGB(80, 130, 255)
OreScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
OreScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
OreScroll.Parent = AutoPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = OreScroll
end

local OreListLayout = Instance.new("UIListLayout")
OreListLayout.Padding = UDim.new(0, 4)
OreListLayout.Parent = OreScroll

local OreListPad = Instance.new("UIPadding")
OreListPad.PaddingLeft = UDim.new(0, 6)
OreListPad.PaddingRight = UDim.new(0, 6)
OreListPad.PaddingTop = UDim.new(0, 4)
OreListPad.Parent = OreScroll

local SelectedLabel = Instance.new("TextLabel")
SelectedLabel.Size = UDim2.new(1, 0, 0, 20)
SelectedLabel.Position = UDim2.new(0, 0, 0, 192)
SelectedLabel.BackgroundTransparency = 1
SelectedLabel.Text = "Selected: None"
SelectedLabel.TextColor3 = Color3.fromRGB(100, 200, 130)
SelectedLabel.TextXAlignment = Enum.TextXAlignment.Left
SelectedLabel.Font = Enum.Font.Gotham
SelectedLabel.TextSize = 12
SelectedLabel.Parent = AutoPage

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, 0, 0, 18)
StatusLabel.Position = UDim2.new(0, 0, 0, 212)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Status: Idle | Fly: OFF"
StatusLabel.TextColor3 = Color3.fromRGB(140, 150, 180)
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextSize = 11
StatusLabel.Parent = AutoPage

local AutoFarmBtn = Instance.new("TextButton")
AutoFarmBtn.Size = UDim2.new(0.48, 0, 0, 34)
AutoFarmBtn.Position = UDim2.new(0, 0, 0, 234)
AutoFarmBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
AutoFarmBtn.BorderSizePixel = 0
AutoFarmBtn.Text = ">  Auto Farm"
AutoFarmBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
AutoFarmBtn.Font = Enum.Font.GothamBold
AutoFarmBtn.TextSize = 13
AutoFarmBtn.AutoButtonColor = false
AutoFarmBtn.Parent = AutoPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = AutoFarmBtn
end

local AllOresBtn = Instance.new("TextButton")
AllOresBtn.Size = UDim2.new(0.48, 0, 0, 34)
AllOresBtn.Position = UDim2.new(0.52, 0, 0, 234)
AllOresBtn.BackgroundColor3 = Color3.fromRGB(140, 80, 180)
AllOresBtn.BorderSizePixel = 0
AllOresBtn.Text = "[M]  All Ores"
AllOresBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
AllOresBtn.Font = Enum.Font.GothamBold
AllOresBtn.TextSize = 13
AllOresBtn.AutoButtonColor = false
AllOresBtn.Parent = AutoPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = AllOresBtn
end

local LoopInfoLabel = Instance.new("TextLabel")
LoopInfoLabel.Size = UDim2.new(1, 0, 0, 16)
LoopInfoLabel.Position = UDim2.new(0, 0, 0, 272)
LoopInfoLabel.BackgroundTransparency = 1
LoopInfoLabel.Text = "Cycles ores when depleted | Fly + Face ore"
LoopInfoLabel.TextColor3 = Color3.fromRGB(90, 100, 130)
LoopInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
LoopInfoLabel.Font = Enum.Font.Gotham
LoopInfoLabel.TextSize = 10
LoopInfoLabel.Parent = AutoPage

-- // AUTO DEPOSIT GOLD SECTION
local GoldDivider = Instance.new("Frame")
GoldDivider.Size = UDim2.new(1, 0, 0, 1)
GoldDivider.Position = UDim2.new(0, 0, 0, 296)
GoldDivider.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
GoldDivider.BorderSizePixel = 0
GoldDivider.Parent = AutoPage

local GoldTitle = Instance.new("TextLabel")
GoldTitle.Size = UDim2.new(1, 0, 0, 18)
GoldTitle.Position = UDim2.new(0, 0, 0, 302)
GoldTitle.BackgroundTransparency = 1
GoldTitle.Text = "Auto Deposit Gold"
GoldTitle.TextColor3 = Color3.fromRGB(255, 200, 80)
GoldTitle.TextXAlignment = Enum.TextXAlignment.Left
GoldTitle.Font = Enum.Font.GothamBold
GoldTitle.TextSize = 13
GoldTitle.Parent = AutoPage

local AutoDepositBtn = Instance.new("TextButton")
AutoDepositBtn.Size = UDim2.new(0.48, 0, 0, 32)
AutoDepositBtn.Position = UDim2.new(0, 0, 0, 324)
AutoDepositBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
AutoDepositBtn.BorderSizePixel = 0
AutoDepositBtn.Text = "Auto Deposit: OFF"
AutoDepositBtn.TextColor3 = Color3.fromRGB(220, 220, 240)
AutoDepositBtn.Font = Enum.Font.GothamBold
AutoDepositBtn.TextSize = 12
AutoDepositBtn.AutoButtonColor = false
AutoDepositBtn.Parent = AutoPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = AutoDepositBtn
end

-- Threshold label + adjusters
local GoldThresholdLabel = Instance.new("TextLabel")
GoldThresholdLabel.Size = UDim2.new(0, 170, 0, 28)
GoldThresholdLabel.Position = UDim2.new(0, 0, 0, 362)
GoldThresholdLabel.BackgroundTransparency = 1
GoldThresholdLabel.Text = "Cooldown: " .. string.format("%.1f", AUTO_DEPOSIT_COOLDOWN) .. "s"
GoldThresholdLabel.TextColor3 = Color3.fromRGB(160, 180, 220)
GoldThresholdLabel.TextXAlignment = Enum.TextXAlignment.Left
GoldThresholdLabel.Font = Enum.Font.Gotham
GoldThresholdLabel.TextSize = 12
GoldThresholdLabel.Parent = AutoPage

local GoldThreshDownBtn = Instance.new("TextButton")
GoldThreshDownBtn.Size = UDim2.new(0, 32, 0, 24)
GoldThreshDownBtn.Position = UDim2.new(0, 176, 0, 365)
GoldThreshDownBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
GoldThreshDownBtn.BorderSizePixel = 0
GoldThreshDownBtn.Text = "-"
GoldThreshDownBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
GoldThreshDownBtn.Font = Enum.Font.GothamBold
GoldThreshDownBtn.TextSize = 14
GoldThreshDownBtn.AutoButtonColor = false
GoldThreshDownBtn.Parent = AutoPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = GoldThreshDownBtn
end

local GoldThreshUpBtn = Instance.new("TextButton")
GoldThreshUpBtn.Size = UDim2.new(0, 32, 0, 24)
GoldThreshUpBtn.Position = UDim2.new(0, 214, 0, 365)
GoldThreshUpBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
GoldThreshUpBtn.BorderSizePixel = 0
GoldThreshUpBtn.Text = "+"
GoldThreshUpBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
GoldThreshUpBtn.Font = Enum.Font.GothamBold
GoldThreshUpBtn.TextSize = 14
GoldThreshUpBtn.AutoButtonColor = false
GoldThreshUpBtn.Parent = AutoPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = GoldThreshUpBtn
end

local GoldStatus = Instance.new("TextLabel")
GoldStatus.Size = UDim2.new(1, 0, 0, 16)
GoldStatus.Position = UDim2.new(0, 0, 0, 392)
GoldStatus.BackgroundTransparency = 1
GoldStatus.Text = "Status: Idle"
GoldStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
GoldStatus.TextXAlignment = Enum.TextXAlignment.Left
GoldStatus.Font = Enum.Font.Gotham
GoldStatus.TextSize = 10
GoldStatus.Parent = AutoPage

-- // MOB PAGE
local MobPage = Instance.new("ScrollingFrame")
MobPage.Name = "MobPage"
MobPage.Size = UDim2.new(1, 0, 1, 0)
MobPage.BackgroundTransparency = 1
MobPage.Visible = false
MobPage.ClipsDescendants = true
MobPage.ScrollBarThickness = 4
MobPage.ScrollBarImageColor3 = Color3.fromRGB(180, 100, 200)
MobPage.CanvasSize = UDim2.new(0, 0, 0, 820)
MobPage.AutomaticCanvasSize = Enum.AutomaticSize.Y
MobPage.Parent = ContentArea
Pages["Mob"] = MobPage

local MobPagePad = Instance.new("UIPadding")
MobPagePad.PaddingLeft = UDim.new(0, 12)
MobPagePad.PaddingRight = UDim.new(0, 12)
MobPagePad.PaddingTop = UDim.new(0, 8)
MobPagePad.Parent = MobPage

local MobTitle = Instance.new("TextLabel")
MobTitle.Size = UDim2.new(1, 0, 0, 20)
MobTitle.BackgroundTransparency = 1
MobTitle.Text = "Select Mobs (click to toggle)"
MobTitle.TextColor3 = Color3.fromRGB(140, 170, 220)
MobTitle.TextXAlignment = Enum.TextXAlignment.Left
MobTitle.Font = Enum.Font.GothamBold
MobTitle.TextSize = 13
MobTitle.Parent = MobPage

local MobSearchBox = Instance.new("TextBox")
MobSearchBox.Size = UDim2.new(0.52, 0, 0, 26)
MobSearchBox.Position = UDim2.new(0, 0, 0, 24)
MobSearchBox.BackgroundColor3 = Color3.fromRGB(28, 28, 40)
MobSearchBox.BorderSizePixel = 0
MobSearchBox.PlaceholderText = "Filter mobs..."
MobSearchBox.PlaceholderColor3 = Color3.fromRGB(90, 100, 130)
MobSearchBox.TextColor3 = Color3.fromRGB(220, 230, 255)
MobSearchBox.Font = Enum.Font.Gotham
MobSearchBox.TextSize = 12
MobSearchBox.ClearTextOnFocus = false
MobSearchBox.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = MobSearchBox
end

local MobSearchPad = Instance.new("UIPadding")
MobSearchPad.PaddingLeft = UDim.new(0, 8)
MobSearchPad.Parent = MobSearchBox

local MobSelAllBtn = Instance.new("TextButton")
MobSelAllBtn.Size = UDim2.new(0, 72, 0, 26)
MobSelAllBtn.Position = UDim2.new(0.52, 6, 0, 24)
MobSelAllBtn.BackgroundColor3 = Color3.fromRGB(40, 80, 140)
MobSelAllBtn.BorderSizePixel = 0
MobSelAllBtn.Text = "Sel All"
MobSelAllBtn.TextColor3 = Color3.fromRGB(200, 220, 255)
MobSelAllBtn.Font = Enum.Font.GothamBold
MobSelAllBtn.TextSize = 10
MobSelAllBtn.AutoButtonColor = false
MobSelAllBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = MobSelAllBtn
end

local MobClrAllBtn = Instance.new("TextButton")
MobClrAllBtn.Size = UDim2.new(0, 72, 0, 26)
MobClrAllBtn.Position = UDim2.new(0.52, 82, 0, 24)
MobClrAllBtn.BackgroundColor3 = Color3.fromRGB(80, 50, 50)
MobClrAllBtn.BorderSizePixel = 0
MobClrAllBtn.Text = "Clr All"
MobClrAllBtn.TextColor3 = Color3.fromRGB(200, 180, 180)
MobClrAllBtn.Font = Enum.Font.GothamBold
MobClrAllBtn.TextSize = 10
MobClrAllBtn.AutoButtonColor = false
MobClrAllBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = MobClrAllBtn
end

local MobScroll = Instance.new("ScrollingFrame")
MobScroll.Size = UDim2.new(1, 0, 0, 80)
MobScroll.Position = UDim2.new(0, 0, 0, 56)
MobScroll.BackgroundColor3 = Color3.fromRGB(22, 22, 34)
MobScroll.BorderSizePixel = 0
MobScroll.ScrollBarThickness = 4
MobScroll.ScrollBarImageColor3 = Color3.fromRGB(80, 130, 255)
MobScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
MobScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
MobScroll.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = MobScroll
end

local MobListLayout = Instance.new("UIListLayout")
MobListLayout.Padding = UDim.new(0, 4)
MobListLayout.Parent = MobScroll

local MobListPad = Instance.new("UIPadding")
MobListPad.PaddingLeft = UDim.new(0, 6)
MobListPad.PaddingRight = UDim.new(0, 6)
MobListPad.PaddingTop = UDim.new(0, 4)
MobListPad.Parent = MobScroll

local MobSelectedLabel = Instance.new("TextLabel")
MobSelectedLabel.Size = UDim2.new(1, 0, 0, 16)
MobSelectedLabel.Position = UDim2.new(0, 0, 0, 140)
MobSelectedLabel.BackgroundTransparency = 1
MobSelectedLabel.Text = "Selected: None"
MobSelectedLabel.TextColor3 = Color3.fromRGB(100, 200, 130)
MobSelectedLabel.TextXAlignment = Enum.TextXAlignment.Left
MobSelectedLabel.Font = Enum.Font.Gotham
MobSelectedLabel.TextSize = 11
MobSelectedLabel.Parent = MobPage

-- Attack type toggles
local AtkTypeLabel = Instance.new("TextLabel")
AtkTypeLabel.Size = UDim2.new(1, 0, 0, 16)
AtkTypeLabel.Position = UDim2.new(0, 0, 0, 158)
AtkTypeLabel.BackgroundTransparency = 1
AtkTypeLabel.Text = "Attack Types (Mob Farm + Camp Farm):"
AtkTypeLabel.TextColor3 = Color3.fromRGB(160, 180, 220)
AtkTypeLabel.TextXAlignment = Enum.TextXAlignment.Left
AtkTypeLabel.Font = Enum.Font.GothamBold
AtkTypeLabel.TextSize = 11
AtkTypeLabel.Parent = MobPage

local LightBtn = Instance.new("TextButton")
LightBtn.Size = UDim2.new(0.3, 0, 0, 26)
LightBtn.Position = UDim2.new(0, 0, 0, 176)
LightBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
LightBtn.BorderSizePixel = 0
LightBtn.Text = "Light (1)"
LightBtn.TextColor3 = Color3.fromRGB(200, 255, 200)
LightBtn.Font = Enum.Font.GothamBold
LightBtn.TextSize = 11
LightBtn.AutoButtonColor = false
LightBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = LightBtn
end

local HeavyBtn = Instance.new("TextButton")
HeavyBtn.Size = UDim2.new(0.3, -2, 0, 26)
HeavyBtn.Position = UDim2.new(0.33, 0, 0, 176)
HeavyBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
HeavyBtn.BorderSizePixel = 0
HeavyBtn.Text = "Heavy (2)"
HeavyBtn.TextColor3 = Color3.fromRGB(180, 180, 200)
HeavyBtn.Font = Enum.Font.GothamBold
HeavyBtn.TextSize = 11
HeavyBtn.AutoButtonColor = false
HeavyBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = HeavyBtn
end

local TechBtn = Instance.new("TextButton")
TechBtn.Size = UDim2.new(0.3, -2, 0, 26)
TechBtn.Position = UDim2.new(0.66, 0, 0, 176)
TechBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
TechBtn.BorderSizePixel = 0
TechBtn.Text = "Tech (3)"
TechBtn.TextColor3 = Color3.fromRGB(180, 180, 200)
TechBtn.Font = Enum.Font.GothamBold
TechBtn.TextSize = 11
TechBtn.AutoButtonColor = false
TechBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = TechBtn
end

-- Distance
local MobDistLabel = Instance.new("TextLabel")
MobDistLabel.Size = UDim2.new(0, 180, 0, 20)
MobDistLabel.Position = UDim2.new(0, 0, 0, 208)
MobDistLabel.BackgroundTransparency = 1
MobDistLabel.Text = "Below mob: " .. tostring(math.abs(MOB_FLY_OFFSET.Y)) .. " studs"
MobDistLabel.TextColor3 = Color3.fromRGB(160, 180, 220)
MobDistLabel.TextXAlignment = Enum.TextXAlignment.Left
MobDistLabel.Font = Enum.Font.Gotham
MobDistLabel.TextSize = 12
MobDistLabel.Parent = MobPage

local MobDistDownBtn = Instance.new("TextButton")
MobDistDownBtn.Size = UDim2.new(0, 30, 0, 20)
MobDistDownBtn.Position = UDim2.new(0, 186, 0, 208)
MobDistDownBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
MobDistDownBtn.BorderSizePixel = 0
MobDistDownBtn.Text = "-"
MobDistDownBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
MobDistDownBtn.Font = Enum.Font.GothamBold
MobDistDownBtn.TextSize = 13
MobDistDownBtn.AutoButtonColor = false
MobDistDownBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = MobDistDownBtn
end

local MobDistUpBtn = Instance.new("TextButton")
MobDistUpBtn.Size = UDim2.new(0, 30, 0, 20)
MobDistUpBtn.Position = UDim2.new(0, 220, 0, 208)
MobDistUpBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
MobDistUpBtn.BorderSizePixel = 0
MobDistUpBtn.Text = "+"
MobDistUpBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
MobDistUpBtn.Font = Enum.Font.GothamBold
MobDistUpBtn.TextSize = 13
MobDistUpBtn.AutoButtonColor = false
MobDistUpBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = MobDistUpBtn
end

-- Attack speed
local MobAtkLabel = Instance.new("TextLabel")
MobAtkLabel.Size = UDim2.new(0, 180, 0, 20)
MobAtkLabel.Position = UDim2.new(0, 0, 0, 232)
MobAtkLabel.BackgroundTransparency = 1
MobAtkLabel.Text = "Attack Speed: " .. string.format("%.2f", MOB_ATTACK_INTERVAL) .. "s"
MobAtkLabel.TextColor3 = Color3.fromRGB(160, 180, 220)
MobAtkLabel.TextXAlignment = Enum.TextXAlignment.Left
MobAtkLabel.Font = Enum.Font.Gotham
MobAtkLabel.TextSize = 12
MobAtkLabel.Parent = MobPage

local MobAtkDownBtn = Instance.new("TextButton")
MobAtkDownBtn.Size = UDim2.new(0, 30, 0, 20)
MobAtkDownBtn.Position = UDim2.new(0, 186, 0, 232)
MobAtkDownBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
MobAtkDownBtn.BorderSizePixel = 0
MobAtkDownBtn.Text = "-"
MobAtkDownBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
MobAtkDownBtn.Font = Enum.Font.GothamBold
MobAtkDownBtn.TextSize = 13
MobAtkDownBtn.AutoButtonColor = false
MobAtkDownBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = MobAtkDownBtn
end

local MobAtkUpBtn = Instance.new("TextButton")
MobAtkUpBtn.Size = UDim2.new(0, 30, 0, 20)
MobAtkUpBtn.Position = UDim2.new(0, 220, 0, 232)
MobAtkUpBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
MobAtkUpBtn.BorderSizePixel = 0
MobAtkUpBtn.Text = "+"
MobAtkUpBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
MobAtkUpBtn.Font = Enum.Font.GothamBold
MobAtkUpBtn.TextSize = 13
MobAtkUpBtn.AutoButtonColor = false
MobAtkUpBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = MobAtkUpBtn
end

-- Status + buttons
local MobStatusLabel = Instance.new("TextLabel")
MobStatusLabel.Size = UDim2.new(1, 0, 0, 16)
MobStatusLabel.Position = UDim2.new(0, 0, 0, 256)
MobStatusLabel.BackgroundTransparency = 1
MobStatusLabel.Text = "Status: Idle"
MobStatusLabel.TextColor3 = Color3.fromRGB(140, 150, 180)
MobStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
MobStatusLabel.Font = Enum.Font.Gotham
MobStatusLabel.TextSize = 11
MobStatusLabel.Parent = MobPage

local MobFarmBtn = Instance.new("TextButton")
MobFarmBtn.Size = UDim2.new(0.48, 0, 0, 34)
MobFarmBtn.Position = UDim2.new(0, 0, 0, 276)
MobFarmBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
MobFarmBtn.BorderSizePixel = 0
MobFarmBtn.Text = ">  Mob Farm"
MobFarmBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MobFarmBtn.Font = Enum.Font.GothamBold
MobFarmBtn.TextSize = 13
MobFarmBtn.AutoButtonColor = false
MobFarmBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = MobFarmBtn
end

local MobAllBtn = Instance.new("TextButton")
MobAllBtn.Size = UDim2.new(0.48, 0, 0, 34)
MobAllBtn.Position = UDim2.new(0.52, 0, 0, 276)
MobAllBtn.BackgroundColor3 = Color3.fromRGB(140, 80, 180)
MobAllBtn.BorderSizePixel = 0
MobAllBtn.Text = "[M]  All Mobs"
MobAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MobAllBtn.Font = Enum.Font.GothamBold
MobAllBtn.TextSize = 13
MobAllBtn.AutoButtonColor = false
MobAllBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = MobAllBtn
end

-- ================================================================
-- // CAMP FARM SECTION (auto-kill mobs within radius of a set point)
-- ================================================================

local CampDivider = Instance.new("Frame")
CampDivider.Size = UDim2.new(1, 0, 0, 1)
CampDivider.Position = UDim2.new(0, 0, 0, 318)
CampDivider.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
CampDivider.BorderSizePixel = 0
CampDivider.Parent = MobPage

local CampTitle = Instance.new("TextLabel")
CampTitle.Size = UDim2.new(1, 0, 0, 18)
CampTitle.Position = UDim2.new(0, 0, 0, 324)
CampTitle.BackgroundTransparency = 1
CampTitle.Text = "Camp Farm (kill mobs in radius)"
CampTitle.TextColor3 = Color3.fromRGB(255, 160, 200)
CampTitle.TextXAlignment = Enum.TextXAlignment.Left
CampTitle.Font = Enum.Font.GothamBold
CampTitle.TextSize = 13
CampTitle.Parent = MobPage

-- Weapon name input + equip button
local WeaponNameBox = Instance.new("TextBox")
WeaponNameBox.Size = UDim2.new(0.62, 0, 0, 26)
WeaponNameBox.Position = UDim2.new(0, 0, 0, 346)
WeaponNameBox.BackgroundColor3 = Color3.fromRGB(28, 28, 40)
WeaponNameBox.BorderSizePixel = 0
WeaponNameBox.PlaceholderText = "Weapon name (e.g. Sword)"
WeaponNameBox.PlaceholderColor3 = Color3.fromRGB(90, 100, 130)
WeaponNameBox.TextColor3 = Color3.fromRGB(220, 230, 255)
WeaponNameBox.Font = Enum.Font.Gotham
WeaponNameBox.TextSize = 12
WeaponNameBox.ClearTextOnFocus = false
WeaponNameBox.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = WeaponNameBox
end

local WNPad = Instance.new("UIPadding")
WNPad.PaddingLeft = UDim.new(0, 8)
WNPad.Parent = WeaponNameBox

local EquipWeaponBtn = Instance.new("TextButton")
EquipWeaponBtn.Size = UDim2.new(0.36, 0, 0, 26)
EquipWeaponBtn.Position = UDim2.new(0.64, 0, 0, 346)
EquipWeaponBtn.BackgroundColor3 = Color3.fromRGB(60, 100, 160)
EquipWeaponBtn.BorderSizePixel = 0
EquipWeaponBtn.Text = "Equip"
EquipWeaponBtn.TextColor3 = Color3.fromRGB(220, 230, 255)
EquipWeaponBtn.Font = Enum.Font.GothamBold
EquipWeaponBtn.TextSize = 12
EquipWeaponBtn.AutoButtonColor = false
EquipWeaponBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = EquipWeaponBtn
end

-- Set Point button + status
local SetPointBtn = Instance.new("TextButton")
SetPointBtn.Size = UDim2.new(0.48, 0, 0, 28)
SetPointBtn.Position = UDim2.new(0, 0, 0, 378)
SetPointBtn.BackgroundColor3 = Color3.fromRGB(120, 60, 100)
SetPointBtn.BorderSizePixel = 0
SetPointBtn.Text = "Set Point (here)"
SetPointBtn.TextColor3 = Color3.fromRGB(255, 230, 240)
SetPointBtn.Font = Enum.Font.GothamBold
SetPointBtn.TextSize = 12
SetPointBtn.AutoButtonColor = false
SetPointBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = SetPointBtn
end

local ClearPointBtn = Instance.new("TextButton")
ClearPointBtn.Size = UDim2.new(0.48, 0, 0, 28)
ClearPointBtn.Position = UDim2.new(0.52, 0, 0, 378)
ClearPointBtn.BackgroundColor3 = Color3.fromRGB(80, 50, 60)
ClearPointBtn.BorderSizePixel = 0
ClearPointBtn.Text = "Clear Point"
ClearPointBtn.TextColor3 = Color3.fromRGB(220, 200, 210)
ClearPointBtn.Font = Enum.Font.GothamBold
ClearPointBtn.TextSize = 12
ClearPointBtn.AutoButtonColor = false
ClearPointBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = ClearPointBtn
end

-- Radius adjuster
local CampRadiusLabel = Instance.new("TextLabel")
CampRadiusLabel.Size = UDim2.new(0, 180, 0, 20)
CampRadiusLabel.Position = UDim2.new(0, 0, 0, 412)
CampRadiusLabel.BackgroundTransparency = 1
CampRadiusLabel.Text = "Radius: 30 studs"
CampRadiusLabel.TextColor3 = Color3.fromRGB(160, 180, 220)
CampRadiusLabel.TextXAlignment = Enum.TextXAlignment.Left
CampRadiusLabel.Font = Enum.Font.Gotham
CampRadiusLabel.TextSize = 12
CampRadiusLabel.Parent = MobPage

local CampRadiusDownBtn = Instance.new("TextButton")
CampRadiusDownBtn.Size = UDim2.new(0, 30, 0, 20)
CampRadiusDownBtn.Position = UDim2.new(0, 186, 0, 412)
CampRadiusDownBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
CampRadiusDownBtn.BorderSizePixel = 0
CampRadiusDownBtn.Text = "-"
CampRadiusDownBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
CampRadiusDownBtn.Font = Enum.Font.GothamBold
CampRadiusDownBtn.TextSize = 13
CampRadiusDownBtn.AutoButtonColor = false
CampRadiusDownBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = CampRadiusDownBtn
end

local CampRadiusUpBtn = Instance.new("TextButton")
CampRadiusUpBtn.Size = UDim2.new(0, 30, 0, 20)
CampRadiusUpBtn.Position = UDim2.new(0, 220, 0, 412)
CampRadiusUpBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
CampRadiusUpBtn.BorderSizePixel = 0
CampRadiusUpBtn.Text = "+"
CampRadiusUpBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
CampRadiusUpBtn.Font = Enum.Font.GothamBold
CampRadiusUpBtn.TextSize = 13
CampRadiusUpBtn.AutoButtonColor = false
CampRadiusUpBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = CampRadiusUpBtn
end

-- Camp status + start/stop button
local CampStatusLabel = Instance.new("TextLabel")
CampStatusLabel.Size = UDim2.new(1, 0, 0, 16)
CampStatusLabel.Position = UDim2.new(0, 0, 0, 436)
CampStatusLabel.BackgroundTransparency = 1
CampStatusLabel.Text = "Camp: Idle | Point: not set"
CampStatusLabel.TextColor3 = Color3.fromRGB(140, 150, 180)
CampStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
CampStatusLabel.Font = Enum.Font.Gotham
CampStatusLabel.TextSize = 10
CampStatusLabel.Parent = MobPage

local CampFarmBtn = Instance.new("TextButton")
CampFarmBtn.Size = UDim2.new(1, 0, 0, 32)
CampFarmBtn.Position = UDim2.new(0, 0, 0, 456)
CampFarmBtn.BackgroundColor3 = Color3.fromRGB(180, 80, 120)
CampFarmBtn.BorderSizePixel = 0
CampFarmBtn.Text = ">  Start Camp Farm"
CampFarmBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CampFarmBtn.Font = Enum.Font.GothamBold
CampFarmBtn.TextSize = 13
CampFarmBtn.AutoButtonColor = false
CampFarmBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = CampFarmBtn
end

-- Attack position selector (applies to BOTH mob farm and camp farm)
local AtkPosLabel = Instance.new("TextLabel")
AtkPosLabel.Size = UDim2.new(1, 0, 0, 18)
AtkPosLabel.Position = UDim2.new(0, 0, 0, 496)
AtkPosLabel.BackgroundTransparency = 1
AtkPosLabel.Text = "Attack from position:"
AtkPosLabel.TextColor3 = Color3.fromRGB(160, 180, 220)
AtkPosLabel.TextXAlignment = Enum.TextXAlignment.Left
AtkPosLabel.Font = Enum.Font.Gotham
AtkPosLabel.TextSize = 12
AtkPosLabel.Parent = MobPage

-- 5 position buttons (Below / Above / Behind / Front / Custom), each 0.19 wide with 0.01 gaps
local AtkPosBelowBtn = Instance.new("TextButton")
AtkPosBelowBtn.Size = UDim2.new(0.19, 0, 0, 28)
AtkPosBelowBtn.Position = UDim2.new(0, 0, 0, 516)
AtkPosBelowBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
AtkPosBelowBtn.BorderSizePixel = 0
AtkPosBelowBtn.Text = "Below"
AtkPosBelowBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
AtkPosBelowBtn.Font = Enum.Font.GothamBold
AtkPosBelowBtn.TextSize = 10
AtkPosBelowBtn.AutoButtonColor = false
AtkPosBelowBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = AtkPosBelowBtn
end

local AtkPosAboveBtn = Instance.new("TextButton")
AtkPosAboveBtn.Size = UDim2.new(0.19, 0, 0, 28)
AtkPosAboveBtn.Position = UDim2.new(0.20, 0, 0, 516)
AtkPosAboveBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
AtkPosAboveBtn.BorderSizePixel = 0
AtkPosAboveBtn.Text = "Above"
AtkPosAboveBtn.TextColor3 = Color3.fromRGB(220, 220, 240)
AtkPosAboveBtn.Font = Enum.Font.GothamBold
AtkPosAboveBtn.TextSize = 10
AtkPosAboveBtn.AutoButtonColor = false
AtkPosAboveBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = AtkPosAboveBtn
end

local AtkPosBehindBtn = Instance.new("TextButton")
AtkPosBehindBtn.Size = UDim2.new(0.19, 0, 0, 28)
AtkPosBehindBtn.Position = UDim2.new(0.40, 0, 0, 516)
AtkPosBehindBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
AtkPosBehindBtn.BorderSizePixel = 0
AtkPosBehindBtn.Text = "Behind"
AtkPosBehindBtn.TextColor3 = Color3.fromRGB(220, 220, 240)
AtkPosBehindBtn.Font = Enum.Font.GothamBold
AtkPosBehindBtn.TextSize = 10
AtkPosBehindBtn.AutoButtonColor = false
AtkPosBehindBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = AtkPosBehindBtn
end

local AtkPosFrontBtn = Instance.new("TextButton")
AtkPosFrontBtn.Size = UDim2.new(0.19, 0, 0, 28)
AtkPosFrontBtn.Position = UDim2.new(0.60, 0, 0, 516)
AtkPosFrontBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
AtkPosFrontBtn.BorderSizePixel = 0
AtkPosFrontBtn.Text = "Front"
AtkPosFrontBtn.TextColor3 = Color3.fromRGB(220, 220, 240)
AtkPosFrontBtn.Font = Enum.Font.GothamBold
AtkPosFrontBtn.TextSize = 10
AtkPosFrontBtn.AutoButtonColor = false
AtkPosFrontBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = AtkPosFrontBtn
end

local AtkPosCustomBtn = Instance.new("TextButton")
AtkPosCustomBtn.Size = UDim2.new(0.19, 0, 0, 28)
AtkPosCustomBtn.Position = UDim2.new(0.80, 0, 0, 516)
AtkPosCustomBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
AtkPosCustomBtn.BorderSizePixel = 0
AtkPosCustomBtn.Text = "Custom"
AtkPosCustomBtn.TextColor3 = Color3.fromRGB(220, 220, 240)
AtkPosCustomBtn.Font = Enum.Font.GothamBold
AtkPosCustomBtn.TextSize = 10
AtkPosCustomBtn.AutoButtonColor = false
AtkPosCustomBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = AtkPosCustomBtn
end

-- Below/Above distance adjuster (row 1)
local BelowAboveDistLabel = Instance.new("TextLabel")
BelowAboveDistLabel.Size = UDim2.new(0, 180, 0, 20)
BelowAboveDistLabel.Position = UDim2.new(0, 0, 0, 552)
BelowAboveDistLabel.BackgroundTransparency = 1
BelowAboveDistLabel.Text = "Below/Above dist: 3 studs"
BelowAboveDistLabel.TextColor3 = Color3.fromRGB(160, 180, 220)
BelowAboveDistLabel.TextXAlignment = Enum.TextXAlignment.Left
BelowAboveDistLabel.Font = Enum.Font.Gotham
BelowAboveDistLabel.TextSize = 12
BelowAboveDistLabel.Parent = MobPage

local BelowAboveDistDownBtn = Instance.new("TextButton")
BelowAboveDistDownBtn.Size = UDim2.new(0, 30, 0, 20)
BelowAboveDistDownBtn.Position = UDim2.new(0, 186, 0, 552)
BelowAboveDistDownBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
BelowAboveDistDownBtn.BorderSizePixel = 0
BelowAboveDistDownBtn.Text = "-"
BelowAboveDistDownBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
BelowAboveDistDownBtn.Font = Enum.Font.GothamBold
BelowAboveDistDownBtn.TextSize = 13
BelowAboveDistDownBtn.AutoButtonColor = false
BelowAboveDistDownBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = BelowAboveDistDownBtn
end

local BelowAboveDistUpBtn = Instance.new("TextButton")
BelowAboveDistUpBtn.Size = UDim2.new(0, 30, 0, 20)
BelowAboveDistUpBtn.Position = UDim2.new(0, 220, 0, 552)
BelowAboveDistUpBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
BelowAboveDistUpBtn.BorderSizePixel = 0
BelowAboveDistUpBtn.Text = "+"
BelowAboveDistUpBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
BelowAboveDistUpBtn.Font = Enum.Font.GothamBold
BelowAboveDistUpBtn.TextSize = 13
BelowAboveDistUpBtn.AutoButtonColor = false
BelowAboveDistUpBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = BelowAboveDistUpBtn
end

-- Behind/Front distance adjuster (row 2)
local BehindDistLabel = Instance.new("TextLabel")
BehindDistLabel.Size = UDim2.new(0, 180, 0, 20)
BehindDistLabel.Position = UDim2.new(0, 0, 0, 580)
BehindDistLabel.BackgroundTransparency = 1
BehindDistLabel.Text = "Behind/Front dist: 4 studs"
BehindDistLabel.TextColor3 = Color3.fromRGB(160, 180, 220)
BehindDistLabel.TextXAlignment = Enum.TextXAlignment.Left
BehindDistLabel.Font = Enum.Font.Gotham
BehindDistLabel.TextSize = 12
BehindDistLabel.Parent = MobPage

local BehindDistDownBtn = Instance.new("TextButton")
BehindDistDownBtn.Size = UDim2.new(0, 30, 0, 20)
BehindDistDownBtn.Position = UDim2.new(0, 186, 0, 580)
BehindDistDownBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
BehindDistDownBtn.BorderSizePixel = 0
BehindDistDownBtn.Text = "-"
BehindDistDownBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
BehindDistDownBtn.Font = Enum.Font.GothamBold
BehindDistDownBtn.TextSize = 13
BehindDistDownBtn.AutoButtonColor = false
BehindDistDownBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = BehindDistDownBtn
end

local BehindDistUpBtn = Instance.new("TextButton")
BehindDistUpBtn.Size = UDim2.new(0, 30, 0, 20)
BehindDistUpBtn.Position = UDim2.new(0, 220, 0, 580)
BehindDistUpBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
BehindDistUpBtn.BorderSizePixel = 0
BehindDistUpBtn.Text = "+"
BehindDistUpBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
BehindDistUpBtn.Font = Enum.Font.GothamBold
BehindDistUpBtn.TextSize = 13
BehindDistUpBtn.AutoButtonColor = false
BehindDistUpBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = BehindDistUpBtn
end

-- Custom offset input (row 3) - text box where user types "x,y,z"
local CustomOffsetLabel = Instance.new("TextLabel")
CustomOffsetLabel.Size = UDim2.new(1, 0, 0, 16)
CustomOffsetLabel.Position = UDim2.new(0, 0, 0, 608)
CustomOffsetLabel.BackgroundTransparency = 1
CustomOffsetLabel.Text = "Custom offset (x,y,z):"
CustomOffsetLabel.TextColor3 = Color3.fromRGB(160, 180, 220)
CustomOffsetLabel.TextXAlignment = Enum.TextXAlignment.Left
CustomOffsetLabel.Font = Enum.Font.Gotham
CustomOffsetLabel.TextSize = 11
CustomOffsetLabel.Parent = MobPage

local CustomOffsetBox = Instance.new("TextBox")
CustomOffsetBox.Size = UDim2.new(0.62, 0, 0, 24)
CustomOffsetBox.Position = UDim2.new(0, 0, 0, 626)
CustomOffsetBox.BackgroundColor3 = Color3.fromRGB(28, 28, 40)
CustomOffsetBox.BorderSizePixel = 0
CustomOffsetBox.PlaceholderText = "e.g. 10,10,4"
CustomOffsetBox.PlaceholderColor3 = Color3.fromRGB(90, 100, 130)
CustomOffsetBox.Text = "0,-3,0"
CustomOffsetBox.TextColor3 = Color3.fromRGB(220, 230, 255)
CustomOffsetBox.Font = Enum.Font.Gotham
CustomOffsetBox.TextSize = 12
CustomOffsetBox.ClearTextOnFocus = false
CustomOffsetBox.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = CustomOffsetBox
end

local COBPad = Instance.new("UIPadding")
COBPad.PaddingLeft = UDim.new(0, 8)
COBPad.Parent = CustomOffsetBox

local CustomOffsetApplyBtn = Instance.new("TextButton")
CustomOffsetApplyBtn.Size = UDim2.new(0.36, 0, 0, 24)
CustomOffsetApplyBtn.Position = UDim2.new(0.64, 0, 0, 626)
CustomOffsetApplyBtn.BackgroundColor3 = Color3.fromRGB(60, 100, 160)
CustomOffsetApplyBtn.BorderSizePixel = 0
CustomOffsetApplyBtn.Text = "Apply"
CustomOffsetApplyBtn.TextColor3 = Color3.fromRGB(220, 230, 255)
CustomOffsetApplyBtn.Font = Enum.Font.GothamBold
CustomOffsetApplyBtn.TextSize = 12
CustomOffsetApplyBtn.AutoButtonColor = false
CustomOffsetApplyBtn.Parent = MobPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = CustomOffsetApplyBtn
end

-- ===== AUTO BOW SHOOT SECTION =====
local BowDivider = Instance.new("Frame")
BowDivider.Size = UDim2.new(1, 0, 0, 1)
BowDivider.Position = UDim2.new(0, 0, 0, 660)
BowDivider.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
BowDivider.BorderSizePixel = 0
BowDivider.Parent = MobPage

local BowTitle = Instance.new("TextLabel")
BowTitle.Size = UDim2.new(1, 0, 0, 18)
BowTitle.Position = UDim2.new(0, 0, 0, 666)
BowTitle.BackgroundTransparency = 1
BowTitle.Text = "Auto Bow Shoot (aims at selected mobs)"
BowTitle.TextColor3 = Color3.fromRGB(180, 220, 255)
BowTitle.TextXAlignment = Enum.TextXAlignment.Left
BowTitle.Font = Enum.Font.GothamBold
BowTitle.TextSize = 13
BowTitle.Parent = MobPage

-- Bow name input
local BowNameBox = Instance.new("TextBox")
BowNameBox.Size = UDim2.new(0.62, 0, 0, 26)
BowNameBox.Position = UDim2.new(0, 0, 0, 688)
BowNameBox.BackgroundColor3 = Color3.fromRGB(28, 28, 40)
BowNameBox.BorderSizePixel = 0
BowNameBox.PlaceholderText = "Bow name (e.g. Prism Bow)"
BowNameBox.PlaceholderColor3 = Color3.fromRGB(90, 100, 130)
BowNameBox.Text = "Prism Bow"
BowNameBox.TextColor3 = Color3.fromRGB(220, 230, 255)
BowNameBox.Font = Enum.Font.Gotham
BowNameBox.TextSize = 12
BowNameBox.ClearTextOnFocus = false
BowNameBox.Parent = MobPage

do
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = BowNameBox
end
do
        local p = Instance.new("UIPadding")
        p.PaddingLeft = UDim.new(0, 8)
        p.Parent = BowNameBox
end

-- Shoot rate label + adjusters
local BowRateLabel = Instance.new("TextLabel")
BowRateLabel.Size = UDim2.new(0, 180, 0, 20)
BowRateLabel.Position = UDim2.new(0, 0, 0, 720)
BowRateLabel.BackgroundTransparency = 1
BowRateLabel.Text = "Bow Shoot Rate: 0.10s"
BowRateLabel.TextColor3 = Color3.fromRGB(160, 180, 220)
BowRateLabel.TextXAlignment = Enum.TextXAlignment.Left
BowRateLabel.Font = Enum.Font.Gotham
BowRateLabel.TextSize = 12
BowRateLabel.Parent = MobPage

local BowRateDownBtn = Instance.new("TextButton")
BowRateDownBtn.Size = UDim2.new(0, 30, 0, 20)
BowRateDownBtn.Position = UDim2.new(0, 186, 0, 720)
BowRateDownBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
BowRateDownBtn.BorderSizePixel = 0
BowRateDownBtn.Text = "-"
BowRateDownBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
BowRateDownBtn.Font = Enum.Font.GothamBold
BowRateDownBtn.TextSize = 13
BowRateDownBtn.AutoButtonColor = false
BowRateDownBtn.Parent = MobPage

do
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = BowRateDownBtn
end

local BowRateUpBtn = Instance.new("TextButton")
BowRateUpBtn.Size = UDim2.new(0, 30, 0, 20)
BowRateUpBtn.Position = UDim2.new(0, 220, 0, 720)
BowRateUpBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
BowRateUpBtn.BorderSizePixel = 0
BowRateUpBtn.Text = "+"
BowRateUpBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
BowRateUpBtn.Font = Enum.Font.GothamBold
BowRateUpBtn.TextSize = 13
BowRateUpBtn.AutoButtonColor = false
BowRateUpBtn.Parent = MobPage

do
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = BowRateUpBtn
end

-- Start/Stop Auto Bow button
local AutoBowBtn = Instance.new("TextButton")
AutoBowBtn.Size = UDim2.new(1, 0, 0, 34)
AutoBowBtn.Position = UDim2.new(0, 0, 0, 746)
AutoBowBtn.BackgroundColor3 = Color3.fromRGB(80, 100, 160)
AutoBowBtn.BorderSizePixel = 0
AutoBowBtn.Text = ">  Start Auto Bow"
AutoBowBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
AutoBowBtn.Font = Enum.Font.GothamBold
AutoBowBtn.TextSize = 13
AutoBowBtn.AutoButtonColor = false
AutoBowBtn.Parent = MobPage

do
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 8)
        c.Parent = AutoBowBtn
end

local BowStatus = Instance.new("TextLabel")
BowStatus.Size = UDim2.new(1, 0, 0, 16)
BowStatus.Position = UDim2.new(0, 0, 0, 784)
BowStatus.BackgroundTransparency = 1
BowStatus.Text = "Idle"
BowStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
BowStatus.TextXAlignment = Enum.TextXAlignment.Left
BowStatus.Font = Enum.Font.Gotham
BowStatus.TextSize = 10
BowStatus.Parent = MobPage

-- // SETTINGS PAGE
local SettingsPage = Instance.new("Frame")
SettingsPage.Name = "SettingsPage"
SettingsPage.Size = UDim2.new(1, 0, 1, 0)
SettingsPage.BackgroundTransparency = 1
SettingsPage.Visible = false
SettingsPage.Parent = ContentArea
Pages["Settings"] = SettingsPage

local SettingsPad = Instance.new("UIPadding")
SettingsPad.PaddingLeft = UDim.new(0, 14)
SettingsPad.PaddingTop = UDim.new(0, 14)
SettingsPad.Parent = SettingsPage

local SettingsTitle = Instance.new("TextLabel")
SettingsTitle.Size = UDim2.new(1, -14, 0, 24)
SettingsTitle.BackgroundTransparency = 1
SettingsTitle.Text = "Settings"
SettingsTitle.TextColor3 = Color3.fromRGB(180, 210, 255)
SettingsTitle.TextXAlignment = Enum.TextXAlignment.Left
SettingsTitle.Font = Enum.Font.GothamBold
SettingsTitle.TextSize = 15
SettingsTitle.Parent = SettingsPage

local MoveToggleLabel = Instance.new("TextLabel")
MoveToggleLabel.Size = UDim2.new(0, 180, 0, 28)
MoveToggleLabel.Position = UDim2.new(0, 0, 0, 34)
MoveToggleLabel.BackgroundTransparency = 1
MoveToggleLabel.Text = "Toggle Button Moveable"
MoveToggleLabel.TextColor3 = Color3.fromRGB(160, 180, 220)
MoveToggleLabel.TextXAlignment = Enum.TextXAlignment.Left
MoveToggleLabel.Font = Enum.Font.Gotham
MoveToggleLabel.TextSize = 13
MoveToggleLabel.Parent = SettingsPage

local MoveToggleBtn = Instance.new("TextButton")
MoveToggleBtn.Size = UDim2.new(0, 46, 0, 24)
MoveToggleBtn.Position = UDim2.new(0, 186, 0, 37)
MoveToggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
MoveToggleBtn.BorderSizePixel = 0
MoveToggleBtn.Text = "OFF"
MoveToggleBtn.TextColor3 = Color3.fromRGB(180, 180, 200)
MoveToggleBtn.Font = Enum.Font.GothamBold
MoveToggleBtn.TextSize = 11
MoveToggleBtn.AutoButtonColor = false
MoveToggleBtn.Parent = SettingsPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = MoveToggleBtn
end

local SwingLabel = Instance.new("TextLabel")
SwingLabel.Size = UDim2.new(0, 180, 0, 28)
SwingLabel.Position = UDim2.new(0, 0, 0, 68)
SwingLabel.BackgroundTransparency = 1
SwingLabel.Text = "Swing Interval: " .. tostring(SWING_INTERVAL) .. "s"
SwingLabel.TextColor3 = Color3.fromRGB(160, 180, 220)
SwingLabel.TextXAlignment = Enum.TextXAlignment.Left
SwingLabel.Font = Enum.Font.Gotham
SwingLabel.TextSize = 13
SwingLabel.Parent = SettingsPage

local SwingDownBtn = Instance.new("TextButton")
SwingDownBtn.Size = UDim2.new(0, 36, 0, 24)
SwingDownBtn.Position = UDim2.new(0, 186, 0, 71)
SwingDownBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
SwingDownBtn.BorderSizePixel = 0
SwingDownBtn.Text = "-"
SwingDownBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
SwingDownBtn.Font = Enum.Font.GothamBold
SwingDownBtn.TextSize = 14
SwingDownBtn.AutoButtonColor = false
SwingDownBtn.Parent = SettingsPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = SwingDownBtn
end

local SwingUpBtn = Instance.new("TextButton")
SwingUpBtn.Size = UDim2.new(0, 36, 0, 24)
SwingUpBtn.Position = UDim2.new(0, 228, 0, 71)
SwingUpBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
SwingUpBtn.BorderSizePixel = 0
SwingUpBtn.Text = "+"
SwingUpBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
SwingUpBtn.Font = Enum.Font.GothamBold
SwingUpBtn.TextSize = 14
SwingUpBtn.AutoButtonColor = false
SwingUpBtn.Parent = SettingsPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = SwingUpBtn
end

local RangeLabel = Instance.new("TextLabel")
RangeLabel.Size = UDim2.new(0, 180, 0, 28)
RangeLabel.Position = UDim2.new(0, 0, 0, 102)
RangeLabel.BackgroundTransparency = 1
RangeLabel.Text = "Parry Range: " .. tostring(PARRY_RANGE) .. " studs"
RangeLabel.TextColor3 = Color3.fromRGB(160, 180, 220)
RangeLabel.TextXAlignment = Enum.TextXAlignment.Left
RangeLabel.Font = Enum.Font.Gotham
RangeLabel.TextSize = 13
RangeLabel.Parent = SettingsPage

local RangeDownBtn = Instance.new("TextButton")
RangeDownBtn.Size = UDim2.new(0, 36, 0, 24)
RangeDownBtn.Position = UDim2.new(0, 186, 0, 105)
RangeDownBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
RangeDownBtn.BorderSizePixel = 0
RangeDownBtn.Text = "-"
RangeDownBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
RangeDownBtn.Font = Enum.Font.GothamBold
RangeDownBtn.TextSize = 14
RangeDownBtn.AutoButtonColor = false
RangeDownBtn.Parent = SettingsPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = RangeDownBtn
end

local RangeUpBtn = Instance.new("TextButton")
RangeUpBtn.Size = UDim2.new(0, 36, 0, 24)
RangeUpBtn.Position = UDim2.new(0, 228, 0, 105)
RangeUpBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
RangeUpBtn.BorderSizePixel = 0
RangeUpBtn.Text = "+"
RangeUpBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
RangeUpBtn.Font = Enum.Font.GothamBold
RangeUpBtn.TextSize = 14
RangeUpBtn.AutoButtonColor = false
RangeUpBtn.Parent = SettingsPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = RangeUpBtn
end

-- Kill Script button (destroys everything)
local KillScriptBtn = Instance.new("TextButton")
KillScriptBtn.Size = UDim2.new(1, 0, 0, 40)
KillScriptBtn.Position = UDim2.new(0, 0, 0, 140)
KillScriptBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
KillScriptBtn.BorderSizePixel = 0
KillScriptBtn.Text = "KILL SCRIPT (remove all)"
KillScriptBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
KillScriptBtn.Font = Enum.Font.GothamBold
KillScriptBtn.TextSize = 13
KillScriptBtn.AutoButtonColor = false
KillScriptBtn.Parent = SettingsPage

do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = KillScriptBtn
end

local KillScriptWarn = Instance.new("TextLabel")
KillScriptWarn.Size = UDim2.new(1, 0, 0, 16)
KillScriptWarn.Position = UDim2.new(0, 0, 0, 184)
KillScriptWarn.BackgroundTransparency = 1
KillScriptWarn.Text = "Stops ALL features and removes the entire UI"
KillScriptWarn.TextColor3 = Color3.fromRGB(160, 100, 100)
KillScriptWarn.TextXAlignment = Enum.TextXAlignment.Left
KillScriptWarn.Font = Enum.Font.Gotham
KillScriptWarn.TextSize = 10
KillScriptWarn.Parent = SettingsPage

-- ================================================================
-- // JUNKPITS PAGE
-- ================================================================

local JunkpitsPage = Instance.new("ScrollingFrame")
JunkpitsPage.Name = "JunkpitsPage"
JunkpitsPage.Size = UDim2.new(1, 0, 1, 0)
JunkpitsPage.BackgroundTransparency = 1
JunkpitsPage.Visible = false
JunkpitsPage.ScrollBarThickness = 4
JunkpitsPage.ScrollBarImageColor3 = Color3.fromRGB(255, 180, 80)
JunkpitsPage.CanvasSize = UDim2.new(0, 0, 0, 400)
JunkpitsPage.AutomaticCanvasSize = Enum.AutomaticSize.Y
JunkpitsPage.Parent = ContentArea
Pages["Junkpits"] = JunkpitsPage

do
        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 14)
        pad.PaddingTop = UDim.new(0, 14)
        pad.PaddingRight = UDim.new(0, 14)
        pad.Parent = JunkpitsPage
end

local JunkpitsTitle = Instance.new("TextLabel")
JunkpitsTitle.Size = UDim2.new(1, -14, 0, 24)
JunkpitsTitle.BackgroundTransparency = 1
JunkpitsTitle.Text = "Junkpits"
JunkpitsTitle.TextColor3 = Color3.fromRGB(255, 200, 120)
JunkpitsTitle.TextXAlignment = Enum.TextXAlignment.Left
JunkpitsTitle.Font = Enum.Font.GothamBold
JunkpitsTitle.TextSize = 15
JunkpitsTitle.Parent = JunkpitsPage

-- ===== CRONO'S CRAZY CHALLENGE KEY COLLECT =====
local CronoTitle = Instance.new("TextLabel")
CronoTitle.Size = UDim2.new(1, 0, 0, 20)
CronoTitle.Position = UDim2.new(0, 0, 0, 34)
CronoTitle.BackgroundTransparency = 1
CronoTitle.Text = "Crono's Crazy Challenge"
CronoTitle.TextColor3 = Color3.fromRGB(255, 180, 80)
CronoTitle.TextXAlignment = Enum.TextXAlignment.Left
CronoTitle.Font = Enum.Font.GothamBold
CronoTitle.TextSize = 13
CronoTitle.Parent = JunkpitsPage

local CronoKeyBtn = Instance.new("TextButton")
CronoKeyBtn.Size = UDim2.new(1, 0, 0, 40)
CronoKeyBtn.Position = UDim2.new(0, 0, 0, 58)
CronoKeyBtn.BackgroundColor3 = Color3.fromRGB(180, 100, 40)
CronoKeyBtn.BorderSizePixel = 0
CronoKeyBtn.Text = "Auto Crono's Crazy Challenge Key Collect"
CronoKeyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CronoKeyBtn.Font = Enum.Font.GothamBold
CronoKeyBtn.TextSize = 12
CronoKeyBtn.AutoButtonColor = false
CronoKeyBtn.Parent = JunkpitsPage

do
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 8)
        c.Parent = CronoKeyBtn
end

local CronoKeyStatus = Instance.new("TextLabel")
CronoKeyStatus.Size = UDim2.new(1, 0, 0, 30)
CronoKeyStatus.Position = UDim2.new(0, 0, 0, 102)
CronoKeyStatus.BackgroundTransparency = 1
CronoKeyStatus.Text = "Status: Idle"
CronoKeyStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
CronoKeyStatus.TextXAlignment = Enum.TextXAlignment.Left
CronoKeyStatus.Font = Enum.Font.Gotham
CronoKeyStatus.TextSize = 10
CronoKeyStatus.TextWrapped = true
CronoKeyStatus.Parent = JunkpitsPage

-- ===== DELETE ENEMIES / KILLBRICKS =====
local DeleteTitle = Instance.new("TextLabel")
DeleteTitle.Size = UDim2.new(1, 0, 0, 20)
DeleteTitle.Position = UDim2.new(0, 0, 0, 140)
DeleteTitle.BackgroundTransparency = 1
DeleteTitle.Text = "Auto-Delete (Crono's Challenge)"
DeleteTitle.TextColor3 = Color3.fromRGB(255, 120, 120)
DeleteTitle.TextXAlignment = Enum.TextXAlignment.Left
DeleteTitle.Font = Enum.Font.GothamBold
DeleteTitle.TextSize = 13
DeleteTitle.Parent = JunkpitsPage

local DeleteBtn = Instance.new("TextButton")
DeleteBtn.Size = UDim2.new(1, 0, 0, 40)
DeleteBtn.Position = UDim2.new(0, 0, 0, 164)
DeleteBtn.BackgroundColor3 = Color3.fromRGB(120, 40, 40)
DeleteBtn.BorderSizePixel = 0
DeleteBtn.Text = "Delete All enemy/Kill brick in Crono's Crazy Challenge"
DeleteBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
DeleteBtn.Font = Enum.Font.GothamBold
DeleteBtn.TextSize = 11
DeleteBtn.AutoButtonColor = false
DeleteBtn.Parent = JunkpitsPage

do
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 8)
        c.Parent = DeleteBtn
end

local DeleteStatus = Instance.new("TextLabel")
DeleteStatus.Size = UDim2.new(1, 0, 0, 30)
DeleteStatus.Position = UDim2.new(0, 0, 0, 208)
DeleteStatus.BackgroundTransparency = 1
DeleteStatus.Text = "Status: Idle"
DeleteStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
DeleteStatus.TextXAlignment = Enum.TextXAlignment.Left
DeleteStatus.Font = Enum.Font.Gotham
DeleteStatus.TextSize = 10
DeleteStatus.TextWrapped = true
DeleteStatus.Parent = JunkpitsPage

-- ================================================================
-- // RIFTS PAGE
-- ================================================================

local RiftsPage = Instance.new("ScrollingFrame")
RiftsPage.Name = "RiftsPage"
RiftsPage.Size = UDim2.new(1, 0, 1, 0)
RiftsPage.BackgroundTransparency = 1
RiftsPage.Visible = false
RiftsPage.ScrollBarThickness = 4
RiftsPage.ScrollBarImageColor3 = Color3.fromRGB(180, 100, 255)
RiftsPage.CanvasSize = UDim2.new(0, 0, 0, 280)
RiftsPage.AutomaticCanvasSize = Enum.AutomaticSize.Y
RiftsPage.Parent = ContentArea
Pages["Rifts"] = RiftsPage

do
        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 14)
        pad.PaddingTop = UDim.new(0, 14)
        pad.PaddingRight = UDim.new(0, 14)
        pad.Parent = RiftsPage
end

local RiftsTitle = Instance.new("TextLabel")
RiftsTitle.Size = UDim2.new(1, -14, 0, 24)
RiftsTitle.BackgroundTransparency = 1
RiftsTitle.Text = "Rifts"
RiftsTitle.TextColor3 = Color3.fromRGB(200, 150, 255)
RiftsTitle.TextXAlignment = Enum.TextXAlignment.Left
RiftsTitle.Font = Enum.Font.GothamBold
RiftsTitle.TextSize = 15
RiftsTitle.Parent = RiftsPage

local RiftsInfo = Instance.new("TextLabel")
RiftsInfo.Size = UDim2.new(1, 0, 0, 30)
RiftsInfo.Position = UDim2.new(0, 0, 0, 28)
RiftsInfo.BackgroundTransparency = 1
RiftsInfo.Text = "Auto TP to RiftSpawn1-7, hold G, kill mobs in radius, wait for 'Rift cleared' message, then next rift"
RiftsInfo.TextColor3 = Color3.fromRGB(120, 100, 160)
RiftsInfo.TextXAlignment = Enum.TextXAlignment.Left
RiftsInfo.Font = Enum.Font.Gotham
RiftsInfo.TextSize = 10
RiftsInfo.TextWrapped = true
RiftsInfo.Parent = RiftsPage

-- Radius adjuster
local RiftsRadiusLabel = Instance.new("TextLabel")
RiftsRadiusLabel.Size = UDim2.new(0, 180, 0, 20)
RiftsRadiusLabel.Position = UDim2.new(0, 0, 0, 64)
RiftsRadiusLabel.BackgroundTransparency = 1
RiftsRadiusLabel.Text = "Mob detect radius: 1000 studs"
RiftsRadiusLabel.TextColor3 = Color3.fromRGB(160, 180, 220)
RiftsRadiusLabel.TextXAlignment = Enum.TextXAlignment.Left
RiftsRadiusLabel.Font = Enum.Font.Gotham
RiftsRadiusLabel.TextSize = 12
RiftsRadiusLabel.Parent = RiftsPage

local RiftsRadiusDownBtn = Instance.new("TextButton")
RiftsRadiusDownBtn.Size = UDim2.new(0, 30, 0, 20)
RiftsRadiusDownBtn.Position = UDim2.new(0, 186, 0, 64)
RiftsRadiusDownBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
RiftsRadiusDownBtn.BorderSizePixel = 0
RiftsRadiusDownBtn.Text = "-"
RiftsRadiusDownBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
RiftsRadiusDownBtn.Font = Enum.Font.GothamBold
RiftsRadiusDownBtn.TextSize = 13
RiftsRadiusDownBtn.AutoButtonColor = false
RiftsRadiusDownBtn.Parent = RiftsPage

do
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = RiftsRadiusDownBtn
end

local RiftsRadiusUpBtn = Instance.new("TextButton")
RiftsRadiusUpBtn.Size = UDim2.new(0, 30, 0, 20)
RiftsRadiusUpBtn.Position = UDim2.new(0, 220, 0, 64)
RiftsRadiusUpBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
RiftsRadiusUpBtn.BorderSizePixel = 0
RiftsRadiusUpBtn.Text = "+"
RiftsRadiusUpBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
RiftsRadiusUpBtn.Font = Enum.Font.GothamBold
RiftsRadiusUpBtn.TextSize = 13
RiftsRadiusUpBtn.AutoButtonColor = false
RiftsRadiusUpBtn.Parent = RiftsPage

do
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = RiftsRadiusUpBtn
end

-- Auto Rifts toggle button
local AutoRiftsBtn = Instance.new("TextButton")
AutoRiftsBtn.Size = UDim2.new(1, 0, 0, 40)
AutoRiftsBtn.Position = UDim2.new(0, 0, 0, 94)
AutoRiftsBtn.BackgroundColor3 = Color3.fromRGB(100, 60, 160)
AutoRiftsBtn.BorderSizePixel = 0
AutoRiftsBtn.Text = ">  Start Auto Rifts"
AutoRiftsBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
AutoRiftsBtn.Font = Enum.Font.GothamBold
AutoRiftsBtn.TextSize = 14
AutoRiftsBtn.AutoButtonColor = false
AutoRiftsBtn.Parent = RiftsPage

do
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 8)
        c.Parent = AutoRiftsBtn
end

local RiftsStatus = Instance.new("TextLabel")
RiftsStatus.Size = UDim2.new(1, 0, 0, 40)
RiftsStatus.Position = UDim2.new(0, 0, 0, 140)
RiftsStatus.BackgroundTransparency = 1
RiftsStatus.Text = "Status: Idle"
RiftsStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
RiftsStatus.TextXAlignment = Enum.TextXAlignment.Left
RiftsStatus.Font = Enum.Font.Gotham
RiftsStatus.TextSize = 10
RiftsStatus.TextWrapped = true
RiftsStatus.Parent = RiftsPage

-- Note about attack position
local RiftsNote = Instance.new("TextLabel")
RiftsNote.Size = UDim2.new(1, 0, 0, 20)
RiftsNote.Position = UDim2.new(0, 0, 0, 184)
RiftsNote.BackgroundTransparency = 1
RiftsNote.Text = "Attack position uses Mob page settings (Below/Above/Behind/Front/Custom)"
RiftsNote.TextColor3 = Color3.fromRGB(100, 90, 130)
RiftsNote.TextXAlignment = Enum.TextXAlignment.Left
RiftsNote.Font = Enum.Font.Gotham
RiftsNote.TextSize = 9
RiftsNote.Parent = RiftsPage

-- Activation mode selection (Mobile = tap screen 2x, Desktop = hold G)
local RiftsActivationLabel = Instance.new("TextLabel")
RiftsActivationLabel.Size = UDim2.new(1, 0, 0, 16)
RiftsActivationLabel.Position = UDim2.new(0, 0, 0, 208)
RiftsActivationLabel.BackgroundTransparency = 1
RiftsActivationLabel.Text = "Rift activation method:"
RiftsActivationLabel.TextColor3 = Color3.fromRGB(160, 180, 220)
RiftsActivationLabel.TextXAlignment = Enum.TextXAlignment.Left
RiftsActivationLabel.Font = Enum.Font.Gotham
RiftsActivationLabel.TextSize = 10
RiftsActivationLabel.Parent = RiftsPage

local RiftsMobileBtn = Instance.new("TextButton")
RiftsMobileBtn.Size = UDim2.new(0.48, 0, 0, 28)
RiftsMobileBtn.Position = UDim2.new(0, 0, 0, 228)
RiftsMobileBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
RiftsMobileBtn.BorderSizePixel = 0
RiftsMobileBtn.Text = "Mobile (tap 2x)"
RiftsMobileBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
RiftsMobileBtn.Font = Enum.Font.GothamBold
RiftsMobileBtn.TextSize = 11
RiftsMobileBtn.AutoButtonColor = false
RiftsMobileBtn.Parent = RiftsPage

do
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = RiftsMobileBtn
end

local RiftsDesktopBtn = Instance.new("TextButton")
RiftsDesktopBtn.Size = UDim2.new(0.48, 0, 0, 28)
RiftsDesktopBtn.Position = UDim2.new(0.52, 0, 0, 228)
RiftsDesktopBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
RiftsDesktopBtn.BorderSizePixel = 0
RiftsDesktopBtn.Text = "Desktop (hold G)"
RiftsDesktopBtn.TextColor3 = Color3.fromRGB(220, 220, 240)
RiftsDesktopBtn.Font = Enum.Font.GothamBold
RiftsDesktopBtn.TextSize = 11
RiftsDesktopBtn.AutoButtonColor = false
RiftsDesktopBtn.Parent = RiftsPage

do
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = RiftsDesktopBtn
end

-- // SIDEBAR BUTTONS
local PlayerBtn = createSidebarButton("Player", "P")
local AutoBtn = createSidebarButton("Auto", ">")
local MobBtn = createSidebarButton("Mob", "!")
local SettingsBtn = createSidebarButton("Settings", "*")
local JunkpitsBtn = createSidebarButton("Junkpits", "J")
local RiftsBtn = createSidebarButton("Rifts", "R")
local allSideBtns = {PlayerBtn, AutoBtn, MobBtn, SettingsBtn, JunkpitsBtn, RiftsBtn}
setActiveSidebarBtn(PlayerBtn, allSideBtns)

-- // SIDEBAR NAVIGATION (outside pcall — basic page switching always works)
PlayerBtn.MouseButton1Click:Connect(function()
        setActiveSidebarBtn(PlayerBtn, allSideBtns)
        showPage("Player")
end)

AutoBtn.MouseButton1Click:Connect(function()
        setActiveSidebarBtn(AutoBtn, allSideBtns)
        showPage("Auto")
        pcall(function() if refreshOreList then refreshOreList() end end)
end)

SettingsBtn.MouseButton1Click:Connect(function()
        setActiveSidebarBtn(SettingsBtn, allSideBtns)
        showPage("Settings")
end)

MobBtn.MouseButton1Click:Connect(function()
        setActiveSidebarBtn(MobBtn, allSideBtns)
        showPage("Mob")
        pcall(function() if refreshMobList then refreshMobList(true) end end)
end)

JunkpitsBtn.MouseButton1Click:Connect(function()
        setActiveSidebarBtn(JunkpitsBtn, allSideBtns)
        showPage("Junkpits")
end)

RiftsBtn.MouseButton1Click:Connect(function()
        setActiveSidebarBtn(RiftsBtn, allSideBtns)
        showPage("Rifts")
end)

print("[Pilgrammed] UI elements created!")

-- ================================================================
-- // SECTION 3: LOGIC CODE (IN PCALL — errors don't kill UI)
-- ================================================================

local ok, err = pcall(function()

local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")

-- // UTILITIES

local function findPickaxe()
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        local char = LocalPlayer.Character
        if backpack then
                for _, tool in ipairs(backpack:GetChildren()) do
                        if tool:IsA("Tool") and tool.Name:lower():find("pickaxe") then
                                return tool
                        end
                end
        end
        if char then
                for _, tool in ipairs(char:GetChildren()) do
                        if tool:IsA("Tool") and tool.Name:lower():find("pickaxe") then
                                return tool
                        end
                end
        end
        return nil
end

local function equipPickaxe(tool)
        local char = LocalPlayer.Character
        if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then
                        hum:EquipTool(tool)
                        State.equippedPickaxe = tool
                end
        end
end

local function getPartContainers()
        local containers = {}
        local oresFolder = workspace:FindFirstChild(ORES_FOLDER_NAME)
        if not oresFolder then return containers end
        for _, desc in ipairs(oresFolder:GetDescendants()) do
                if desc.Name == "Part" then
                        table.insert(containers, desc)
                end
        end
        return containers
end

local function getOreNames()
        local names = {}
        local seen = {}
        for _, partContainer in ipairs(getPartContainers()) do
                for _, orePart in ipairs(partContainer:GetChildren()) do
                        if orePart:IsA("BasePart") and not seen[orePart.Name] then
                                seen[orePart.Name] = true
                                table.insert(names, orePart.Name)
                        end
                end
        end
        table.sort(names)
        return names
end

local function getAllPartsOfOre(oreName)
        local parts = {}
        for _, partContainer in ipairs(getPartContainers()) do
                for _, orePart in ipairs(partContainer:GetChildren()) do
                        if orePart:IsA("BasePart") and orePart.Name == oreName then
                                table.insert(parts, orePart)
                        end
                end
        end
        return parts
end

local function deleteBase(orePart)
        local oresFolder = workspace:FindFirstChild(ORES_FOLDER_NAME)
        local current = orePart.Parent
        while current and current ~= oresFolder and current ~= workspace do
                local base = current:FindFirstChild("Base")
                if base and base:IsA("BasePart") then
                        base:Destroy()
                        return
                end
                current = current.Parent
        end
end

local function flyUnderAndFacePart(part)
        local char = LocalPlayer.Character
        if char then
                local hrp = char:FindFirstChild("HumanoidRootPart")
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hrp and part and part.Parent then
                        if hum then
                                hum.PlatformStand = true
                        end
                        hrp.Velocity = Vector3.new(0, 0, 0)
                        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                        local flyPos = part.Position + FLY_OFFSET
                        hrp.CFrame = CFrame.lookAt(flyPos, part.Position)
                end
        end
end

-- // NOCLIP (cached — same pattern as mob farm, avoids GetDescendants every frame)
local _noclipCache = {}
local _noclipCacheTime = 0
local function startNoclip()
        if State.noclipConnection then return end
        _noclipCache = {}
        _noclipCacheTime = 0
        State.noclipConnection = RunService.Stepped:Connect(function()
                local now = tick()
                if now - _noclipCacheTime > NOCLIP_REFRESH_INTERVAL then
                        _noclipCacheTime = now
                        _noclipCache = {}
                        local char = LocalPlayer.Character
                        if char then
                                for _, part in ipairs(char:GetDescendants()) do
                                        if part:IsA("BasePart") then
                                                table.insert(_noclipCache, part)
                                        end
                                end
                        end
                end
                for _, part in ipairs(_noclipCache) do
                        part.CanCollide = false
                end
        end)
end

local function stopNoclip()
        if State.noclipConnection then
                State.noclipConnection:Disconnect()
                State.noclipConnection = nil
        end
        local char = LocalPlayer.Character
        if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then
                        hum.PlatformStand = false
                end
                for _, part in ipairs(char:GetDescendants()) do
                        if part:IsA("BasePart") then
                                part.CanCollide = true
                        end
                end
        end
end

-- // AUTO PARRY (2-Layer: AttackWarning remote + animation pre-block)
local lastParryTime = 0

local function getBlockRemote()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if remotes then
                return remotes:FindFirstChild("Block")
        end
        return nil
end

local function getAttackWarningRemote()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if remotes then
                return remotes:FindFirstChild("AttackWarning")
        end
        return nil
end

local function fireBlock(value)
        local br = getBlockRemote()
        if br then
                pcall(function()
                        br:FireServer(value)
                end)
        end
end

local function doParry(source)
        if not State.autoParry then return end
        -- Allow re-trigger even if blocking (so we can extend hold if another hit comes)

        local now = tick()
        -- Small cooldown to prevent double-fire from same source within same frame
        if now - lastParryTime < 0.05 then return end
        lastParryTime = now

        State.isBlocking = true
        State.parryCount = State.parryCount + 1

        if ParryStatus then
                ParryStatus.Text = "BLOCKING! (" .. source .. ") #" .. tostring(State.parryCount)
                ParryStatus.TextColor3 = Color3.fromRGB(255, 220, 80)
        end

        -- Hold block true for PARRY_HOLD_TIME (0.5s)
        fireBlock(true)

        -- After PARRY_HOLD_TIME, unhold (block false) regardless of parry success
        -- This is what the user requested: detect hit -> hold 0.5s -> unhold
        task.delay(PARRY_HOLD_TIME, function()
                if not State.autoParry then return end
                fireBlock(false)
                State.isBlocking = false
                if ParryStatus then
                        ParryStatus.Text = "Watching for attacks... (" .. tostring(State.parryCount) .. " parried)"
                        ParryStatus.TextColor3 = Color3.fromRGB(100, 220, 255)
                end
        end)
end

-- Track which NPCs we are already watching
local watchedNPCs = {}

local function watchNPC(humanoid)
        if watchedNPCs[humanoid] then return end
        watchedNPCs[humanoid] = true

        humanoid.AnimationPlayed:Connect(function(track)
                if not State.autoParry then return end
                -- Note: do NOT check State.isBlocking here — we want to detect new hits
                -- even while blocking, so we can extend the hold

                local anim = track.Animation
                if not anim then return end
                local name = anim.Name:lower()
                local id = anim.AnimationId or ""

                -- Detect attack animations by name keyword
                local isAttack = name:find("attack") or name:find("swing") or name:find("slash")
                        or name:find("hit") or name:find("combat") or name:find("m1") or name:find("m2")
                        or name:find("ability") or name:find("heavy") or name:find("light")
                        or name:find("strike") or name:find("melee") or name:find("punch")
                        or name:find("kick") or name:find("lunge") or name:find("charge")
                        or name:find("bite") or name:find("claw") or name:find("smash")
                        or name:find("stab") or name:find("throw") or name:find("cast")
                        or name:find("action") or name:find("wind") or name:find("spin")

                if isAttack then
                        -- Re-check range NOW, at the moment of the swing — not just when the
                        -- mob was first spotted. If it walked out of PARRY_RANGE, skip it.
                        local char = LocalPlayer.Character
                        local hrp = char and char:FindFirstChild("HumanoidRootPart")
                        local eChar = humanoid.Parent
                        local eHrp = eChar and eChar:FindFirstChild("HumanoidRootPart")
                        if hrp and eHrp and (eHrp.Position - hrp.Position).Magnitude <= PARRY_RANGE then
                                -- Small reaction delay so the block lands closer to actual impact
                                -- instead of firing the instant the animation starts.
                                task.delay(PARRY_PRE_BLOCK, function()
                                        if not State.autoParry then return end
                                        doParry("Anim:" .. name)
                                end)
                        end
                end
        end)

        -- Clean up when NPC dies or is removed
        humanoid.AncestryChanged:Connect(function()
                if humanoid.Parent == nil then
                        watchedNPCs[humanoid] = nil
                end
        end)
        if humanoid.Health <= 0 then
                watchedNPCs[humanoid] = nil
        end
end

local function scanForNearbyNPCs()
        local char = LocalPlayer.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local pos = hrp.Position
        -- Scan workspace.Mobs folder (event-based hook will catch new spawns, this is fallback)
        local function scanModel(parent)
                for _, obj in ipairs(parent:GetChildren()) do
                        if obj:IsA("Model") and obj ~= char then
                                local hum = obj:FindFirstChildOfClass("Humanoid")
                                if hum and hum.Health > 0 then
                                        local eHrp = obj:FindFirstChild("HumanoidRootPart")
                                        if eHrp and (eHrp.Position - pos).Magnitude <= PARRY_RANGE then
                                                watchNPC(hum)
                                        end
                                end
                        end
                        -- Recurse into folders
                        if obj:IsA("Folder") or obj:IsA("Model") then
                                scanModel(obj)
                        end
                end
        end
        -- Only scan the Mobs folder (where enemies live) - skip rest of workspace for speed
        local mobsFolder = workspace:FindFirstChild("Mobs")
        if mobsFolder then
                scanModel(mobsFolder)
        end
end

-- Helper: when a new mob spawns, check if it's in parry range and watch it
local function onMobSpawnedForParry(mob)
        if not State.autoParry then return end
        if not mob:IsA("Model") then return end
        local hum = mob:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return end
        local char = LocalPlayer.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local eHrp = mob:FindFirstChild("HumanoidRootPart")
        if not hrp or not eHrp then
                -- Mob might not have HRP yet — wait briefly and retry once
                task.spawn(function()
                        task.wait(0.3)
                        if not State.autoParry then return end
                        if not mob.Parent then return end
                        local h = mob:FindFirstChildOfClass("Humanoid")
                        if not h or h.Health <= 0 then return end
                        local c = LocalPlayer.Character
                        if not c then return end
                        local hp = c:FindFirstChild("HumanoidRootPart")
                        local ep = mob:FindFirstChild("HumanoidRootPart")
                        if hp and ep and (ep.Position - hp.Position).Magnitude <= PARRY_RANGE then
                                watchNPC(h)
                        end
                end)
                return
        end
        if (eHrp.Position - hrp.Position).Magnitude <= PARRY_RANGE then
                watchNPC(hum)
        end
end

-- Set up event-based mob spawn detection (replaces polling scan)
-- Recursively attach ChildAdded listeners so we catch mobs at any depth
-- (handles workspace.Mobs.Roadini AND workspace.Mobs.Prairie3.Thief AND any deeper nesting)
local function attachMobWatcher(parent, connsTable)
        local conn = parent.ChildAdded:Connect(function(child)
                if child:IsA("Model") then
                        -- It might be a mob directly
                        onMobSpawnedForParry(child)
                        -- Or it might be a container holding mobs deeper
                        attachMobWatcher(child, connsTable)
                elseif child:IsA("Folder") then
                        attachMobWatcher(child, connsTable)
                end
        end)
        table.insert(connsTable, conn)
end

local function setupMobSpawnWatcher()
        -- Clean up any existing watchers
        for _, conn in ipairs(State.mobSpawnConns) do
                conn:Disconnect()
        end
        State.mobSpawnConns = {}

        local mobsFolder = workspace:FindFirstChild("Mobs")
        if not mobsFolder then
                -- Mobs folder doesn't exist yet - wait for it
                local conn
                conn = workspace.ChildAdded:Connect(function(child)
                        if child.Name == "Mobs" then
                                conn:Disconnect()
                                setupMobSpawnWatcher()
                        end
                end)
                table.insert(State.mobSpawnConns, conn)
                return
        end

        -- Attach recursive watcher to Mobs folder
        -- This catches: direct mob children, area folders, and any deeper nesting
        attachMobWatcher(mobsFolder, State.mobSpawnConns)
end

local function startAutoParry()
        if State.autoParry then return end
        State.autoParry = true
        State.parryCount = 0
        lastParryTime = 0

        local layersActive = 0

        -- ===== LAYER 1: AttackWarning Remote (server warns BEFORE hit — best timing) =====
        local awRemote = getAttackWarningRemote()
        if awRemote and awRemote:IsA("RemoteEvent") then
                State.attackWarningConn = awRemote.OnClientEvent:Connect(function(...)
                        if not State.autoParry then return end
                        doParry("AttackWarning")
                end)
                layersActive = layersActive + 1
                print("[AutoParry] Layer 1 ACTIVE: AttackWarning remote")
        else
                warn("[AutoParry] Layer 1 MISS: AttackWarning remote not found")
        end

        -- ===== LAYER 2: Animation-based NPC watching =====
        scanForNearbyNPCs()
        setupMobSpawnWatcher()
        -- Fallback scan every 15s for any missed mobs
        State.npcScanThread = task.spawn(function()
                while State.autoParry do
                        task.wait(NPC_SCAN_INTERVAL)
                        if State.autoParry then scanForNearbyNPCs() end
                end
        end)
        layersActive = layersActive + 1
        print("[AutoParry] Layer 2 ACTIVE: Animation watcher")

        -- ===== LAYER 3: Health-drop detector (most reliable fallback) =====
        -- If our health drops, we got hit — block immediately to catch the next hit
        -- Works regardless of remote/animation detection
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then
                State.lastHealth = hum.Health
                State.maxHealth = hum.MaxHealth
                State.parryHealthConn = hum.HealthChanged:Connect(function(newHealth)
                        if not State.autoParry then return end
                        if newHealth < State.lastHealth then
                                -- Health dropped — we took a hit, block immediately for the next one
                                local dmg = State.lastHealth - newHealth
                                print("[AutoParry] Layer 3: Health drop " .. string.format("%.1f", dmg) .. " — blocking!")
                                doParry("HealthDrop")
                        end
                        State.lastHealth = newHealth
                end)
                layersActive = layersActive + 1
                print("[AutoParry] Layer 3 ACTIVE: Health-drop detector")
        else
                warn("[AutoParry] Layer 3 MISS: No humanoid found")
        end

        if ParryStatus then
                ParryStatus.Text = "Watching (" .. layersActive .. " layers active)"
                ParryStatus.TextColor3 = Color3.fromRGB(100, 220, 255)
        end
end

local function stopAutoParry()
        State.autoParry = false
        State.isBlocking = false
        watchedNPCs = {}
        if State.attackWarningConn then
                State.attackWarningConn:Disconnect()
                State.attackWarningConn = nil
        end
        if State.parryHealthConn then
                State.parryHealthConn:Disconnect()
                State.parryHealthConn = nil
        end
        if State.parryConnection then
                State.parryConnection:Disconnect()
                State.parryConnection = nil
        end
        if State.npcWatchConn then
                State.npcWatchConn:Disconnect()
                State.npcWatchConn = nil
        end
        for _, conn in ipairs(State.mobSpawnConns) do
                conn:Disconnect()
        end
        State.mobSpawnConns = {}
        State.npcScanThread = nil
        fireBlock(false)
end

local function swingPickaxe()
        local char = LocalPlayer.Character
        if not char then return end
        local pickaxe = char:FindFirstChild(State.equippedPickaxe and State.equippedPickaxe.Name or "")
        if not pickaxe then
                pickaxe = findPickaxe()
                if pickaxe then
                        equipPickaxe(pickaxe)
                        task.wait(0.5)
                        pickaxe = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild(pickaxe.Name)
                end
        end
        if not pickaxe then return end
        local slash = pickaxe:FindFirstChild("Slash")
        if slash then
                local ok2, err2 = pcall(function()
                        slash:FireServer(1)
                end)
                if not ok2 then
                        warn("[AutoMiner] FireServer error: " .. tostring(err2))
                end
        end
end

-- // MOB FARMING UTILITIES

-- (Legacy getMobNames / getAllMobsOfName were replaced by recursive versions below)

-- ================================================================
-- // MOB SCANNING HELPERS (recursive — handles both workspace.Mobs.Area.Mob AND workspace.Mobs.Mob)
-- ================================================================

-- Recursively iterate all descendants of `parent` that are Models with Humanoids
-- callback(mobModel, humanoid) is called for each alive mob found
local function forEachMob(parent, callback)
        if not parent then return end
        for _, child in ipairs(parent:GetChildren()) do
                if child:IsA("Model") then
                        local hum = child:FindFirstChildOfClass("Humanoid")
                        if hum and not MOB_BLACKLIST[child.Name] then
                                callback(child, hum)
                        end
                        -- Always recurse into models too (some mobs nest inside other models)
                        forEachMob(child, callback)
                elseif child:IsA("Folder") then
                        forEachMob(child, callback)
                end
        end
end

-- Get all alive mobs matching mobName (recursive)
local function getAllMobsByName(mobName)
        local mobs = {}
        local mobsFolder = workspace:FindFirstChild("Mobs")
        if not mobsFolder then return mobs end
        forEachMob(mobsFolder, function(mob, hum)
                if mob.Name == mobName and hum.Health > 0 then
                        table.insert(mobs, mob)
                end
        end)
        return mobs
end

-- Get all unique mob names (recursive)
local function getMobNames()
        local names = {}
        local seen = {}
        local mobsFolder = workspace:FindFirstChild("Mobs")
        if not mobsFolder then return names end
        forEachMob(mobsFolder, function(mob, hum)
                if not seen[mob.Name] then
                        seen[mob.Name] = true
                        table.insert(names, mob.Name)
                end
        end)
        table.sort(names)
        return names
end

-- Get all alive mobs (recursive, no name filter)
local function getAllAliveMobs()
        local mobs = {}
        local mobsFolder = workspace:FindFirstChild("Mobs")
        if not mobsFolder then return mobs end
        forEachMob(mobsFolder, function(mob, hum)
                if hum.Health > 0 then
                        table.insert(mobs, mob)
                end
        end)
        return mobs
end

-- Find nearest alive mob to a point (recursive)
local function findNearestMobToPoint(point, maxDist)
        local mobsFolder = workspace:FindFirstChild("Mobs")
        if not mobsFolder then return nil end
        local nearestMob = nil
        local nearestDist = maxDist or math.huge
        forEachMob(mobsFolder, function(mob, hum)
                if hum.Health > 0 then
                        local hrp = mob:FindFirstChild("HumanoidRootPart")
                        if hrp then
                                local dist = (hrp.Position - point).Magnitude
                                if dist <= nearestDist then
                                        nearestDist = dist
                                        nearestMob = mob
                                end
                        end
                end
        end)
        return nearestMob
end

-- Keep old name as alias for backward compatibility (used by mob farm logic)
local getAllMobsOfName = getAllMobsByName

local function findWeapon()
        local char = LocalPlayer.Character
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        -- Check equipped weapon first
        if char then
                for _, tool in ipairs(char:GetChildren()) do
                        if tool:IsA("Tool") and tool:FindFirstChild("Slash") then
                                return tool
                        end
                end
        end
        -- Check backpack
        if backpack then
                for _, tool in ipairs(backpack:GetChildren()) do
                        if tool:IsA("Tool") and tool:FindFirstChild("Slash") then
                                return tool
                        end
                end
        end
        return nil
end

local function findWeaponByName(name)
        local char = LocalPlayer.Character
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        if char then
                local tool = char:FindFirstChild(name)
                if tool and tool:IsA("Tool") and tool:FindFirstChild("Slash") then
                        return tool
                end
        end
        if backpack then
                local tool = backpack:FindFirstChild(name)
                if tool and tool:IsA("Tool") and tool:FindFirstChild("Slash") then
                        return tool
                end
        end
        return nil
end

local function equipWeapon(tool)
        local char = LocalPlayer.Character
        if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then
                        hum:EquipTool(tool)
                        State.equippedWeapon = tool
                        State.lastEquippedWeaponName = tool.Name
                end
        end
end

local function flyToMob(mob)
        local char = LocalPlayer.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        local mobHrp = mob:FindFirstChild("HumanoidRootPart")
        if not hrp or not mobHrp then return end
        if hum then hum.PlatformStand = true end

        local mobPos = mobHrp.Position
        local mobCFrame = mobHrp.CFrame
        local targetPos
        local faceSameDir = false  -- true if player should face same direction as mob

        if ATTACK_POSITION == "below" then
                targetPos = mobPos + Vector3.new(0, -BELOW_DISTANCE, 0)
                faceSameDir = true
        elseif ATTACK_POSITION == "above" then
                targetPos = mobPos + Vector3.new(0, ABOVE_DISTANCE, 0)
                faceSameDir = true
        elseif ATTACK_POSITION == "behind" then
                targetPos = mobPos - mobCFrame.LookVector * BEHIND_DISTANCE
                faceSameDir = true
        elseif ATTACK_POSITION == "front" then
                targetPos = mobPos + mobCFrame.LookVector * BEHIND_DISTANCE
                faceSameDir = false
        elseif ATTACK_POSITION == "custom" then
                targetPos = mobPos + CUSTOM_OFFSET
                -- Decide facing based on whether we have horizontal offset
                local diff = targetPos - mobPos
                if diff.Magnitude > 0.1 and math.abs(diff.X) + math.abs(diff.Z) > 0.1 then
                        faceSameDir = false
                else
                        faceSameDir = true
                end
        else
                targetPos = mobPos + Vector3.new(0, -BELOW_DISTANCE, 0)
                faceSameDir = true
        end

        local distSq = (hrp.Position - targetPos).Magnitude
        if distSq > 0.5 then
                hrp.Velocity = Vector3.new(0, 0, 0)
                hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                if faceSameDir then
                        hrp.CFrame = CFrame.new(targetPos, targetPos + mobCFrame.LookVector)
                else
                        hrp.CFrame = CFrame.lookAt(targetPos, mobPos)
                end
        end
end

-- Get the next enabled attack type (cycles through Light→Heavy→Tech→Light...)
-- Returns the attack type number (1, 2, or 3) to fire, or nil if none enabled
local function getNextAttackType()
        -- Find first enabled attack type starting from current
        local tried = 0
        while tried < 3 do
                if State.attackTypes[State.currentAttackType] then
                        break
                end
                State.currentAttackType = State.currentAttackType % 3 + 1
                tried = tried + 1
        end
        if not State.attackTypes[State.currentAttackType] then return nil end
        local atkType = State.currentAttackType
        -- Advance to next enabled attack type for next swing
        local nextType = State.currentAttackType % 3 + 1
        local nextTried = 0
        while nextTried < 3 and not State.attackTypes[nextType] do
                nextType = nextType % 3 + 1
                nextTried = nextTried + 1
        end
        State.currentAttackType = nextType
        return atkType
end

local function attackMob()
        local char = LocalPlayer.Character
        if not char then return end

        -- If Auto Bow is ON, ONLY use bow — never switch to melee weapons
        if State.autoBow then
                -- Find equipped bow (has "Shoot" remote)
                local bowWeapon = nil
                for _, tool in ipairs(char:GetChildren()) do
                        if tool:IsA("Tool") and tool:FindFirstChild("Shoot") then
                                bowWeapon = tool
                                break
                        end
                end
                -- If no bow equipped, try to equip the bow by name from backpack
                if not bowWeapon then
                        local backpack = LocalPlayer:FindFirstChild("Backpack")
                        if backpack and State.bowName and State.bowName ~= "" then
                                local bowTool = backpack:FindFirstChild(State.bowName)
                                if not bowTool then
                                        -- case-insensitive search
                                        for _, tool in ipairs(backpack:GetChildren()) do
                                                if tool:IsA("Tool") and tool.Name:lower() == State.bowName:lower() and tool:FindFirstChild("Shoot") then
                                                        bowTool = tool
                                                        break
                                                end
                                        end
                                end
                                if bowTool then
                                        local hum = char:FindFirstChildOfClass("Humanoid")
                                        if hum then
                                                pcall(function() hum:EquipTool(bowTool) end)
                                                task.wait(0.1)
                                                for _, tool in ipairs(char:GetChildren()) do
                                                        if tool:IsA("Tool") and tool:FindFirstChild("Shoot") then
                                                                bowWeapon = tool
                                                                break
                                                        end
                                                end
                                        end
                                end
                        end
                end
                -- Fire bow at current mob
                if bowWeapon then
                        local shootRemote = bowWeapon:FindFirstChild("Shoot")
                        if not shootRemote then return end
                        local targetMob = State.currentMob
                        if not targetMob then return end
                        local mobHrp = targetMob:FindFirstChild("HumanoidRootPart")
                        if not mobHrp then return end
                        pcall(function()
                                shootRemote:InvokeServer(mobHrp.Position, "Arrow", true, 1)
                        end)
                end
                return  -- NEVER fall through to melee when Auto Bow is ON
        end

        -- Normal mode (Auto Bow OFF): detect weapon type
        local bowWeapon = nil
        local meleeWeapon = nil
        for _, tool in ipairs(char:GetChildren()) do
                if tool:IsA("Tool") then
                        if tool:FindFirstChild("Shoot") then
                                bowWeapon = tool
                                break  -- prefer bow if equipped
                        elseif tool:FindFirstChild("Slash") then
                                meleeWeapon = tool
                        end
                end
        end

        -- If no weapon equipped, try to find one in backpack
        if not bowWeapon and not meleeWeapon then
                local foundWeapon = findWeapon()
                if foundWeapon then
                        equipWeapon(foundWeapon)
                        task.wait(0.3)
                        -- Re-check character after equip
                        for _, tool in ipairs(char:GetChildren()) do
                                if tool:IsA("Tool") then
                                        if tool:FindFirstChild("Shoot") then
                                                bowWeapon = tool
                                                break
                                        elseif tool:FindFirstChild("Slash") then
                                                meleeWeapon = tool
                                        end
                                end
                        end
                end
        end

        -- BOW ATTACK: if bow equipped, fire at current mob
        if bowWeapon then
                local shootRemote = bowWeapon:FindFirstChild("Shoot")
                if not shootRemote then return end
                local targetMob = State.currentMob
                if not targetMob then return end
                local mobHrp = targetMob:FindFirstChild("HumanoidRootPart")
                if not mobHrp then return end
                pcall(function()
                        shootRemote:InvokeServer(mobHrp.Position, "Arrow", true, 1)
                end)
                return
        end

        -- MELEE ATTACK: if melee weapon equipped, fire Slash with attack type
        if not meleeWeapon then return end
        local slash = meleeWeapon:FindFirstChild("Slash")
        if not slash then return end
        local atkType = getNextAttackType()
        if not atkType then return end  -- no attack types enabled

        pcall(function()
                slash:FireServer(atkType)
        end)
end

-- MOB FARMING LOGIC
local startMobFarmFunc
local advanceToNextMobFunc

local function getMobHealth(mob)
        local hum = mob:FindFirstChildOfClass("Humanoid")
        return hum and hum.Health or 0
end

local function findNextAliveMob(mobName)
        local mobs = getAllMobsOfName(mobName)
        if #mobs > 0 then return mobs[1] end
        return nil
end

startMobFarmFunc = function(mob)
        if State.mobWatchConnection then
                State.mobWatchConnection:Disconnect()
                State.mobWatchConnection = nil
        end
        State.currentMob = mob
        flyToMob(mob)

        -- Watch mob health - when dead, advance
        local hum = mob:FindFirstChildOfClass("Humanoid")
        if hum then
                State.mobWatchConnection = hum.HealthChanged:Connect(function(hp)
                        if not State.autoMobFarming then return end
                        if hp <= 0 then
                                task.wait(0.5)
                                advanceToNextMobFunc()
                        end
                end)
        end

        -- Also watch if mob is removed
        mob.AncestryChanged:Connect(function()
                if mob.Parent == nil and State.autoMobFarming then
                        task.wait(0.5)
                        advanceToNextMobFunc()
                end
        end)
end

advanceToNextMobFunc = function()
        -- Try same mob type first
        local currentName = State.currentMobQueue[State.currentMobQueueIndex]
        if currentName then
                local nextMob = findNextAliveMob(currentName)
                if nextMob then
                        startMobFarmFunc(nextMob)
                        return
                end
        end

        -- Try other mob types in queue
        local attempts = 0
        repeat
                State.currentMobQueueIndex = State.currentMobQueueIndex + 1
                if State.currentMobQueueIndex > #State.currentMobQueue then
                        State.currentMobQueueIndex = 1
                end
                currentName = State.currentMobQueue[State.currentMobQueueIndex]
                local nextMob = findNextAliveMob(currentName)
                if nextMob then
                        startMobFarmFunc(nextMob)
                        return
                end
                attempts = attempts + 1
        until attempts > #State.currentMobQueue

        -- No alive mobs found - main Heartbeat will retry on next tick
        State.currentMob = nil
        if MobStatusLabel then
                MobStatusLabel.Text = "Waiting for mob respawn..."
                MobStatusLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
        end
end

local function startAutoMobFarm()
        if #State.currentMobQueue == 0 then return end

        -- Find and equip weapon
        local weapon
        if State.lastEquippedWeaponName then
                weapon = findWeaponByName(State.lastEquippedWeaponName)
        end
        if not weapon then
                weapon = findWeapon()
        end
        if weapon then
                equipWeapon(weapon)
                task.wait(0.5)
        else
                warn("[AutoMob] No weapon found!")
                return
        end

        State.autoMobFarming = true
        State.currentMobQueueIndex = 1
        State.currentAttackType = 1

        -- ===== OPTIMIZED NOCLIP: cache parts list, refresh every 0.5s =====
        if State.mobNoclipConn then State.mobNoclipConn:Disconnect() end
        State.noclipCacheChar = LocalPlayer.Character
        State.noclipPartsCache = {}
        State.noclipLastRefresh = 0
        local function refreshNoclipCache()
                State.noclipCacheChar = LocalPlayer.Character
                State.noclipPartsCache = {}
                if State.noclipCacheChar then
                        for _, part in ipairs(State.noclipCacheChar:GetDescendants()) do
                                if part:IsA("BasePart") then
                                        table.insert(State.noclipPartsCache, part)
                                end
                        end
                end
                State.noclipLastRefresh = tick()
        end
        refreshNoclipCache()
        State.mobNoclipConn = RunService.Stepped:Connect(function()
                -- Re-cache only every NOCLIP_REFRESH_INTERVAL seconds
                if tick() - State.noclipLastRefresh > NOCLIP_REFRESH_INTERVAL then
                        refreshNoclipCache()
                end
                for _, part in ipairs(State.noclipPartsCache) do
                        part.CanCollide = false
                end
        end)

        -- Find first alive mob
        for i, mobName in ipairs(State.currentMobQueue) do
                local mobs = getAllMobsOfName(mobName)
                if #mobs > 0 then
                        State.currentMobQueueIndex = i
                        startMobFarmFunc(mobs[1])
                        break
                end
        end

        -- ===== SINGLE MASTER HEARTBEAT: fly + attack + respawn check =====
        if State.mobMainConnection then State.mobMainConnection:Disconnect() end
        local lastAttack = 0
        local lastRespawnCheck = 0
        State.mobMainConnection = RunService.Heartbeat:Connect(function()
                if not State.autoMobFarming then return end

                -- If no current mob, periodically try to find one (every 2s)
                local now = tick()
                if not State.currentMob or not State.currentMob.Parent then
                        if now - lastRespawnCheck >= 2 then
                                lastRespawnCheck = now
                                for _, mobName in ipairs(State.currentMobQueue) do
                                        local mobs = getAllMobsOfName(mobName)
                                        if #mobs > 0 then
                                                for idx, qName in ipairs(State.currentMobQueue) do
                                                        if qName == mobName then
                                                                State.currentMobQueueIndex = idx
                                                                break
                                                        end
                                                end
                                                startMobFarmFunc(mobs[1])
                                                return
                                        end
                                end
                        end
                        return
                end

                -- Current mob still alive? Fly + attack
                local hum = State.currentMob:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                        flyToMob(State.currentMob)
                        if now - lastAttack >= MOB_ATTACK_INTERVAL then
                                lastAttack = now
                                attackMob()
                        end
                end
        end)

        if MobStatusLabel then
                MobStatusLabel.Text = "Fighting mobs..."
                MobStatusLabel.TextColor3 = Color3.fromRGB(100, 220, 255)
        end
end

local function stopAutoMobFarm()
        State.autoMobFarming = false
        State.currentMob = nil
        if State.mobMainConnection then
                State.mobMainConnection:Disconnect()
                State.mobMainConnection = nil
        end
        if State.mobWatchConnection then
                State.mobWatchConnection:Disconnect()
                State.mobWatchConnection = nil
        end
        if State.mobNoclipConn then
                State.mobNoclipConn:Disconnect()
                State.mobNoclipConn = nil
        end
        State.noclipPartsCache = {}
        -- Stop noclip and platform stand
        local char = LocalPlayer.Character
        if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then hum.PlatformStand = false end
                for _, part in ipairs(char:GetDescendants()) do
                        if part:IsA("BasePart") then
                                part.CanCollide = true
                        end
                end
        end
end

-- ================================================================
-- // CAMP FARM LOGIC (auto-kill mobs within radius of saved point)
-- ================================================================

-- Create or update the visual radius circle (a flat cylinder on the ground)
local function updateCampCircle()
        if State.campCirclePart then
                State.campCirclePart:Destroy()
                State.campCirclePart = nil
        end
        if not State.campPoint then return end

        local part = Instance.new("Part")
        part.Name = "CampRadiusCircle"
        part.Shape = Enum.PartType.Cylinder
        part.Material = Enum.Material.ForceField
        part.Color = Color3.fromRGB(255, 100, 180)
        part.Transparency = 0.6
        part.Anchored = true
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        -- Cylinder is laid along X axis by default, so rotate to lie flat (along Y vertical)
        -- We want a flat disc on the XZ plane (visible from above)
        part.Size = Vector3.new(0.2, State.campRadius * 2, State.campRadius * 2)
        -- Position: at camp point, slightly above ground (so it doesn't z-fight)
        part.CFrame = CFrame.new(State.campPoint + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
        part.Parent = workspace
        State.campCirclePart = part
end

-- Find nearest alive mob within camp radius (recursive — handles all mob nesting depths)
local function findCampTarget()
        if not State.campPoint then return nil end
        return findNearestMobToPoint(State.campPoint, State.campRadius)
end

-- TELEPORT directly to a mob (instant TP, not gradual fly)
-- Position player based on ATTACK_POSITION setting (below/above/behind/front/custom)
local function tpToMob(mob)
        local char = LocalPlayer.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        local mobHrp = mob:FindFirstChild("HumanoidRootPart")
        if not hrp or not mobHrp then return end
        if hum then hum.PlatformStand = true end

        local mobPos = mobHrp.Position
        local mobCFrame = mobHrp.CFrame
        local targetPos

        -- Stop velocity so we don't drift
        hrp.Velocity = Vector3.new(0, 0, 0)
        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)

        if ATTACK_POSITION == "below" then
                targetPos = mobPos + Vector3.new(0, -BELOW_DISTANCE, 0)
                hrp.CFrame = CFrame.new(targetPos, targetPos + mobCFrame.LookVector)
        elseif ATTACK_POSITION == "above" then
                targetPos = mobPos + Vector3.new(0, ABOVE_DISTANCE, 0)
                hrp.CFrame = CFrame.new(targetPos, targetPos + mobCFrame.LookVector)
        elseif ATTACK_POSITION == "behind" then
                targetPos = mobPos - mobCFrame.LookVector * BEHIND_DISTANCE
                hrp.CFrame = CFrame.new(targetPos, targetPos + mobCFrame.LookVector)
        elseif ATTACK_POSITION == "front" then
                targetPos = mobPos + mobCFrame.LookVector * BEHIND_DISTANCE
                hrp.CFrame = CFrame.lookAt(targetPos, mobPos)
        elseif ATTACK_POSITION == "custom" then
                -- Custom offset applied in WORLD space (X, Y, Z)
                -- If player wants mob-relative, they can think of it as offset from mob position
                targetPos = mobPos + CUSTOM_OFFSET
                -- Face the mob (unless they're directly above/below)
                local diff = targetPos - mobPos
                if diff.Magnitude > 0.1 and math.abs(diff.X) + math.abs(diff.Z) > 0.1 then
                        hrp.CFrame = CFrame.lookAt(targetPos, mobPos)
                else
                        hrp.CFrame = CFrame.new(targetPos, targetPos + mobCFrame.LookVector)
                end
        else
                targetPos = mobPos + Vector3.new(0, -BELOW_DISTANCE, 0)
                hrp.CFrame = CFrame.new(targetPos, targetPos + mobCFrame.LookVector)
        end
end

-- TELEPORT directly to camp point (instant TP, not gradual fly)
local function tpToCampPoint()
        local char = LocalPlayer.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hrp or not State.campPoint then return end
        if hum then hum.PlatformStand = true end
        local target = State.campPoint + Vector3.new(0, 3, 0)  -- hover 3 studs above point
        -- Always TP (even if close, to ensure we're exactly at center)
        hrp.Velocity = Vector3.new(0, 0, 0)
        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        hrp.CFrame = CFrame.new(target)
end

-- Camp attack reuses attackMob() — set currentMob to campTargetMob before calling
local function campAttack()
        if not State.campTargetMob then return end
        local prev = State.currentMob
        State.currentMob = State.campTargetMob
        attackMob()
        State.currentMob = prev
end

local function startCampFarm()
        if State.autoCampFarming then return end
        if not State.campPoint then
                if CampStatusLabel then
                        CampStatusLabel.Text = "Camp: No point set! Click 'Set Point' first"
                        CampStatusLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
                end
                return
        end

        -- Equip weapon (by typed name, or fallback to any weapon)
        local weapon
        if State.campWeaponName and State.campWeaponName ~= "" then
                weapon = findWeaponByName(State.campWeaponName)
        end
        if not weapon then
                weapon = findWeapon()
        end
        if weapon then
                equipWeapon(weapon)
                task.wait(0.5)
        else
                if CampStatusLabel then
                        CampStatusLabel.Text = "Camp: No weapon found!"
                        CampStatusLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
                end
                return
        end

        State.autoCampFarming = true
        State.campLastAttack = 0
        State.campTargetMob = nil
        local lastSearchTime = 0
        local searchInterval = 0.3  -- throttle target search to every 0.3s
        local returnedToCenter = false  -- only TP back to center ONCE per "no target" phase

        -- Noclip (reuse cached pattern)
        State.noclipCacheChar = LocalPlayer.Character
        State.noclipPartsCache = {}
        local function refreshCampNoclip()
                State.noclipCacheChar = LocalPlayer.Character
                State.noclipPartsCache = {}
                if State.noclipCacheChar then
                        for _, part in ipairs(State.noclipCacheChar:GetDescendants()) do
                                if part:IsA("BasePart") then
                                        table.insert(State.noclipPartsCache, part)
                                end
                        end
                end
                State.noclipLastRefresh = tick()
        end
        refreshCampNoclip()
        State.campNoclipConn = RunService.Stepped:Connect(function()
                if tick() - State.noclipLastRefresh > NOCLIP_REFRESH_INTERVAL then
                        refreshCampNoclip()
                end
                for _, part in ipairs(State.noclipPartsCache) do
                        part.CanCollide = false
                end
        end)

        -- Update the visual circle
        updateCampCircle()

        print("[CampFarm] Started. Point: " .. tostring(State.campPoint) .. " | Radius: " .. tostring(State.campRadius))

        -- ===== SINGLE MASTER HEARTBEAT for camp farm =====
        -- Strategy: TP to mob → attack → when dead/missing → TP back to camp point ONCE → fall (gravity)
        State.campMainConn = RunService.Heartbeat:Connect(function()
                if not State.autoCampFarming then return end
                local now = tick()

                -- Validate current target
                if State.campTargetMob then
                        if not State.campTargetMob.Parent then
                                State.campTargetMob = nil
                        else
                                local hum = State.campTargetMob:FindFirstChildOfClass("Humanoid")
                                if not hum or hum.Health <= 0 then
                                        State.campTargetMob = nil
                                else
                                        -- Check if mob wandered out of radius (give some leeway)
                                        local hrp = State.campTargetMob:FindFirstChild("HumanoidRootPart")
                                        if hrp and State.campPoint then
                                                local dist = (hrp.Position - State.campPoint).Magnitude
                                                if dist > State.campRadius * 1.5 then
                                                        -- Mob ran too far, abandon
                                                        State.campTargetMob = nil
                                                end
                                        end
                                end
                        end
                end

                -- If no target, try to find one (throttled)
                if not State.campTargetMob and (now - lastSearchTime) >= searchInterval then
                        lastSearchTime = now
                        State.campTargetMob = findCampTarget()
                        if State.campTargetMob then
                                print("[CampFarm] Target found: " .. State.campTargetMob.Name)
                                if CampStatusLabel then
                                        CampStatusLabel.Text = "Camp: TP to " .. State.campTargetMob.Name
                                        CampStatusLabel.TextColor3 = Color3.fromRGB(255, 180, 220)
                                end
                        end
                end

                -- Act on target
                if State.campTargetMob and State.campTargetMob.Parent then
                        local hum = State.campTargetMob:FindFirstChildOfClass("Humanoid")
                        if hum and hum.Health > 0 then
                                -- We have a target: reset "returned to center" flag
                                returnedToCenter = false
                                -- Re-enable noclip + PlatformStand so we can fly to mob
                                local char = LocalPlayer.Character
                                if char then
                                        local charHum = char:FindFirstChildOfClass("Humanoid")
                                        if charHum then charHum.PlatformStand = true end
                                end
                                -- TP directly to mob every frame (instant teleport)
                                tpToMob(State.campTargetMob)
                                -- Attack at MOB_ATTACK_INTERVAL
                                if now - State.campLastAttack >= MOB_ATTACK_INTERVAL then
                                        State.campLastAttack = now
                                        campAttack()
                                end
                        end
                else
                        -- No target — TP back to camp point ONCE (not every frame)
                        if not returnedToCenter then
                                returnedToCenter = true
                                tpToCampPoint()
                                -- Disable PlatformStand so player falls naturally (gravity)
                                -- Also re-enable collisions so player can land on ground
                                local char = LocalPlayer.Character
                                if char then
                                        local charHum = char:FindFirstChildOfClass("Humanoid")
                                        if charHum then charHum.PlatformStand = false end
                                        for _, part in ipairs(char:GetDescendants()) do
                                                if part:IsA("BasePart") then
                                                        part.CanCollide = true
                                                end
                                        end
                                end
                                if CampStatusLabel then
                                        CampStatusLabel.Text = "Camp: No mobs - returned to center (falling)"
                                        CampStatusLabel.TextColor3 = Color3.fromRGB(200, 200, 130)
                                end
                                print("[CampFarm] No target - TP'd to center, falling")
                        end
                        -- While waiting for a target, keep checking for new mobs
                        -- (the throttled search above handles this)
                end
        end)

        if CampStatusLabel then
                CampStatusLabel.Text = "Camp: ACTIVE | Point set"
                CampStatusLabel.TextColor3 = Color3.fromRGB(100, 255, 180)
        end
end

local function stopCampFarm()
        State.autoCampFarming = false
        State.campTargetMob = nil
        if State.campMainConn then
                State.campMainConn:Disconnect()
                State.campMainConn = nil
        end
        if State.campNoclipConn then
                State.campNoclipConn:Disconnect()
                State.campNoclipConn = nil
        end
        -- Restore collision
        local char = LocalPlayer.Character
        if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then hum.PlatformStand = false end
                for _, part in ipairs(char:GetDescendants()) do
                        if part:IsA("BasePart") then
                                part.CanCollide = true
                        end
                end
        end
        if CampStatusLabel then
                CampStatusLabel.Text = "Camp: Stopped"
                CampStatusLabel.TextColor3 = Color3.fromRGB(140, 150, 180)
        end
end

-- // ORE LIST BUILDER

local oreButtonRefs = {}

local function updateSelectedLabel()
        local count = 0
        local names = {}
        for name, _ in pairs(State.selectedOres) do
                count = count + 1
                table.insert(names, name)
        end
        table.sort(names)
        if count == 0 then
                SelectedLabel.Text = "Selected: None"
                SelectedLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
        elseif count <= 3 then
                SelectedLabel.Text = "Selected: " .. table.concat(names, ", ")
                SelectedLabel.TextColor3 = Color3.fromRGB(100, 200, 130)
        else
                SelectedLabel.Text = "Selected: " .. count .. " ores"
                SelectedLabel.TextColor3 = Color3.fromRGB(100, 200, 130)
        end
end

local function buildOreList(filter)
        for _, child in ipairs(OreScroll:GetChildren()) do
                if child:IsA("TextButton") then
                        child:Destroy()
                end
        end
        oreButtonRefs = {}
        local names = getOreNames()
        local filterLower = filter and filter:lower() or ""
        for _, oreName in ipairs(names) do
                if filterLower == "" or oreName:lower():find(filterLower, 1, true) then
                        local btn = Instance.new("TextButton")
                        btn.Size = UDim2.new(1, 0, 0, 26)
                        btn.BorderSizePixel = 0
                        btn.Text = "  " .. oreName
                        btn.Font = Enum.Font.Gotham
                        btn.TextSize = 12
                        btn.TextXAlignment = Enum.TextXAlignment.Left
                        btn.AutoButtonColor = false
                        btn.Parent = OreScroll
                        local bc = Instance.new("UICorner")
                        bc.CornerRadius = UDim.new(0, 6)
                        bc.Parent = btn
                        local bp = Instance.new("UIPadding")
                        bp.PaddingLeft = UDim.new(0, 6)
                        bp.Parent = btn
                        if State.selectedOres[oreName] then
                                btn.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
                                btn.TextColor3 = Color3.fromRGB(200, 255, 200)
                        else
                                btn.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
                                btn.TextColor3 = Color3.fromRGB(200, 220, 255)
                        end
                        local capturedName = oreName
                        btn.MouseButton1Click:Connect(function()
                                if State.selectedOres[capturedName] then
                                        State.selectedOres[capturedName] = nil
                                        btn.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
                                        btn.TextColor3 = Color3.fromRGB(200, 220, 255)
                                else
                                        State.selectedOres[capturedName] = true
                                        btn.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
                                        btn.TextColor3 = Color3.fromRGB(200, 255, 200)
                                end
                                updateSelectedLabel()
                        end)
                        table.insert(oreButtonRefs, btn)
                end
        end
end

buildOreList("")
updateSelectedLabel()

refreshOreList = function()
        buildOreList(SearchBox.Text)
end

SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
        refreshOreList()
end)

-- FARM UI HELPERS
local function updateFarmButton(isFarming)
        if isFarming then
                AutoFarmBtn.Text = "[ ]  Stop Farm"
                AutoFarmBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
                AllOresBtn.Text = "[ ]  Stop"
                AllOresBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
        else
                AutoFarmBtn.Text = ">  Auto Farm"
                AutoFarmBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
                AllOresBtn.Text = "[M]  All Ores"
                AllOresBtn.BackgroundColor3 = Color3.fromRGB(140, 80, 180)
        end
end

local function updateStatusLabel()
        if not State.autoFarming then
                StatusLabel.Text = "Status: Idle | Fly: OFF"
                StatusLabel.TextColor3 = Color3.fromRGB(140, 150, 180)
        else
                local oreName = State.currentOreQueue[State.currentOreQueueIndex] or "?"
                StatusLabel.Text = "Mining: " .. oreName .. " [" .. tostring(State.currentPartIndex) .. "] | Fly: ON"
                StatusLabel.TextColor3 = Color3.fromRGB(100, 220, 255)
        end
end

-- STOP FARM
local function stopAutoFarm()
        State.autoFarming = false
        if State.swingConnection then
                State.swingConnection:Disconnect()
                State.swingConnection = nil
        end
        if State.flyConnection then
                State.flyConnection:Disconnect()
                State.flyConnection = nil
        end
        if State.oreWatchConnection then
                State.oreWatchConnection:Disconnect()
                State.oreWatchConnection = nil
        end
        if State.respawnConnection then
                State.respawnConnection:Disconnect()
                State.respawnConnection = nil
        end
        State.currentPart = nil
        stopNoclip()
end

-- MINING CYCLE
local startMiningPartFunc
local advanceToNextOreFunc
local moveToCurrentOreFunc

startMiningPartFunc = function(part)
        if State.oreWatchConnection then
                State.oreWatchConnection:Disconnect()
                State.oreWatchConnection = nil
        end
        State.currentPart = part
        deleteBase(part)
        flyUnderAndFacePart(part)
        updateStatusLabel()
        State.oreWatchConnection = part.AncestryChanged:Connect(function(_, newParent)
                if newParent == nil and State.autoFarming then
                        if State.oreWatchConnection then
                                State.oreWatchConnection:Disconnect()
                                State.oreWatchConnection = nil
                        end
                        task.wait(0.2)
                        State.currentPartIndex = State.currentPartIndex + 1
                        local oreName = State.currentOreQueue[State.currentOreQueueIndex]
                        local parts = getAllPartsOfOre(oreName)
                        if #parts == 0 or State.currentPartIndex > #parts then
                                advanceToNextOreFunc()
                                return
                        end
                        local nextPart = parts[State.currentPartIndex]
                        if nextPart then
                                startMiningPartFunc(nextPart)
                        else
                                advanceToNextOreFunc()
                        end
                end
        end)
end

advanceToNextOreFunc = function()
        State.currentOreQueueIndex = State.currentOreQueueIndex + 1
        if State.currentOreQueueIndex > #State.currentOreQueue then
                State.currentOreQueueIndex = 1
        end
        task.wait(0.3)
        moveToCurrentOreFunc()
end

moveToCurrentOreFunc = function()
        if not State.autoFarming then return end
        local oreName = State.currentOreQueue[State.currentOreQueueIndex]
        if not oreName then
                stopAutoFarm()
                updateFarmButton(false)
                updateStatusLabel()
                return
        end
        local parts = getAllPartsOfOre(oreName)
        if #parts == 0 then
                local attempts = 0
                repeat
                        State.currentOreQueueIndex = State.currentOreQueueIndex + 1
                        if State.currentOreQueueIndex > #State.currentOreQueue then
                                State.currentOreQueueIndex = 1
                        end
                        oreName = State.currentOreQueue[State.currentOreQueueIndex]
                        parts = getAllPartsOfOre(oreName)
                        attempts = attempts + 1
                until #parts > 0 or attempts > #State.currentOreQueue
        end
        if #parts > 0 then
                if State.respawnConnection then
                        State.respawnConnection:Disconnect()
                        State.respawnConnection = nil
                end
                State.currentPartIndex = 1
                startMiningPartFunc(parts[1])
        else
                State.currentPart = nil
                if State.respawnConnection then
                        State.respawnConnection:Disconnect()
                        State.respawnConnection = nil
                end
                StatusLabel.Text = "Waiting for respawn..."
                StatusLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
                local respawnCheckTick = 0
                State.respawnConnection = RunService.Heartbeat:Connect(function()
                        if not State.autoFarming then return end
                        local now = tick()
                        if now - respawnCheckTick < 2 then return end
                        respawnCheckTick = now
                        for _, checkName in ipairs(State.currentOreQueue) do
                                local checkParts = getAllPartsOfOre(checkName)
                                if #checkParts > 0 then
                                        for idx, qName in ipairs(State.currentOreQueue) do
                                                if qName == checkName then
                                                        State.currentOreQueueIndex = idx
                                                        break
                                                end
                                        end
                                        moveToCurrentOreFunc()
                                        return
                                end
                        end
                end)
        end
end

local function startAutoFarm()
        if #State.currentOreQueue == 0 then return end
        local pickaxe = findPickaxe()
        if pickaxe then
                equipPickaxe(pickaxe)
                task.wait(0.6)
        else
                warn("[AutoMiner] No pickaxe found.")
                return
        end
        State.autoFarming = true
        State.currentOreQueueIndex = 1
        startNoclip()
        moveToCurrentOreFunc()
        -- Fly
        if State.flyConnection then State.flyConnection:Disconnect() end
        State.flyConnection = RunService.Heartbeat:Connect(function()
                if not State.autoFarming then return end
                if State.currentPart and State.currentPart.Parent then
                        flyUnderAndFacePart(State.currentPart)
                end
        end)
        -- Swing
        if State.swingConnection then State.swingConnection:Disconnect() end
        local lastSwing = 0
        State.swingConnection = RunService.Heartbeat:Connect(function()
                if not State.autoFarming then return end
                local now = tick()
                if now - lastSwing >= SWING_INTERVAL then
                        lastSwing = now
                        swingPickaxe()
                end
        end)
end

local function buildOreQueue()
        local queue = {}
        local names = getOreNames()
        for _, name in ipairs(names) do
                if State.selectedOres[name] then
                        table.insert(queue, name)
                end
        end
        return queue
end

-- // MOB LIST BUILDER
local mobButtonRefs = {}

local function updateMobSelectedLabel()
        local count = 0
        local names = {}
        for name, _ in pairs(State.selectedMobs) do
                count = count + 1
                table.insert(names, name)
        end
        table.sort(names)
        if count == 0 then
                MobSelectedLabel.Text = "Selected: None"
                MobSelectedLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
        elseif count <= 3 then
                MobSelectedLabel.Text = "Selected: " .. table.concat(names, ", ")
                MobSelectedLabel.TextColor3 = Color3.fromRGB(100, 200, 130)
        else
                MobSelectedLabel.Text = "Selected: " .. count .. " mobs"
                MobSelectedLabel.TextColor3 = Color3.fromRGB(100, 200, 130)
        end
end

refreshMobList = function(force)
        -- Debounce: skip if called too recently (unless forced)
        local now = tick()
        if not force and (now - State.lastMobRefresh) < MOB_REFRESH_DEBOUNCE then
                return
        end
        State.lastMobRefresh = now

        for _, child in ipairs(MobScroll:GetChildren()) do
                if child:IsA("TextButton") then
                        child:Destroy()
                end
        end
        mobButtonRefs = {}
        local names = getMobNames()
        local filterLower = MobSearchBox and MobSearchBox.Text:lower() or ""
        for _, mobName in ipairs(names) do
                if filterLower == "" or mobName:lower():find(filterLower, 1, true) then
                        local btn = Instance.new("TextButton")
                        btn.Size = UDim2.new(1, 0, 0, 26)
                        btn.BorderSizePixel = 0
                        btn.Text = "  " .. mobName
                        btn.Font = Enum.Font.Gotham
                        btn.TextSize = 12
                        btn.TextXAlignment = Enum.TextXAlignment.Left
                        btn.AutoButtonColor = false
                        btn.Parent = MobScroll
                        local bc = Instance.new("UICorner")
                        bc.CornerRadius = UDim.new(0, 6)
                        bc.Parent = btn
                        local bp = Instance.new("UIPadding")
                        bp.PaddingLeft = UDim.new(0, 6)
                        bp.Parent = btn
                        if State.selectedMobs[mobName] then
                                btn.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
                                btn.TextColor3 = Color3.fromRGB(200, 255, 200)
                        else
                                btn.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
                                btn.TextColor3 = Color3.fromRGB(200, 220, 255)
                        end
                        local capturedName = mobName
                        btn.MouseButton1Click:Connect(function()
                                if State.selectedMobs[capturedName] then
                                        State.selectedMobs[capturedName] = nil
                                        btn.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
                                        btn.TextColor3 = Color3.fromRGB(200, 220, 255)
                                else
                                        State.selectedMobs[capturedName] = true
                                        btn.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
                                        btn.TextColor3 = Color3.fromRGB(200, 255, 200)
                                end
                                updateMobSelectedLabel()
                        end)
                        table.insert(mobButtonRefs, btn)
                end
        end
        updateMobSelectedLabel()
end

pcall(function() refreshMobList(true) end)

MobSearchBox:GetPropertyChangedSignal("Text"):Connect(function()
        refreshMobList(true)
end)

-- MOB ATTACK TYPE TOGGLES
LightBtn.MouseButton1Click:Connect(function()
        State.attackTypes[1] = not State.attackTypes[1]
        LightBtn.BackgroundColor3 = State.attackTypes[1] and Color3.fromRGB(40, 120, 60) or Color3.fromRGB(60, 60, 80)
        LightBtn.TextColor3 = State.attackTypes[1] and Color3.fromRGB(200, 255, 200) or Color3.fromRGB(180, 180, 200)
end)

HeavyBtn.MouseButton1Click:Connect(function()
        State.attackTypes[2] = not State.attackTypes[2]
        HeavyBtn.BackgroundColor3 = State.attackTypes[2] and Color3.fromRGB(40, 120, 60) or Color3.fromRGB(60, 60, 80)
        HeavyBtn.TextColor3 = State.attackTypes[2] and Color3.fromRGB(200, 255, 200) or Color3.fromRGB(180, 180, 200)
end)

TechBtn.MouseButton1Click:Connect(function()
        State.attackTypes[3] = not State.attackTypes[3]
        TechBtn.BackgroundColor3 = State.attackTypes[3] and Color3.fromRGB(40, 120, 60) or Color3.fromRGB(60, 60, 80)
        TechBtn.TextColor3 = State.attackTypes[3] and Color3.fromRGB(200, 255, 200) or Color3.fromRGB(180, 180, 200)
end)

-- MOB DISTANCE
MobDistDownBtn.MouseButton1Click:Connect(function()
        local y = math.abs(MOB_FLY_OFFSET.Y) - 1
        y = math.max(1, y)
        MOB_FLY_OFFSET = Vector3.new(0, -y, 0)
        MobDistLabel.Text = "Below mob: " .. tostring(y) .. " studs"
end)

MobDistUpBtn.MouseButton1Click:Connect(function()
        local y = math.abs(MOB_FLY_OFFSET.Y) + 1
        y = math.min(20, y)
        MOB_FLY_OFFSET = Vector3.new(0, -y, 0)
        MobDistLabel.Text = "Below mob: " .. tostring(y) .. " studs"
end)

-- MOB ATTACK SPEED
MobAtkDownBtn.MouseButton1Click:Connect(function()
        MOB_ATTACK_INTERVAL = math.max(0.1, MOB_ATTACK_INTERVAL - 0.05)
        MobAtkLabel.Text = "Attack Speed: " .. string.format("%.2f", MOB_ATTACK_INTERVAL) .. "s"
end)

MobAtkUpBtn.MouseButton1Click:Connect(function()
        MOB_ATTACK_INTERVAL = math.min(2.0, MOB_ATTACK_INTERVAL + 0.05)
        MobAtkLabel.Text = "Attack Speed: " .. string.format("%.2f", MOB_ATTACK_INTERVAL) .. "s"
end)

-- MOB SELECT ALL / CLEAR ALL
MobSelAllBtn.MouseButton1Click:Connect(function()
        local names = getMobNames()
        for _, name in ipairs(names) do
                State.selectedMobs[name] = true
        end
        refreshMobList(true)
end)

MobClrAllBtn.MouseButton1Click:Connect(function()
        State.selectedMobs = {}
        refreshMobList(true)
end)

-- MOB FARM BUTTON
local function updateMobFarmBtn(isFarming)
        if isFarming then
                MobFarmBtn.Text = "[ ]  Stop Mob"
                MobFarmBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
                MobAllBtn.Text = "[ ]  Stop"
                MobAllBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
        else
                MobFarmBtn.Text = ">  Mob Farm"
                MobFarmBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
                MobAllBtn.Text = "[M]  All Mobs"
                MobAllBtn.BackgroundColor3 = Color3.fromRGB(140, 80, 180)
        end
end

MobFarmBtn.MouseButton1Click:Connect(function()
        if State.autoMobFarming then
                stopAutoMobFarm()
                updateMobFarmBtn(false)
                MobStatusLabel.Text = "Status: Idle"
                MobStatusLabel.TextColor3 = Color3.fromRGB(140, 150, 180)
                return
        end
        -- Build queue
        local queue = {}
        local names = getMobNames()
        for _, name in ipairs(names) do
                if State.selectedMobs[name] then
                        table.insert(queue, name)
                end
        end
        if #queue == 0 then
                MobSelectedLabel.Text = "! Select at least 1 mob!"
                MobSelectedLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
                task.delay(2, function() updateMobSelectedLabel() end)
                return
        end
        State.currentMobQueue = queue
        State.currentMobQueueIndex = 1
        updateMobFarmBtn(true)
        startAutoMobFarm()
end)

MobAllBtn.MouseButton1Click:Connect(function()
        if State.autoMobFarming then
                stopAutoMobFarm()
                updateMobFarmBtn(false)
                MobStatusLabel.Text = "Status: Idle"
                MobStatusLabel.TextColor3 = Color3.fromRGB(140, 150, 180)
                return
        end
        local names = getMobNames()
        if #names == 0 then
                warn("[AutoMob] No mobs found in workspace.")
                return
        end
        State.selectedMobs = {}
        for _, name in ipairs(names) do
                State.selectedMobs[name] = true
        end
        refreshMobList(true)
        State.currentMobQueue = names
        State.currentMobQueueIndex = 1
        updateMobFarmBtn(true)
        startAutoMobFarm()
end)

-- ================================================================
-- // AUTO DEPOSIT GOLD (event-driven, no polling)
-- ================================================================

local function getGoldValue()
        local playerStats = LocalPlayer:FindFirstChild("PlayerStats")
        if not playerStats then return nil end
        local gold = playerStats:FindFirstChild("Gold")
        if not gold then return nil end
        return gold
end

local function fireBankDeposit()
        local bank = ReplicatedStorage:FindFirstChild("Remotes")
        if bank then bank = bank:FindFirstChild("Bank") end
        if not bank then
                warn("[AutoDeposit] Bank remote not found")
                return false
        end
        local ok, err = pcall(function()
                bank:InvokeServer(true, 1)
        end)
        if not ok then
                warn("[AutoDeposit] InvokeServer error: " .. tostring(err))
                return false
        end
        return true
end

local function startAutoDepositGold()
        if State.autoDepositGold then return end
        State.autoDepositGold = true
        State.lastDepositTime = 0

        if GoldStatus then
                GoldStatus.Text = "Watching gold..."
                GoldStatus.TextColor3 = Color3.fromRGB(100, 220, 255)
        end
        print("[AutoDeposit] Started - will deposit whenever Gold > 0")

        -- EVENT-DRIVEN: GetPropertyChangedSignal fires only when Gold.Value changes
        -- Strategy: when gold changes, if current gold > 0, deposit it (with cooldown)
        State.goldConn = nil
        local function hookGold()
                local gold = getGoldValue()
                if not gold then return false end
                if State.goldConn then State.goldConn:Disconnect() end
                State.goldConn = gold:GetPropertyChangedSignal("Value"):Connect(function()
                        if not State.autoDepositGold then return end
                        local currentGold = gold.Value

                        -- Only deposit if gold > 0
                        if currentGold > 0 then
                                local now = tick()
                                -- Cooldown to prevent Bank remote spam
                                if now - State.lastDepositTime < AUTO_DEPOSIT_COOLDOWN then
                                        if GoldStatus then
                                                GoldStatus.Text = "Gold: " .. tostring(currentGold) .. " (cooldown...)"
                                                GoldStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
                                        end
                                        return
                                end
                                State.lastDepositTime = now

                                if GoldStatus then
                                        GoldStatus.Text = "Depositing " .. tostring(currentGold) .. " gold..."
                                        GoldStatus.TextColor3 = Color3.fromRGB(100, 255, 150)
                                end

                                local success = fireBankDeposit()

                                if GoldStatus then
                                        if success then
                                                GoldStatus.Text = "Deposited! (waiting for next gain)"
                                                GoldStatus.TextColor3 = Color3.fromRGB(100, 220, 130)
                                        else
                                                GoldStatus.Text = "Deposit failed - will retry next change"
                                                GoldStatus.TextColor3 = Color3.fromRGB(255, 120, 120)
                                        end
                                end
                        else
                                if GoldStatus then
                                        GoldStatus.Text = "Gold: 0 (waiting...)"
                                        GoldStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
                                end
                        end
                end)
                -- Also do an immediate check on hook
                if gold.Value > 0 then
                        task.spawn(function()
                                task.wait(0.1)
                                if State.autoDepositGold and gold.Value > 0 then
                                        State.lastDepositTime = 0  -- force deposit
                                        -- Manually trigger by reading value (the connection won't fire if no change)
                                        local currentGold = gold.Value
                                        if GoldStatus then
                                                GoldStatus.Text = "Depositing " .. tostring(currentGold) .. " gold..."
                                                GoldStatus.TextColor3 = Color3.fromRGB(100, 255, 150)
                                        end
                                        local success = fireBankDeposit()
                                        State.lastDepositTime = tick()
                                        if GoldStatus then
                                                GoldStatus.Text = success and "Deposited!" or "Deposit failed"
                                                GoldStatus.TextColor3 = success and Color3.fromRGB(100, 220, 130) or Color3.fromRGB(255, 120, 120)
                                        end
                                end
                        end)
                end
                return true
        end

        -- Try to hook immediately; if PlayerStats doesn't exist yet, wait and retry
        task.spawn(function()
                while State.autoDepositGold do
                        if hookGold() then break end
                        task.wait(2)
                end
        end)
end

local function stopAutoDepositGold()
        State.autoDepositGold = false
        if State.goldConn then
                State.goldConn:Disconnect()
                State.goldConn = nil
        end
        if GoldStatus then
                GoldStatus.Text = "Status: Stopped"
                GoldStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
        end
        print("[AutoDeposit] Stopped")
end

AutoDepositBtn.MouseButton1Click:Connect(function()
        if State.autoDepositGold then
                stopAutoDepositGold()
                AutoDepositBtn.Text = "Auto Deposit: OFF"
                AutoDepositBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
                AutoDepositBtn.TextColor3 = Color3.fromRGB(220, 220, 240)
        else
                startAutoDepositGold()
                AutoDepositBtn.Text = "Auto Deposit: ON"
                AutoDepositBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
                AutoDepositBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        end
end)

-- Keep threshold buttons but make them adjust the COOLDOWN instead (since threshold no longer needed)
GoldThreshDownBtn.MouseButton1Click:Connect(function()
        AUTO_DEPOSIT_COOLDOWN = math.max(0.5, AUTO_DEPOSIT_COOLDOWN - 0.5)
        GoldThresholdLabel.Text = "Cooldown: " .. string.format("%.1f", AUTO_DEPOSIT_COOLDOWN) .. "s"
end)

GoldThreshUpBtn.MouseButton1Click:Connect(function()
        AUTO_DEPOSIT_COOLDOWN = math.min(30, AUTO_DEPOSIT_COOLDOWN + 0.5)
        GoldThresholdLabel.Text = "Cooldown: " .. string.format("%.1f", AUTO_DEPOSIT_COOLDOWN) .. "s"
end)

-- ================================================================
-- // CAMP FARM UI HANDLERS
-- ================================================================

-- Equip weapon by typed name
EquipWeaponBtn.MouseButton1Click:Connect(function()
        local name = WeaponNameBox.Text
        if not name or name == "" then
                if CampStatusLabel then
                        CampStatusLabel.Text = "Camp: Type a weapon name first"
                        CampStatusLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
                end
                return
        end
        State.campWeaponName = name
        local weapon = findWeaponByName(name)
        if weapon then
                equipWeapon(weapon)
                if CampStatusLabel then
                        CampStatusLabel.Text = "Camp: Equipped " .. name
                        CampStatusLabel.TextColor3 = Color3.fromRGB(100, 220, 255)
                end
                EquipWeaponBtn.Text = "Equipped!"
                task.delay(1, function()
                        EquipWeaponBtn.Text = "Equip"
                end)
        else
                if CampStatusLabel then
                        CampStatusLabel.Text = "Camp: Weapon '" .. name .. "' not found"
                        CampStatusLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
                end
        end
end)

-- Save current player position as camp point
SetPointBtn.MouseButton1Click:Connect(function()
        local char = LocalPlayer.Character
        if not char then
                if CampStatusLabel then
                        CampStatusLabel.Text = "Camp: No character!"
                        CampStatusLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
                end
                return
        end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        State.campPoint = hrp.Position
        updateCampCircle()
        if CampStatusLabel then
                CampStatusLabel.Text = "Camp: Point saved at (" ..
                        string.format("%.0f", State.campPoint.X) .. ", " ..
                        string.format("%.0f", State.campPoint.Y) .. ", " ..
                        string.format("%.0f", State.campPoint.Z) .. ")"
                CampStatusLabel.TextColor3 = Color3.fromRGB(255, 180, 220)
        end
        SetPointBtn.Text = "Set Point (here)"
        task.delay(0.5, function()
                SetPointBtn.Text = "Re-set Point"
        end)
end)

-- Clear the camp point
ClearPointBtn.MouseButton1Click:Connect(function()
        State.campPoint = nil
        if State.campCirclePart then
                State.campCirclePart:Destroy()
                State.campCirclePart = nil
        end
        if State.autoCampFarming then
                stopCampFarm()
                CampFarmBtn.Text = ">  Start Camp Farm"
                CampFarmBtn.BackgroundColor3 = Color3.fromRGB(180, 80, 120)
        end
        if CampStatusLabel then
                CampStatusLabel.Text = "Camp: Point cleared"
                CampStatusLabel.TextColor3 = Color3.fromRGB(140, 150, 180)
        end
        SetPointBtn.Text = "Set Point (here)"
end)

-- Radius adjuster
CampRadiusDownBtn.MouseButton1Click:Connect(function()
        State.campRadius = math.max(5, State.campRadius - 5)
        CampRadiusLabel.Text = "Radius: " .. tostring(State.campRadius) .. " studs"
        if State.campPoint then updateCampCircle() end
end)

CampRadiusUpBtn.MouseButton1Click:Connect(function()
        State.campRadius = math.min(200, State.campRadius + 5)
        CampRadiusLabel.Text = "Radius: " .. tostring(State.campRadius) .. " studs"
        if State.campPoint then updateCampCircle() end
end)

-- Start/Stop camp farm
CampFarmBtn.MouseButton1Click:Connect(function()
        if State.autoCampFarming then
                stopCampFarm()
                CampFarmBtn.Text = ">  Start Camp Farm"
                CampFarmBtn.BackgroundColor3 = Color3.fromRGB(180, 80, 120)
        else
                -- Save typed weapon name (if any)
                State.campWeaponName = WeaponNameBox.Text
                startCampFarm()
                if State.autoCampFarming then
                        CampFarmBtn.Text = "[ ]  Stop Camp Farm"
                        CampFarmBtn.BackgroundColor3 = Color3.fromRGB(120, 40, 80)
                end
        end
end)

-- ================================================================
-- // ATTACK POSITION SELECTOR (applies to mob farm AND camp farm)
-- ================================================================

local function setAttackPosition(pos)
        ATTACK_POSITION = pos
        -- Update button colors to reflect selection
        local function updateBtn(btn, isSelected)
                btn.BackgroundColor3 = isSelected and Color3.fromRGB(40, 160, 80) or Color3.fromRGB(60, 60, 80)
                btn.TextColor3 = isSelected and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(220, 220, 240)
        end
        updateBtn(AtkPosBelowBtn, pos == "below")
        updateBtn(AtkPosAboveBtn, pos == "above")
        updateBtn(AtkPosBehindBtn, pos == "behind")
        updateBtn(AtkPosFrontBtn, pos == "front")
        updateBtn(AtkPosCustomBtn, pos == "custom")
        print("[AttackPos] Set to: " .. pos)
end

AtkPosBelowBtn.MouseButton1Click:Connect(function() setAttackPosition("below") end)
AtkPosAboveBtn.MouseButton1Click:Connect(function() setAttackPosition("above") end)
AtkPosBehindBtn.MouseButton1Click:Connect(function() setAttackPosition("behind") end)
AtkPosFrontBtn.MouseButton1Click:Connect(function() setAttackPosition("front") end)
AtkPosCustomBtn.MouseButton1Click:Connect(function() setAttackPosition("custom") end)

-- Below/Above distance adjuster
BelowAboveDistDownBtn.MouseButton1Click:Connect(function()
        BELOW_DISTANCE = math.max(1, BELOW_DISTANCE - 1)
        ABOVE_DISTANCE = math.max(1, ABOVE_DISTANCE - 1)
        BelowAboveDistLabel.Text = "Below/Above dist: " .. tostring(BELOW_DISTANCE) .. " studs"
end)

BelowAboveDistUpBtn.MouseButton1Click:Connect(function()
        BELOW_DISTANCE = math.min(20, BELOW_DISTANCE + 1)
        ABOVE_DISTANCE = math.min(20, ABOVE_DISTANCE + 1)
        BelowAboveDistLabel.Text = "Below/Above dist: " .. tostring(BELOW_DISTANCE) .. " studs"
end)

-- Behind/Front distance adjuster
BehindDistDownBtn.MouseButton1Click:Connect(function()
        BEHIND_DISTANCE = math.max(1, BEHIND_DISTANCE - 1)
        BehindDistLabel.Text = "Behind/Front dist: " .. tostring(BEHIND_DISTANCE) .. " studs"
end)

BehindDistUpBtn.MouseButton1Click:Connect(function()
        BEHIND_DISTANCE = math.min(20, BEHIND_DISTANCE + 1)
        BehindDistLabel.Text = "Behind/Front dist: " .. tostring(BEHIND_DISTANCE) .. " studs"
end)

-- Custom offset parser - takes "x,y,z" string and converts to Vector3
local function parseCustomOffset(text)
        -- Try to split by comma
        local parts = {}
        for num in string.gmatch(text, "(-?%d+%.?%d*)") do
                table.insert(parts, tonumber(num))
        end
        if #parts >= 3 then
                return Vector3.new(parts[1], parts[2], parts[3]), nil
        end
        return nil, "Need 3 numbers separated by commas (e.g. 10,10,4)"
end

CustomOffsetApplyBtn.MouseButton1Click:Connect(function()
        local text = CustomOffsetBox.Text
        local parsed, err = parseCustomOffset(text)
        if parsed then
                CUSTOM_OFFSET = parsed
                -- Auto-switch to "custom" mode so user sees immediate effect
                setAttackPosition("custom")
                CustomOffsetApplyBtn.Text = "Applied!"
                print("[AttackPos] Custom offset set to: " .. tostring(parsed))
                task.delay(1, function()
                        CustomOffsetApplyBtn.Text = "Apply"
                end)
        else
                CustomOffsetApplyBtn.Text = "Invalid!"
                warn("[AttackPos] Custom offset parse error: " .. tostring(err))
                task.delay(1.5, function()
                        CustomOffsetApplyBtn.Text = "Apply"
                end)
        end
end)

-- ================================================================
-- // AUTO BOW SHOOT (aims at selected mobs)
-- ================================================================

-- Find nearest alive mob that matches the user's selected mobs list
local function findNearestSelectedMobForBow(maxDist)
        local char = LocalPlayer.Character
        if not char then return nil end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return nil end
        local pos = hrp.Position

        local nearestMob = nil
        local nearestDist = maxDist or math.huge

        -- Use the recursive forEachMob helper
        local mobsFolder = workspace:FindFirstChild("Mobs")
        if not mobsFolder then return nil end

        forEachMob(mobsFolder, function(mob, hum)
                if hum.Health > 0 then
                        -- Only target mobs that are in the user's selected list
                        -- If no mobs selected, target ALL mobs (fallback)
                        local isSelected = false
                        if State.selectedMobs and next(State.selectedMobs) then
                                isSelected = State.selectedMobs[mob.Name] == true
                        else
                                isSelected = true  -- no selection = target everything
                        end

                        if isSelected then
                                local mobHrp = mob:FindFirstChild("HumanoidRootPart")
                                if mobHrp then
                                        local dist = (mobHrp.Position - pos).Magnitude
                                        if dist <= nearestDist then
                                                nearestDist = dist
                                                nearestMob = mob
                                        end
                                end
                        end
                end
        end)
        return nearestMob
end

-- Find the Shoot remote on the player's currently equipped bow (by name)
local function findBowShootRemote(bowName)
        if not bowName or bowName == "" then return nil end
        local char = LocalPlayer.Character
        if not char then return nil end
        -- Check if bow is equipped (in character)
        local bow = char:FindFirstChild(bowName)
        if bow and bow:FindFirstChild("Shoot") then
                return bow.Shoot
        end
        -- Check backpack (need to equip it first)
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        if backpack then
                local bowTool = backpack:FindFirstChild(bowName)
                if bowTool and bowTool:IsA("Tool") then
                        local hum = char:FindFirstChildOfClass("Humanoid")
                        if hum then
                                hum:EquipTool(bowTool)
                                task.wait(0.1)
                                -- Re-check character after equip
                                bow = char:FindFirstChild(bowName)
                                if bow and bow:FindFirstChild("Shoot") then
                                        return bow.Shoot
                                end
                        end
                end
        end
        return nil
end

local function startAutoBow()
        if State.autoBow then return end
        local bowName = BowNameBox.Text
        if not bowName or bowName == "" then
                if BowStatus then
                        BowStatus.Text = "Type a bow name first!"
                        BowStatus.TextColor3 = Color3.fromRGB(255, 120, 120)
                end
                return
        end
        State.bowName = bowName
        State.autoBow = true
        AutoBowBtn.Text = "[ ]  Stop Auto Bow"
        AutoBowBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 80)

        if BowStatus then
                BowStatus.Text = "Auto Bow ON - aiming at selected mobs..."
                BowStatus.TextColor3 = Color3.fromRGB(100, 220, 255)
        end
        print("[AutoBow] Started with bow: " .. bowName .. " | rate: " .. tostring(State.bowShootRate) .. "s")

        State.bowThread = task.spawn(function()
                local lastShot = 0
                while State.autoBow do
                        local now = tick()
                        if now - lastShot >= State.bowShootRate then
                                lastShot = now
                                -- Find target (nearest selected mob within 300 studs)
                                local targetMob = findNearestSelectedMobForBow(300)
                                if targetMob then
                                        local mobHrp = targetMob:FindFirstChild("HumanoidRootPart")
                                        if mobHrp then
                                                -- Find the bow's Shoot remote
                                                local shootRemote = findBowShootRemote(State.bowName)
                                                if shootRemote then
                                                        pcall(function()
                                                                shootRemote:InvokeServer(
                                                                        mobHrp.Position,
                                                                        "Arrow",
                                                                        true,
                                                                        1
                                                                )
                                                        end)
                                                        if BowStatus then
                                                                BowStatus.Text = "Shooting " .. targetMob.Name .. "..."
                                                                BowStatus.TextColor3 = Color3.fromRGB(100, 220, 130)
                                                        end
                                                else
                                                        if BowStatus then
                                                                BowStatus.Text = "Bow '" .. State.bowName .. "' not equipped/found"
                                                                BowStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
                                                        end
                                                end
                                        end
                                else
                                        if BowStatus then
                                                BowStatus.Text = "No selected mobs in range..."
                                                BowStatus.TextColor3 = Color3.fromRGB(200, 200, 130)
                                        end
                                end
                        end
                        task.wait(0.05)  -- short sleep between checks (rate-throttled above)
                end
        end)
end

local function stopAutoBow()
        State.autoBow = false
        AutoBowBtn.Text = ">  Start Auto Bow"
        AutoBowBtn.BackgroundColor3 = Color3.fromRGB(80, 100, 160)
        if BowStatus then
                BowStatus.Text = "Stopped"
                BowStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
        end
        print("[AutoBow] Stopped")
end

AutoBowBtn.MouseButton1Click:Connect(function()
        if State.autoBow then
                stopAutoBow()
        else
                startAutoBow()
        end
end)

BowRateDownBtn.MouseButton1Click:Connect(function()
        State.bowShootRate = math.max(0.05, State.bowShootRate - 0.05)
        BowRateLabel.Text = "Bow Shoot Rate: " .. string.format("%.2f", State.bowShootRate) .. "s"
end)

BowRateUpBtn.MouseButton1Click:Connect(function()
        State.bowShootRate = math.min(2.0, State.bowShootRate + 0.05)
        BowRateLabel.Text = "Bow Shoot Rate: " .. string.format("%.2f", State.bowShootRate) .. "s"
end)

-- ================================================================
-- // KILL SCRIPT — stops everything and destroys UI
-- ================================================================

local function killScript()
        print("[Pilgrammed] Kill script activated - shutting down everything")

        -- Stop all features (wrapped in pcall in case state is mid-transition)
        pcall(function()
                if State.autoFarming then
                        -- Call stopAutoFarm if exists (we need to find it)
                        -- Since we don't have direct ref, just disconnect everything
                end
                if State.autoMobFarming then
                        -- stopAutoMobFarm exists in scope
                end
                if State.autoCampFarming then stopCampFarm() end
                if State.autoParry then stopAutoParry() end
                if State.spamParry then stopSpamParry() end
                if State.autoDepositGold then stopAutoDepositGold() end
                if State.autoCronoKey then stopCronoKeyCollect() end
                if State.autoDeleteEnemies then stopAutoDelete() end
                if State.autoBow then stopAutoBow() end
                if State.autoFish then stopAutoFish() end
                if State.fishDiscovery then stopFishDiscovery() end
                if State.autoRifts then stopAutoRifts() end
        end)

        -- Disconnect ALL connections in State
        pcall(function()
                local conns = {
                        State.swingConnection, State.flyConnection, State.oreWatchConnection,
                        State.respawnConnection, State.noclipConnection,
                        State.parryConnection, State.parryHealthConn, State.npcWatchConn,
                        State.attackWarningConn,
                        State.mobMainConnection, State.mobWatchConnection, State.mobNoclipConn,
                        State.campMainConn, State.campNoclipConn,
                        State.goldConn,
                }
                for _, c in ipairs(conns) do
                        if c then pcall(function() c:Disconnect() end) end
                end
                for _, c in ipairs(State.mobSpawnConns or {}) do
                        pcall(function() c:Disconnect() end)
                end
                for _, c in ipairs(mobRefreshConns or {}) do
                        pcall(function() c:Disconnect() end)
                end
                for _, c in ipairs(State.deleteConns or {}) do
                        pcall(function() c:Disconnect() end)
                end
                for _, c in ipairs(State.fishConns or {}) do
                        pcall(function() c:Disconnect() end)
                end
                for _, c in ipairs(State.riftsConns or {}) do
                        pcall(function() c:Disconnect() end)
                end
        end)

        -- Restore character (un-noclip, un-platform-stand)
        pcall(function()
                local char = LocalPlayer.Character
                if char then
                        local hum = char:FindFirstChildOfClass("Humanoid")
                        if hum then hum.PlatformStand = false end
                        for _, part in ipairs(char:GetDescendants()) do
                                if part:IsA("BasePart") then
                                        part.CanCollide = true
                                end
                        end
                end
        end)

        -- Remove camp visual circle
        pcall(function()
                if State.campCirclePart then
                        State.campCirclePart:Destroy()
                        State.campCirclePart = nil
                end
        end)

        -- Destroy the entire UI
        pcall(function()
                if ScreenGui then
                        ScreenGui:Destroy()
                end
        end)

        -- Final message (will print to console since UI is gone)
        print("[Pilgrammed] Script killed. All features stopped, UI destroyed.")
end

KillScriptBtn.MouseButton1Click:Connect(function()
        killScript()
end)

-- MOVE TOGGLE SETTING
MoveToggleBtn.MouseButton1Click:Connect(function()
        State.toggleSquareMoveable = not State.toggleSquareMoveable
        if State.toggleSquareMoveable then
                MoveToggleBtn.Text = "ON"
                MoveToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
                MoveToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        else
                MoveToggleBtn.Text = "OFF"
                MoveToggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
                MoveToggleBtn.TextColor3 = Color3.fromRGB(180, 180, 200)
        end
end)

-- SWING INTERVAL
SwingDownBtn.MouseButton1Click:Connect(function()
        SWING_INTERVAL = math.max(0.1, SWING_INTERVAL - 0.05)
        SwingLabel.Text = "Swing Interval: " .. string.format("%.2f", SWING_INTERVAL) .. "s"
end)

SwingUpBtn.MouseButton1Click:Connect(function()
        SWING_INTERVAL = math.min(1.0, SWING_INTERVAL + 0.05)
        SwingLabel.Text = "Swing Interval: " .. string.format("%.2f", SWING_INTERVAL) .. "s"
end)

-- PARRY RANGE
RangeDownBtn.MouseButton1Click:Connect(function()
        PARRY_RANGE = math.max(5, PARRY_RANGE - 5)
        RangeLabel.Text = "Parry Range: " .. tostring(PARRY_RANGE) .. " studs"
end)

RangeUpBtn.MouseButton1Click:Connect(function()
        PARRY_RANGE = math.min(100, PARRY_RANGE + 5)
        RangeLabel.Text = "Parry Range: " .. tostring(PARRY_RANGE) .. " studs"
end)

-- SELECT ALL / CLEAR ALL (Ores)
SelectAllBtn.MouseButton1Click:Connect(function()
        local names = getOreNames()
        for _, name in ipairs(names) do
                State.selectedOres[name] = true
        end
        refreshOreList()
        updateSelectedLabel()
end)

DeselectAllBtn.MouseButton1Click:Connect(function()
        State.selectedOres = {}
        refreshOreList()
        updateSelectedLabel()
end)

-- AUTO FARM BUTTON
AutoFarmBtn.MouseButton1Click:Connect(function()
        if State.autoFarming then
                stopAutoFarm()
                updateFarmButton(false)
                updateStatusLabel()
                return
        end
        local queue = buildOreQueue()
        if #queue == 0 then
                SelectedLabel.Text = "! Select at least 1 ore!"
                SelectedLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
                task.delay(2, function()
                        updateSelectedLabel()
                end)
                return
        end
        State.currentOreQueue = queue
        State.currentOreQueueIndex = 1
        updateFarmButton(true)
        startAutoFarm()
end)

-- ALL ORES BUTTON
AllOresBtn.MouseButton1Click:Connect(function()
        if State.autoFarming then
                stopAutoFarm()
                updateFarmButton(false)
                updateStatusLabel()
                return
        end
        local names = getOreNames()
        if #names == 0 then
                warn("[AutoMiner] No ores found in workspace.")
                return
        end
        State.selectedOres = {}
        for _, name in ipairs(names) do
                State.selectedOres[name] = true
        end
        refreshOreList()
        updateSelectedLabel()
        State.currentOreQueue = names
        State.currentOreQueueIndex = 1
        updateFarmButton(true)
        startAutoFarm()
end)

-- AUTO PARRY BUTTON
AutoParryBtn.MouseButton1Click:Connect(function()
        if State.autoParry then
                stopAutoParry()
                AutoParryBtn.Text = "Auto Parry: OFF"
                AutoParryBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 180)
                ParryStatus.Text = "Status: Idle"
                ParryStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
        else
                startAutoParry()
                AutoParryBtn.Text = "Auto Parry: ON"
                AutoParryBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
                ParryStatus.Text = "Status: Watching for attacks..."
                ParryStatus.TextColor3 = Color3.fromRGB(100, 220, 255)
        end
end)

-- ================================================================
-- // SPAM PARRY LOGIC
-- ================================================================

local function startSpamParry()
        if State.spamParry then return end
        State.spamParry = true

        if SpamParryStatus then
                SpamParryStatus.Text = "Spamming block (hold " .. string.format("%.2f", State.spamParryLength) .. "s)..."
                SpamParryStatus.TextColor3 = Color3.fromRGB(255, 180, 80)
        end

        State.spamParryThread = task.spawn(function()
                while State.spamParry do
                        -- Hold block true
                        fireBlock(true)
                        task.wait(State.spamParryLength)
                        if not State.spamParry then break end
                        -- Release block false
                        fireBlock(false)
                        task.wait(0.05)  -- tiny gap before next hold
                end
                -- Final cleanup: ensure block is released
                fireBlock(false)
        end)
end

local function stopSpamParry()
        State.spamParry = false
        -- Thread will exit on next loop iteration; release block for safety
        fireBlock(false)
        if SpamParryStatus then
                SpamParryStatus.Text = "Stopped"
                SpamParryStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
        end
end

SpamParryBtn.MouseButton1Click:Connect(function()
        if State.spamParry then
                stopSpamParry()
                SpamParryBtn.Text = "Spam Parry: OFF"
                SpamParryBtn.BackgroundColor3 = Color3.fromRGB(120, 60, 160)
        else
                startSpamParry()
                SpamParryBtn.Text = "Spam Parry: ON"
                SpamParryBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 80)
        end
end)

SpamParryDownBtn.MouseButton1Click:Connect(function()
        State.spamParryLength = math.max(0.1, State.spamParryLength - 0.05)
        SpamParryLenLabel.Text = "Hold length: " .. string.format("%.2f", State.spamParryLength) .. "s"
        if State.spamParry and SpamParryStatus then
                SpamParryStatus.Text = "Spamming block (hold " .. string.format("%.2f", State.spamParryLength) .. "s)..."
        end
end)

SpamParryUpBtn.MouseButton1Click:Connect(function()
        State.spamParryLength = math.min(0.7, State.spamParryLength + 0.05)
        SpamParryLenLabel.Text = "Hold length: " .. string.format("%.2f", State.spamParryLength) .. "s"
        if State.spamParry and SpamParryStatus then
                SpamParryStatus.Text = "Spamming block (hold " .. string.format("%.2f", State.spamParryLength) .. "s)..."
        end
end)

-- ================================================================
-- // JUNKPITS: CRONO'S CRAZY CHALLENGE KEY COLLECT
-- ================================================================

-- Helper: TP player to a part's position (handles BasePart, Model, or Folder)
local function tpToPart(part)
        if not part then return false end
        local char = LocalPlayer.Character
        if not char then return false end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end

        -- Get target position from BasePart, Model with PrimaryPart, or Model with HumanoidRootPart
        local targetPos = nil
        local targetCF = nil
        if part:IsA("BasePart") then
                targetCF = part.CFrame
                targetPos = part.Position
        elseif part:IsA("Model") then
                if part.PrimaryPart then
                        targetCF = part.PrimaryPart.CFrame
                        targetPos = part.PrimaryPart.Position
                else
                        local pp = part:FindFirstChild("HumanoidRootPart")
                        if pp then
                                targetCF = pp.CFrame
                                targetPos = pp.Position
                        else
                                -- Find first BasePart in model
                                for _, d in ipairs(part:GetDescendants()) do
                                        if d:IsA("BasePart") then
                                                targetCF = d.CFrame
                                                targetPos = d.Position
                                                break
                                        end
                                end
                        end
                end
        elseif part:IsA("Folder") then
                -- Find first BasePart inside folder
                for _, d in ipairs(part:GetDescendants()) do
                        if d:IsA("BasePart") then
                                targetCF = d.CFrame
                                targetPos = d.Position
                                break
                        end
                end
        end

        if not targetPos then return false end
        hrp.Velocity = Vector3.new(0, 0, 0)
        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        -- TP 3 studs above target
        if targetCF then
                hrp.CFrame = targetCF + Vector3.new(0, 3, 0)
        else
                hrp.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0))
        end
        return true
end

-- Helper: get all Level folders from workspace (Level1, Level2, ... LevelN)
local function getAllLevels()
        local levels = {}
        for _, child in ipairs(workspace:GetChildren()) do
                local name = child.Name
                if name:match("^Level%d+$") then
                        table.insert(levels, child)
                end
        end
        table.sort(levels, function(a, b)
                local na = tonumber(a.Name:match("%d+"))
                local nb = tonumber(b.Name:match("%d+"))
                return na < nb
        end)
        return levels
end

-- Helper: find all Key parts inside a level's Keys folder
-- Handles: Keys.Key (single), Keys.Key1/Key2/... (multiple), Keys folder containing parts directly
local function getAllKeys(levelFolder)
        local keys = {}
        local keysFolder = levelFolder:FindFirstChild("Keys")
        if not keysFolder then return keys end
        print("[CronoKey] Scanning " .. levelFolder.Name .. ".Keys children:")
        for _, child in ipairs(keysFolder:GetChildren()) do
                print("  - " .. child.Name .. " (" .. child.ClassName .. ")")
        end

        -- Strategy 1: Keys folder has direct BasePart children
        for _, child in ipairs(keysFolder:GetChildren()) do
                if child:IsA("BasePart") then
                        table.insert(keys, child)
                end
        end
        if #keys > 0 then return keys end

        -- Strategy 2: Look for "Key" subfolder/submodel containing parts
        local keyObj = keysFolder:FindFirstChild("Key")
        if keyObj then
                if keyObj:IsA("BasePart") then
                        table.insert(keys, keyObj)
                elseif keyObj:IsA("Folder") or keyObj:IsA("Model") then
                        for _, d in ipairs(keyObj:GetDescendants()) do
                                if d:IsA("BasePart") then
                                        table.insert(keys, d)
                                end
                        end
                end
        end
        if #keys > 0 then return keys end

        -- Strategy 3: Iterate all children of Keys folder, find any BasePart descendants
        for _, child in ipairs(keysFolder:GetChildren()) do
                if child:IsA("Folder") or child:IsA("Model") then
                        for _, d in ipairs(child:GetDescendants()) do
                                if d:IsA("BasePart") then
                                        table.insert(keys, d)
                                end
                        end
                end
        end
        return keys
end

local function startCronoKeyCollect()
        if State.autoCronoKey then return end
        State.autoCronoKey = true
        CronoKeyBtn.Text = "[ ]  Stop Crono Key Collect"
        CronoKeyBtn.BackgroundColor3 = Color3.fromRGB(120, 40, 40)

        State.cronoThread = task.spawn(function()
                while State.autoCronoKey do
                        local levels = getAllLevels()
                        print("[CronoKey] Found " .. tostring(#levels) .. " level folders in workspace")
                        for _, lvl in ipairs(levels) do
                                local children = {}
                                for _, c in ipairs(lvl:GetChildren()) do
                                        table.insert(children, c.Name .. "(" .. c.ClassName .. ")")
                                end
                                print("[CronoKey]   " .. lvl.Name .. " children: " .. table.concat(children, ", "))
                        end
                        if #levels == 0 then
                                if CronoKeyStatus then
                                        CronoKeyStatus.Text = "No Level folders found in workspace"
                                        CronoKeyStatus.TextColor3 = Color3.fromRGB(255, 120, 120)
                                end
                                task.wait(2)
                                -- Still continue to try Exit
                        end

                        -- Phase 1: TP to each level's Firewall (fast — just TP and tiny wait)
                        for _, level in ipairs(levels) do
                                if not State.autoCronoKey then break end
                                local firewall = level:FindFirstChild("Firewall")
                                if firewall then
                                        if CronoKeyStatus then
                                                CronoKeyStatus.Text = "TP to " .. level.Name .. ".Firewall..."
                                                CronoKeyStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
                                        end
                                        tpToPart(firewall)
                                        task.wait(0.1)  -- brief wait for firewall to register TP
                                end
                        end

                        -- Phase 2: TP to each level's Keys (fast — TP each key with brief wait)
                        for _, level in ipairs(levels) do
                                if not State.autoCronoKey then break end
                                local keys = getAllKeys(level)
                                if #keys > 0 then
                                        for i, keyPart in ipairs(keys) do
                                                if not State.autoCronoKey then break end
                                                if keyPart.Parent then
                                                        if CronoKeyStatus then
                                                                CronoKeyStatus.Text = "Collect " .. level.Name .. " key " .. tostring(i) .. "/" .. tostring(#keys)
                                                                CronoKeyStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
                                                        end
                                                        tpToPart(keyPart)
                                                        task.wait(0.15)  -- brief wait for key pickup
                                                end
                                        end
                                end
                        end

                        -- Phase 3: TP to Exit (scan ALL levels for an Exit, like auto-delete does)
                        if State.autoCronoKey then
                                local foundExit = nil
                                local foundLevelName = nil
                                for _, level in ipairs(workspace:GetChildren()) do
                                        if level.Name:match("^Level%d+$") then
                                                local exitObj = level:FindFirstChild("Exit")
                                                if exitObj then
                                                        foundExit = exitObj
                                                        foundLevelName = level.Name
                                                        break
                                                end
                                        end
                                end
                                if foundExit then
                                        if CronoKeyStatus then
                                                CronoKeyStatus.Text = "TP to " .. foundLevelName .. ".Exit - Done!"
                                                CronoKeyStatus.TextColor3 = Color3.fromRGB(100, 255, 150)
                                        end
                                        print("[CronoKey] TP to " .. foundLevelName .. ".Exit (" .. foundExit.ClassName .. ")")
                                        tpToPart(foundExit)
                                        print("[CronoKey] Complete! TP'd to " .. foundLevelName .. ".Exit")
                                else
                                        -- Fallback: explicitly try Level19.Exit
                                        local l19 = workspace:FindFirstChild("Level19")
                                        if l19 then
                                                local exitObj = l19:FindFirstChild("Exit")
                                                if exitObj then
                                                        if CronoKeyStatus then
                                                                CronoKeyStatus.Text = "TP to Level19.Exit - Done!"
                                                                CronoKeyStatus.TextColor3 = Color3.fromRGB(100, 255, 150)
                                                        end
                                                        print("[CronoKey] TP to Level19.Exit (" .. exitObj.ClassName .. ")")
                                                        tpToPart(exitObj)
                                                        print("[CronoKey] Complete! TP'd to Level19.Exit")
                                                else
                                                        if CronoKeyStatus then
                                                                CronoKeyStatus.Text = "Level19 has no Exit child"
                                                                CronoKeyStatus.TextColor3 = Color3.fromRGB(255, 120, 120)
                                                        end
                                                        print("[CronoKey] Level19 has no Exit child")
                                                end
                                        else
                                                if CronoKeyStatus then
                                                        CronoKeyStatus.Text = "No Exit found in any Level folder"
                                                        CronoKeyStatus.TextColor3 = Color3.fromRGB(255, 120, 120)
                                                end
                                                print("[CronoKey] No Exit found in any Level folder (Level1-Level25)")
                                        end
                                end
                        end

                        -- Done — stop
                        State.autoCronoKey = false
                        CronoKeyBtn.Text = "Auto Crono's Crazy Challenge Key Collect"
                        CronoKeyBtn.BackgroundColor3 = Color3.fromRGB(180, 100, 40)
                        if CronoKeyStatus then
                                if CronoKeyStatus.Text:find("Done") then
                                        CronoKeyStatus.Text = "Complete! Stopped."
                                else
                                        CronoKeyStatus.Text = "Stopped"
                                        CronoKeyStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
                                end
                        end
                        break
                end
        end)
end

local function stopCronoKeyCollect()
        State.autoCronoKey = false
        CronoKeyBtn.Text = "Auto Crono's Crazy Challenge Key Collect"
        CronoKeyBtn.BackgroundColor3 = Color3.fromRGB(180, 100, 40)
        if CronoKeyStatus then
                CronoKeyStatus.Text = "Stopped"
                CronoKeyStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
        end
end

CronoKeyBtn.MouseButton1Click:Connect(function()
        if State.autoCronoKey then
                stopCronoKeyCollect()
        else
                startCronoKeyCollect()
        end
end)

-- ================================================================
-- // JUNKPITS: AUTO DELETE ENEMIES / KILLBRICKS (ALL LEVELS)
-- ================================================================

-- Target names to delete inside each Level folder
local DELETE_TARGET_NAMES = {
        "Drones",        -- Level9 and possibly others
        "Killbricks",    -- Level25 and possibly others
        "ThiefOrb",      -- Level1 and possibly others
        "SniperOrb",     -- Level21 and possibly others
}

-- Delete target aggressively — try multiple strategies because server-owned instances
-- sometimes resist client-side Destroy()
local function deleteIfExists(target)
        if not target or not target.Parent then return false end
        local deleted = false

        -- Strategy 1: Destroy each child first (children often easier to remove than parent)
        pcall(function()
                for _, child in ipairs(target:GetChildren()) do
                        pcall(function() child:Destroy() end)
                end
        end)

        -- Strategy 2: Destroy the parent itself
        local ok = pcall(function()
                target:Destroy()
        end)
        if ok or not target.Parent then
                deleted = true
        end

        -- Strategy 3: If Destroy failed, try setting Parent to nil directly
        if not deleted then
                pcall(function() target.Parent = nil end)
                if not target.Parent then deleted = true end
        end

        -- Strategy 4: If still there, disable all BaseParts (CanTouch, CanCollide, Transparency)
        -- so even if we can't delete it, it can't hurt the player
        if not deleted then
                pcall(function()
                        for _, d in ipairs(target:GetDescendants()) do
                                if d:IsA("BasePart") then
                                        d.CanCollide = false
                                        d.CanTouch = false
                                        d.CanQuery = false
                                        d.Transparency = 1
                                        -- Try to destroy the part itself
                                        pcall(function() d:Destroy() end)
                                end
                        end
                end)
        end

        return deleted
end

-- Scan ALL Level folders (Level1 to Level25) and delete any matching targets
local function scanAndDeleteAllLevels()
        local deleted = 0
        local found = 0
        -- Iterate all workspace children that match "Level<number>"
        for _, level in ipairs(workspace:GetChildren()) do
                if level.Name:match("^Level%d+$") then
                        -- Check each target name inside this level
                        for _, targetName in ipairs(DELETE_TARGET_NAMES) do
                                local target = level:FindFirstChild(targetName)
                                if target and target.Parent then
                                        found = found + 1
                                        if deleteIfExists(target) then
                                                deleted = deleted + 1
                                                print("[AutoDelete] Deleted " .. level.Name .. "." .. targetName)
                                        else
                                                -- Disabled but not deleted
                                                print("[AutoDelete] Disabled (couldn't fully delete) " .. level.Name .. "." .. targetName)
                                                deleted = deleted + 1  -- count as handled
                                        end
                                end
                        end
                end
        end

        -- ALSO check ReplicatedStorage.Effects.VirtualReality.Levels (in case Drones/Killbricks live there)
        local eff = game:GetService("ReplicatedStorage"):FindFirstChild("Effects")
        if eff then
                local vr = eff:FindFirstChild("VirtualReality")
                if vr then
                        -- Check Levels subfolder (Drones, Killbricks, etc.)
                        local levelsFolder = vr:FindFirstChild("Levels")
                        if levelsFolder then
                                for _, level in ipairs(levelsFolder:GetChildren()) do
                                        if level.Name:match("^Level%d+$") then
                                                for _, targetName in ipairs(DELETE_TARGET_NAMES) do
                                                        local target = level:FindFirstChild(targetName)
                                                        if target and target.Parent then
                                                                found = found + 1
                                                                if deleteIfExists(target) then
                                                                        deleted = deleted + 1
                                                                        print("[AutoDelete] Deleted Effects.VirtualReality.Levels." .. level.Name .. "." .. targetName)
                                                                else
                                                                        print("[AutoDelete] Disabled (couldn't fully delete) Effects.VirtualReality.Levels." .. level.Name .. "." .. targetName)
                                                                        deleted = deleted + 1
                                                                end
                                                        end
                                                end
                                        end
                                end
                        end

                        -- ALSO check Effects.VirtualReality.Effects directly (SniperOrb lives here)
                        local effectsFolder = vr:FindFirstChild("Effects")
                        if effectsFolder then
                                for _, targetName in ipairs(DELETE_TARGET_NAMES) do
                                        local target = effectsFolder:FindFirstChild(targetName)
                                        if target and target.Parent then
                                                found = found + 1
                                                if deleteIfExists(target) then
                                                        deleted = deleted + 1
                                                        print("[AutoDelete] Deleted Effects.VirtualReality.Effects." .. targetName)
                                                else
                                                        print("[AutoDelete] Disabled (couldn't fully delete) Effects.VirtualReality.Effects." .. targetName)
                                                        deleted = deleted + 1
                                                end
                                        end
                                end
                        end
                end
        end

        return deleted, found
end

local function startAutoDelete()
        if State.autoDeleteEnemies then return end
        State.autoDeleteEnemies = true
        DeleteBtn.Text = "[ ]  Stop Auto-Delete"
        DeleteBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 60)

        if DeleteStatus then
                DeleteStatus.Text = "Auto-delete ON - scanning all levels..."
                DeleteStatus.TextColor3 = Color3.fromRGB(100, 220, 130)
        end
        print("[AutoDelete] Started - scanning all Level1-Level25 for Drones/Killbricks/ThiefOrb/SniperOrb")

        -- Immediate scan on start
        local deleted, found = scanAndDeleteAllLevels()
        if DeleteStatus then
                if deleted > 0 then
                        DeleteStatus.Text = "Deleted " .. tostring(deleted) .. " target(s) on start"
                        DeleteStatus.TextColor3 = Color3.fromRGB(100, 220, 130)
                else
                        DeleteStatus.Text = "No targets found yet - will keep scanning..."
                        DeleteStatus.TextColor3 = Color3.fromRGB(200, 200, 130)
                end
        end

        -- Polling loop: scan every 1 second (as user requested)
        State.deleteThread = task.spawn(function()
                while State.autoDeleteEnemies do
                        local n, found = scanAndDeleteAllLevels()
                        if n > 0 and DeleteStatus then
                                DeleteStatus.Text = "Deleted " .. tostring(n) .. " target(s) (loop)"
                                DeleteStatus.TextColor3 = Color3.fromRGB(100, 220, 130)
                        elseif DeleteStatus and DeleteStatus.Text:find("loop") then
                                -- Reset to "watching" if we previously deleted but now found nothing
                                DeleteStatus.Text = "Watching... (no new targets)"
                                DeleteStatus.TextColor3 = Color3.fromRGB(200, 200, 130)
                        end
                        task.wait(1)  -- scan every 1 second
                end
        end)
end

local function stopAutoDelete()
        State.autoDeleteEnemies = false
        for _, conn in ipairs(State.deleteConns) do
                pcall(function() conn:Disconnect() end)
        end
        State.deleteConns = {}
        DeleteBtn.Text = "Delete All enemy/Kill brick in Crono's Crazy Challenge"
        DeleteBtn.BackgroundColor3 = Color3.fromRGB(120, 40, 40)
        if DeleteStatus then
                DeleteStatus.Text = "Stopped"
                DeleteStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
        end
        print("[AutoDelete] Stopped")
end

DeleteBtn.MouseButton1Click:Connect(function()
        if State.autoDeleteEnemies then
                stopAutoDelete()
        else
                startAutoDelete()
        end
end)

-- AUTO-REFRESH ORE LIST (debounced, only on Model-level changes)
local oreRefreshPending = false
local function scheduleOreRefresh()
        if oreRefreshPending then return end
        oreRefreshPending = true
        task.delay(MOB_REFRESH_DEBOUNCE, function()
                oreRefreshPending = false
                if AutoPage and AutoPage.Visible then
                        refreshOreList()
                end
        end)
end

local function setupOreAutoRefresh()
        local oresFolder = workspace:FindFirstChild(ORES_FOLDER_NAME)
        if not oresFolder then
                local conn
                conn = workspace.ChildAdded:Connect(function(child)
                        if child.Name == ORES_FOLDER_NAME then
                                conn:Disconnect()
                                setupOreAutoRefresh()
                        end
                end)
                return
        end
        -- Watch area folders for new ore Models only (NOT DescendantAdded which fires for every part)
        local function watchArea(area)
                area.ChildAdded:Connect(function(child)
                        if child:IsA("Model") or child:IsA("BasePart") then
                                scheduleOreRefresh()
                        end
                end)
                area.ChildRemoved:Connect(function(child)
                        if child:IsA("Model") or child:IsA("BasePart") then
                                scheduleOreRefresh()
                        end
                end)
        end
        oresFolder.ChildAdded:Connect(function(child)
                if child:IsA("Folder") or child:IsA("Model") then
                        watchArea(child)
                end
                scheduleOreRefresh()
        end)
        for _, area in ipairs(oresFolder:GetChildren()) do
                if area:IsA("Folder") or area:IsA("Model") then
                        watchArea(area)
                end
        end
end
setupOreAutoRefresh()

-- TRACK EQUIPPED WEAPON (so we can re-equip after death)
pcall(function()
        LocalPlayer.Character.ChildAdded:Connect(function(child)
                if child:IsA("Tool") and child:FindFirstChild("Slash") then
                        State.lastEquippedWeaponName = child.Name
                        State.equippedWeapon = child
                end
        end)
end)

-- AUTO-REFRESH MOB LIST (debounced)
local mobRefreshPending = false
local function scheduleMobRefresh()
        if mobRefreshPending then return end
        mobRefreshPending = true
        task.delay(MOB_REFRESH_DEBOUNCE, function()
                mobRefreshPending = false
                if MobPage and MobPage.Visible then
                        refreshMobList(true)
                end
        end)
end

-- Recursively attach ChildAdded for the mob list refresh (catches mobs at any depth)
local mobRefreshConns = {}
local function attachMobRefreshWatcher(parent)
        local conn = parent.ChildAdded:Connect(function(child)
                if child:IsA("Model") then
                        scheduleMobRefresh()
                        attachMobRefreshWatcher(child)
                elseif child:IsA("Folder") then
                        attachMobRefreshWatcher(child)
                end
        end)
        table.insert(mobRefreshConns, conn)
end

local function setupMobAutoRefresh()
        local mobsFolder = workspace:FindFirstChild("Mobs")
        if not mobsFolder then
                local conn
                conn = workspace.ChildAdded:Connect(function(child)
                        if child.Name == "Mobs" then
                                conn:Disconnect()
                                setupMobAutoRefresh()
                        end
                end)
                return
        end
        -- Recursive watcher: catches direct mob children AND nested ones
        attachMobRefreshWatcher(mobsFolder)
end
pcall(function() setupMobAutoRefresh() end)

-- CHARACTER RESPAWN (resume farming after death)
LocalPlayer.CharacterAdded:Connect(function(newChar)
        Character = newChar
        Humanoid = newChar:WaitForChild("Humanoid")
        HumanoidRootPart = newChar:WaitForChild("HumanoidRootPart")

        if State.autoFarming then
                task.wait(1)
                local pickaxe = findPickaxe()
                if pickaxe then
                        equipPickaxe(pickaxe)
                        task.wait(0.5)
                end
                startNoclip()
                if State.flyConnection then State.flyConnection:Disconnect() end
                State.flyConnection = RunService.Heartbeat:Connect(function()
                        if not State.autoFarming then return end
                        if State.currentPart and State.currentPart.Parent then
                                flyUnderAndFacePart(State.currentPart)
                        end
                end)
                if State.swingConnection then State.swingConnection:Disconnect() end
                local lastSwing = 0
                State.swingConnection = RunService.Heartbeat:Connect(function()
                        if not State.autoFarming then return end
                        local now = tick()
                        if now - lastSwing >= SWING_INTERVAL then
                                lastSwing = now
                                swingPickaxe()
                        end
                end)
                moveToCurrentOreFunc()
        end

        -- Restart auto parry if it was on
        if State.autoParry then
                stopAutoParry()
                task.wait(1.5)
                -- Reconnect to new humanoid
                Humanoid = newChar:WaitForChild("Humanoid")
                startAutoParry()
        end

        -- Restart mob farming if it was on
        if State.autoMobFarming then
                stopAutoMobFarm()
                task.wait(1.5)
                -- Re-equip the same weapon
                local weapon
                if State.lastEquippedWeaponName then
                        weapon = findWeaponByName(State.lastEquippedWeaponName)
                end
                if not weapon then
                        weapon = findWeapon()
                end
                if weapon then
                        equipWeapon(weapon)
                        task.wait(0.5)
                end
                -- Restart mob farm using the same optimized startAutoMobFarm logic
                State.autoMobFarming = false  -- will be set true inside startAutoMobFarm
                State.currentAttackType = 1
                -- Re-run startAutoMobFarm (handles noclip + single Heartbeat + initial mob search)
                task.spawn(function()
                        startAutoMobFarm()
                end)
        end
end)

-- ================================================================
-- // AUTO FISHING (with Discovery Mode to find the fishing signal)
-- ================================================================

-- Find the rod tool (equipped or in backpack) — case-insensitive name match
local function findRodTool(rodName)
        if not rodName or rodName == "" then return nil end
        local rodLower = rodName:lower()
        local char = LocalPlayer.Character
        if char then
                for _, tool in ipairs(char:GetChildren()) do
                        if tool:IsA("Tool") and tool.Name:lower() == rodLower then
                                return tool
                        end
                end
        end
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        if backpack then
                for _, tool in ipairs(backpack:GetChildren()) do
                        if tool:IsA("Tool") and tool.Name:lower() == rodLower then
                                return tool
                        end
                end
        end
        return nil
end

-- Find the SeaBox Water part (where the player is fishing)
local function findWaterPart()
        local map = workspace:FindFirstChild("Map")
        if not map then return nil end
        local seaBox = map:FindFirstChild("SeaBox")
        if not seaBox then return nil end
        return seaBox:FindFirstChild("Water")
end

-- Find the bait name (look for "Gelatinous Sludge" or similar in player's inventory/rod)
local function getBaitName()
        -- Default bait in Pilgrammed fishing
        return "Gelatinous Sludge"
end

-- Fire the fishing Event remote on the rod (this is what casts AND reels in)
-- Args: (WaterPart, position, baitName)
local function fireFishingEvent(rod, position)
        if not rod then return false end
        local ok = pcall(function()
                local waterPart = workspace:WaitForChild("Map"):WaitForChild("SeaBox"):WaitForChild("Water")
                local event = rod:WaitForChild("Event")
                local args = { waterPart, position, getBaitName() }
                event:FireServer(unpack(args))
        end)
        if not ok then
                print("[AutoFish] Failed to fire fishing Event")
        end
        return ok
end

-- Get the position to cast at (in front of player, slightly down toward water)
local function getCastPosition()
        -- pinned known-working cast vector
        return Vector3.new(-324.7981262207031, -29.400001525878906, -935.5565185546875)
end

-- PRECISE fishing detection based on Discovery Mode findings:
-- Pattern: Character.ChildAdded: Cooldown (BoolValue) = CAST or BITE
--   - 1st Cooldown = cast line (ignore)
--   - 2nd Cooldown (after Bobber appears) = FISH BITE!
--   - After bite, fire Remotes.Loot or click to reel in
-- The Workspace.Bobber object appears when line is cast in water

-- Track fishing state
local fishState = "idle"  -- "idle" -> "casting" -> "waiting" -> "biting" -> "reeling"
local fishCastTime = 0
local fishBiteTime = 0
local lastCooldownTime = 0

-- Try to reel in the fish by clicking (the rod tool activation)
local function tryReelIn(rod)
        if not rod then return false end
        -- In Pilgrammed, fishing reels in by activating the rod tool (like clicking)
        -- Strategy 1: Activate the tool
        pcall(function()
                rod:Activate()
        end)
        -- Strategy 2: Fire the tool's Activated event
        pcall(function()
                if rod:IsA("Tool") then
                        fireSignal(rod.Activated)
                end
        end)
        -- Strategy 3: Look for a "Use" or "Cast" or "Reel" remote on the rod
        for _, name in ipairs({"Use", "Cast", "Reel", "Fish", "Click", "Activate"}) do
                local remote = rod:FindFirstChild(name)
                if remote then
                        if remote:IsA("RemoteEvent") then
                                pcall(function() remote:FireServer() end)
                                print("[AutoFish] Fired rod RemoteEvent: " .. name)
                                return true
                        elseif remote:IsA("RemoteFunction") then
                                pcall(function() remote:InvokeServer() end)
                                print("[AutoFish] Invoked rod RemoteFunction: " .. name)
                                return true
                        end
                end
        end
        -- Strategy 4: Simulate a mouse click on the tool (Tool requires click to activate)
        pcall(function()
                local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                if hum then
                        -- Unequip and re-equip to trigger activation
                        -- Actually, just fire the Activate signal
                end
        end)
        return false
end

-- Set up PRECISE fishing detection
local function setupFishDetection(onBite, onEvent)
        -- Clean up old connections
        for _, c in ipairs(State.fishConns) do
                pcall(function() c:Disconnect() end)
        end
        State.fishConns = {}

        local char = LocalPlayer.Character

        -- 1. Watch Character.ChildAdded for "Cooldown" BoolValue (THE BITE SIGNAL)
        --    Pattern: 1st Cooldown = cast, 2nd Cooldown = bite
        if char then
                local charConn = char.ChildAdded:Connect(function(child)
                        if child.Name == "Cooldown" and child:IsA("BoolValue") then
                                local now = tick()
                                local timeSinceLast = now - lastCooldownTime
                                lastCooldownTime = now

                                if fishState == "idle" or fishState == "reeling" then
                                        -- This is a CAST (1st cooldown after idle)
                                        fishState = "casting"
                                        fishCastTime = now
                                        if onEvent then onEvent("CAST detected (Cooldown added)") end
                                        print("[AutoFish] CAST detected - line cast, waiting for bite...")
                                elseif fishState == "casting" or fishState == "waiting" then
                                        -- This is a BITE! (2nd cooldown after cast)
                                        -- Only count as bite if at least 2 seconds since cast (avoid double-cast)
                                        if now - fishCastTime >= 2 then
                                                fishState = "biting"
                                                fishBiteTime = now
                                                if onEvent then onEvent("BITE detected (2nd Cooldown)") end
                                                print("[AutoFish] *** BITE DETECTED! *** (Cooldown re-added after " .. string.format("%.1f", now - fishCastTime) .. "s)")
                                                onBite("bite", child)
                                        end
                                end
                        else
                                -- Other child added - log for discovery
                                if onEvent then onEvent("Character.ChildAdded: " .. child.Name .. " (" .. child.ClassName .. ")") end
                        end
                end)
                table.insert(State.fishConns, charConn)

                -- Watch Cooldown being removed (cast complete -> waiting for bite)
                local charRemovedConn = char.ChildRemoved:Connect(function(child)
                        if child.Name == "Cooldown" and fishState == "casting" then
                                fishState = "waiting"
                                if onEvent then onEvent("Cast complete - waiting for bite...") end
                                print("[AutoFish] Cast complete - waiting for bite...")
                        end
                end)
                table.insert(State.fishConns, charRemovedConn)
        end

        -- 2. Watch for Workspace.Bobber appearing (confirms line is in water)
        local bobberConn = workspace.ChildAdded:Connect(function(child)
                if child.Name == "Bobber" then
                        if onEvent then onEvent("Bobber appeared in workspace (line in water)") end
                        print("[AutoFish] Bobber appeared - line is in water")
                end
        end)
        table.insert(State.fishConns, bobberConn)

        -- 3. Watch for Workspace.Bobber being removed (fish caught or escaped)
        local bobberRemovedConn = workspace.ChildRemoved:Connect(function(child)
                if child.Name == "Bobber" then
                        if fishState == "biting" or fishState == "reeling" then
                                fishState = "idle"
                                if onEvent then onEvent("Bobber removed - fish caught or escaped") end
                                print("[AutoFish] Bobber removed - resetting to idle")
                        end
                end
        end)
        table.insert(State.fishConns, bobberRemovedConn)

        -- 4. Hook RemoteEvent "Loot" (fires when fish is caught)
        local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
        if remotesFolder then
                local lootRemote = remotesFolder:FindFirstChild("Loot")
                if lootRemote and lootRemote:IsA("RemoteEvent") then
                        local lootConn = lootRemote.OnClientEvent:Connect(function(...)
                                local args = {...}
                                local argStr = ""
                                for i, v in ipairs(args) do
                                        argStr = argStr .. tostring(v) .. (i < #args and ", " or "")
                                end
                                if onEvent then onEvent("Loot RemoteEvent fired: " .. argStr) end
                                print("[AutoFish] FISH CAUGHT! Loot: " .. argStr)
                                fishState = "idle"
                        end)
                        table.insert(State.fishConns, lootConn)
                end
        end

        -- 5. For Discovery Mode: also log sounds and other remotes (filtered to fishing-related)
        if onEvent then
                local soundConn = workspace.DescendantAdded:Connect(function(child)
                        if child:IsA("Sound") then
                                local fullName = child:GetFullName()
                                -- Only log fishing-related sounds (Bobber, Splash, Rippling)
                                if fullName:find("Bobber") or child.Name:find("Splash") or child.Name:find("Rippling") then
                                        onEvent("Sound: " .. child.Name .. " at " .. fullName)
                                end
                        end
                end)
                table.insert(State.fishConns, soundConn)
        end
end

local function startFishDiscovery()
        if State.fishDiscovery then return end
        State.fishDiscovery = true
        State.fishRodName = RodNameBox.Text or "Rod Of Kings"
        FishDiscoveryBtn.Text = "Discovery Mode: ON (logging...)"
        FishDiscoveryBtn.BackgroundColor3 = Color3.fromRGB(180, 140, 40)

        fishState = "idle"
        if FishStatus then
                FishStatus.Text = "DISCOVERY ON - Cast your rod and wait for bite!"
                FishStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
        end
        print("[FishDiscovery] === STARTED ===")
        print("[FishDiscovery] Rod name: " .. State.fishRodName)
        print("[FishDiscovery] Cast your rod NOW. Watch for CAST and BITE events.")

        setupFishDetection(
                function(signalType, obj)  -- onBite
                        print("[FishDiscovery] *** BITE! ***")
                        if FishStatus then
                                FishStatus.Text = "BITE detected! Click to reel in!"
                                FishStatus.TextColor3 = Color3.fromRGB(100, 255, 150)
                        end
                end,
                function(eventStr)  -- onEvent
                        print("[FishDiscovery] EVENT: " .. eventStr)
                        if FishStatus then
                                FishStatus.Text = eventStr:sub(1, 60)
                        end
                end
        )
end

local function stopFishDiscovery()
        State.fishDiscovery = false
        for _, c in ipairs(State.fishConns) do
                pcall(function() c:Disconnect() end)
        end
        State.fishConns = {}
        FishDiscoveryBtn.Text = "Discovery Mode: OFF (log fishing events)"
        FishDiscoveryBtn.BackgroundColor3 = Color3.fromRGB(100, 80, 40)
        if FishStatus then
                FishStatus.Text = "Discovery stopped."
                FishStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
        end
        print("[FishDiscovery] === STOPPED ===")
end

-- // AUTO FISHING (timer-based, fully automatic)
-- Flow: cast -> wait N sec -> try to catch for 1 sec (stop early if Loot fires) -> if no fish, recast -> repeat

-- Wait time button handlers
FishWaitDownBtn.MouseButton1Click:Connect(function()
        State.fishWaitSeconds = math.max(0.1, State.fishWaitSeconds - 0.1)
        FishWaitLabel.Text = "Wait before reel: " .. string.format("%.2f", State.fishWaitSeconds) .. " sec"
end)
FishWaitUpBtn.MouseButton1Click:Connect(function()
        State.fishWaitSeconds = math.min(15, State.fishWaitSeconds + 0.1)
        FishWaitLabel.Text = "Wait before reel: " .. string.format("%.2f", State.fishWaitSeconds) .. " sec"
end)


-- NEW: detect if rod is actually equipped (i.e. player is fishing)
local function isRodEquipped(rodName)
        local char = LocalPlayer.Character
        if not char or not rodName or rodName == "" then return false end
        local rodLower = rodName:lower()
        for _, tool in ipairs(char:GetChildren()) do
                if tool:IsA("Tool") and tool.Name:lower() == rodLower then
                        return true
                end
        end
        return false
end


local function startAutoFish()
        if State.autoFish then return end
        State.autoFish = true
        State.fishRodName = RodNameBox.Text or "Rod of Kings"
        AutoFishBtn.Text = "[ ]  Stop Auto Fish"
        AutoFishBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
        FishStatus.Text = "Waiting for you to cast..."
        FishStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
        print("[AutoFish] === STARTED === | Rod: " .. State.fishRodName)
        print("[AutoFish] CAST YOUR LINE manually — script will detect it and go full auto!")

        local catchCount = 0
        local fishCaught = false
        local savedCastPos = nil  -- position where player first cast (saved for auto-cast)

        -- Hook Remotes.Loot to detect catches (stops the spam early)
        local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
        if remotesFolder then
                local lootRemote = remotesFolder:FindFirstChild("Loot")
                if lootRemote and lootRemote:IsA("RemoteEvent") then
                        local lootConn = lootRemote.OnClientEvent:Connect(function(...)
                                catchCount = catchCount + 1
                                fishCaught = true
                                local name = tostring(select(1, ...) or "?")
                                print("[AutoFish] CAUGHT #" .. catchCount .. ": " .. name)
                                FishStatus.Text = "Caught #" .. catchCount .. ": " .. name
                                FishStatus.TextColor3 = Color3.fromRGB(100, 255, 150)
                        end)
                        table.insert(State.fishConns, lootConn)
                end
        end

        -- Helper: detect if player is currently fishing (Bobber exists in workspace)
        local function isPlayerFishing()
                local bobber = workspace:FindFirstChild("Bobber")
                return bobber ~= nil
        end

        -- Helper: wait for player to cast (Bobber appears)
        local function waitForPlayerCast()
                FishStatus.Text = "Waiting for you to cast..."
                FishStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
                print("[AutoFish] Waiting for player to cast line...")
                while State.autoFish and not isPlayerFishing() do
                        task.wait(0.1)
                end
                if not State.autoFish then return false end
                -- Save the cast position (where the bobber is)
                local bobber = workspace:FindFirstChild("Bobber")
                if bobber then
                        if bobber:IsA("BasePart") then
                                savedCastPos = bobber.Position
                        elseif bobber:IsA("Model") then
                                local pp = bobber.PrimaryPart or bobber:FindFirstChildWhichIsA("BasePart")
                                if pp then savedCastPos = pp.Position end
                        elseif bobber:IsA("Folder") then
                                for _, d in ipairs(bobber:GetDescendants()) do
                                        if d:IsA("BasePart") then
                                                savedCastPos = d.Position
                                                break
                                        end
                                end
                        end
                end
                -- Fallback: use player position if bobber position not found
                if not savedCastPos then
                        local char = LocalPlayer.Character
                        local hrp = char and char:FindFirstChild("HumanoidRootPart")
                        savedCastPos = hrp and hrp.Position or getCastPosition()
                end
                print("[AutoFish] Player cast detected! Saved position: " .. tostring(savedCastPos))
                return true
        end

        -- Main loop
        State.fishThread = task.spawn(function()
                -- PHASE 1: Wait for player to cast manually (do nothing until then)
                if not waitForPlayerCast() then return end

                -- Now we're in full auto mode
                while State.autoFish do
                        -- STEP 2: Wait N seconds (full wait — for fish to bite)
                        FishStatus.Text = "Fishing... waiting " .. string.format("%.2f", State.fishWaitSeconds) .. "s for bite"
                        FishStatus.TextColor3 = Color3.fromRGB(100, 220, 255)
                        local waitStart = tick()
                        while State.autoFish and (tick() - waitStart) < State.fishWaitSeconds do
                                task.wait(0.1)
                        end
                        if not State.autoFish then break end

                        -- STEP 3: Spam fishing (catching) for 1 second OR until fish is caught
                        FishStatus.Text = "Catching (spam 1s)..."
                        FishStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
                        fishCaught = false
                        local catchStart = tick()
                        local reelCount = 0
                        while State.autoFish and not fishCaught and (tick() - catchStart) < 1 do
                                local rod = findRodTool(State.fishRodName)
                                if rod then
                                        fireFishingEvent(rod, savedCastPos or getCastPosition())
                                        reelCount = reelCount + 1
                                end
                                task.wait(0.05)  -- 20 fires per second
                        end
                        print("[AutoFish] Catch done: fired " .. reelCount .. "x | caught=" .. tostring(fishCaught))

                        -- STEP 4: Cooldown 0.25 seconds
                        if State.autoFish then
                                FishStatus.Text = "Cooldown 0.25s..."
                                FishStatus.TextColor3 = Color3.fromRGB(200, 200, 130)
                                task.wait(0.25)
                        end

                        -- STEP 5: Auto-cast at saved position (fire fishing script once)
                        if State.autoFish then
                                fishCaught = false
                                local rod = findRodTool(State.fishRodName)
                                if rod then
                                        fireFishingEvent(rod, savedCastPos or getCastPosition())
                                        print("[AutoFish] Auto-cast at " .. tostring(savedCastPos))
                                        FishStatus.Text = "Cast! Waiting " .. string.format("%.2f", State.fishWaitSeconds) .. "s..."
                                        FishStatus.TextColor3 = Color3.fromRGB(100, 220, 255)
                                end
                        end

                        -- STEP 6: Back to step 2 (loop continues)
                end
        end)
end

local function stopAutoFish()
        State.autoFish = false
        for _, c in ipairs(State.fishConns) do
                pcall(function() c:Disconnect() end)
        end
        State.fishConns = {}
        AutoFishBtn.Text = ">  Start Auto Fish"
        AutoFishBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 100)
        if FishStatus then
                FishStatus.Text = "Auto Fish stopped"
                FishStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
        end
        print("[AutoFish] Stopped")
end

AutoFishBtn.MouseButton1Click:Connect(function()
        if State.autoFish then stopAutoFish() else startAutoFish() end
end)

-- ================================================================
-- // AUTO RIFTS
-- ================================================================

-- Check if equipped weapon is a bow (has "Shoot" remote) or melee (has "Slash" remote)
local function getEquippedWeaponType()
        local char = LocalPlayer.Character
        if not char then return nil, nil end
        for _, tool in ipairs(char:GetChildren()) do
                if tool:IsA("Tool") then
                        if tool:FindFirstChild("Shoot") then
                                return "bow", tool
                        elseif tool:FindFirstChild("Slash") then
                                return "melee", tool
                        end
                end
        end
        return nil, nil
end

-- Attack with bow (same as Auto Bow: fire Shoot:InvokeServer)
local function riftsBowAttack(targetMob)
        local _, bow = getEquippedWeaponType()
        if not bow then return end
        local mobHrp = targetMob:FindFirstChild("HumanoidRootPart")
        if not mobHrp then return end
        local shootRemote = bow:FindFirstChild("Shoot")
        if not shootRemote then return end
        pcall(function()
                shootRemote:InvokeServer(mobHrp.Position, "Arrow", true, 1)
        end)
end

-- Attack with melee (same as mob farm: fire Slash:FireServer with attack type)
local function riftsMeleeAttack()
        local char = LocalPlayer.Character
        if not char then return end
        local _, weapon = getEquippedWeaponType()
        if not weapon then return end
        local slash = weapon:FindFirstChild("Slash")
        if not slash then return end
        local atkType = getNextAttackType()
        if not atkType then return end
        pcall(function()
                slash:FireServer(atkType)
        end)
end

-- Hold G key for 2.5 seconds (to activate rift) - works on mobile + desktop
-- Uses multiple input simulation methods for maximum compatibility
local function holdGKey(duration)
        local vim = game:GetService("VirtualInputManager")
        local userInput = game:GetService("UserInputService")

        -- Method 1: VirtualInputManager SendKeyEvent (works on mobile + desktop)
        local function pressG()
                pcall(function() vim:SendKeyEvent(true, Enum.KeyCode.G, false, game) end)
        end
        local function releaseG()
                pcall(function() vim:SendKeyEvent(false, Enum.KeyCode.G, false, game) end)
        end

        -- Method 2: Also simulate a touch tap (for mobile games that listen for touch)
        -- Some games detect "G" via ContextActionService which mobile users bind to a tap
        local function pressTouch()
                pcall(function()
                        -- Get center of screen for tap position
                        local viewport = workspace.CurrentCamera.ViewportSize
                        vim:SendTouchEvent(true, viewport.X/2, viewport.Y/2, 1, game)
                end)
        end
        local function releaseTouch()
                pcall(function()
                        local viewport = workspace.CurrentCamera.ViewportSize
                        vim:SendTouchEvent(false, viewport.X/2, viewport.Y/2, 1, game)
                end)
        end

        -- Press G (and touch)
        pressG()
        pressTouch()

        -- Also fire ContextActionService G action if bound (some games use this for mobile)
        pcall(function()
                game:GetService("ContextActionService"):FireActionButton("G")
        end)

        print("[AutoRifts] Holding G for " .. tostring(duration) .. "s (mobile + desktop)...")

        -- Keep G held for the duration (re-press every 0.2s to ensure it stays registered)
        local elapsed = 0
        while elapsed < duration do
                task.wait(0.2)
                elapsed = elapsed + 0.2
                -- Re-press to keep the key "held" (some games detect this differently)
                pressG()
        end

        -- Release G (and touch)
        releaseG()
        releaseTouch()
        print("[AutoRifts] Released G after " .. tostring(duration) .. "s")
end

-- Mobile activation: activate rift via proximity prompts, ContextActionService, G key, and GUI buttons
-- This replaces the old unreliable screen-coordinate tap approach
local function tapScreenForRift(riftSpawnPos)
        local vim = game:GetService("VirtualInputManager")
        local CAS = game:GetService("ContextActionService")
        print("[AutoRifts] Activating rift (mobile method)...")

        -- Face the rift spawn point before activating
        if riftSpawnPos then
                local c = LocalPlayer.Character
                local h = c and c:FindFirstChild("HumanoidRootPart")
                if h then
                        local dir = (riftSpawnPos - h.Position)
                        dir = Vector3.new(dir.X, 0, dir.Z)
                        if dir.Magnitude > 0.1 then
                                h.CFrame = CFrame.lookAt(h.Position, h.Position + dir)
                        end
                end
        end

        -- METHOD 1: Fire all ProximityPrompts in range directly (most reliable)
        -- Pilgrammed's rifts use ProximityPrompts which fire on the server side
        local triggered = false
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
                for _, obj in ipairs(workspace:GetDescendants()) do
                        if obj:IsA("ProximityPrompt") and obj.Enabled then
                                local promptPart = obj.Parent
                                if promptPart and promptPart:IsA("BasePart") then
                                        local dist = (promptPart.Position - hrp.Position).Magnitude
                                        if dist <= (obj.MaxActivationDistance + 15) then
                                                print("[AutoRifts] Triggering ProximityPrompt: " .. obj:GetFullName())
                                                pcall(function()
                                                        fireproximityprompt(obj)
                                                end)
                                                -- Also try the remote directly
                                                pcall(function()
                                                        local remote = ReplicatedStorage:FindFirstChild("Remotes")
                                                        if remote then
                                                                local interact = remote:FindFirstChild("Interact")
                                                                        or remote:FindFirstChild("ProximityPrompt")
                                                                        or remote:FindFirstChild("Activate")
                                                                if interact and interact:IsA("RemoteEvent") then
                                                                        interact:FireServer(obj)
                                                                elseif interact and interact:IsA("RemoteFunction") then
                                                                        interact:InvokeServer(obj)
                                                                end
                                                        end
                                                end)
                                                triggered = true
                                        end
                                end
                        end
                end
        end
        print("[AutoRifts] ProximityPrompt triggered: " .. tostring(triggered))

        -- METHOD 2: Fire ContextActionService actions bound to "Interact" / G key
        -- On mobile Pilgrammed binds G to a virtual button; firing the action directly works
        local casActions = {"Interact", "interact", "UseRift", "ActivateRift",
                "InteractAction", "UseAction", "G", "ContextInteract"}
        for _, actionName in ipairs(casActions) do
                pcall(function()
                        CAS:FireActionButton(actionName)
                end)
        end
        print("[AutoRifts] ContextActionService actions fired")

        task.wait(0.1)

        -- METHOD 3: G key hold (works on desktop and as backup on mobile)
        holdGKey(2.5)

        task.wait(0.2)

        -- METHOD 4: Find and directly click any visible GUI button near "E" / interact prompts
        -- (Roblox ProximityPrompt UI shows a button that we can fire)
        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        if playerGui then
                for _, obj in ipairs(playerGui:GetDescendants()) do
                        if obj:IsA("ProximityPrompt") and obj.Enabled then
                                pcall(function() fireproximityprompt(obj) end)
                        end
                        if (obj:IsA("TextButton") or obj:IsA("ImageButton")) and obj.Visible then
                                local n = obj.Name:lower()
                                if n:find("prompt") or n:find("interact") or n:find("rift")
                                        or n:find("enter") or n:find("use") or n:find("activate") then
                                        print("[AutoRifts] Clicking GUI button: " .. obj:GetFullName())
                                        pcall(function() obj:Activate() end)
                                end
                        end
                end
        end

        print("[AutoRifts] Rift activation complete (all methods tried)")
end

-- TP to a RiftSpawn part
local function tpToRiftSpawn(index)
        local spawnName = "RiftSpawn" .. tostring(index)
        local spawnPart = workspace:FindFirstChild(spawnName)
        if not spawnPart then
                print("[AutoRifts] " .. spawnName .. " not found in workspace!")
                return false
        end
        local char = LocalPlayer.Character
        if not char then return false end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end

        -- Get position from the spawn part
        local targetPos = nil
        if spawnPart:IsA("BasePart") then
                targetPos = spawnPart.Position
        elseif spawnPart:IsA("Model") then
                if spawnPart.PrimaryPart then
                        targetPos = spawnPart.PrimaryPart.Position
                else
                        local pp = spawnPart:FindFirstChild("HumanoidRootPart")
                        if pp then targetPos = pp.Position end
                end
        elseif spawnPart:IsA("Folder") then
                for _, d in ipairs(spawnPart:GetDescendants()) do
                        if d:IsA("BasePart") then
                                targetPos = d.Position
                                break
                        end
                end
        end
        if not targetPos then return false, nil end

        hrp.Velocity = Vector3.new(0, 0, 0)
        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        hrp.CFrame = CFrame.new(targetPos + Vector3.new(0, 5, 0))
        print("[AutoRifts] TP'd to " .. spawnName .. " at " .. tostring(targetPos))
        return true, targetPos
end

local function startAutoRifts()
        if State.autoRifts then return end
        State.autoRifts = true
        State.riftsCurrentIndex = 1
        AutoRiftsBtn.Text = "[ ]  Stop Auto Rifts"
        AutoRiftsBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 80)

        if RiftsStatus then
                RiftsStatus.Text = "Auto Rifts ON - starting from RiftSpawn1..."
                RiftsStatus.TextColor3 = Color3.fromRGB(200, 150, 255)
        end
        print("[AutoRifts] === STARTED ===")
        print("[AutoRifts] Will TP to RiftSpawn1-7, hold G 2.5s, wait for NewZone change, kill mobs, wait for 'Rift cleared'")

        -- Hook ReplicatedStorage.Remotes.Message to detect "Rift cleared"
        local riftCleared = false
        -- Hook ReplicatedStorage.Remotes.NewZone to detect zone changes (rift activated)
        local newZoneChanged = false
        local newZoneName = nil
        local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
        if remotesFolder then
                local msgRemote = remotesFolder:FindFirstChild("Message")
                if msgRemote and msgRemote:IsA("RemoteEvent") then
                        local msgConn = msgRemote.OnClientEvent:Connect(function(...)
                                local args = {...}
                                local msg = tostring(args[1] or "")
                                print("[AutoRifts] Message received: " .. msg)
                                if msg:find("Rift cleared") or msg:find("Returning home") then
                                        riftCleared = true
                                end
                        end)
                        table.insert(State.riftsConns, msgConn)
                end

                -- Hook NewZone remote (fires when zone changes - rift activated)
                local newZoneRemote = remotesFolder:FindFirstChild("NewZone")
                if newZoneRemote then
                        local function onNewZone(...)
                                local args = {...}
                                newZoneName = tostring(args[1] or "unknown")
                                newZoneChanged = true
                                print("[AutoRifts] NewZone changed to: " .. newZoneName)
                        end
                        -- NewZone might be RemoteEvent or RemoteFunction
                        if newZoneRemote:IsA("RemoteEvent") then
                                local conn = newZoneRemote.OnClientEvent:Connect(onNewZone)
                                table.insert(State.riftsConns, conn)
                                print("[AutoRifts] Hooked NewZone RemoteEvent")
                        elseif newZoneRemote:IsA("RemoteFunction") then
                                newZoneRemote.OnClientInvoke = onNewZone
                                -- Add a fake "disconnect" that clears the hook
                                table.insert(State.riftsConns, {Disconnect = function()
                                        pcall(function() newZoneRemote.OnClientInvoke = nil end)
                                end})
                                print("[AutoRifts] Hooked NewZone RemoteFunction")
                        end
                else
                        print("[AutoRifts] WARNING: NewZone remote not found - will skip zone change detection")
                end
        end

        -- Noclip (reuse cached pattern)
        local noclipConn = RunService.Stepped:Connect(function()
                local char = LocalPlayer.Character
                if char then
                        for _, part in ipairs(char:GetDescendants()) do
                                if part:IsA("BasePart") then
                                        part.CanCollide = false
                                end
                        end
                end
        end)
        table.insert(State.riftsConns, noclipConn)

        -- Main rift loop
        State.riftsThread = task.spawn(function()
                while State.autoRifts do
                        -- Step 1: TP to current RiftSpawn
                        local idx = State.riftsCurrentIndex
                        if RiftsStatus then
                                RiftsStatus.Text = "TP to RiftSpawn" .. tostring(idx) .. "..."
                                RiftsStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
                        end
                        local tpOk, riftPos = tpToRiftSpawn(idx)
                        if not tpOk then
                                print("[AutoRifts] RiftSpawn" .. tostring(idx) .. " not found - skipping to next")
                                State.riftsCurrentIndex = (idx % 7) + 1
                                task.wait(1)
                        else
                                -- Step 2: Activate rift (mobile = tap screen 2x, desktop = hold G 2.5s)
                                task.wait(0.5)
                                if State.riftsActivationMode == "mobile" then
                                        if RiftsStatus then
                                                RiftsStatus.Text = "Tapping screen 2x (mobile)..."
                                                RiftsStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
                                        end
                                        tapScreenForRift(riftPos)
                                else
                                        if RiftsStatus then
                                                RiftsStatus.Text = "Holding G for 2.5s (desktop)..."
                                                RiftsStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
                                        end
                                        holdGKey(2.5)
                                end
                                task.wait(0.5)

                                -- Step 2b: Check if dungeon loaded (workspace.DungeonRing.Outer exists)
                                if RiftsStatus then
                                        RiftsStatus.Text = "Checking for DungeonRing.Outer..."
                                        RiftsStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
                                end
                                print("[AutoRifts] Checking workspace.DungeonRing.Outer...")
                                local dungeonRing = workspace:FindFirstChild("DungeonRing")
                                local dungeonOuter = dungeonRing and dungeonRing:FindFirstChild("Outer")
                                if not dungeonOuter then
                                        print("[AutoRifts] DungeonRing.Outer gone - waiting 2s before camp/kill")
                                        if RiftsStatus then
                                                RiftsStatus.Text = "Ring gone! Waiting 2s..."
                                                RiftsStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
                                        end
                                        task.wait(2)
                                        if RiftsStatus then
                                                RiftsStatus.Text = "Rift active - starting camp/kill"
                                                RiftsStatus.TextColor3 = Color3.fromRGB(100, 255, 150)
                                        end
                                else
                                        print("[AutoRifts] DungeonRing.Outer still exists - rift not activated, retrying")
                                        if RiftsStatus then
                                                RiftsStatus.Text = "DungeonRing.Outer found - rift not active"
                                                RiftsStatus.TextColor3 = Color3.fromRGB(255, 150, 150)
                                        end
                                end
                                task.wait(0.5)

                                -- Step 3: Set camp point at current position
                                local char = LocalPlayer.Character
                                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                                local campPoint = hrp and hrp.Position or Vector3.new(0, 0, 0)
                                print("[AutoRifts] Camp point set at " .. tostring(campPoint))

                                -- Step 4: Fight mobs in radius
                                riftCleared = false
                                local lastAttack = 0
                                local noMobCount = 0
                                while State.autoRifts and not riftCleared do
                                        local targetMob = findNearestMobToPoint(campPoint, State.riftsRadius)
                                        if targetMob then
                                                noMobCount = 0
                                                local mobName = targetMob.Name
                                                if RiftsStatus then
                                                        RiftsStatus.Text = "Fighting " .. mobName .. " (RiftSpawn" .. tostring(idx) .. ")"
                                                        RiftsStatus.TextColor3 = Color3.fromRGB(255, 120, 120)
                                                end

                                                -- Check weapon type — if Auto Bow is ON, always use bow
                                                local wType, _ = getEquippedWeaponType()
                                                if State.autoBow then
                                                        wType = "bow"  -- force bow mode when Auto Bow is ON
                                                end

                                                if wType == "bow" then
                                                        -- Bow: TP close to mob and shoot
                                                        tpToMob(targetMob)
                                                        local now = tick()
                                                        if now - lastAttack >= 0.1 then
                                                                lastAttack = now
                                                                riftsBowAttack(targetMob)
                                                        end
                                                        task.wait(0.05)
                                                else
                                                        -- Melee: TP to mob and attack
                                                        tpToMob(targetMob)
                                                        local now = tick()
                                                        if now - lastAttack >= MOB_ATTACK_INTERVAL then
                                                                lastAttack = now
                                                                riftsMeleeAttack()
                                                        end
                                                        task.wait(0.05)
                                                end
                                        else
                                                -- No mob found
                                                noMobCount = noMobCount + 1
                                                if noMobCount == 1 then
                                                        if RiftsStatus then
                                                                RiftsStatus.Text = "No mobs found - waiting for 'Rift cleared' message..."
                                                                RiftsStatus.TextColor3 = Color3.fromRGB(200, 200, 130)
                                                        end
                                                        print("[AutoRifts] No mobs in radius - waiting for 'Rift cleared' message...")
                                                end
                                                -- Wait for rift cleared message (checked by while condition)
                                                -- Also check every 0.5s for new mobs
                                                task.wait(0.5)
                                        end
                                end

                                -- Step 5: Rift cleared! Wait 5s cooldown, then move to next rift
                                if riftCleared then
                                        print("[AutoRifts] Rift cleared! Waiting 5s cooldown...")
                                        if RiftsStatus then
                                                RiftsStatus.Text = "Rift cleared! Cooldown 5s..."
                                                RiftsStatus.TextColor3 = Color3.fromRGB(100, 255, 150)
                                        end
                                        task.wait(5)
                                        print("[AutoRifts] Cooldown done - moving to next rift")
                                        if RiftsStatus then
                                                RiftsStatus.Text = "Moving to next rift..."
                                                RiftsStatus.TextColor3 = Color3.fromRGB(200, 150, 255)
                                        end
                                end

                                -- Increment rift index (1->2->...->7->1)
                                State.riftsCurrentIndex = (State.riftsCurrentIndex % 7) + 1
                                task.wait(1)
                        end
                end
        end)
end

local function stopAutoRifts()
        State.autoRifts = false
        for _, c in ipairs(State.riftsConns) do
                pcall(function() c:Disconnect() end)
        end
        State.riftsConns = {}
        AutoRiftsBtn.Text = ">  Start Auto Rifts"
        AutoRiftsBtn.BackgroundColor3 = Color3.fromRGB(100, 60, 160)
        if RiftsStatus then
                RiftsStatus.Text = "Stopped"
                RiftsStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
        end
        -- Restore collision
        local char = LocalPlayer.Character
        if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then hum.PlatformStand = false end
                for _, part in ipairs(char:GetDescendants()) do
                        if part:IsA("BasePart") then
                                part.CanCollide = true
                        end
                end
        end
        print("[AutoRifts] === STOPPED ===")
end

-- Wrapped in its own pcall so a crash earlier in the script (before this point)
-- can no longer prevent Rifts buttons from being connected.
local riftsWireOk, riftsWireErr = pcall(function()
        AutoRiftsBtn.MouseButton1Click:Connect(function()
                if State.autoRifts then
                        stopAutoRifts()
                else
                        startAutoRifts()
                end
        end)

        RiftsRadiusDownBtn.MouseButton1Click:Connect(function()
                State.riftsRadius = math.max(50, State.riftsRadius - 50)
                RiftsRadiusLabel.Text = "Mob detect radius: " .. tostring(State.riftsRadius) .. " studs"
        end)

        RiftsRadiusUpBtn.MouseButton1Click:Connect(function()
                State.riftsRadius = math.min(5000, State.riftsRadius + 50)
                RiftsRadiusLabel.Text = "Mob detect radius: " .. tostring(State.riftsRadius) .. " studs"
        end)

        -- Activation mode handlers
        local function setRiftsActivationMode(mode)
                State.riftsActivationMode = mode
                RiftsMobileBtn.BackgroundColor3 = (mode == "mobile") and Color3.fromRGB(40, 160, 80) or Color3.fromRGB(60, 60, 80)
                RiftsMobileBtn.TextColor3 = (mode == "mobile") and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(220, 220, 240)
                RiftsDesktopBtn.BackgroundColor3 = (mode == "desktop") and Color3.fromRGB(40, 160, 80) or Color3.fromRGB(60, 60, 80)
                RiftsDesktopBtn.TextColor3 = (mode == "desktop") and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(220, 220, 240)
                print("[AutoRifts] Activation mode: " .. mode)
        end

        RiftsMobileBtn.MouseButton1Click:Connect(function() setRiftsActivationMode("mobile") end)
        RiftsDesktopBtn.MouseButton1Click:Connect(function() setRiftsActivationMode("desktop") end)
end)
if not riftsWireOk then
        warn("[Pilgrammed] Rifts button wiring failed: " .. tostring(riftsWireErr))
end

end) -- end pcall

if not ok then
        warn("[Pilgrammed] Script error: " .. tostring(err))
end
print("[Pilgrammed] Script loaded!")
