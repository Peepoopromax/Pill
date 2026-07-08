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
        bowAutoEquip = false,   -- if false, only shoots when bow already equipped/held
        -- Auto-equip toggles
        mineAutoEquip = false,
        mobAutoEquip = false,
        campAutoEquip = false,
        -- Page draggable
        pageDraggable = false,
        uiScale = 1.0,
        -- Gold Farm Chicken
        autoChickenFarm = false,
        chickenDrinkMagmatic = false,
        chickenRange = 30,
        chickenThread = nil,
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
-- // SECTION 1+2 (REBUILT): "AURORA" PREMIUM UI SYSTEM
-- ------------------------------------------------------------------
-- Everything below is a from-scratch UI rebuild. It creates the exact
-- same set of global element names the automation logic (Section 3,
-- untouched below) reads and writes — so every feature keeps working —
-- but the construction, styling, layout and animation are entirely new.
-- ================================================================

local TweenService = game:GetService("TweenService")

-- ================================================================
-- // DESIGN TOKENS
-- ================================================================
local Theme = {
        Backdrop    = Color3.fromRGB(8, 6, 14),      -- behind the panel (drag shadow)
        Base        = Color3.fromRGB(26, 18, 40),    -- #1A1228 — main panel
        Sidebar     = Color3.fromRGB(19, 13, 30),    -- dock / title bar well
        Card        = Color3.fromRGB(36, 26, 54),
        Elevated    = Color3.fromRGB(50, 36, 76),    -- resting buttons / inputs
        Surface     = Color3.fromRGB(30, 21, 46),    -- scroll frame wells
        Track       = Color3.fromRGB(60, 44, 88),
        Accent      = Color3.fromRGB(176, 92, 255),  -- vivid violet
        Accent2     = Color3.fromRGB(255, 102, 196), -- hot pink — pairs with Accent for glow/gradient "life"
        AccentText  = Color3.fromRGB(18, 8, 28),     -- near-black plum for on-accent text (contrast ~5.4:1, AA)
        Text        = Color3.fromRGB(244, 240, 250),
        TextDim     = Color3.fromRGB(180, 168, 200),
        TextFaint   = Color3.fromRGB(122, 108, 142),
        Danger      = Color3.fromRGB(255, 82, 92),
        Stroke      = Color3.fromRGB(255, 255, 255),
        Font        = Enum.Font.Gotham,
        FontBold    = Enum.Font.GothamBold,
}

-- ================================================================
-- // CORE HELPERS
-- ================================================================

-- Compact instance constructor — cuts boilerplate vs. one-property-per-line.
local function new(className, props, parent)
        local inst = Instance.new(className)
        for k, v in pairs(props or {}) do
                inst[k] = v
        end
        if parent then inst.Parent = parent end
        return inst
end

local function corner(inst, radius)
        return new("UICorner", { CornerRadius = UDim.new(0, radius) }, inst)
end

local function stroke(inst, color, thickness, transparency)
        return new("UIStroke", {
                Color = color, Thickness = thickness or 1,
                Transparency = transparency or 0.85,
        }, inst)
end

local function pad(inst, l, t, r, b)
        return new("UIPadding", {
                PaddingLeft = UDim.new(0, l or 0), PaddingTop = UDim.new(0, t or 0),
                PaddingRight = UDim.new(0, r or 0), PaddingBottom = UDim.new(0, b or 0),
        }, inst)
end

-- Short tween helper. Returns the Tween in case the caller wants to chain.
local function tw(inst, time, props, style, dir)
        local info = TweenInfo.new(time, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out)
        local t = TweenService:Create(inst, info, props)
        t:Play()
        return t
end

-- Universal hover/press feedback. Uses an overlay + UIScale so it NEVER
-- touches BackgroundColor3/Text — those stay fully owned by the feature
-- logic, which sets its own on/off/active colors independently.
local function polish(btn, opts)
        opts = opts or {}
        local hl = new("Frame", {
                Name = "Highlight", BackgroundColor3 = Color3.new(1, 1, 1),
                BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0),
                ZIndex = (btn.ZIndex or 1) + 1, Parent = btn,
        })
        hl.Active = false
        corner(hl, opts.radius or 10)
        local scale
        if not opts.noScale then
                scale = new("UIScale", { Scale = 1 }, btn)
        end
        btn.MouseEnter:Connect(function()
                tw(hl, 0.15, { BackgroundTransparency = 0.90 })
                if scale then tw(scale, 0.15, { Scale = 1.02 }) end
        end)
        btn.MouseLeave:Connect(function()
                tw(hl, 0.15, { BackgroundTransparency = 1 })
                if scale then tw(scale, 0.15, { Scale = 1 }) end
        end)
        btn.MouseButton1Down:Connect(function()
                tw(hl, 0.08, { BackgroundTransparency = 0.80 })
                if scale then tw(scale, 0.08, { Scale = 0.97 }) end
        end)
        btn.MouseButton1Up:Connect(function()
                if scale then tw(scale, 0.12, { Scale = 1.02 }) end
        end)
        return hl
end

-- Slow looping "breathing" glow — the one bit of motion that says "alive"
-- without being distracting. Self-terminates once the instance is gone.
local function livePulse(inst, prop, lo, hi, dur)
        task.spawn(function()
                while inst and inst.Parent do
                        tw(inst, dur, { [prop] = hi }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
                        task.wait(dur)
                        if not (inst and inst.Parent) then break end
                        tw(inst, dur, { [prop] = lo }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
                        task.wait(dur)
                end
        end)
end

-- Two-stop violet -> pink gradient with a slow continuous rotation.
-- Used sparingly on the panel border / active-tab accents for a bit of
-- "growing" color life rather than a single flat static line.
local function lifeGradient(inst, rotSpeed)
        local grad = new("UIGradient", {
                Color = ColorSequence.new(Theme.Accent, Theme.Accent2),
                Rotation = 0,
        }, inst)
        task.spawn(function()
                while inst and inst.Parent do
                        local t = tw(grad, rotSpeed or 6, { Rotation = 360 }, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
                        t.Completed:Wait()
                        if not (inst and inst.Parent) then break end
                        grad.Rotation = 0
                end
        end)
        return grad
end

-- ================================================================
-- // VECTOR ICON LIBRARY (zero external assets — always renders)
-- ================================================================
local Icons = {}

local function shape(parent, xS, yS, wPx, hPx, color, cornerUDim, rot)
        local s = new("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(xS, 0, yS, 0),
                Size = UDim2.new(0, wPx, 0, hPx), BackgroundColor3 = color,
                BorderSizePixel = 0, Rotation = rot or 0,
        }, parent)
        if cornerUDim then corner(s, cornerUDim) end
        return s
end

local function iconBase(parent, sz)
        return new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, sz, 0, sz) }, parent)
end

function Icons.player(parent, sz, color) -- Player page
        local f = iconBase(parent, sz)
        local head = shape(f, 0.5, 0.28, sz * 0.34, sz * 0.34, color, sz)
        local body = shape(f, 0.5, 0.80, sz * 0.60, sz * 0.42, color, sz * 0.18)
        return f, { head, body }
end

function Icons.diamond(parent, sz, color) -- Auto (mining/loot) page
        local f = iconBase(parent, sz)
        local d = shape(f, 0.5, 0.5, sz * 0.5, sz * 0.5, color, 3)
        d.Rotation = 45
        return f, { d }
end

function Icons.cross(parent, sz, color) -- Mob (combat) page
        local f = iconBase(parent, sz)
        local a = shape(f, 0.5, 0.5, sz * 0.62, sz * 0.15, color, 3, 45)
        local b = shape(f, 0.5, 0.5, sz * 0.62, sz * 0.15, color, 3, -45)
        return f, { a, b }
end

function Icons.gear(parent, sz, color) -- Settings page
        local f = iconBase(parent, sz)
        local a = shape(f, 0.5, 0.5, sz * 0.62, sz * 0.14, color, 2, 0)
        local b = shape(f, 0.5, 0.5, sz * 0.62, sz * 0.14, color, 2, 60)
        local c = shape(f, 0.5, 0.5, sz * 0.62, sz * 0.14, color, 2, 120)
        local hole = shape(f, 0.5, 0.5, sz * 0.22, sz * 0.22, Theme.Sidebar, sz)
        return f, { a, b, c }, hole
end

function Icons.trash(parent, sz, color) -- Junkpits page
        local f = iconBase(parent, sz)
        local body = shape(f, 0.5, 0.60, sz * 0.46, sz * 0.44, color, 4)
        local lid = shape(f, 0.5, 0.30, sz * 0.60, sz * 0.12, color, 2)
        return f, { body, lid }
end

function Icons.portal(parent, sz, color) -- Rifts page
        local f = iconBase(parent, sz)
        local ring = shape(f, 0.5, 0.5, sz * 0.66, sz * 0.66, color, sz)
        local hole = shape(f, 0.5, 0.5, sz * 0.30, sz * 0.30, Theme.Sidebar, sz)
        return f, { ring }, hole
end

function Icons.close(parent, sz, color)
        local f = iconBase(parent, sz)
        local a = shape(f, 0.5, 0.5, sz * 0.72, sz * 0.12, color, 2, 45)
        local b = shape(f, 0.5, 0.5, sz * 0.72, sz * 0.12, color, 2, -45)
        return f, { a, b }
end

function Icons.menu(parent, sz, color)
        local f = iconBase(parent, sz)
        local a = shape(f, 0.5, 0.30, sz * 0.6, sz * 0.10, color, 2)
        local b = shape(f, 0.5, 0.5, sz * 0.6, sz * 0.10, color, 2)
        local c = shape(f, 0.5, 0.70, sz * 0.6, sz * 0.10, color, 2)
        return f, { a, b, c }
end

-- ================================================================
-- // ROOT CONTAINER
-- ================================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "OreMinerGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui

-- ================================================================
-- // FLOATING DOCK (icon rail — its own frame, not attached to a panel)
-- ================================================================
local Dock = new("CanvasGroup", {
        Name = "Dock", AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 18, 0.5, 0), Size = UDim2.new(0, 84, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Theme.Sidebar,
        BorderSizePixel = 0, Active = true, Visible = true, GroupTransparency = 1, ZIndex = 60,
}, ScreenGui)
corner(Dock, 20)
local dockStroke = stroke(Dock, Theme.Accent, 1, 0.6)
lifeGradient(dockStroke, 8)
local DockScale = new("UIScale", { Scale = 0.9 }, Dock)
pad(Dock, 8, 10, 8, 12)
new("UIListLayout", {
        Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
}, Dock)

local DockShadow = new("Frame", {
        BackgroundColor3 = Theme.Backdrop, BackgroundTransparency = 0.5,
        BorderSizePixel = 0, ZIndex = 58, Visible = false,
}, ScreenGui)
corner(DockShadow, 24)
local function syncDockShadow()
        DockShadow.Size = UDim2.new(0, Dock.AbsoluteSize.X + 14, 0, Dock.AbsoluteSize.Y + 14)
        DockShadow.Position = UDim2.new(0, Dock.AbsolutePosition.X - 7, 0, Dock.AbsolutePosition.Y - 7)
end
Dock:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncDockShadow)
Dock:GetPropertyChangedSignal("AbsolutePosition"):Connect(syncDockShadow)
syncDockShadow()

-- Drag grip strip (top of dock, LayoutOrder 1)
local DockGrip = new("Frame", { Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1, LayoutOrder = 1 }, Dock)
local gripBar = new("Frame", {
        Size = UDim2.new(0, 28, 0, 4), Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Theme.TextFaint, BorderSizePixel = 0,
}, DockGrip)
corner(gripBar, 2)

-- Nav items live in here (LayoutOrder 2), one row per top-level entry
local DockList = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, LayoutOrder = 2,
}, Dock)
new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, DockList)

