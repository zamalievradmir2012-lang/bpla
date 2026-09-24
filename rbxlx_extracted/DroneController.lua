-- ============================================================
--  DroneController — клиент оператора:
--  магазин дронов, управление Тип A (WASD + мышь) и Тип B (FPV-мышь),
--  «Ланцет» — захват цели кликом (квадрат-маркер + автозаход),
--  камеры от 1-го и 3-го лица (клавиша V), HUD, рой, барражирование,
--  экран помех.
-- ============================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)
local DroneFactory = require(ReplicatedStorage.Shared.DroneFactory)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local launchRF = Remotes:WaitForChild(Config.REM.LaunchDrone)
local droneFireEv = Remotes:WaitForChild(Config.REM.DroneFire)
local detonateEv = Remotes:WaitForChild(Config.REM.Detonate)
local swarmAttackEv = Remotes:WaitForChild(Config.REM.SwarmAttack)
local swarmFormEv = Remotes:WaitForChild(Config.REM.SwarmFormation)
local loiterEv = Remotes:WaitForChild(Config.REM.Loiter)
local setModeEv = Remotes:WaitForChild(Config.REM.SetMode)
local markerEv = Remotes:WaitForChild(Config.REM.DropMarker)
local returnEv = Remotes:WaitForChild(Config.REM.ReturnDrone)
local operFXEv = Remotes:WaitForChild(Config.REM.OperFX)
local shakeEv = Remotes:WaitForChild(Config.REM.Shake)
local markerFXEv = Remotes:WaitForChild(Config.REM.MarkerFX)
local unlockEv = Remotes:WaitForChild(Config.REM.DroneUnlocked)

-- купленные НАВСЕГДА дроны: [droneId] = true
local unlockedSet = {}

-- ------------------------------------------------------------
-- СОСТОЯНИЕ
-- ------------------------------------------------------------
local flying = nil        -- {model, cfg, primary, align, lvel, kind, yaw, pitch, throttle, units, view, attackPos}
local loitering = false
local camMode = "gun"     -- или "camera" (Орлан)
local camZoom = 120
local shopGui, fpvGui, wasdGui, staticGui
local markers = {}
local lancetMark = nil    -- квадрат-маркер цели «Ланцета» {anchor, lbl}
local camPos = nil        -- сглаженная позиция камеры (общая для всех веток)
local GuiServiceInset = GuiService:GetGuiInset()

-- ------------------------------------------------------------
-- КВАДРАТ-МАРКЕР ЦЕЛИ «ЛАНЦЕТА»
-- ------------------------------------------------------------
local function clearLancetMark()
	if lancetMark and lancetMark.anchor then
		lancetMark.anchor:Destroy()
	end
	lancetMark = nil
end

local function setLancetMark(pos)
	clearLancetMark()
	local fx = workspace:FindFirstChild("FX") or workspace
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = pos
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 58, 0, 58)
	gui.AlwaysOnTop = true
	gui.Parent = anchor
	-- красный квадратик (рамка)
	local sq = Instance.new("Frame")
	sq.Size = UDim2.new(1, 0, 1, 0)
	sq.BackgroundTransparency = 1
	sq.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 60, 45)
	stroke.Thickness = 2.6
	stroke.Transparency = 0.08
	stroke.Parent = sq
	-- белые уголки-скобки
	local function bar(px, py, w, h)
		local f = Instance.new("Frame")
		f.Size = UDim2.new(0, w, 0, h)
		f.Position = UDim2.new(px[1], px[2], py[1], py[2])
		f.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		f.BorderSizePixel = 0
		f.Parent = gui
	end
	bar({ 0, -3 }, { 0, -3 }, 18, 4) bar({ 0, -3 }, { 0, -3 }, 4, 18)
	bar({ 1, -15 }, { 0, -3 }, 18, 4) bar({ 1, -1 }, { 0, -3 }, 4, 18)
	bar({ 0, -3 }, { 1, -1 }, 18, 4) bar({ 0, -3 }, { 1, -15 }, 4, 18)
	bar({ 1, -15 }, { 1, -1 }, 18, 4) bar({ 1, -1 }, { 1, -15 }, 4, 18)
	-- точка в центре
	local dot = Instance.new("Frame")
	dot.Size = UDim2.new(0, 4, 0, 4)
	dot.Position = UDim2.new(0.5, -2, 0.5, -2)
	dot.BackgroundColor3 = Color3.fromRGB(255, 60, 45)
	dot.BorderSizePixel = 0
	dot.Parent = gui
	-- подпись с дальностью
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0, 200, 0, 20)
	lbl.Position = UDim2.new(0.5, -100, 1, 8)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.Code
	lbl.TextSize = 16
	lbl.TextColor3 = Color3.fromRGB(255, 120, 90)
	lbl.Text = "ЦЕЛЬ ЗАХВАЧЕНА"
	lbl.Parent = gui
	anchor.Parent = fx
	lancetMark = { anchor = anchor, lbl = lbl }
end

-- ------------------------------------------------------------
-- УТИЛИТЫ GUI
-- ------------------------------------------------------------
local function mk(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end

local function toast(text, color)
	local pg = player:WaitForChild("PlayerGui")
	local t = mk("TextLabel", {
		Size = UDim2.new(0, 420, 0, 40), Position = UDim2.new(0.5, -210, 0.3, 0),
		BackgroundColor3 = Color3.fromRGB(15, 18, 22), BackgroundTransparency = 0.25,
		Font = Enum.Font.GothamBold, Text = text, TextSize = 18,
		TextColor3 = color or Color3.fromRGB(255, 220, 120), ZIndex = 50,
	}, pg)
	mk("UICorner", { CornerRadius = UDim.new(0, 8) }, t)
	TweenService:Create(t, TweenInfo.new(2.5), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
	game:GetService("Debris"):AddItem(t, 2.6)
end

-- ------------------------------------------------------------
-- ТРЯСКА ЭКРАНА
-- ------------------------------------------------------------
local shakePower = 0
shakeEv.OnClientEvent:Connect(function(power) shakePower = math.max(shakePower, power or 1) end)

-- ------------------------------------------------------------
-- FPV HUD / WASD HUD
-- ------------------------------------------------------------
local function buildFpvHud()
	local pg = player:WaitForChild("PlayerGui")
	local gui = mk("ScreenGui", { Name = "FPVHud", ResetOnSpawn = false, IgnoreGuiInset = true }, pg)
	-- зелёный кадр
	mk("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1 }, gui)
	-- сетка-прицел
	for i = 1, 9 do
		local x = i / 10
		mk("Frame", { Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(x, 0, 0, 0), BackgroundColor3 = Color3.fromRGB(80, 255, 120), BackgroundTransparency = 0.85, BorderSizePixel = 0 }, gui)
		mk("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, x, 0), BackgroundColor3 = Color3.fromRGB(80, 255, 120), BackgroundTransparency = 0.85, BorderSizePixel = 0 }, gui)
	end
	-- уголки кадра
	for _, a in ipairs({ { 0, 0, 1, 1 }, { 1, 0, -1, 1 }, { 0, 1, 1, -1 }, { 1, 1, -1, -1 } }) do
		mk("Frame", { Size = UDim2.new(0, 60, 0, 3), Position = UDim2.new(a[1] == 1 and 1 or 0, a[3] * -60, a[2] == 1 and 1 or 0, a[4] * -60), BackgroundColor3 = Color3.fromRGB(90, 255, 120), BorderSizePixel = 0 }, gui)
	end
	-- перекрестие
	mk("Frame", { Size = UDim2.new(0, 26, 0, 2), Position = UDim2.new(0.5, -13, 0.5, -1), BackgroundColor3 = Color3.fromRGB(120, 255, 140), BorderSizePixel = 0 }, gui)
	mk("Frame", { Size = UDim2.new(0, 2, 0, 26), Position = UDim2.new(0.5, -1, 0.5, -13), BackgroundColor3 = Color3.fromRGB(120, 255, 140), BorderSizePixel = 0 }, gui)
	-- телеметрия
	local telL = mk("TextLabel", { Size = UDim2.new(0, 260, 0, 110), Position = UDim2.new(0, 14, 0, 14), BackgroundTransparency = 1, Font = Enum.Font.Code, Text = "", TextSize = 17, TextColor3 = Color3.fromRGB(120, 255, 140), TextXAlignment = Enum.TextXAlignment.Left }, gui)
	local telR = mk("TextLabel", { Size = UDim2.new(0, 220, 0, 80), Position = UDim2.new(1, -234, 0, 14), BackgroundTransparency = 1, Font = Enum.Font.Code, Text = "", TextSize = 17, TextColor3 = Color3.fromRGB(120, 255, 140), TextXAlignment = Enum.TextXAlignment.Right }, gui)
	local compass = mk("TextLabel", { Size = UDim2.new(0, 300, 0, 30), Position = UDim2.new(0.5, -150, 0, 8), BackgroundTransparency = 1, Font = Enum.Font.Code, Text = "С", TextSize = 22, TextColor3 = Color3.fromRGB(120, 255, 140) }, gui)
	-- HP дрон
	local hpBack = mk("Frame", { Size = UDim2.new(0, 320, 0, 14), Position = UDim2.new(0.5, -160, 1, -46), BackgroundColor3 = Color3.fromRGB(20, 30, 20), BackgroundTransparency = 0.3, BorderColor3 = Color3.fromRGB(90, 255, 120) }, gui)
	local hpBar = mk("Frame", { Size = UDim2.new(1, -4, 1, -4), Position = UDim2.new(0, 2, 0, 2), BackgroundColor3 = Color3.fromRGB(90, 255, 120), BorderSizePixel = 0 }, hpBack)
	-- виньетка по краям кадра (как у реальной FPV-камеры)
	local vig = mk("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = -1 }, gui)
	vig.BackgroundColor3 = Color3.new(0, 0, 0)
	mk("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(0, 0, 0)), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.62), NumberSequenceKeypoint.new(0.14, 1), NumberSequenceKeypoint.new(0.86, 1), NumberSequenceKeypoint.new(1, 0.62) }) }, vig)
	local vig2 = mk("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = -1 }, gui)
	mk("UIGradient", { Rotation = 0, Color = ColorSequence.new(Color3.new(0, 0, 0)), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.62), NumberSequenceKeypoint.new(0.16, 1), NumberSequenceKeypoint.new(0.84, 1), NumberSequenceKeypoint.new(1, 0.62) }) }, vig2)
	-- REC + таймер полёта
	local rec = mk("TextLabel", { Size = UDim2.new(0, 190, 0, 26), Position = UDim2.new(1, -204, 0, 100), BackgroundTransparency = 1, Font = Enum.Font.Code, Text = "● REC  00:00", TextSize = 19, TextColor3 = Color3.fromRGB(255, 70, 60), TextXAlignment = Enum.TextXAlignment.Right }, gui)
	-- батарея (топливо) и сигнал связи
	local battBack = mk("Frame", { Size = UDim2.new(0, 150, 0, 12), Position = UDim2.new(0, 14, 0, 128), BackgroundColor3 = Color3.fromRGB(20, 30, 20), BackgroundTransparency = 0.3, BorderColor3 = Color3.fromRGB(90, 255, 120) }, gui)
	local battBar = mk("Frame", { Size = UDim2.new(1, -4, 1, -4), Position = UDim2.new(0, 2, 0, 2), BackgroundColor3 = Color3.fromRGB(255, 210, 80), BorderSizePixel = 0 }, battBack)
	local sig = mk("TextLabel", { Size = UDim2.new(0, 200, 0, 20), Position = UDim2.new(0, 14, 0, 146), BackgroundTransparency = 1, Font = Enum.Font.Code, Text = "СИГНАЛ: ▮▮▮▮▮", TextSize = 15, TextColor3 = Color3.fromRGB(120, 255, 140), TextXAlignment = Enum.TextXAlignment.Left }, gui)
	-- подсказки
	local help = mk("TextLabel", { Size = UDim2.new(0, 340, 0, 70), Position = UDim2.new(0, 14, 1, -110), BackgroundTransparency = 1, Font = Enum.Font.Code, Text = "", TextSize = 14, TextColor3 = Color3.fromRGB(150, 255, 170), TextXAlignment = Enum.TextXAlignment.Left, TextTransparency = 0.25 }, gui)
	gui.Enabled = false
	return { gui = gui, telL = telL, telR = telR, compass = compass, hpBar = hpBar, help = help, rec = rec, battBar = battBar, sig = sig }
end

local function buildWasdHud()
	local pg = player:WaitForChild("PlayerGui")
	local gui = mk("ScreenGui", { Name = "WasdHud", ResetOnSpawn = false }, pg)
	local tel = mk("TextLabel", { Size = UDim2.new(0, 280, 0, 110), Position = UDim2.new(0, 14, 0, 14), BackgroundTransparency = 1, Font = Enum.Font.Code, Text = "", TextSize = 17, TextColor3 = Color3.fromRGB(200, 230, 255), TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 0.6 }, gui)
	local hpBack = mk("Frame", { Size = UDim2.new(0, 260, 0, 14), Position = UDim2.new(0.5, -130, 1, -40), BackgroundColor3 = Color3.fromRGB(20, 25, 35), BackgroundTransparency = 0.3, BorderColor3 = Color3.fromRGB(120, 180, 255) }, gui)
	local hpBar = mk("Frame", { Size = UDim2.new(1, -4, 1, -4), Position = UDim2.new(0, 2, 0, 2), BackgroundColor3 = Color3.fromRGB(120, 180, 255), BorderSizePixel = 0 }, hpBack)
	local help = mk("TextLabel", { Size = UDim2.new(0, 420, 0, 46), Position = UDim2.new(0.5, -210, 1, -84), BackgroundTransparency = 1, Font = Enum.Font.Code, Text = "WASD — полёт · Пробел/Shift — высота · ЛКМ — сброс · X — на базу", TextSize = 15, TextColor3 = Color3.fromRGB(255, 255, 255), TextTransparency = 0.25 }, gui)
	gui.Enabled = false
	return { gui = gui, tel = tel, hpBar = hpBar, help = help }
end

-- статика (помехи)
local function buildStatic()
	local pg = player:WaitForChild("PlayerGui")
	local gui = mk("ScreenGui", { Name = "StaticFX", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Global }, pg)
	local cover = mk("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(180, 180, 180), BackgroundTransparency = 1, ZIndex = 40, BorderSizePixel = 0 }, gui)
	for i = 1, 24 do
		mk("Frame", { Size = UDim2.new(1, 0, 0, math.random(2, 6)), Position = UDim2.new(0, 0, math.random(), 0), BackgroundColor3 = Color3.fromRGB(220, 220, 220), BackgroundTransparency = 0.75, BorderSizePixel = 0, ZIndex = 41 }, cover)
	end
	local msg = mk("TextLabel", { Size = UDim2.new(1, 0, 0, 60), Position = UDim2.new(0, 0, 0.42, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, Text = "СИГНАЛ ПОТЕРЯН", TextSize = 40, TextColor3 = Color3.fromRGB(255, 80, 80), ZIndex = 42 }, gui)
	gui.Enabled = false
	return { gui = gui, cover = cover, msg = msg }
end

-- ------------------------------------------------------------
-- МАГАЗИН ДРОНОВ
-- ------------------------------------------------------------
local function buildShop()
	local pg = player:WaitForChild("PlayerGui")
	local gui = mk("ScreenGui", { Name = "DroneShop", ResetOnSpawn = false }, pg)
	mk("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(8, 10, 14), BackgroundTransparency = 0.12, BorderSizePixel = 0 }, gui)
	local title = mk("TextLabel", { Size = UDim2.new(1, 0, 0, 54), Position = UDim2.new(0, 0, 0, 8), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, Text = "МАГАЗИН БПЛА  ·  B — закрыть", TextSize = 30, TextColor3 = Color3.fromRGB(120, 220, 255) }, gui)
	local coinsLabel = mk("TextLabel", { Size = UDim2.new(0, 260, 0, 36), Position = UDim2.new(1, -280, 0, 14), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "", TextSize = 22, TextColor3 = Color3.fromRGB(255, 210, 80) }, gui)
	local scroll = mk("ScrollingFrame", { Size = UDim2.new(1, -40, 1, -150), Position = UDim2.new(0, 20, 0, 100), BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(0, 0, 0, 0), ScrollBarThickness = 8, ScrollBarImageColor3 = Color3.fromRGB(90, 180, 255) }, gui)
	mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	mk("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6) }, scroll)

	local viewports = {}
	local cards = {}
	local function refreshShopButtons()
		for _, c in ipairs(cards) do
			local d = c.drone
			if d.Price == 0 then
				c.btn.Text = "ВЫЛЕТЕТЬ (бесплатно)"
				c.btn.BackgroundColor3 = Color3.fromRGB(40, 110, 200)
				c.note.Text = "Стартовый дрон"
			elseif unlockedSet[d.Id] then
				c.btn.Text = "ЗАПУСТИТЬ (бесплатно)"
				c.btn.BackgroundColor3 = Color3.fromRGB(40, 150, 80)
				c.note.Text = "✔ Куплен навсегда"
			else
				c.btn.Text = "КУПИТЬ НАВСЕГДА · " .. d.Price .. " монет"
				c.btn.BackgroundColor3 = Color3.fromRGB(40, 110, 200)
				c.note.Text = "Платишь 1 раз — летать можно всегда"
			end
		end
	end
	for order, drone in ipairs(Config.DRONES) do
		local card = mk("Frame", { Size = UDim2.new(0, 250, 0, 395), BackgroundColor3 = Color3.fromRGB(16, 20, 28), BorderColor3 = Color3.fromRGB(60, 120, 180), LayoutOrder = order }, scroll)
		mk("UICorner", { CornerRadius = UDim.new(0, 10) }, card)
		local vp = mk("ViewportFrame", { Size = UDim2.new(1, -16, 0, 150), Position = UDim2.new(0, 8, 0, 8), BackgroundColor3 = Color3.fromRGB(10, 13, 18), BorderSizePixel = 0, Ambient = Color3.fromRGB(120, 140, 170), LightColor = Color3.fromRGB(240, 245, 255), LightDirection = Vector3.new(-0.5, -1, -0.3) }, card)
		mk("UICorner", { CornerRadius = UDim.new(0, 8) }, vp)
		local world = mk("WorldModel", {}, vp)
		local model = DroneFactory.build(drone.Id)
		local vpCam = mk("Camera", {}, world)
		vp.CurrentCamera = vpCam
		if model then
			model.Parent = world
			local cf = CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, 0)
			model:PivotTo(cf)
			local dist = model:GetAttribute("PreviewDist") or 24
		vpCam.CFrame = CFrame.new(0, dist * 0.28, dist) * CFrame.Angles(math.rad(-14), math.rad(18), 0)
			table.insert(viewports, { model = model, cam = vpCam })
		end
		mk("TextLabel", { Size = UDim2.new(1, -16, 0, 26), Position = UDim2.new(0, 8, 0, 160), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = drone.Name, TextSize = 19, TextColor3 = Color3.fromRGB(140, 220, 255) }, card)
		mk("TextLabel", { Size = UDim2.new(1, -16, 0, 88), Position = UDim2.new(0, 8, 0, 186), BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = drone.Desc, TextSize = 12, TextColor3 = Color3.fromRGB(190, 200, 215), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }, card)
		mk("TextLabel", { Size = UDim2.new(1, -16, 0, 34), Position = UDim2.new(0, 8, 0, 274), BackgroundTransparency = 1, Font = Enum.Font.Code, Text = string.format("Скор. %d · HP %d\nБоееприпасы: %d · %s", drone.Speed, drone.HP, drone.Ammo, drone.Control == "A" and "WASD" or "FPV"), TextSize = 13, TextColor3 = Color3.fromRGB(130, 240, 160), TextXAlignment = Enum.TextXAlignment.Left }, card)
		local btn = mk("TextButton", { Size = UDim2.new(1, -16, 0, 42), Position = UDim2.new(0, 8, 0, 316), Font = Enum.Font.GothamBold, TextSize = 17, TextColor3 = Color3.fromRGB(255, 255, 255), BackgroundColor3 = Color3.fromRGB(40, 110, 200), Text = drone.Price == 0 and "ВЫЛЕТЕТЬ (бесплатно)" or ("КУПИТЬ НАВСЕГДА · " .. drone.Price .. " монет") }, card)
		mk("UICorner", { CornerRadius = UDim.new(0, 8) }, btn)
		btn.MouseButton1Click:Connect(function()
			local result, err = launchRF:InvokeServer(drone.Id)
			if result then
				shopGui.gui.Enabled = false
				startFlying(result, drone)
			else
				toast(err or "Не удалось запустить дрон", Color3.fromRGB(255, 120, 100))
			end
		end)
		local note = mk("TextLabel", { Size = UDim2.new(1, -16, 0, 22), Position = UDim2.new(0, 8, 0, 362), BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = drone.Price == 0 and "Стартовый дрон" or "Платишь 1 раз — летать можно всегда", TextSize = 11, TextColor3 = Color3.fromRGB(120, 130, 150) }, card)
		table.insert(cards, { drone = drone, btn = btn, note = note })
	end
	refreshShopButtons()
	coinsLabel.Parent = gui
	gui.Enabled = false
	return { gui = gui, coins = coinsLabel, viewports = viewports, Frame = gui, refresh = refreshShopButtons }
end


-- ------------------------------------------------------------
-- ПОЛЁТ
-- ------------------------------------------------------------
local function isOperator()
	return player.Team and player.Team.Name == Config.TEAM_OPS
end

local function nearBunker()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	return (root.Position - Config.BUNKER_POS).Magnitude < 70
end

function startFlying(model, cfg)
	local primary = model.PrimaryPart or model:WaitForChild("Hull", 3)
	if not primary then
		toast("Дрон не собрался", Color3.fromRGB(255, 120, 100))
		return
	end
	-- ждём репликацию ограничений, иначе полёт молча не начинается и аппарат падает
	local align = primary:FindFirstChild("FlightAlign") or primary:WaitForChild("FlightAlign", 3)
	local lvel = primary:FindFirstChild("FlightVel") or primary:WaitForChild("FlightVel", 3)
	if not align or not lvel then
		toast("Нет двигателя дрона — перезапусти вылет", Color3.fromRGB(255, 120, 100))
		return
	end
	-- юниты роя
	local units = {}
	if cfg.Kind == "swarm" then
		task.delay(0.3, function()
			for _, u in ipairs(workspace.Drones:GetChildren()) do
				if u:GetAttribute("Unit") and u:GetAttribute("Owner") == player.Name then
					table.insert(units, u)
				end
			end
		end)
	end
	local look = primary.CFrame.LookVector
	flying = {
		model = model, cfg = cfg, primary = primary, align = align, lvel = lvel,
		yaw = math.atan2(-look.X, -look.Z), pitch = math.rad(-8), throttle = 1, kind = cfg.Kind, units = units,
		takeoffUntil = os.clock() + 2.4,
		view = cfg.Control == "B" and "fpv" or "chase", -- дроны всегда от 1-го лица, самолёты от 3-го
		startedAt = os.clock(),
		fuelMax = cfg.Fuel,
	}
	-- сброс режимов с прошлого полёта (иначе камера Орлана/барраж «застревают»)
	camMode = "gun"
	camZoom = 120
	loitering = false
	clearLancetMark()
	-- звук мотора: высота тона меняется от газа (локально для оператора)
	local engSound = primary:FindFirstChildOfClass("Sound")
	if engSound then
		flying.engineSound = engSound
		flying.enginePitch = engSound.PlaybackSpeed
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 70
	if cfg.Control == "B" then
		fpvGui.gui.Enabled = true
		wasdGui.gui.Enabled = false
		if cfg.Id == "lancet" then
			fpvGui.help.Text = "ЛКМ — цель (квадрат) · SPACE — подрыв · C — барраж · W/S — газ · V — камера"
		else
			fpvGui.help.Text = "ЛКМ/SPACE — подрыв · W/S — газ · мышь — направление · V — камера"
		end
		if cfg.Id ~= "lancet" then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = false
		end
	else
		wasdGui.gui.Enabled = true
		fpvGui.gui.Enabled = false
		wasdGui.help.Text = "W/S — газ · мышь — поворот · Пробел/Shift — высота · ЛКМ — " .. (cfg.Kind == "bomber" and "сброс бомбы" or cfg.Kind == "missile" and "пуск ракеты" or cfg.Kind == "heavy" and "сброс (R — ракеты)" or cfg.Kind == "swarm" and "атака роя (G — строй)" or "сброс гранаты") .. (cfg.Flags.Marker and " · E — камера/маркер" or "") .. " · V — вид 1/3 лицо"
		-- курсор нужен: мышь указывает, куда повернуть
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
	-- скрываем персонажа от камеры FPV
	local char = player.Character
	if char then
		for _, p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") then p.LocalTransparencyModifier = 1 end
		end
	end
end

local function stopFlying()
	local model = flying and flying.model
	if model then
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then p.LocalTransparencyModifier = 0 end
		end
	end
	flying = nil
	clearLancetMark()
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	if fpvGui then fpvGui.gui.Enabled = false end
	if wasdGui then wasdGui.gui.Enabled = false end
	-- вернуть видимость персонажа
	local char = player.Character
	if char then
		for _, p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") then p.LocalTransparencyModifier = 0 end
		end
	end
end

-- клиентская анимация пропеллеров (все дроны на клиенте)
local propParts = {}
task.spawn(function()
	while true do
		propParts = {}
		for _, model in ipairs(workspace.Drones:GetChildren()) do
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and d:GetAttribute("SpinSpeed") then
					table.insert(propParts, d)
				end
			end
		end
		task.wait(2)
	end
end)
RunService.Heartbeat:Connect(function(dt)
	for _, p in ipairs(propParts) do
		if p.Parent then
			p.CFrame = p.CFrame * CFrame.Angles(0, 0, math.rad(p:GetAttribute("SpinSpeed") * dt * 0.25))
		end
	end
end)

-- мигающие LED
task.spawn(function()
	while true do
		for _, model in ipairs(workspace.Drones:GetChildren()) do
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and d:GetAttribute("Blink") then
					d.Transparency = (math.floor(os.clock() * 3) % 2 == 0) and 0 or 0.7
				end
			end
		end
		task.wait(0.15)
	end
end)

-- ------------------------------------------------------------
-- УПРАВЛЕНИЕ
-- ------------------------------------------------------------
local firing = false
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 and flying then
		firing = true
		local cfg = flying.cfg
		if cfg.Kind == "swarm" then
			-- атака ближайшего к прицелу
			local ray = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 900)
			local pos = ray and ray.Position or (camera.CFrame.Position + camera.CFrame.LookVector * 900)
			swarmAttackEv:FireServer(pos, false)
			task.delay(0.7, function()
				local t0 = os.clock()
				while firing and flying and os.clock() - t0 < 5 do
					swarmAttackEv:FireServer(pos, true)
					task.wait(0.4)
				end
			end)
		elseif cfg.Id == "lancet" then
			-- «Ланцет»: клик по объекту → квадратик-маркер → автозаход на цель
			local mpos = UserInputService:GetMouseLocation()
			local ray = camera:ViewportPointToRay(mpos.X, mpos.Y - GuiServiceInset.Y)
			local rp = RaycastParams.new()
			rp.FilterType = Enum.RaycastFilterType.Exclude
			local excl = { flying.model }
			for _, n in ipairs({ "FX", "Debris", "Drones" }) do
				local fo = workspace:FindFirstChild(n)
				if fo then table.insert(excl, fo) end
			end
			rp.FilterDescendantsInstances = excl
			local hit = workspace:Raycast(ray.Origin, ray.Direction * 1600, rp)
			local pos = hit and hit.Position or (ray.Origin + ray.Direction * 1600)
			flying.attackPos = pos
			setLancetMark(pos)
			if loitering then
				loitering = false
				loiterEv:FireServer(false)
			end
			toast("ЦЕЛЬ ЗАХВАЧЕНА — «Ланцет» пикирует", Color3.fromRGB(255, 140, 90))
		elseif cfg.Kind == "kamikaze" then
			detonateEv:FireServer()
		else
			droneFireEv:FireServer(flying.primary.Position, camera.CFrame.LookVector)
		end
	elseif input.KeyCode == Enum.KeyCode.Space and flying and flying.cfg.Kind == "kamikaze" then
		-- ручной подрыв (у «Ланцета» ЛКМ занят целью)
		detonateEv:FireServer()
	elseif input.KeyCode == Enum.KeyCode.C and flying and flying.cfg.Flags.Loiter then
		loitering = not loitering
		loiterEv:FireServer(loitering)
		if loitering and flying.attackPos then
			flying.attackPos = nil
			clearLancetMark()
		end
		toast(loitering and "БАРРАЖИРОВАНИЕ ВКЛ" or "БАРРАЖИРОВАНИЕ ВЫКЛ")
	elseif input.KeyCode == Enum.KeyCode.V and flying then
		-- смена вида: 1-е лицо (FPV) ⇄ 3-е лицо (за дроном)
		flying.view = flying.view == "fpv" and "chase" or "fpv"
		camPos = nil
		toast(flying.view == "fpv" and "Камера: от 1-го лица (FPV)" or "Камера: от 3-го лица")
	elseif input.KeyCode == Enum.KeyCode.R and flying and flying.cfg.Flags.Modes then
		local cur = flying.model:GetAttribute("Mode")
		local new = cur == "cruise" and "bombs" or "cruise"
		setModeEv:FireServer(new)
		toast(new == "cruise" and "Режим: крылатые ракеты" or "Режим: бомбы")
	elseif input.KeyCode == Enum.KeyCode.G and flying and flying.cfg.Kind == "swarm" then
		local cur = flying.model:GetAttribute("Formation")
		local new = cur == "cloud" and "wedge" or "cloud"
		swarmFormEv:FireServer(new)
		toast(new == "cloud" and "Строй: облако" or "Строй: клин")
	elseif input.KeyCode == Enum.KeyCode.E and flying and flying.cfg.Flags.Marker then
		camMode = camMode == "gun" and "camera" or "gun"
		if camMode == "camera" then
			toast("Подвесная камера: ЛКМ — маркер цели, колесо — зум")
		end
	elseif input.KeyCode == Enum.KeyCode.X and flying then
		returnEv:FireServer()
	elseif input.KeyCode == Enum.KeyCode.B then
		if flying then return end
		if isOperator() then
			shopGui.gui.Enabled = not shopGui.gui.Enabled
		end
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then firing = false end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseWheel and flying and camMode == "camera" then
		camZoom = math.clamp(camZoom - input.Position.Z * 20, 40, 400)
	end
end)

-- ------------------------------------------------------------
-- ЦИКЛ КАМЕРЫ / ФИЗИКИ
-- ------------------------------------------------------------
local blur = Instance.new("BlurEffect")
blur.Size = 0
blur.Parent = game:GetService("Lighting")

RunService.RenderStepped:Connect(function(dt)
	-- вращение витрин магазина
	if shopGui and shopGui.gui.Enabled then
		for _, v in ipairs(shopGui.viewports) do
			if v.model.Parent then
				v.model:PivotTo(CFrame.new() * CFrame.Angles(0, os.clock() % (math.pi * 2), 0))
			end
		end
	end
	if not flying then return end
	local f = flying
	local model = f.model
	if not model.Parent then stopFlying() return end
	local cfg = f.cfg
	local loiterOn = model:GetAttribute("Loiter")

	local takingOff = f.takeoffUntil and os.clock() < f.takeoffUntil
	if takingOff then
		-- автонабор: видно, что дрон оторвался, даже если игрок ещё не нажал W
		f.yaw = math.pi
		f.pitch = math.rad(-10)
		f.lvel.VectorVelocity = Vector3.new(0, 34, 58)
		f.align.CFrame = CFrame.Angles(f.pitch, f.yaw, 0)
		local target = f.primary.Position
		local back = math.clamp(f.primary.Size.Magnitude * 3 + 16, 20, 42)
		local behind = (CFrame.Angles(0, f.yaw, 0) * CFrame.new(0, 8, back)).Position
		camPos = camPos and Util.lerp(camPos, target + behind, math.clamp(8 * dt, 0, 1)) or (target + behind)
		camera.CFrame = CFrame.lookAt(camPos, target)
	elseif cfg.Control == "A" then
		-- ===== ТИП A: WASD + МЫШЬ (куда мышка — туда и поворачивает) =====
		local maxYaw = math.rad(cfg.Turn)
		local mpos = UserInputService:GetMouseLocation()
		local vp = camera.ViewportSize
		local center = Vector2.new(vp.X / 2, vp.Y / 2 + GuiServiceInset.Y / 2)
		local off = (mpos - center) / math.max(vp.Y, 1)
		-- мёртвая зона в центре: аппарат летит прямо, даже если курсор чуть смещён
		if math.abs(off.X) < 0.06 then off = Vector2.new(0, off.Y) end
		if math.abs(off.Y) < 0.06 then off = Vector2.new(off.X, 0) end
		local mYaw = math.clamp(off.X * 3.2, -1, 1) * maxYaw
		local mPitch = math.clamp(-off.Y * 3.2, -1, 1) * maxYaw * 0.7
		local forward = 0
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then forward = forward + 1 end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then forward = forward - 0.6 end
		local turn = 0
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then turn = turn + 1 end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then turn = turn - 1 end
		if loiterOn then turn = 0.5 forward = 0.4 mYaw = 0 mPitch = 0 end
		local isPlane = cfg.Id == "orlan" or cfg.Id == "inohodets" or cfg.Id == "ohotnik" or cfg.Id == "strizh"
		-- самолёт всегда летит вперёд (минимальная скорость), не висит в воздухе
		if isPlane then forward = math.max(forward, 0.55) end
		f.yaw = f.yaw + (turn * maxYaw * 0.85 + mYaw) * dt
		f.pitch = math.clamp((f.pitch or 0) + mPitch * dt, math.rad(-55), math.rad(40))
		-- квадрокоптеры сами выравнивают нос, когда мышь в центре
		if not isPlane and off.Y == 0 then
			f.pitch = f.pitch * math.clamp(1 - 1.6 * dt, 0, 1)
		end
		local vertical = 0
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then vertical = vertical + 1 end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then vertical = vertical - 1 end
		local targetBank = math.clamp(-mYaw / maxYaw * 0.45 - turn * 0.25, -0.6, 0.6)
		f.bank = Util.lerp(f.bank or 0, targetBank, math.clamp(7 * dt, 0, 1))
		local rot = CFrame.Angles(f.pitch * (isPlane and 1 or 0.45), f.yaw, f.bank)
		local look = isPlane and rot.LookVector or CFrame.Angles(0, f.yaw, 0).LookVector
		local vel = look * cfg.Speed * forward + Vector3.new(0, vertical * cfg.Speed * 0.8, 0)
		f.lvel.VectorVelocity = Util.lerp(f.lvel.VectorVelocity, vel, math.clamp(6 * dt, 0, 1))
		f.align.CFrame = rot - Vector3.new()
		-- камера
		local target = f.primary.Position
		local shakeOff = Vector3.new((math.random() - 0.5), (math.random() - 0.5), (math.random() - 0.5)) * shakePower
		if f.view == "fpv" then
			-- от 1-го лица: камера в носу аппарата (перед корпусом, чтобы не внутри деталей)
			local size = f.model:GetExtentsSize()
			local nose = target + rot.LookVector * math.clamp(size.Z * 0.5 + 0.5, 1.5, 12)
			camera.CFrame = CFrame.new(nose + shakeOff) * rot
			camera.FieldOfView = 72 + math.clamp(f.lvel.VectorVelocity.Magnitude * 0.045, 0, 12)
		else
			-- от 3-го лица со сглаживанием
			local back = math.clamp(f.primary.Size.Magnitude * 3 + 16, 18, 46)
			local behind = (CFrame.Angles(0, f.yaw, 0) * CFrame.new(0, 8, back)).Position
			camPos = camPos and Util.lerp(camPos, target + behind, math.clamp(8 * dt, 0, 1)) or (target + behind)
			camera.CFrame = CFrame.lookAt(camPos + shakeOff, target + shakeOff)
			camera.FieldOfView = 70
		end
	else
		-- ===== ТИП B: FPV-дроны. =====
		-- «Ланцет» — свободный курсор (оператор кликает по цели),
		-- остальные — мышь в центре, дрон доворачивает дельтой.
		local isLancet = cfg.Id == "lancet"
		if isLancet then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		else
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = false
		end
		if isLancet and f.attackPos then
			-- АВТОЗАХОД НА ЦЕЛЬ: «Ланцет» сам летит в квадратик
			local to = f.attackPos - f.primary.Position
			local dist = to.Magnitude
			if dist < 9 then
				f.attackPos = nil
				clearLancetMark()
				detonateEv:FireServer()
			else
				local u = to / dist
				local wantYaw = math.atan2(-u.X, -u.Z)
				local dy = (wantYaw - f.yaw + math.pi) % (math.pi * 2) - math.pi
				local maxYawStep = math.rad(cfg.Turn) * 1.15 * dt
				f.yaw = f.yaw + math.clamp(dy, -maxYawStep, maxYawStep)
				local horiz = math.sqrt(u.X * u.X + u.Z * u.Z)
				-- цель ниже → тангаж отрицательный (нос вниз); знак как у ручного управления
				local wantPitch = math.atan2(u.Y, horiz)
				local dp = wantPitch - f.pitch
				local maxPStep = math.rad(cfg.Turn) * 0.9 * dt
				f.pitch = math.clamp(f.pitch + math.clamp(dp, -maxPStep, maxPStep), math.rad(-80), math.rad(60))
				f.bank = math.clamp(-dy * 1.1, -0.5, 0.5)
				f.throttle = 1.5
			end
		elseif loiterOn then
			f.yaw = f.yaw + math.rad(40) * dt
			f.bank = (f.bank or 0) * 0.9
		elseif isLancet then
			-- ручное пилотирование «Ланцета»: дрон доворачивает в сторону курсора
			local mpos = UserInputService:GetMouseLocation()
			local vp = camera.ViewportSize
			local center = Vector2.new(vp.X / 2, vp.Y / 2 + GuiServiceInset.Y / 2)
			local off = (mpos - center) / math.max(vp.Y, 1)
			local maxYaw = math.rad(cfg.Turn)
			f.yaw = f.yaw + math.clamp(off.X * 5, -1, 1) * maxYaw * dt
			f.pitch = math.clamp(f.pitch + math.clamp(-off.Y * 5, -1, 1) * maxYaw * 0.8 * dt, math.rad(-75), math.rad(55))
			f.bank = math.clamp(-off.X * 0.9, -0.4, 0.4)
		else
			local delta = UserInputService:GetMouseDelta()
			local sens = 0.0036
			-- положительный yaw крутит влево, поэтому знак мыши обратный старому
			f.yaw = f.yaw - delta.X * sens
			f.pitch = math.clamp(f.pitch - delta.Y * sens, math.rad(-70), math.rad(50))
			f.bank = math.clamp((f.bank or 0) * 0.82 - delta.X * 0.0016, -0.4, 0.4)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then f.throttle = math.clamp(f.throttle + dt * 0.7, 0.35, 1.5) end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then f.throttle = math.clamp(f.throttle - dt * 0.7, 0.35, 1.5) end
		local speed = cfg.Speed * f.throttle
		if cfg.Flags.Dive and f.pitch < math.rad(-35) then
			speed = math.min(speed * 1.35, 200)
		end
		local rot = CFrame.Angles(f.pitch, f.yaw, f.bank or 0)
		f.align.CFrame = rot - Vector3.new()
		-- инерция: скорость подтягивается к целевой, а не телепортируется
		f.lvel.VectorVelocity = Util.lerp(f.lvel.VectorVelocity, rot.LookVector * speed, math.clamp(9 * dt, 0, 1))
		-- гул мотора меняется от газа
		if f.engineSound then
			f.engineSound.PlaybackSpeed = f.enginePitch * (0.65 + f.throttle * 0.45)
		end
		local size = f.model:GetExtentsSize()
		local shakeOff = Vector3.new((math.random() - 0.5), (math.random() - 0.5), (math.random() - 0.5)) * shakePower
		if f.view == "fpv" then
			-- от 1-го лица: камера в носу, лёгкая вибрация, динамический FOV
			local nose = f.primary.Position + rot.LookVector * math.clamp(size.Z * 0.5 + 0.5, 1.5, 10)
			local noise = Vector3.new((math.random() - 0.5), (math.random() - 0.5), (math.random() - 0.5)) * (0.08 + shakePower * 0.3)
			camera.CFrame = CFrame.new(nose + noise) * rot
			camera.FieldOfView = 72 + math.clamp(speed * 0.06, 0, 16)
			for _, part in ipairs(f.model:GetDescendants()) do
				if part:IsA("BasePart") then part.LocalTransparencyModifier = 0 end
			end
		else
			-- от 3-го лица (как было)
			local back = math.clamp(size.Z * 0.4 + 9, 11, 26)
			local height = math.clamp(size.Y + 4.5, 5, 12)
			local desired = f.primary.Position - rot.LookVector * back + Vector3.new(0, height, 0)
			camPos = camPos and Util.lerp(camPos, desired, math.clamp(12 * dt, 0, 1)) or desired
			local aim = f.primary.Position + rot.LookVector * 28
			camera.CFrame = CFrame.lookAt(camPos + shakeOff, aim)
			camera.FieldOfView = 70
			local look = camera.CFrame.LookVector
			for _, part in ipairs(f.model:GetDescendants()) do
				if part:IsA("BasePart") then
					local rel = part.Position - camera.CFrame.Position
					local along = rel:Dot(look)
					local side = (rel - look * along).Magnitude
					if rel.Magnitude < part.Size.Magnitude * 0.55 + 2 or (along > -1 and along < 7 and side < part.Size.Magnitude * 0.6 + 0.8) then
						part.LocalTransparencyModifier = 1
					else
						part.LocalTransparencyModifier = 0
					end
				end
			end
		end
	end

	-- дальность до цели «Ланцета» на маркере
	if flying and flying.cfg.Id == "lancet" and lancetMark and flying.attackPos then
		local d = (flying.attackPos - flying.primary.Position).Magnitude
		lancetMark.lbl.Text = string.format("ЦЕЛЬ ЗАХВАЧЕНА · %d м", math.floor(d))
	end

	-- режим подвесной камеры «Орлана»
	if camMode == "camera" then
		camera.CFrame = CFrame.new(f.primary.Position + Vector3.new(0, camZoom, camZoom * 0.2)) * CFrame.Angles(math.rad(-75), 0, 0)
	end

	-- размытие у «Молнии»
	if cfg.Flags.Blur then
		local spd = f.primary.AssemblyLinearVelocity.Magnitude
		blur.Size = math.clamp((spd - 200) / 6, 0, 26)
	end

	shakePower = math.max(0, shakePower - dt * 2.5)
end)

-- ЛКМ в режиме камеры Орлана → маркер
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe or not flying then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 and camMode == "camera" and flying.cfg.Flags.Marker then
		local ray = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 1000)
		if ray then markerEv:FireServer(ray.Position) end
	end
end)

-- ------------------------------------------------------------
-- HUD ОБНОВЛЕНИЕ
-- ------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(0.12)
		if flying and flying.model.Parent then
			local f = flying
			local pos = f.primary.Position
			local gPos = Util.groundAt(pos, { f.model })
			local alt = math.floor(pos.Y - gPos.Y)
			local spd = math.floor(f.primary.AssemblyLinearVelocity.Magnitude)
			local ammo = f.model:GetAttribute("Ammo") or 0
			local hp = f.model:GetAttribute("HP") or 0
			local maxhp = f.model:GetAttribute("MaxHP") or 1
			local fuel = f.model:GetAttribute("Fuel") or -1
			local mode = f.model:GetAttribute("Mode")
			local dirs = { "С", "СВ", "В", "ЮВ", "Ю", "ЮЗ", "З", "СЗ" }
			local heading = dirs[(math.floor(((math.deg(f.yaw) % 360) + 360) % 360 / 45) % 8) + 1]
			if f.cfg.Control == "B" then
				fpvGui.telL.Text = string.format("ВЫСОТА: %d studs\nСКОРОСТЬ: %d studs/s\nТОПЛИВО: %s", alt, spd, fuel >= 0 and (fuel .. " c") or "∞")
				fpvGui.telR.Text = string.format("X: %d  Z: %d\n%s\nБОЕПРИПАСЫ: %d", math.floor(pos.X), math.floor(pos.Z), mode and ("РЕЖИМ: " .. mode:upper()) or "", ammo)
				fpvGui.compass.Text = heading .. string.rep("  ·", 6) .. "  " .. heading
				fpvGui.hpBar.Size = UDim2.new(math.max(hp / maxhp, 0) - 0.006, 0, 1, -4)
				-- REC + время в воздухе
				local t = math.floor(os.clock() - (f.startedAt or os.clock()))
				local blink = math.floor(os.clock() * 1.5) % 2 == 0
				if fpvGui.rec then
					fpvGui.rec.Text = string.format("%s REC  %02d:%02d", blink and "●" or "○", math.floor(t / 60), t % 60)
					fpvGui.rec.TextColor3 = blink and Color3.fromRGB(255, 70, 60) or Color3.fromRGB(160, 50, 45)
				end
				-- батарея (по топливу)
				if fpvGui.battBar then
					local frac = 1
					if f.fuelMax and f.fuelMax > 0 then
						frac = math.clamp((fuel >= 0 and fuel or 0) / f.fuelMax, 0, 1)
					end
					fpvGui.battBar.Size = UDim2.new(math.max(frac - 0.01, 0), 0, 1, -4)
					fpvGui.battBar.BackgroundColor3 = frac > 0.3 and Color3.fromRGB(255, 210, 80) or Color3.fromRGB(255, 90, 60)
				end
				-- сигнал связи (по HP)
				if fpvGui.sig then
					local bars = math.ceil(math.clamp(hp / maxhp, 0, 1) * 5)
					fpvGui.sig.Text = "СИГНАЛ: " .. string.rep("▮", bars) .. string.rep("▯", 5 - bars)
					fpvGui.sig.TextColor3 = bars >= 3 and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 120, 90)
				end
				-- помехи при повреждении
				if hp / maxhp < 0.5 then
					fpvGui.gui.Enabled = math.random() > 0.06
				end
			else
				wasdGui.tel.Text = string.format("ВЫСОТА: %d\nСКОРОСТЬ: %d\nБОЕПРИПАСЫ: %d\nТОПЛИВО: %s", alt, spd, ammo, fuel >= 0 and (fuel .. " c") or "∞")
				wasdGui.hpBar.Size = UDim2.new(math.max(hp / maxhp, 0) - 0.006, 0, 1, -4)
			end
		end
	end
end)

-- ------------------------------------------------------------
-- РОЙ: формации
-- ------------------------------------------------------------
local formation = "wedge"
local function swarmOffsets(i, n)
	if formation == "cloud" then
		local ang = (i / n) * math.pi * 2
		return Vector3.new(math.cos(ang) * (8 + (i % 4) * 4), ((i * 7) % 5) * 3 - 4, math.sin(ang) * (8 + (i % 3) * 4))
	else
		-- клин за лидером
		local row = math.floor((i - 1) / 3)
		local col = (i - 1) % 3 - 1
		return Vector3.new(col * 8, -row * 2, 8 + row * 10)
	end
end

RunService.Heartbeat:Connect(function(dt)
	if not flying or flying.cfg.Kind ~= "swarm" then return end
	local leaderPos = flying.primary.Position
	local leaderRot = CFrame.Angles(0, flying.yaw, 0)
	for i, unit in ipairs(flying.units) do
		if unit.Parent and unit.PrimaryPart then
			local target = leaderPos + leaderRot:VectorToWorldSpace(swarmOffsets(i, #flying.units))
			local toT = target - unit.PrimaryPart.Position
			local lv = unit.PrimaryPart:FindFirstChildOfClass("LinearVelocity")
			local ao = unit.PrimaryPart:FindFirstChildOfClass("AlignOrientation")
			if lv then
				lv.VectorVelocity = Util.clampMag(toT * 4, flying.cfg.Speed + 30)
			end
			if ao then
				local v = lv and lv.VectorVelocity
				if v and v.Magnitude > 2 then
					ao.CFrame = CFrame.lookAt(Vector3.new(), v.Unit) - Vector3.new()
				end
			end
		end
	end
end)

-- ------------------------------------------------------------
-- СОБЫТИЯ СЕРВЕРА
-- ------------------------------------------------------------
operFXEv.OnClientEvent:Connect(function(payload)
	if payload.type == "launch" and payload.drone then
		local cfg = Config.DRONE_BY_ID[payload.drone:GetAttribute("DroneId")]
		if cfg then startFlying(payload.drone, cfg) end
	elseif payload.type == "hit" then
		toast("ПОПАДАНИЕ ПО ДРОНУ", Color3.fromRGB(255, 90, 80))
	elseif payload.type == "dead" then
		local success = payload.success
		stopFlying()
		-- экран помех 3 сек
		staticGui.gui.Enabled = true
		task.delay(3, function()
			staticGui.gui.Enabled = false
			if isOperator() then
				shopGui.gui.Enabled = true
			end
		end)
		if success then
			-- «килл-момент»: короткий наезд камеры
			camera.FieldOfView = 60
			TweenService:Create(camera, TweenInfo.new(1.2, Enum.EasingStyle.Quad), { FieldOfView = 70 }):Play()
		end
	elseif payload.type == "landed" then
		stopFlying()
		toast("Дрон вернулся на базу. Запускай снова — бесплатно!", Color3.fromRGB(120, 255, 140))
		if isOperator() then shopGui.gui.Enabled = true end
	elseif payload.type == "msg" then
		toast(payload.text or "")
	end
end)

-- маркеры цели «Орлана»
markerFXEv.OnClientEvent:Connect(function(pos)
	local anchor = Instance.new("Part")
	anchor.Anchored = true; anchor.CanCollide = false; anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = pos
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 90, 0, 90)
	gui.AlwaysOnTop = true
	gui.Parent = anchor
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.fromRGB(255, 70, 70)
	lbl.Text = "◎ ЦЕЛЬ"
	lbl.Parent = gui
	anchor.Parent = workspace.FX
	game:GetService("Debris"):AddItem(anchor, 30)
end)

-- ------------------------------------------------------------
-- ИНИЦИАЛИЗАЦИЯ
-- ------------------------------------------------------------
fpvGui = buildFpvHud()
wasdGui = buildWasdHud()
staticGui = buildStatic()
shopGui = buildShop()

-- сервер прислал список дронов, купленных навсегда
unlockEv.OnClientEvent:Connect(function(list)
	if type(list) == "table" then
		unlockedSet = list
		if shopGui and shopGui.refresh then shopGui.refresh() end
	end
end)

local shopBtnGui = mk("ScreenGui", { Name = "ShopButton", ResetOnSpawn = false, DisplayOrder = 20 }, player:WaitForChild("PlayerGui"))
local shopBtn = mk("TextButton", {
	Size = UDim2.new(0, 280, 0, 48),
	Position = UDim2.new(0.5, -140, 1, -70),
	BackgroundColor3 = Color3.fromRGB(30, 110, 210),
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Text = "МАГАЗИН БПЛА  (B)",
	Visible = false,
	AutoButtonColor = true,
}, shopBtnGui)
mk("UICorner", { CornerRadius = UDim.new(0, 10) }, shopBtn)
shopBtn.MouseButton1Click:Connect(function()
	if not isOperator() or flying then return end
	shopGui.gui.Enabled = not shopGui.gui.Enabled
end)

local function refreshCoins()
	local ls = player:FindFirstChild("leaderstats")
	local coins = ls and ls:FindFirstChild("Монеты")
	shopGui.coins.Text = "Монеты: " .. (coins and coins.Value or 0)
end

local shopAutoOpened = false
player.CharacterAdded:Connect(function()
	shopAutoOpened = false
end)

-- Один раз открываем магазин, когда оператор появился в бункере.
-- Повторно не открываем, чтобы кнопку «закрыть» можно было нажать.
task.spawn(function()
	while true do
		task.wait(0.4)
		local op = isOperator() and not flying
		shopBtn.Visible = op
		shopBtn.Text = shopGui.gui.Enabled and "ЗАКРЫТЬ МАГАЗИН  (B)" or "МАГАЗИН БПЛА  (B)"
		if op and nearBunker() and not shopAutoOpened then
			shopAutoOpened = true
			shopGui.gui.Enabled = true
		end
		if shopGui.gui.Enabled then refreshCoins() end
	end
end)