-- Top-level nav row: icon + label, matches original sidebar button look,
-- with an optional rotating chevron badge for entries that expand (Auto).
local function navRow(parent, iconFn, label, order, hasChevron)
        local btn = new("TextButton", {
                Size = UDim2.new(1, 0, 0, 58), BackgroundColor3 = Theme.Accent, BackgroundTransparency = 1,
                AutoButtonColor = false, BorderSizePixel = 0, Text = "", LayoutOrder = order,
        }, parent)
        corner(btn, 12)
        local bar = new("Frame", {
                Size = UDim2.new(0, 3, 0, 0), Position = UDim2.new(0, 0, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
                BackgroundColor3 = Theme.Accent, BorderSizePixel = 0,
        }, btn)
        corner(bar, 2)
        local iconHolder = new("Frame", {
                Size = UDim2.new(0, 22, 0, 22), Position = UDim2.new(0.5, 0, 0.30, 0),
                AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1,
        }, btn)
        local _, iconParts = iconFn(iconHolder, 22, Theme.TextDim)
        local lbl = new("TextLabel", {
                Size = UDim2.new(1, -6, 0, 14), Position = UDim2.new(0.5, 0, 0.74, 0), AnchorPoint = Vector2.new(0.5, 0.5),
                BackgroundTransparency = 1, Text = label, Font = Theme.FontBold, TextSize = 10, TextColor3 = Theme.TextDim,
        }, btn)
        local chevron
        if hasChevron then
                chevron = new("TextLabel", {
                        Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(1, -3, 0, 3),
                        AnchorPoint = Vector2.new(1, 0), BackgroundTransparency = 1, Text = ">",
                        Font = Theme.FontBold, TextSize = 12, TextColor3 = Theme.TextDim, Rotation = 0,
                }, btn)
        end
        polish(btn, { noScale = true })
        return { btn = btn, bar = bar, iconParts = iconParts, lbl = lbl, chevron = chevron, name = label }
end

-- ================================================================
-- // FLOATING CONTENT PANEL (independent of the dock — appears on tap)
-- ================================================================
local ContentPanel = new("CanvasGroup", {
        Name = "ContentPanel", AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.58, 0, 0.5, 0), Size = UDim2.new(0.4, 0, 0.7, 0),
        BackgroundColor3 = Theme.Base, BorderSizePixel = 0, Active = true,
        Visible = false, GroupTransparency = 1, ZIndex = 50,
}, ScreenGui)
corner(ContentPanel, 18)
local panelStroke = stroke(ContentPanel, Theme.Accent, 1, 0.7)
lifeGradient(panelStroke, 7)
new("UISizeConstraint", { MinSize = Vector2.new(320, 420), MaxSize = Vector2.new(560, 720) }, ContentPanel)
local ContentScale = new("UIScale", { Scale = 0.92 }, ContentPanel)
local panelBaseScale = 1.0   -- user-adjustable via Settings > UI (Panel Size)
local panelSizePercent = 100

local PanelShadow = new("Frame", {
        AnchorPoint = Vector2.new(0, 0), BackgroundColor3 = Theme.Backdrop,
        BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 49, Visible = false,
}, ScreenGui)
corner(PanelShadow, 20)
local function syncPanelShadow()
        PanelShadow.Size = UDim2.new(0, ContentPanel.AbsoluteSize.X + 16, 0, ContentPanel.AbsoluteSize.Y + 16)
        PanelShadow.Position = UDim2.new(0, ContentPanel.AbsolutePosition.X - 8, 0, ContentPanel.AbsolutePosition.Y - 2)
end
ContentPanel:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncPanelShadow)
ContentPanel:GetPropertyChangedSignal("AbsolutePosition"):Connect(syncPanelShadow)
syncPanelShadow()

-- Title bar
local PanelTitleBar = new("Frame", {
        Name = "TitleBar", Size = UDim2.new(1, 0, 0, 44),
        BackgroundColor3 = Theme.Sidebar, BorderSizePixel = 0, ZIndex = 2,
}, ContentPanel)
local pMarkHolder = new("Frame", {
        Size = UDim2.new(0, 18, 0, 18), Position = UDim2.new(0, 14, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5), BackgroundTransparency = 1,
}, PanelTitleBar)
Icons.diamond(pMarkHolder, 18, Theme.Accent)
local PanelTitleLabel = new("TextLabel", {
        Size = UDim2.new(1, -96, 0, 18), Position = UDim2.new(0, 40, 0, 6),
        BackgroundTransparency = 1, Text = "PILGRAMMED", TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.FontBold, TextSize = 14,
}, PanelTitleBar)
local PanelBreadcrumb = new("TextLabel", {
        Size = UDim2.new(1, -96, 0, 14), Position = UDim2.new(0, 40, 0, 23),
        BackgroundTransparency = 1, Text = "", TextColor3 = Theme.TextFaint,
        TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.Font, TextSize = 10,
}, PanelTitleBar)

local PanelCloseBtn = new("TextButton", {
        Size = UDim2.new(0, 28, 0, 28), Position = UDim2.new(1, -38, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Theme.Elevated,
        AutoButtonColor = false, BorderSizePixel = 0, Text = "",
}, PanelTitleBar)
corner(PanelCloseBtn, 14)
local panelCloseIconHolder = new("Frame", {
        Size = UDim2.new(0, 12, 0, 12), Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1,
}, PanelCloseBtn)
Icons.close(panelCloseIconHolder, 12, Theme.TextDim)
polish(PanelCloseBtn, { radius = 14 })

-- Body (also a CanvasGroup -> smooth cross-fade between pages)
local ContentBody = new("CanvasGroup", {
        Name = "ContentBody", Size = UDim2.new(1, 0, 1, -44), Position = UDim2.new(0, 0, 0, 44),
        BackgroundColor3 = Theme.Base, BackgroundTransparency = 1,
}, ContentPanel)

local Pages = {}

local function newPage(name)
        local page = new("ScrollingFrame", {
                Name = name .. "Page", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
                ScrollBarThickness = 5, ScrollBarImageColor3 = Theme.Accent, ScrollBarImageTransparency = 0.2,
                CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollingDirection = Enum.ScrollingDirection.Y, ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
                Active = true, Visible = false,
        }, ContentBody)
        pad(page, 16, 14, 14, 16)
        new("UIListLayout", { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, page)
        Pages[name] = page
        return page
end

-- ================================================================
-- // CONTENT-BUILDING HELPERS (used across all pages)
-- ================================================================

local function card(parent, order, titleText, titleColor)
        local c = new("Frame", {
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = Theme.Card, BorderSizePixel = 0, LayoutOrder = order,
        }, parent)
        corner(c, 16)
        stroke(c, Theme.Stroke, 1, 0.92)
        pad(c, 16, 14, 16, 14)
        new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, c)
        if titleText then
                new("TextLabel", {
                        Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Text = titleText,
                        Font = Theme.FontBold, TextSize = 13, TextColor3 = titleColor or Theme.Accent,
                        TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 0,
                }, c)
        end
        return c
end

local function caption(parent, order, text)
        return new("TextLabel", {
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
                Text = text, Font = Theme.Font, TextSize = 12, TextColor3 = Theme.TextDim,
                TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, LayoutOrder = order,
        }, parent)
end

local function statusLabel(parent, order, text)
        return new("TextLabel", {
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
                Text = text, Font = Theme.Font, TextSize = 11, TextColor3 = Theme.TextFaint,
                TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, LayoutOrder = order,
        }, parent)
end

local function actionButton(parent, order, text, variant)
        local bg = Theme.Elevated
        local fg = Theme.Text
        if variant == "primary" then bg, fg = Theme.Accent, Theme.AccentText
        elseif variant == "danger" then bg, fg = Theme.Danger, Theme.Text end
        local b = new("TextButton", {
                Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = bg, BorderSizePixel = 0,
                Text = text, Font = Theme.FontBold, TextSize = 13, TextColor3 = fg,
                AutoButtonColor = false, LayoutOrder = order,
        }, parent)
        corner(b, 12)
        polish(b)
        return b
end

local function textInput(parent, order, placeholder, initialText)
        local box = new("TextBox", {
                Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = Theme.Elevated, BorderSizePixel = 0,
                PlaceholderText = placeholder, PlaceholderColor3 = Theme.TextFaint, Text = initialText or "",
                TextColor3 = Theme.Text, Font = Theme.Font, TextSize = 13, ClearTextOnFocus = false,
                LayoutOrder = order,
        }, parent)
        corner(box, 10)
        pad(box, 12, 0, 10, 0)
        return box
end

local function inputWithButton(parent, order, placeholder, initialText, btnText)
        local row = new("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, LayoutOrder = order }, parent)
        local box = new("TextBox", {
                Size = UDim2.new(1, -80, 1, 0), BackgroundColor3 = Theme.Elevated, BorderSizePixel = 0,
                PlaceholderText = placeholder, PlaceholderColor3 = Theme.TextFaint, Text = initialText or "",
                TextColor3 = Theme.Text, Font = Theme.Font, TextSize = 13, ClearTextOnFocus = false,
        }, row)
        corner(box, 10)
        pad(box, 12, 0, 8, 0)
        local btn = new("TextButton", {
                Size = UDim2.new(0, 74, 1, 0), Position = UDim2.new(1, -74, 0, 0), BackgroundColor3 = Theme.Accent,
                Text = btnText, Font = Theme.FontBold, TextSize = 12, TextColor3 = Theme.AccentText,
                AutoButtonColor = false, BorderSizePixel = 0,
        }, row)
        corner(btn, 10)
        polish(btn)
        return box, btn
end

-- Numeric "stepper" row: label shows the live descriptive text (owned by
-- the logic layer), +/- buttons drive the actual value change (unchanged
-- logic hookup), and a slim accent track underneath gives a real slider
-- *visual* by reading the number back out of the label whenever it changes.
local function stepper(parent, order, initialText, minV, maxV)
        local row = new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, LayoutOrder = order }, parent)
        local lbl = new("TextLabel", {
                Size = UDim2.new(1, -80, 0, 20), BackgroundTransparency = 1, Text = initialText,
                Font = Theme.Font, TextSize = 12, TextColor3 = Theme.TextDim,
                TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
        }, row)
        local down = new("TextButton", {
                Size = UDim2.new(0, 32, 0, 26), Position = UDim2.new(1, -72, 0, 0), BackgroundColor3 = Theme.Elevated,
                Text = "-", Font = Theme.FontBold, TextSize = 16, TextColor3 = Theme.Text,
                AutoButtonColor = false, BorderSizePixel = 0,
        }, row)
        corner(down, 9)
        polish(down, { noScale = true })
        local up = new("TextButton", {
                Size = UDim2.new(0, 32, 0, 26), Position = UDim2.new(1, -36, 0, 0), BackgroundColor3 = Theme.Elevated,
                Text = "+", Font = Theme.FontBold, TextSize = 16, TextColor3 = Theme.Text,
                AutoButtonColor = false, BorderSizePixel = 0,
        }, row)
        corner(up, 9)
        polish(up, { noScale = true })

        local track = new("Frame", {
                Size = UDim2.new(1, 0, 0, 3), Position = UDim2.new(0, 0, 1, -3),
                BackgroundColor3 = Theme.Track, BorderSizePixel = 0,
        }, row)
        corner(track, 2)
        local fill = new("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0 }, track)
        corner(fill, 2)

        if minV and maxV then
                local function sync()
                        local n = tonumber(lbl.Text:match("%-?%d+%.?%d*"))
                        if n then
                                local pct = math.clamp((n - minV) / (maxV - minV), 0, 1)
                                tw(fill, 0.18, { Size = UDim2.new(pct, 0, 1, 0) })
                        end
                end
                lbl:GetPropertyChangedSignal("Text"):Connect(sync)
                sync()
        end

        return down, up, lbl
end

-- Equal-width segmented button row (2-5 options). Colors are left neutral;
-- the logic layer recolors the selected option itself.
local function segmented(parent, order, labels, opts)
        opts = opts or {}
        local n = #labels
        local row = new("Frame", { Size = UDim2.new(1, 0, 0, opts.height or 32), BackgroundTransparency = 1, LayoutOrder = order }, parent)
        new("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6),
                SortOrder = Enum.SortOrder.LayoutOrder,
        }, row)
        local gap = 6 * (n - 1) / n
        local btns = {}
        for i, text in ipairs(labels) do
                local b = new("TextButton", {
                        Size = UDim2.new(1 / n, -gap, 1, 0), BackgroundColor3 = Theme.Elevated, BorderSizePixel = 0,
                        Text = text, Font = Theme.FontBold, TextSize = opts.textSize or 12, TextColor3 = Theme.TextDim,
                        TextWrapped = true, AutoButtonColor = false, LayoutOrder = i,
                }, row)
                corner(b, 9)
                polish(b, { noScale = true })
                btns[i] = b
        end
        return table.unpack(btns)
end

-- Ore/mob searchable checklist section
local function searchSection(parent, order, placeholderText)
        local wrap = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order }, parent)
        new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, wrap)

        local searchBox = new("TextBox", {
                Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = Theme.Elevated, BorderSizePixel = 0,
                PlaceholderText = placeholderText, PlaceholderColor3 = Theme.TextFaint, Text = "",
                TextColor3 = Theme.Text, Font = Theme.Font, TextSize = 13, ClearTextOnFocus = false, LayoutOrder = 1,
        }, wrap)
        corner(searchBox, 10)
        pad(searchBox, 34, 0, 10, 0)
        local searchIconHolder = new("Frame", {
                Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(0, 12, 0.5, 0),
                AnchorPoint = Vector2.new(0, 0.5), BackgroundTransparency = 1,
        }, searchBox)
        local ring = new("Frame", { Size = UDim2.new(0, 9, 0, 9), Position = UDim2.new(0, 0, 0, 0), BackgroundColor3 = Theme.TextFaint, BorderSizePixel = 0 }, searchIconHolder)
        corner(ring, 5)
        stroke(ring, Theme.TextFaint, 1.5, 0)
        ring.BackgroundTransparency = 1
        local handle = new("Frame", {
                Size = UDim2.new(0, 6, 0, 2), Position = UDim2.new(0, 8, 0, 9), Rotation = 45,
                BackgroundColor3 = Theme.TextFaint, BorderSizePixel = 0,
        }, searchIconHolder)
        corner(handle, 1)

        local btnRow = new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 2 }, wrap)
        new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, btnRow)
        local selAll = new("TextButton", {
                Size = UDim2.new(0.5, -4, 1, 0), BackgroundColor3 = Theme.Elevated, Text = "Select All",
                Font = Theme.FontBold, TextSize = 12, TextColor3 = Theme.TextDim, AutoButtonColor = false,
                BorderSizePixel = 0, LayoutOrder = 1,
        }, btnRow)
        corner(selAll, 9); polish(selAll, { noScale = true })
        local clrAll = new("TextButton", {
                Size = UDim2.new(0.5, -4, 1, 0), BackgroundColor3 = Theme.Elevated, Text = "Clear All",
                Font = Theme.FontBold, TextSize = 12, TextColor3 = Theme.TextDim, AutoButtonColor = false,
                BorderSizePixel = 0, LayoutOrder = 2,
        }, btnRow)
        corner(clrAll, 9); polish(clrAll, { noScale = true })

        local scroll = new("ScrollingFrame", {
                Size = UDim2.new(1, 0, 0, 168), BackgroundColor3 = Theme.Surface, BorderSizePixel = 0,
                ScrollBarThickness = 4, ScrollBarImageColor3 = Theme.Accent, ScrollBarImageTransparency = 0.3,
                CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, LayoutOrder = 3,
        }, wrap)
        corner(scroll, 10)
        new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
        pad(scroll, 6, 6, 6, 6)

        local selectedLabel = new("TextLabel", {
                Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Text = "Selected: None",
                Font = Theme.Font, TextSize = 12, TextColor3 = Color3.fromRGB(255, 120, 120),
                TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 4,
        }, wrap)

        return searchBox, selAll, clrAll, scroll, selectedLabel
end

-- ================================================================
-- // PLAYER PAGE
-- ================================================================
local UI = {}  -- shared table for UI refs (avoids 200-local limit)

local PlayerPage = newPage("Player")

local parryCard = card(PlayerPage, 1, "Auto Parry")
caption(parryCard, 1, "Blocks enemy attacks automatically using a 2-layer detector (attack-warning remote + animation watch).")
local AutoParryBtn = actionButton(parryCard, 2, "Auto Parry: OFF")
caption(parryCard, 3, "Hold: " .. tostring(PARRY_HOLD_TIME) .. "s   |   Cooldown: " .. tostring(PARRY_COOLDOWN) .. "s")
local ParryStatus = statusLabel(parryCard, 4, "Status: Idle")

local spamCard = card(PlayerPage, 2, "Spam Parry")
caption(spamCard, 1, "Holds and releases block in a continuous loop.")
local SpamParryBtn = actionButton(spamCard, 2, "Spam Parry: OFF")
local SpamParryDownBtn, SpamParryUpBtn, SpamParryLenLabel = stepper(spamCard, 3, "Hold length: " .. string.format("%.2f", State.spamParryLength) .. "s", 0.1, 0.7)
local SpamParryStatus = statusLabel(spamCard, 4, "Idle")

-- ================================================================
-- // AUTO > FARM  (ore mining + mob farm + camp farm + attack position)
-- ================================================================
local AutoFarmPage = newPage("AutoFarm")

local oreCard = card(AutoFarmPage, 1, "Ore Selection")
local SearchBox, SelectAllBtn, DeselectAllBtn, OreScroll, SelectedLabel = searchSection(oreCard, 1, "Search ores...")

local mineCard = card(AutoFarmPage, 2, "Mining")
local mineRow = new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, LayoutOrder = 1 }, mineCard)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, mineRow)
local AutoFarmBtn = new("TextButton", {
        Size = UDim2.new(0.62, -4, 1, 0), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0,
        Text = "Auto Farm", Font = Theme.FontBold, TextSize = 13, TextColor3 = Theme.AccentText,
        AutoButtonColor = false, LayoutOrder = 1,
}, mineRow)
corner(AutoFarmBtn, 12); polish(AutoFarmBtn)
local AllOresBtn = new("TextButton", {
        Size = UDim2.new(0.38, -4, 1, 0), BackgroundColor3 = Theme.Elevated, BorderSizePixel = 0,
        Text = "All Ores", Font = Theme.FontBold, TextSize = 13, TextColor3 = Theme.Text,
        AutoButtonColor = false, LayoutOrder = 2,
}, mineRow)
corner(AllOresBtn, 12); polish(AllOresBtn)
local StatusLabel = statusLabel(mineCard, 2, "Status: Idle | Fly: OFF")
local MineAutoEquipBtn = actionButton(mineCard, 3, "Auto-Equip Pickaxe: OFF")

local mobSelCard = card(AutoFarmPage, 3, "Mob Selection")
local MobSearchBox, MobSelAllBtn, MobClrAllBtn, MobScroll, MobSelectedLabel = searchSection(mobSelCard, 1, "Search mobs...")

local atkTypeCard = card(AutoFarmPage, 4, "Attack Type & Range")
local LightBtn, HeavyBtn, TechBtn = segmented(atkTypeCard, 1, { "Light", "Heavy", "Technique" })
local MobDistDownBtn, MobDistUpBtn, MobDistLabel = stepper(atkTypeCard, 2, "Below mob: " .. tostring(math.abs(MOB_FLY_OFFSET.Y)) .. " studs", 1, 50)
local MobAtkDownBtn, MobAtkUpBtn, MobAtkLabel = stepper(atkTypeCard, 3, "Attack Speed: " .. string.format("%.2f", MOB_ATTACK_INTERVAL) .. "s", 0.1, 2.0)

local mobFarmCard = card(AutoFarmPage, 5, "Mob Farm")
local MobStatusLabel = statusLabel(mobFarmCard, 1, "Status: Idle")
local mobFarmRow = new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, LayoutOrder = 2 }, mobFarmCard)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, mobFarmRow)
local MobFarmBtn = new("TextButton", {
        Size = UDim2.new(0.62, -4, 1, 0), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0,
        Text = "Mob Farm", Font = Theme.FontBold, TextSize = 13, TextColor3 = Theme.AccentText,
        AutoButtonColor = false, LayoutOrder = 1,
}, mobFarmRow)
corner(MobFarmBtn, 12); polish(MobFarmBtn)
local MobAllBtn = new("TextButton", {
        Size = UDim2.new(0.38, -4, 1, 0), BackgroundColor3 = Theme.Elevated, BorderSizePixel = 0,
        Text = "All Mobs", Font = Theme.FontBold, TextSize = 13, TextColor3 = Theme.Text,
        AutoButtonColor = false, LayoutOrder = 2,
}, mobFarmRow)
corner(MobAllBtn, 12); polish(MobAllBtn)
local MobAutoEquipBtn = actionButton(mobFarmCard, 3, "Auto-Equip Weapon: OFF")

local campCard = card(AutoFarmPage, 6, "Camp Farm")
local WeaponNameBox, EquipWeaponBtn = inputWithButton(campCard, 1, "Weapon name", "", "Equip")
local pointRow = new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = 2 }, campCard)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, pointRow)
local SetPointBtn = new("TextButton", {
        Size = UDim2.new(0.5, -4, 1, 0), BackgroundColor3 = Theme.Elevated, BorderSizePixel = 0,
        Text = "Set Point (here)", Font = Theme.FontBold, TextSize = 12, TextColor3 = Theme.Text,
        AutoButtonColor = false, LayoutOrder = 1,
}, pointRow)
corner(SetPointBtn, 10); polish(SetPointBtn, { noScale = true })
local ClearPointBtn = new("TextButton", {
        Size = UDim2.new(0.5, -4, 1, 0), BackgroundColor3 = Theme.Elevated, BorderSizePixel = 0,
        Text = "Clear Point", Font = Theme.FontBold, TextSize = 12, TextColor3 = Theme.Text,
        AutoButtonColor = false, LayoutOrder = 2,
}, pointRow)
corner(ClearPointBtn, 10); polish(ClearPointBtn, { noScale = true })
local CampRadiusDownBtn, CampRadiusUpBtn, CampRadiusLabel = stepper(campCard, 3, "Radius: " .. tostring(State.campRadius) .. " studs", 5, 200)
local CampStatusLabel = statusLabel(campCard, 4, "Camp: Idle")
local CampFarmBtn = actionButton(campCard, 5, "Start Camp Farm", "primary")
local CampAutoEquipBtn = actionButton(campCard, 6, "Auto-Equip Weapon: OFF")

local atkPosCard = card(AutoFarmPage, 7, "Attack Position")
caption(atkPosCard, 1, "Applies to both Mob Farm and Camp Farm.")
local AtkPosBelowBtn, AtkPosAboveBtn, AtkPosBehindBtn, AtkPosFrontBtn, AtkPosCustomBtn =
        segmented(atkPosCard, 2, { "Below", "Above", "Behind", "Front", "Custom" }, { height = 40, textSize = 11 })
local BelowAboveDistDownBtn, BelowAboveDistUpBtn, BelowAboveDistLabel = stepper(atkPosCard, 3, "Below/Above dist: " .. tostring(BELOW_DISTANCE) .. " studs", 1, 50)
local BehindDistDownBtn, BehindDistUpBtn, BehindDistLabel = stepper(atkPosCard, 4, "Behind/Front dist: " .. tostring(BEHIND_DISTANCE) .. " studs", 1, 50)
local CustomOffsetBox, CustomOffsetApplyBtn = inputWithButton(atkPosCard, 5, "Custom offset: x,y,z", "", "Apply")

-- ================================================================
-- // AUTO > GOLD
-- ================================================================
local AutoGoldPage = newPage("AutoGold")
local goldCard = card(AutoGoldPage, 1, "Auto Deposit Gold")
local AutoDepositBtn = actionButton(goldCard, 1, "Auto Deposit: OFF")
local GoldThreshDownBtn, GoldThreshUpBtn, GoldThresholdLabel = stepper(goldCard, 2, "Cooldown: " .. string.format("%.1f", AUTO_DEPOSIT_COOLDOWN) .. "s", 0.5, 30)
local GoldStatus = statusLabel(goldCard, 3, "Status: Idle")

-- ================================================================
-- // AUTO > EVENT  (was: Junkpits)
-- ================================================================
local AutoEventPage = newPage("AutoEvent")
do
local cronoCard = card(AutoEventPage, 1, "Crono's Key Collect")
UI.CronoKeyBtn = actionButton(cronoCard, 1, "Start Crono Key Collect", "primary")
UI.CronoKeyStatus = statusLabel(cronoCard, 2, "Idle")

local deleteCard = card(AutoEventPage, 2, "Delete Enemies")
UI.DeleteBtn = actionButton(deleteCard, 1, "Start Delete Enemies", "primary")
UI.DeleteStatus = statusLabel(deleteCard, 2, "Idle")
end

-- ================================================================
-- // AUTO > RIFTS
-- ================================================================
local AutoRiftsPage = newPage("AutoRifts")
do
local riftsCard = card(AutoRiftsPage, 1, "Auto Rifts")
caption(riftsCard, 1, "Automatically detects and clears nearby rifts.")
UI.RiftsRadiusDownBtn, UI.RiftsRadiusUpBtn, UI.RiftsRadiusLabel = stepper(riftsCard, 2, "Mob detect radius: " .. tostring(State.riftsRadius) .. " studs", 50, 5000)
UI.AutoRiftsBtn = actionButton(riftsCard, 3, "Start Auto Rifts", "primary")
UI.RiftsStatus = statusLabel(riftsCard, 4, "Idle")

local riftsModeCard = card(AutoRiftsPage, 2, "Activation Mode")
UI.RiftsMobileBtn, UI.RiftsDesktopBtn = segmented(riftsModeCard, 1, { "Mobile", "Desktop" })
end

-- ================================================================
-- // AUTO > FISHING
-- ================================================================
local AutoFishingPage = newPage("AutoFishing")
do
local fishCard = card(AutoFishingPage, 1, "Auto Fishing")
UI.RodNameBox = textInput(fishCard, 1, "Rod name (e.g. Rod of Kings)", "")
UI.FishWaitDownBtn, UI.FishWaitUpBtn, UI.FishWaitLabel = stepper(fishCard, 2, "Wait before reel: " .. string.format("%.2f", State.fishWaitSeconds) .. " sec", 0.1, 15)
UI.AutoFishBtn = actionButton(fishCard, 3, "Start Auto Fish", "primary")
UI.FishStatus = statusLabel(fishCard, 4, "Status: Idle")
end

-- ================================================================
-- // GOLD FARM CHICKEN METHOD (in Auto > Gold page)
-- ================================================================
ChickenFarmBtn = nil
ChickenDrinkBtn = nil
ChickenStatus = nil
ChickenWeaponBox = nil
do
local chickenCard = card(AutoGoldPage, 3, "Gold Farm Chicken Method")
local ChickenRangeDownBtn, ChickenRangeUpBtn, ChickenRangeLabel = stepper(chickenCard, 1, "Detect range: 30 studs", 5, 100)
ChickenWeaponBox = textInput(chickenCard, 2, "Weapon name (bow or melee)", "")
ChickenFarmBtn = actionButton(chickenCard, 3, "Start Chicken Farm", "primary")
ChickenDrinkBtn = actionButton(chickenCard, 4, "Auto Drink Magmatic: OFF")
ChickenStatus = statusLabel(chickenCard, 5, "Status: Idle")

ChickenRangeDownBtn.MouseButton1Click:Connect(function()
        State.chickenRange = math.max(5, State.chickenRange - 5)
        ChickenRangeLabel.Text = "Detect range: " .. tostring(State.chickenRange) .. " studs"
end)
ChickenRangeUpBtn.MouseButton1Click:Connect(function()
        State.chickenRange = math.min(100, State.chickenRange + 5)
        ChickenRangeLabel.Text = "Detect range: " .. tostring(State.chickenRange) .. " studs"
end)
end

-- ================================================================
-- // FIGHT  (weapons)
-- ================================================================
local FightPage = newPage("Fight")
do
local bowCard = card(FightPage, 1, "Auto Bow")
UI.BowNameBox = textInput(bowCard, 1, "Bow name", "")
UI.BowRateDownBtn, UI.BowRateUpBtn, UI.BowRateLabel = stepper(bowCard, 2, "Bow Shoot Rate: " .. string.format("%.2f", State.bowShootRate) .. "s", 0.05, 2.0)
UI.AutoBowBtn = actionButton(bowCard, 3, "Start Auto Bow", "primary")
local BowAutoEquipBtn = actionButton(bowCard, 4, "Auto-Equip: OFF (manual hold only)")
UI.BowStatus = statusLabel(bowCard, 5, "Idle")

-- This one small toggle is wired at creation time (outside the logic pcall),
-- kept exactly as in the original to preserve behaviour identically.
BowAutoEquipBtn.MouseButton1Click:Connect(function()
        State.bowAutoEquip = not State.bowAutoEquip
        if State.bowAutoEquip then
                BowAutoEquipBtn.Text = "Auto-Equip: ON"
                BowAutoEquipBtn.BackgroundColor3 = Theme.Accent
                BowAutoEquipBtn.TextColor3 = Theme.AccentText
        else
                BowAutoEquipBtn.Text = "Auto-Equip: OFF (manual hold only)"
                BowAutoEquipBtn.BackgroundColor3 = Theme.Elevated
                BowAutoEquipBtn.TextColor3 = Theme.Text
        end
end)
end

-- Mining auto-equip toggle
MineAutoEquipBtn.MouseButton1Click:Connect(function()
        State.mineAutoEquip = not State.mineAutoEquip
        if State.mineAutoEquip then
                MineAutoEquipBtn.Text = "Auto-Equip Pickaxe: ON"
                MineAutoEquipBtn.BackgroundColor3 = Theme.Accent
                MineAutoEquipBtn.TextColor3 = Theme.AccentText
        else
                MineAutoEquipBtn.Text = "Auto-Equip Pickaxe: OFF"
                MineAutoEquipBtn.BackgroundColor3 = Theme.Elevated
                MineAutoEquipBtn.TextColor3 = Theme.Text
        end
end)

-- Mob Farm auto-equip toggle
MobAutoEquipBtn.MouseButton1Click:Connect(function()
        State.mobAutoEquip = not State.mobAutoEquip
        if State.mobAutoEquip then
                MobAutoEquipBtn.Text = "Auto-Equip Weapon: ON"
                MobAutoEquipBtn.BackgroundColor3 = Theme.Accent
                MobAutoEquipBtn.TextColor3 = Theme.AccentText
        else
                MobAutoEquipBtn.Text = "Auto-Equip Weapon: OFF"
                MobAutoEquipBtn.BackgroundColor3 = Theme.Elevated
                MobAutoEquipBtn.TextColor3 = Theme.Text
        end
end)

-- Camp Farm auto-equip toggle
CampAutoEquipBtn.MouseButton1Click:Connect(function()
        State.campAutoEquip = not State.campAutoEquip
        if State.campAutoEquip then
                CampAutoEquipBtn.Text = "Auto-Equip Weapon: ON"
                CampAutoEquipBtn.BackgroundColor3 = Theme.Accent
                CampAutoEquipBtn.TextColor3 = Theme.AccentText
        else
                CampAutoEquipBtn.Text = "Auto-Equip Weapon: OFF"
                CampAutoEquipBtn.BackgroundColor3 = Theme.Elevated
                CampAutoEquipBtn.TextColor3 = Theme.Text
        end
end)

-- ================================================================
-- // SETTINGS
-- ================================================================
local SettingsPage = newPage("Settings")
do
local uiSizeCard = card(SettingsPage, 1, "UI")
caption(uiSizeCard, 1, "Adjust the size of this panel. Starts smaller for phones -- turn it up on PC.")
local UISizeDownBtn, UISizeUpBtn, UISizeLabel = stepper(uiSizeCard, 2, "Panel Size: 100%", 70, 140)

local moveCard = card(SettingsPage, 2, "Movement")
local moveRow = new("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = 1 }, moveCard)
new("TextLabel", {
        Size = UDim2.new(1, -60, 1, 0), BackgroundTransparency = 1, Text = "Toggle-square move mode",
        Font = Theme.Font, TextSize = 12, TextColor3 = Theme.TextDim, TextXAlignment = Enum.TextXAlignment.Left,
}, moveRow)
UI.MoveToggleBtn = new("TextButton", {
        Size = UDim2.new(0, 54, 0, 28), Position = UDim2.new(1, -54, 0, 2), BackgroundColor3 = Theme.Elevated,
        BorderSizePixel = 0, Text = "OFF", Font = Theme.FontBold, TextSize = 12, TextColor3 = Theme.TextDim,
        AutoButtonColor = false,
}, moveRow)
corner(UI.MoveToggleBtn, 10); polish(UI.MoveToggleBtn, { noScale = true })

local timingCard = card(SettingsPage, 3, "Timing")
UI.SwingDownBtn, UI.SwingUpBtn, UI.SwingLabel = stepper(timingCard, 1, "Swing Interval: " .. string.format("%.2f", SWING_INTERVAL) .. "s", 0.1, 1.0)
UI.RangeDownBtn, UI.RangeUpBtn, UI.RangeLabel = stepper(timingCard, 2, "Parry Range: " .. tostring(PARRY_RANGE) .. " studs", 5, 100)

local dragCard = card(SettingsPage, 4, "Page Position")
caption(dragCard, 1, "Enable dragging to move the page UI. Disable to lock it.")
local dragRow = new("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = 2 }, dragCard)
new("TextLabel", {
        Size = UDim2.new(1, -60, 1, 0), BackgroundTransparency = 1, Text = "Page Draggable",
        Font = Theme.Font, TextSize = 12, TextColor3 = Theme.TextDim, TextXAlignment = Enum.TextXAlignment.Left,
}, dragRow)
UI.DragToggleBtn = new("TextButton", {
        Size = UDim2.new(0, 54, 0, 28), Position = UDim2.new(1, -54, 0, 2), BackgroundColor3 = Theme.Elevated,
        BorderSizePixel = 0, Text = "OFF", Font = Theme.FontBold, TextSize = 12, TextColor3 = Theme.TextDim,
        AutoButtonColor = false,
}, dragRow)
corner(UI.DragToggleBtn, 10); polish(UI.DragToggleBtn, { noScale = true })
UI.ResetPosBtn = actionButton(dragCard, 3, "Reset Position to Center")

local dangerCard = card(SettingsPage, 5, "Danger Zone", Theme.Danger)
caption(dangerCard, 1, "Stops every feature and completely destroys the UI. This cannot be undone without re-running the script.")
UI.KillScriptBtn = actionButton(dangerCard, 2, "Kill Script", "danger")

-- UI size is visual-only (no automation reads it), so it's safe to wire here
-- at creation time, same convention as the Bow Auto-Equip toggle above.
UISizeDownBtn.MouseButton1Click:Connect(function()
        panelSizePercent = math.max(70, panelSizePercent - 5)
        UISizeLabel.Text = "Panel Size: " .. tostring(panelSizePercent) .. "%"
        panelBaseScale = panelSizePercent / 100
        if ContentPanel.Visible then tw(ContentScale, 0.15, { Scale = panelBaseScale }) end
end)
UISizeUpBtn.MouseButton1Click:Connect(function()
        panelSizePercent = math.min(140, panelSizePercent + 5)
        UISizeLabel.Text = "Panel Size: " .. tostring(panelSizePercent) .. "%"
        panelBaseScale = panelSizePercent / 100
        if ContentPanel.Visible then tw(ContentScale, 0.15, { Scale = panelBaseScale }) end
end)
end

-- ================================================================
-- // NAVIGATION (dock rail + independent floating content panel)
-- ================================================================
local navEntries = {}      -- top-level dock entries, for active-state styling
local currentOpenKey = nil -- key of the leaf whose content is showing, or nil
local autoExpanded = false

local playerEntry = navRow(DockList, Icons.player, "Player", 1, false)
navEntries[#navEntries + 1] = playerEntry

local autoEntry = navRow(DockList, Icons.diamond, "Auto", 2, true)
navEntries[#navEntries + 1] = autoEntry

local AutoChildrenWrap = new("Frame", {
        Name = "AutoChildren", Size = UDim2.new(1, 0, 0, 0), ClipsDescendants = true,
        BackgroundTransparency = 1, LayoutOrder = 3,
}, DockList)
new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, AutoChildrenWrap)
pad(AutoChildrenWrap, 6, 6, 2, 2)

local autoChildDefs = {
        { key = "AutoFarm", label = "Farm" },
        { key = "AutoGold", label = "Gold" },
        { key = "AutoEvent", label = "Event" },
        { key = "AutoRifts", label = "Rifts" },
        { key = "AutoFishing", label = "Fishing" },
}
local autoChildBtns = {}
for i, def in ipairs(autoChildDefs) do
        local b = new("TextButton", {
                Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = Theme.Accent, BackgroundTransparency = 1,
                AutoButtonColor = false, BorderSizePixel = 0, Text = def.label, Font = Theme.FontBold,
                TextSize = 10, TextColor3 = Theme.TextDim, LayoutOrder = i,
        }, AutoChildrenWrap)
        corner(b, 8)
        polish(b, { noScale = true, radius = 8 })
        autoChildBtns[i] = { btn = b, key = def.key, label = def.label }
end
local autoChildRowH, autoChildGap = 28, 3
local autoOpenHeight = (#autoChildDefs * autoChildRowH) + ((#autoChildDefs - 1) * autoChildGap) + 8

local fightEntry = navRow(DockList, Icons.cross, "Fight", 4, false)
navEntries[#navEntries + 1] = fightEntry

local settingsEntry = navRow(DockList, Icons.gear, "Settings", 5, false)
navEntries[#navEntries + 1] = settingsEntry

local function setActiveNav(activeEntry)
        for _, e in ipairs(navEntries) do
                local isActive = (e == activeEntry)
                tw(e.btn, 0.18, { BackgroundTransparency = isActive and 0.88 or 1 })
                tw(e.bar, 0.18, { Size = UDim2.new(0, 3, 0, isActive and 26 or 0) })
                tw(e.lbl, 0.15, { TextColor3 = isActive and Theme.Text or Theme.TextDim })
                for _, p in ipairs(e.iconParts) do
                        tw(p, 0.15, { BackgroundColor3 = isActive and Theme.Accent or Theme.TextDim })
                end
        end
end

local function setActiveChild(activeBtn)
        for _, c in ipairs(autoChildBtns) do
                local isActive = (c.btn == activeBtn)
                tw(c.btn, 0.15, { BackgroundTransparency = isActive and 0.85 or 1, TextColor3 = isActive and Theme.Text or Theme.TextDim })
        end
end

local function setAutoExpanded(open)
        autoExpanded = open
        tw(AutoChildrenWrap, 0.2, { Size = UDim2.new(1, 0, 0, open and autoOpenHeight or 0) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        tw(autoEntry.chevron, 0.2, { Rotation = open and 90 or 0 })
        tw(autoEntry.lbl, 0.15, { TextColor3 = (open or currentOpenKey == "AutoFarm" or currentOpenKey == "AutoGold" or currentOpenKey == "AutoEvent" or currentOpenKey == "AutoRifts" or currentOpenKey == "AutoFishing") and Theme.Text or Theme.TextDim })
end

autoEntry.btn.MouseButton1Click:Connect(function()
        setAutoExpanded(not autoExpanded)
end)

local function closeContentPanel()
        if not currentOpenKey then return end
        currentOpenKey = nil
        tw(ContentPanel, 0.14, { GroupTransparency = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
        tw(ContentScale, 0.14, { Scale = panelBaseScale * 0.94 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
        task.delay(0.14, function()
                if not currentOpenKey then
                        ContentPanel.Visible = false
                        PanelShadow.Visible = false
                end
        end)
end

local function openLeaf(key, label, crumb)
        if not Pages[key] then return end
        local wasVisible = ContentPanel.Visible
        currentOpenKey = key
        PanelBreadcrumb.Text = crumb or label
        for name, frame in pairs(Pages) do
                frame.Visible = (name == key)
        end
        if wasVisible then return end -- already open elsewhere: just swapped content, no re-pop
        ContentPanel.Visible = true
        PanelShadow.Visible = true
        tw(ContentPanel, 0.22, { GroupTransparency = 0 }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        tw(ContentScale, 0.22, { Scale = panelBaseScale }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

-- key/label/crumb identify the page; activateFn sets which dock element(s)
-- light up; onOpen runs any one-off side effect (e.g. refreshing a list).
local function toggleLeaf(key, label, crumb, activateFn, onOpen)
        if currentOpenKey == key and ContentPanel.Visible then
                closeContentPanel()
                setActiveNav(nil)
                setActiveChild(nil)
                return
        end
        setActiveNav(nil)
        setActiveChild(nil)
        if activateFn then activateFn() end
        openLeaf(key, label, crumb)
        if onOpen then pcall(onOpen) end
end

playerEntry.btn.MouseButton1Click:Connect(function()
        toggleLeaf("Player", "Player", "Player", function() setActiveNav(playerEntry) end)
end)

fightEntry.btn.MouseButton1Click:Connect(function()
        toggleLeaf("Fight", "Fight", "Fight", function() setActiveNav(fightEntry) end)
end)

settingsEntry.btn.MouseButton1Click:Connect(function()
        toggleLeaf("Settings", "Settings", "Settings", function() setActiveNav(settingsEntry) end)
end)

for _, c in ipairs(autoChildBtns) do
        c.btn.MouseButton1Click:Connect(function()
                toggleLeaf(c.key, c.label, "Auto  ›  " .. c.label,
                        function()
                                setActiveNav(autoEntry)
                                setActiveChild(c.btn)
                        end,
                        function()
                                if c.key == "AutoFarm" then
                                        pcall(function() if refreshOreList then refreshOreList() end end)
                                        pcall(function() if refreshMobList then refreshMobList(true) end end)
                                end
                        end
                )
        end)
end

PanelCloseBtn.MouseButton1Click:Connect(function()
        closeContentPanel()
        setActiveNav(nil)
        setActiveChild(nil)
end)

-- ================================================================
-- // DRAGGING (single shared listener — no per-frame connection leaks)
-- ================================================================
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

local function makeDraggable(dragHandle, targetFrame)
        local d = { dragging = false, dragStart = nil, startPos = nil, dragInput = nil, targetFrame = targetFrame }
        table.insert(_dragTargets, d)
        dragHandle.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
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
                if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                        d.dragInput = input
                end
        end)
end

makeDraggable(DockGrip, Dock)
makeDraggable(PanelTitleBar, ContentPanel)

-- ================================================================
-- // OPEN / CLOSE (dock show/hide FAB — the panel toggles per-tab instead)
-- ================================================================
local ToggleButton = new("TextButton", {
        Name = "ToggleButton", Size = UDim2.new(0, 52, 0, 52),
        Position = UDim2.new(1, -68, 0, 24), BackgroundColor3 = Theme.Base,
        AutoButtonColor = false, BorderSizePixel = 0, Text = "", ZIndex = 100,
}, ScreenGui)
corner(ToggleButton, 26)
local toggleStroke = stroke(ToggleButton, Theme.Accent, 1.5, 0.5)
lifeGradient(toggleStroke, 5)
new("UIAspectRatioConstraint", { AspectRatio = 1 }, ToggleButton)
local toggleIconHolder = new("Frame", {
        Size = UDim2.new(0, 20, 0, 20), Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1,
}, ToggleButton)
Icons.menu(toggleIconHolder, 20, Theme.Accent)
polish(ToggleButton)

local dockOpen = false

local function setDockOpen(open)
        dockOpen = open
        if open then
                Dock.Visible = true
                DockShadow.Visible = true
                tw(Dock, 0.24, { GroupTransparency = 0 }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
                tw(DockScale, 0.24, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        else
                closeContentPanel()
                setActiveNav(nil)
                setActiveChild(nil)
                tw(Dock, 0.16, { GroupTransparency = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
                tw(DockScale, 0.16, { Scale = 0.92 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
                task.delay(0.16, function()
                        if not dockOpen then
                                Dock.Visible = false
                                DockShadow.Visible = false
                        end
                end)
        end
end

ToggleButton.MouseButton1Click:Connect(function()
        setDockOpen(not dockOpen)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == Enum.KeyCode.M then
                setDockOpen(not dockOpen)
        end
end)

print("[Pilgrammed] Aurora UI ready!")

-- Initial state: only the dock appears. No content page opens until tapped.
setDockOpen(true)

print("[Pilgrammed] UI elements created!")
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
                if not State.mineAutoEquip then return end
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
                if tool and tool:IsA("Tool") and (tool:FindFirstChild("Slash") or tool:FindFirstChild("Shoot")) then
                        return tool
                end
        end
        if backpack then
                local tool = backpack:FindFirstChild(name)
                if tool and tool:IsA("Tool") and (tool:FindFirstChild("Slash") or tool:FindFirstChild("Shoot")) then
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

        -- Find and equip weapon (only if auto-equip is ON)
        if State.mobAutoEquip then
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

        -- Equip weapon (by typed name, or fallback to any weapon) — only if auto-equip is ON
        if State.campAutoEquip then
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
        y = math.min(50, y)
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
        BELOW_DISTANCE = math.min(50, BELOW_DISTANCE + 1)
        ABOVE_DISTANCE = math.min(50, ABOVE_DISTANCE + 1)
        BelowAboveDistLabel.Text = "Below/Above dist: " .. tostring(BELOW_DISTANCE) .. " studs"
end)

-- Behind/Front distance adjuster
BehindDistDownBtn.MouseButton1Click:Connect(function()
        BEHIND_DISTANCE = math.max(1, BEHIND_DISTANCE - 1)
        BehindDistLabel.Text = "Behind/Front dist: " .. tostring(BEHIND_DISTANCE) .. " studs"
end)

BehindDistUpBtn.MouseButton1Click:Connect(function()
        BEHIND_DISTANCE = math.min(50, BEHIND_DISTANCE + 1)
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
        if not State.bowAutoEquip then return nil end -- toggle off: require manual equip/hold
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
        local bowName = UI.BowNameBox.Text
        if not bowName or bowName == "" then
                if UI.BowStatus then
                        UI.BowStatus.Text = "Type a bow name first!"
                        UI.BowStatus.TextColor3 = Color3.fromRGB(255, 120, 120)
                end
                return
        end
        State.bowName = bowName
        State.autoBow = true
        UI.AutoBowBtn.Text = "[ ]  Stop Auto Bow"
        UI.AutoBowBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 80)

        if UI.BowStatus then
                UI.BowStatus.Text = "Auto Bow ON - aiming at selected mobs..."
                UI.BowStatus.TextColor3 = Color3.fromRGB(100, 220, 255)
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
                                                        if UI.BowStatus then
                                                                UI.BowStatus.Text = "Shooting " .. targetMob.Name .. "..."
                                                                UI.BowStatus.TextColor3 = Color3.fromRGB(100, 220, 130)
                                                        end
                                                else
                                                        if UI.BowStatus then
                                                                UI.BowStatus.Text = "Bow '" .. State.bowName .. "' not equipped/found"
                                                                UI.BowStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
                                                        end
                                                end
                                        end
                                else
                                        if UI.BowStatus then
                                                UI.BowStatus.Text = "No selected mobs in range..."
                                                UI.BowStatus.TextColor3 = Color3.fromRGB(200, 200, 130)
                                        end
                                end
                        end
                        task.wait(0.05)  -- short sleep between checks (rate-throttled above)
                end
        end)
end

local function stopAutoBow()
        State.autoBow = false
        UI.AutoBowBtn.Text = ">  Start Auto Bow"
        UI.AutoBowBtn.BackgroundColor3 = Color3.fromRGB(80, 100, 160)
        if UI.BowStatus then
                UI.BowStatus.Text = "Stopped"
                UI.BowStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
        end
        print("[AutoBow] Stopped")
end

UI.AutoBowBtn.MouseButton1Click:Connect(function()
        if State.autoBow then
                stopAutoBow()
        else
                startAutoBow()
        end
end)

UI.BowRateDownBtn.MouseButton1Click:Connect(function()
        State.bowShootRate = math.max(0.05, State.bowShootRate - 0.05)
        UI.BowRateLabel.Text = "Bow Shoot Rate: " .. string.format("%.2f", State.bowShootRate) .. "s"
end)

UI.BowRateUpBtn.MouseButton1Click:Connect(function()
        State.bowShootRate = math.min(2.0, State.bowShootRate + 0.05)
        UI.BowRateLabel.Text = "Bow Shoot Rate: " .. string.format("%.2f", State.bowShootRate) .. "s"
end)

-- ================================================================
-- // KILL SCRIPT — stops everything and destroys UI
-- ================================================================

local function killScript()
        print("[Pilgrammed] Kill script activated - shutting down everything")

        -- Stop all features (wrapped in pcall in case state is mid-transition)
        pcall(function()
                if State.autoFarming then stopAutoFarm() end
                if State.autoMobFarming then stopAutoMobFarm() end
                if State.autoChickenFarm then stopChickenFarm() end
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
                if State.chickenThread then
                        State.autoChickenFarm = false
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

UI.KillScriptBtn.MouseButton1Click:Connect(function()
        killScript()
end)

-- MOVE TOGGLE SETTING
UI.MoveToggleBtn.MouseButton1Click:Connect(function()
        State.toggleSquareMoveable = not State.toggleSquareMoveable
        if State.toggleSquareMoveable then
                UI.MoveToggleBtn.Text = "ON"
                UI.MoveToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
                UI.MoveToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        else
                UI.MoveToggleBtn.Text = "OFF"
                UI.MoveToggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
                UI.MoveToggleBtn.TextColor3 = Color3.fromRGB(180, 180, 200)
        end
end)

-- SWING INTERVAL
UI.SwingDownBtn.MouseButton1Click:Connect(function()
        SWING_INTERVAL = math.max(0.1, SWING_INTERVAL - 0.05)
        UI.SwingLabel.Text = "Swing Interval: " .. string.format("%.2f", SWING_INTERVAL) .. "s"
end)

UI.SwingUpBtn.MouseButton1Click:Connect(function()
        SWING_INTERVAL = math.min(1.0, SWING_INTERVAL + 0.05)
        UI.SwingLabel.Text = "Swing Interval: " .. string.format("%.2f", SWING_INTERVAL) .. "s"
end)

-- PARRY RANGE
UI.RangeDownBtn.MouseButton1Click:Connect(function()
        PARRY_RANGE = math.max(5, PARRY_RANGE - 5)
        UI.RangeLabel.Text = "Parry Range: " .. tostring(PARRY_RANGE) .. " studs"
end)

UI.RangeUpBtn.MouseButton1Click:Connect(function()
        PARRY_RANGE = math.min(100, PARRY_RANGE + 5)
        UI.RangeLabel.Text = "Parry Range: " .. tostring(PARRY_RANGE) .. " studs"
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
        UI.CronoKeyBtn.Text = "[ ]  Stop Crono Key Collect"
        UI.CronoKeyBtn.BackgroundColor3 = Color3.fromRGB(120, 40, 40)

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
                                if UI.CronoKeyStatus then
                                        UI.CronoKeyStatus.Text = "No Level folders found in workspace"
                                        UI.CronoKeyStatus.TextColor3 = Color3.fromRGB(255, 120, 120)
                                end
                                task.wait(2)
                                -- Still continue to try Exit
                        end

                        -- Phase 1: TP to each level's Firewall (fast — just TP and tiny wait)
                        for _, level in ipairs(levels) do
                                if not State.autoCronoKey then break end
                                local firewall = level:FindFirstChild("Firewall")
                                if firewall then
                                        if UI.CronoKeyStatus then
                                                UI.CronoKeyStatus.Text = "TP to " .. level.Name .. ".Firewall..."
                                                UI.CronoKeyStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
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
                                                        if UI.CronoKeyStatus then
                                                                UI.CronoKeyStatus.Text = "Collect " .. level.Name .. " key " .. tostring(i) .. "/" .. tostring(#keys)
                                                                UI.CronoKeyStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
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
                                        if UI.CronoKeyStatus then
                                                UI.CronoKeyStatus.Text = "TP to " .. foundLevelName .. ".Exit - Done!"
                                                UI.CronoKeyStatus.TextColor3 = Color3.fromRGB(100, 255, 150)
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
                                                        if UI.CronoKeyStatus then
                                                                UI.CronoKeyStatus.Text = "TP to Level19.Exit - Done!"
                                                                UI.CronoKeyStatus.TextColor3 = Color3.fromRGB(100, 255, 150)
                                                        end
                                                        print("[CronoKey] TP to Level19.Exit (" .. exitObj.ClassName .. ")")
                                                        tpToPart(exitObj)
                                                        print("[CronoKey] Complete! TP'd to Level19.Exit")
                                                else
                                                        if UI.CronoKeyStatus then
                                                                UI.CronoKeyStatus.Text = "Level19 has no Exit child"
                                                                UI.CronoKeyStatus.TextColor3 = Color3.fromRGB(255, 120, 120)
                                                        end
                                                        print("[CronoKey] Level19 has no Exit child")
                                                end
                                        else
                                                if UI.CronoKeyStatus then
                                                        UI.CronoKeyStatus.Text = "No Exit found in any Level folder"
                                                        UI.CronoKeyStatus.TextColor3 = Color3.fromRGB(255, 120, 120)
                                                end
                                                print("[CronoKey] No Exit found in any Level folder (Level1-Level25)")
                                        end
                                end
                        end

                        -- Done — stop
                        State.autoCronoKey = false
                        UI.CronoKeyBtn.Text = "Auto Crono's Crazy Challenge Key Collect"
                        UI.CronoKeyBtn.BackgroundColor3 = Color3.fromRGB(180, 100, 40)
                        if UI.CronoKeyStatus then
                                if UI.CronoKeyStatus.Text:find("Done") then
                                        UI.CronoKeyStatus.Text = "Complete! Stopped."
                                else
                                        UI.CronoKeyStatus.Text = "Stopped"
                                        UI.CronoKeyStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
                                end
                        end
                        break
                end
        end)
end

local function stopCronoKeyCollect()
        State.autoCronoKey = false
        UI.CronoKeyBtn.Text = "Auto Crono's Crazy Challenge Key Collect"
        UI.CronoKeyBtn.BackgroundColor3 = Color3.fromRGB(180, 100, 40)
        if UI.CronoKeyStatus then
                UI.CronoKeyStatus.Text = "Stopped"
                UI.CronoKeyStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
        end
end

UI.CronoKeyBtn.MouseButton1Click:Connect(function()
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
        UI.DeleteBtn.Text = "[ ]  Stop Auto-Delete"
        UI.DeleteBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 60)

        if UI.DeleteStatus then
                UI.DeleteStatus.Text = "Auto-delete ON - scanning all levels..."
                UI.DeleteStatus.TextColor3 = Color3.fromRGB(100, 220, 130)
        end
        print("[AutoDelete] Started - scanning all Level1-Level25 for Drones/Killbricks/ThiefOrb/SniperOrb")

        -- Immediate scan on start
        local deleted, found = scanAndDeleteAllLevels()
        if UI.DeleteStatus then
                if deleted > 0 then
                        UI.DeleteStatus.Text = "Deleted " .. tostring(deleted) .. " target(s) on start"
                        UI.DeleteStatus.TextColor3 = Color3.fromRGB(100, 220, 130)
                else
                        UI.DeleteStatus.Text = "No targets found yet - will keep scanning..."
                        UI.DeleteStatus.TextColor3 = Color3.fromRGB(200, 200, 130)
                end
        end

        -- Polling loop: scan every 1 second (as user requested)
        State.deleteThread = task.spawn(function()
                while State.autoDeleteEnemies do
                        local n, found = scanAndDeleteAllLevels()
                        if n > 0 and UI.DeleteStatus then
                                UI.DeleteStatus.Text = "Deleted " .. tostring(n) .. " target(s) (loop)"
                                UI.DeleteStatus.TextColor3 = Color3.fromRGB(100, 220, 130)
                        elseif UI.DeleteStatus and UI.DeleteStatus.Text:find("loop") then
                                -- Reset to "watching" if we previously deleted but now found nothing
                                UI.DeleteStatus.Text = "Watching... (no new targets)"
                                UI.DeleteStatus.TextColor3 = Color3.fromRGB(200, 200, 130)
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
        UI.DeleteBtn.Text = "Delete All enemy/Kill brick in Crono's Crazy Challenge"
        UI.DeleteBtn.BackgroundColor3 = Color3.fromRGB(120, 40, 40)
        if UI.DeleteStatus then
                UI.DeleteStatus.Text = "Stopped"
                UI.DeleteStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
        end
        print("[AutoDelete] Stopped")
end

UI.DeleteBtn.MouseButton1Click:Connect(function()
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
                if AutoFarmPage and AutoFarmPage.Visible then
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
                if AutoFarmPage and AutoFarmPage.Visible then
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
        State.fishRodName = UI.RodNameBox.Text or "Rod Of Kings"
        FishDiscoveryBtn.Text = "Discovery Mode: ON (logging...)"
        FishDiscoveryBtn.BackgroundColor3 = Color3.fromRGB(180, 140, 40)

        fishState = "idle"
        if UI.FishStatus then
                UI.FishStatus.Text = "DISCOVERY ON - Cast your rod and wait for bite!"
                UI.FishStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
        end
        print("[FishDiscovery] === STARTED ===")
        print("[FishDiscovery] Rod name: " .. State.fishRodName)
        print("[FishDiscovery] Cast your rod NOW. Watch for CAST and BITE events.")

        setupFishDetection(
                function(signalType, obj)  -- onBite
                        print("[FishDiscovery] *** BITE! ***")
                        if UI.FishStatus then
                                UI.FishStatus.Text = "BITE detected! Click to reel in!"
                                UI.FishStatus.TextColor3 = Color3.fromRGB(100, 255, 150)
                        end
                end,
                function(eventStr)  -- onEvent
                        print("[FishDiscovery] EVENT: " .. eventStr)
                        if UI.FishStatus then
                                UI.FishStatus.Text = eventStr:sub(1, 60)
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
        if UI.FishStatus then
                UI.FishStatus.Text = "Discovery stopped."
                UI.FishStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
        end
        print("[FishDiscovery] === STOPPED ===")
end

-- // AUTO FISHING (timer-based, fully automatic)
-- Flow: cast -> wait N sec -> try to catch for 1 sec (stop early if Loot fires) -> if no fish, recast -> repeat

-- Wait time button handlers
UI.FishWaitDownBtn.MouseButton1Click:Connect(function()
        State.fishWaitSeconds = math.max(0.1, State.fishWaitSeconds - 0.1)
        UI.FishWaitLabel.Text = "Wait before reel: " .. string.format("%.2f", State.fishWaitSeconds) .. " sec"
end)
UI.FishWaitUpBtn.MouseButton1Click:Connect(function()
        State.fishWaitSeconds = math.min(15, State.fishWaitSeconds + 0.1)
        UI.FishWaitLabel.Text = "Wait before reel: " .. string.format("%.2f", State.fishWaitSeconds) .. " sec"
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
        State.fishRodName = UI.RodNameBox.Text or "Rod of Kings"
        UI.AutoFishBtn.Text = "[ ]  Stop Auto Fish"
        UI.AutoFishBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
        UI.FishStatus.Text = "Waiting for you to cast..."
        UI.FishStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
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
                                UI.FishStatus.Text = "Caught #" .. catchCount .. ": " .. name
                                UI.FishStatus.TextColor3 = Color3.fromRGB(100, 255, 150)
                        end)
                        table.insert(State.fishConns, lootConn)
                end
        end

        -- Also detect catches via workspace.Chests.Fishing (fish sometimes drops as a chest, not Loot event)
        local chestsFishing = workspace:FindFirstChild("Chests") and workspace.Chests:FindFirstChild("Fishing")
        if chestsFishing then
                local chestConn = chestsFishing.ChildAdded:Connect(function(child)
                        catchCount = catchCount + 1
                        fishCaught = true
                        print("[AutoFish] CAUGHT #" .. catchCount .. " (chest): " .. child.Name)
                        UI.FishStatus.Text = "Caught #" .. catchCount .. " (chest)"
                        UI.FishStatus.TextColor3 = Color3.fromRGB(100, 255, 150)
                end)
                table.insert(State.fishConns, chestConn)
        end

        -- Bait/bobber detector: name-pattern + 15 stud range, event-cached (not polled) since
        -- cast/catch fire the SAME remote — physical presence is the only reliable "in/out" signal
        local BAIT_RANGE = 15
        local BAIT_PATTERNS = {"bobber", "bait", "float", "cork", "hook", "lure", "line"}
        local cachedBait = nil

        local function baitPos(inst)
                if inst:IsA("BasePart") then return inst.Position end
                if inst.PrimaryPart then return inst.PrimaryPart.Position end
                local p = inst:FindFirstChildWhichIsA("BasePart", true)
                return p and p.Position
        end

        local function nearPlayer(pos)
                local char = LocalPlayer.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                return hrp and pos and (pos - hrp.Position).Magnitude <= BAIT_RANGE
        end

        local function matchesBaitName(n)
                n = n:lower()
                for _, pat in ipairs(BAIT_PATTERNS) do
                        if n:find(pat, 1, true) then return true end
                end
                return false
        end

        local function tryCacheBait(inst)
                if not cachedBait and matchesBaitName(inst.Name) then
                        local pos = baitPos(inst)
                        if pos and nearPlayer(pos) then cachedBait = inst end
                end
        end
        -- scan what's already there, then track live add/remove
        for _, d in ipairs(workspace:GetDescendants()) do tryCacheBait(d) end
        table.insert(State.fishConns, workspace.DescendantAdded:Connect(tryCacheBait))
        table.insert(State.fishConns, workspace.DescendantRemoving:Connect(function(inst)
                if inst == cachedBait then cachedBait = nil end
        end))

        local function isPlayerFishing()
                return cachedBait ~= nil and cachedBait.Parent ~= nil
        end

        -- Helper: wait for player to cast (Bobber appears)
        local function waitForPlayerCast()
                UI.FishStatus.Text = "Waiting for you to cast..."
                UI.FishStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
                print("[AutoFish] Waiting for player to cast line...")
                while State.autoFish and not isPlayerFishing() do
                        task.wait(0.1)
                end
                if not State.autoFish then return false end
                -- Save the cast position from the detected bait model
                if cachedBait then
                        savedCastPos = baitPos(cachedBait)
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
                        UI.FishStatus.Text = "Fishing... waiting " .. string.format("%.2f", State.fishWaitSeconds) .. "s for bite"
                        UI.FishStatus.TextColor3 = Color3.fromRGB(100, 220, 255)
                        local waitStart = tick()
                        while State.autoFish and (tick() - waitStart) < State.fishWaitSeconds do
                                task.wait(0.1)
                        end
                        if not State.autoFish then break end

                        -- STEP 3: Spam fishing (catching) max 5x @ 0.15s cooldown, stop early if caught (Loot or chest)
                        UI.FishStatus.Text = "Catching..."
                        UI.FishStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
                        fishCaught = false
                        local reelCount = 0
                        while State.autoFish and not fishCaught and reelCount < 5 and isPlayerFishing() do
                                local rod = findRodTool(State.fishRodName)
                                if rod then
                                        fireFishingEvent(rod, savedCastPos or getCastPosition())
                                        reelCount = reelCount + 1
                                end
                                if fishCaught then break end
                                task.wait(0.15)
                        end
                        print("[AutoFish] Catch done: fired " .. reelCount .. "x | caught=" .. tostring(fishCaught))

                        -- STEP 4: Cooldown 0.25 seconds
                        if State.autoFish then
                                UI.FishStatus.Text = "Cooldown 0.25s..."
                                UI.FishStatus.TextColor3 = Color3.fromRGB(200, 200, 130)
                                task.wait(0.25)
                        end

                        -- STEP 5: Auto-cast — ONLY if bait isn't already in water (same remote as catch, so
                        -- physical check prevents firing "cast" while actually still mid-catch = infinite stall)
                        if State.autoFish and not isPlayerFishing() then
                                fishCaught = false
                                local rod = findRodTool(State.fishRodName)
                                if rod then
                                        fireFishingEvent(rod, savedCastPos or getCastPosition())
                                        print("[AutoFish] Auto-cast at " .. tostring(savedCastPos))
                                        UI.FishStatus.Text = "Cast! Waiting " .. string.format("%.2f", State.fishWaitSeconds) .. "s..."
                                        UI.FishStatus.TextColor3 = Color3.fromRGB(100, 220, 255)
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
        UI.AutoFishBtn.Text = ">  Start Auto Fish"
        UI.AutoFishBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 100)
        if UI.FishStatus then
                UI.FishStatus.Text = "Auto Fish stopped"
                UI.FishStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
        end
        print("[AutoFish] Stopped")
end

UI.AutoFishBtn.MouseButton1Click:Connect(function()
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
        UI.AutoRiftsBtn.Text = "[ ]  Stop Auto Rifts"
        UI.AutoRiftsBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 80)

        if UI.RiftsStatus then
                UI.RiftsStatus.Text = "Auto Rifts ON - starting from RiftSpawn1..."
                UI.RiftsStatus.TextColor3 = Color3.fromRGB(200, 150, 255)
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
                        if UI.RiftsStatus then
                                UI.RiftsStatus.Text = "TP to RiftSpawn" .. tostring(idx) .. "..."
                                UI.RiftsStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
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
                                        if UI.RiftsStatus then
                                                UI.RiftsStatus.Text = "Tapping screen 2x (mobile)..."
                                                UI.RiftsStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
                                        end
                                        tapScreenForRift(riftPos)
                                else
                                        if UI.RiftsStatus then
                                                UI.RiftsStatus.Text = "Holding G for 2.5s (desktop)..."
                                                UI.RiftsStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
                                        end
                                        holdGKey(2.5)
                                end
                                task.wait(0.5)

                                -- Step 2b: Check if dungeon loaded (workspace.DungeonRing.Outer exists)
                                if UI.RiftsStatus then
                                        UI.RiftsStatus.Text = "Checking for DungeonRing.Outer..."
                                        UI.RiftsStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
                                end
                                print("[AutoRifts] Checking workspace.DungeonRing.Outer...")
                                local dungeonRing = workspace:FindFirstChild("DungeonRing")
                                local dungeonOuter = dungeonRing and dungeonRing:FindFirstChild("Outer")
                                if not dungeonOuter then
                                        print("[AutoRifts] DungeonRing.Outer gone - waiting 2s before camp/kill")
                                        if UI.RiftsStatus then
                                                UI.RiftsStatus.Text = "Ring gone! Waiting 2s..."
                                                UI.RiftsStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
                                        end
                                        task.wait(2)
                                        if UI.RiftsStatus then
                                                UI.RiftsStatus.Text = "Rift active - starting camp/kill"
                                                UI.RiftsStatus.TextColor3 = Color3.fromRGB(100, 255, 150)
                                        end
                                else
                                        print("[AutoRifts] DungeonRing.Outer still exists - rift not activated, retrying")
                                        if UI.RiftsStatus then
                                                UI.RiftsStatus.Text = "DungeonRing.Outer found - rift not active"
                                                UI.RiftsStatus.TextColor3 = Color3.fromRGB(255, 150, 150)
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
                                                if UI.RiftsStatus then
                                                        UI.RiftsStatus.Text = "Fighting " .. mobName .. " (RiftSpawn" .. tostring(idx) .. ")"
                                                        UI.RiftsStatus.TextColor3 = Color3.fromRGB(255, 120, 120)
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
                                                        if UI.RiftsStatus then
                                                                UI.RiftsStatus.Text = "No mobs found - waiting for 'Rift cleared' message..."
                                                                UI.RiftsStatus.TextColor3 = Color3.fromRGB(200, 200, 130)
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
                                        if UI.RiftsStatus then
                                                UI.RiftsStatus.Text = "Rift cleared! Cooldown 5s..."
                                                UI.RiftsStatus.TextColor3 = Color3.fromRGB(100, 255, 150)
                                        end
                                        task.wait(5)
                                        print("[AutoRifts] Cooldown done - moving to next rift")
                                        if UI.RiftsStatus then
                                                UI.RiftsStatus.Text = "Moving to next rift..."
                                                UI.RiftsStatus.TextColor3 = Color3.fromRGB(200, 150, 255)
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
        UI.AutoRiftsBtn.Text = ">  Start Auto Rifts"
        UI.AutoRiftsBtn.BackgroundColor3 = Color3.fromRGB(100, 60, 160)
        if UI.RiftsStatus then
                UI.RiftsStatus.Text = "Stopped"
                UI.RiftsStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
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
        UI.AutoRiftsBtn.MouseButton1Click:Connect(function()
                if State.autoRifts then
                        stopAutoRifts()
                else
                        startAutoRifts()
                end
        end)

        UI.RiftsRadiusDownBtn.MouseButton1Click:Connect(function()
                State.riftsRadius = math.max(50, State.riftsRadius - 50)
                UI.RiftsRadiusLabel.Text = "Mob detect radius: " .. tostring(State.riftsRadius) .. " studs"
        end)

        UI.RiftsRadiusUpBtn.MouseButton1Click:Connect(function()
                State.riftsRadius = math.min(5000, State.riftsRadius + 50)
                UI.RiftsRadiusLabel.Text = "Mob detect radius: " .. tostring(State.riftsRadius) .. " studs"
        end)

        -- Activation mode handlers
        local function setRiftsActivationMode(mode)
                State.riftsActivationMode = mode
                UI.RiftsMobileBtn.BackgroundColor3 = (mode == "mobile") and Color3.fromRGB(40, 160, 80) or Color3.fromRGB(60, 60, 80)
                UI.RiftsMobileBtn.TextColor3 = (mode == "mobile") and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(220, 220, 240)
                UI.RiftsDesktopBtn.BackgroundColor3 = (mode == "desktop") and Color3.fromRGB(40, 160, 80) or Color3.fromRGB(60, 60, 80)
                UI.RiftsDesktopBtn.TextColor3 = (mode == "desktop") and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(220, 220, 240)
                print("[AutoRifts] Activation mode: " .. mode)
        end

        UI.RiftsMobileBtn.MouseButton1Click:Connect(function() setRiftsActivationMode("mobile") end)
        UI.RiftsDesktopBtn.MouseButton1Click:Connect(function() setRiftsActivationMode("desktop") end)
end)
if not riftsWireOk then
        warn("[Pilgrammed] Rifts button wiring failed: " .. tostring(riftsWireErr))
end

end) -- end pcall

-- ================================================================
-- // GOLD FARM CHICKEN METHOD
-- ================================================================

local function findKillerChicken(maxDist)
        local char = LocalPlayer.Character
        if not char then return nil end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return nil end
        local myPos = hrp.Position
        local nearest = nil
        local nearestDist = maxDist or 30
        local mobsFolder = workspace:FindFirstChild("Mobs")
        if not mobsFolder then return nil end
        forEachMob(mobsFolder, function(mob, hum)
                if hum.Health > 0 and mob.Name == "Killer Chicken" then
                        local mobHrp = mob:FindFirstChild("HumanoidRootPart")
                        if mobHrp then
                                local d = (mobHrp.Position - myPos).Magnitude
                                if d <= nearestDist then
                                        nearestDist = d
                                        nearest = mob
                                end
                        end
                end
        end)
        return nearest
end

local function drinkMagmaticSlime()
        local char = LocalPlayer.Character
        if not char then return false end
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        local slime = char:FindFirstChild("Gold Magmatic Slime")
        if not slime and backpack then
                slime = backpack:FindFirstChild("Gold Magmatic Slime")
                if slime then
                        local hum = char:FindFirstChildOfClass("Humanoid")
                        if hum then
                                hum:EquipTool(slime)
                                task.wait(0.3)
                                slime = char:FindFirstChild("Gold Magmatic Slime")
                        end
                end
        end
        if not slime then return false end
        local remote = slime:FindFirstChild("RemoteEvent")
        if not remote then return false end
        pcall(function() remote:FireServer() end)
        return true
end

local function startChickenFarm()
        if State.autoChickenFarm then return end
        State.autoChickenFarm = true
        ChickenFarmBtn.Text = "[ ]  Stop Chicken Farm"
        ChickenFarmBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 80)
        ChickenStatus.Text = "Starting..."
        ChickenStatus.TextColor3 = Color3.fromRGB(100, 220, 255)
        print("[ChickenFarm] === STARTED ===")

        State.chickenThread = task.spawn(function()
                local lastAttack = 0
                while State.autoChickenFarm do
                        local nest = workspace:FindFirstChild("Map")
                        if nest then nest = nest:FindFirstChild("Landfill") end
                        if nest then nest = nest:FindFirstChild("Nest") end
                        if not nest then
                                ChickenStatus.Text = "Nest not found! Waiting..."
                                task.wait(2)
                        else
                                local nestPos = nil
                                if nest:IsA("BasePart") then nestPos = nest.Position
                                elseif nest:IsA("Model") then
                                        nestPos = (nest.PrimaryPart or nest:FindFirstChildWhichIsA("BasePart"))
                                        nestPos = nestPos and nestPos.Position
                                elseif nest:IsA("Folder") then
                                        for _, d in ipairs(nest:GetDescendants()) do
                                                if d:IsA("BasePart") then nestPos = d.Position break end
                                        end
                                end
                                if nestPos then
                                        local char = LocalPlayer.Character
                                        local hrp = char and char:FindFirstChild("HumanoidRootPart")
                                        if hrp then hrp.CFrame = CFrame.new(nestPos + Vector3.new(0, 5, 0)) end
                                end

                                ChickenStatus.Text = "Toggling Egg of Pain... Waiting for Killer Chicken..."
                                ChickenStatus.TextColor3 = Color3.fromRGB(255, 200, 80)

                                local chicken = nil
                                while State.autoChickenFarm and not chicken do
                                        chicken = findKillerChicken(State.chickenRange)
                                        if not chicken then
                                                local char = LocalPlayer.Character
                                                local backpack = LocalPlayer:FindFirstChild("Backpack")
                                                if char then
                                                        local hum = char:FindFirstChildOfClass("Humanoid")
                                                        local eggInChar = char:FindFirstChild("Egg of Pain")
                                                        local eggInBackpack = backpack and backpack:FindFirstChild("Egg of Pain")
                                                        if hum then
                                                                if eggInChar then
                                                                        pcall(function() hum:UnequipTools() end)
                                                                elseif eggInBackpack then
                                                                        pcall(function() hum:EquipTool(eggInBackpack) end)
                                                                end
                                                        end
                                                end
                                                task.wait(1)
                                        end
                                end
                                if not State.autoChickenFarm then break end

                                ChickenStatus.Text = "Killer Chicken found! Killing..."
                                ChickenStatus.TextColor3 = Color3.fromRGB(255, 120, 120)

                                local weaponName = ChickenWeaponBox and ChickenWeaponBox.Text or ""
                                local hasDrunkThisChicken = false

                                if weaponName and weaponName ~= "" then
                                        local w = findWeaponByName(weaponName)
                                        if w then
                                                local char = LocalPlayer.Character
                                                local h = char and char:FindFirstChildOfClass("Humanoid")
                                                if h then pcall(function() h:EquipTool(w) end) end
                                                task.wait(0.3)
                                        end
                                end

                                while State.autoChickenFarm and chicken and chicken.Parent do
                                        local hum = chicken:FindFirstChildOfClass("Humanoid")
                                        if not hum or hum.Health <= 0 then break end

                                        if State.chickenDrinkMagmatic and hum.Health < 500 and not hasDrunkThisChicken then
                                                hasDrunkThisChicken = true
                                                ChickenStatus.Text = "Chicken HP < 500! Drinking potion..."
                                                ChickenStatus.TextColor3 = Color3.fromRGB(255, 200, 80)
                                                local char = LocalPlayer.Character
                                                local h = char and char:FindFirstChildOfClass("Humanoid")
                                                if h then pcall(function() h:UnequipTools() end) end
                                                task.wait(0.2)
                                                drinkMagmaticSlime()
                                                local drinkStart = tick()
                                                while State.autoChickenFarm and (tick() - drinkStart) < 1.5 do
                                                        task.wait(0.1)
                                                end
                                                char = LocalPlayer.Character
                                                h = char and char:FindFirstChildOfClass("Humanoid")
                                                if h then pcall(function() h:UnequipTools() end) end
                                                task.wait(0.2)
                                                ChickenStatus.Text = "Re-equipping weapon..."
                                                ChickenStatus.TextColor3 = Color3.fromRGB(255, 120, 120)
                                                if weaponName and weaponName ~= "" then
                                                        local w = findWeaponByName(weaponName)
                                                        if w then
                                                                h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                                                                if h then pcall(function() h:EquipTool(w) end) end
                                                                task.wait(0.3)
                                                        end
                                                end
                                        else
                                                if weaponName and weaponName ~= "" then
                                                        local char = LocalPlayer.Character
                                                        local weapon = char and char:FindFirstChild(weaponName)
                                                        if not weapon then
                                                                local w = findWeaponByName(weaponName)
                                                                if w then
                                                                        local h = char and char:FindFirstChildOfClass("Humanoid")
                                                                        if h then pcall(function() h:EquipTool(w) end) end
                                                                        task.wait(0.1)
                                                                        weapon = char and char:FindFirstChild(weaponName)
                                                                end
                                                        end
                                                        if weapon then
                                                                tpToMob(chicken)
                                                                local mobHrp = chicken:FindFirstChild("HumanoidRootPart")
                                                                local now = tick()
                                                                if weapon:FindFirstChild("Shoot") and mobHrp then
                                                                        if now - lastAttack >= 0.1 then
                                                                                lastAttack = now
                                                                                pcall(function() weapon.Shoot:InvokeServer(mobHrp.Position, "Arrow", true, 1) end)
                                                                        end
                                                                elseif weapon:FindFirstChild("Slash") then
                                                                        if now - lastAttack >= MOB_ATTACK_INTERVAL then
                                                                                lastAttack = now
                                                                                local atkType = getNextAttackType() or 1
                                                                                pcall(function() weapon.Slash:FireServer(atkType) end)
                                                                        end
                                                                end
                                                                task.wait(0.05)
                                                        else
                                                                task.wait(0.2)
                                                        end
                                                else
                                                        task.wait(0.5)
                                                end
                                        end
                                end

                                if State.autoChickenFarm then
                                        ChickenStatus.Text = "Killer Chicken killed! Going back to Nest..."
                                        ChickenStatus.TextColor3 = Color3.fromRGB(100, 255, 150)
                                end
                        end
                        task.wait(0.5)
                end
        end)
end

local function stopChickenFarm()
        State.autoChickenFarm = false
        ChickenFarmBtn.Text = "Start Chicken Farm"
        ChickenFarmBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 100)
        ChickenStatus.Text = "Stopped"
        ChickenStatus.TextColor3 = Color3.fromRGB(140, 150, 180)
        print("[ChickenFarm] === STOPPED ===")
end

ChickenFarmBtn.MouseButton1Click:Connect(function()
        if State.autoChickenFarm then stopChickenFarm() else startChickenFarm() end
end)

ChickenDrinkBtn.MouseButton1Click:Connect(function()
        State.chickenDrinkMagmatic = not State.chickenDrinkMagmatic
        if State.chickenDrinkMagmatic then
                ChickenDrinkBtn.Text = "Auto Drink Magmatic: ON"
                ChickenDrinkBtn.BackgroundColor3 = Theme.Accent
                ChickenDrinkBtn.TextColor3 = Theme.AccentText
        else
                ChickenDrinkBtn.Text = "Auto Drink Magmatic: OFF"
                ChickenDrinkBtn.BackgroundColor3 = Theme.Elevated
                ChickenDrinkBtn.TextColor3 = Theme.Text
        end
end)

-- Page draggable toggle
UI.DragToggleBtn.MouseButton1Click:Connect(function()
        State.pageDraggable = not State.pageDraggable
        if State.pageDraggable then
                UI.DragToggleBtn.Text = "ON"
                UI.DragToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
                UI.DragToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        else
                UI.DragToggleBtn.Text = "OFF"
                UI.DragToggleBtn.BackgroundColor3 = Theme.Elevated
                UI.DragToggleBtn.TextColor3 = Theme.TextDim
                ContentPanel.Position = UDim2.new(0.58, 0, 0.5, 0)
        end
end)
UI.ResetPosBtn.MouseButton1Click:Connect(function()
        ContentPanel.Position = UDim2.new(0.58, 0, 0.5, 0)
end)




if not ok then
        warn("[Pilgrammed] Script error: " .. tostring(err))
end
print("[Pilgrammed] Script loaded!")
