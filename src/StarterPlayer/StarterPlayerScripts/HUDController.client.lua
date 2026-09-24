-- ============================================================
--  HUDController — общий интерфейс:
--  выбор команды, монеты, килфид, радар-миникарта, таймер раунда,
--  сирена, итоги, погода (дождь), табло (Tab).
-- ============================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local selectTeamEv = Remotes:WaitForChild(Config.REM.SelectTeam)
local killfeedEv = Remotes:WaitForChild(Config.REM.Killfeed)
local radarEv = Remotes:WaitForChild(Config.REM.Radar)
local sirenEv = Remotes:WaitForChild(Config.REM.Siren)
local resultsEv = Remotes:WaitForChild(Config.REM.Results)
local phaseEv = Remotes:WaitForChild(Config.REM.Phase)
local awardEv = Remotes:WaitForChild(Config.REM.Award)

local function mk(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end

local pg = player:WaitForChild("PlayerGui")

-- ============================================================
-- 1. ВЫБОР КОМАНДЫ
-- ============================================================
local teamGui = mk("ScreenGui", { Name = "TeamSelect", ResetOnSpawn = false, IgnoreGuiInset = true }, pg)
mk("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(6, 8, 12), BackgroundTransparency = 0.15, BorderSizePixel = 0 }, teamGui)
mk("TextLabel", { Size = UDim2.new(1, 0, 0, 90), Position = UDim2.new(0, 0, 0, 60), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, Text = "Б Е С П И Л О Т Н И К И", TextSize = 56, TextColor3 = Color3.fromRGB(240, 244, 250) }, teamGui)
mk("TextLabel", { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 150), BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = "Выберите сторону конфликта", TextSize = 22, TextColor3 = Color3.fromRGB(150, 160, 175) }, teamGui)

local function teamButton(x, color, title, subtitle, teamName)
	local btn = mk("TextButton", { Size = UDim2.new(0, 420, 0, 300), Position = UDim2.new(0.5, x, 0.5, -150), BackgroundColor3 = Color3.fromRGB(16, 20, 28), BorderColor3 = color, BorderSizePixel = 2, AutoButtonColor = true, Text = "" }, teamGui)
	mk("UICorner", { CornerRadius = UDim.new(0, 14) }, btn)
	mk("TextLabel", { Size = UDim2.new(1, -20, 0, 50), Position = UDim2.new(0, 10, 0, 60), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, Text = title, TextSize = 34, TextColor3 = color }, btn)
	mk("TextLabel", { Size = UDim2.new(1, -50, 0, 140), Position = UDim2.new(0, 25, 0, 130), BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = subtitle, TextSize = 18, TextColor3 = Color3.fromRGB(200, 210, 220), TextWrapped = true }, btn)
	btn.MouseButton1Click:Connect(function()
		selectTeamEv:FireServer(teamName)
		teamGui.Enabled = false
	end)
	return btn
end
teamButton(-440, Color3.fromRGB(90, 170, 255), "ОПЕРАТОРЫ БПЛА", "Управляйте ударными дронами из подземного бункера. Разрушайте город, зарабатывайте монеты и открывайте новые БПЛА — от «Пчелы» до гиперзвуковой «Молнии».", Config.TEAM_OPS)
teamButton(20, Color3.fromRGB(255, 100, 80), "ЗАЩИТНИКИ ПВО", "Обороняйте город: АК-74М, пулемёт «Корд», ПЗРК «Игла-С», зенитки ЗУ-23-2 и «Панцирь-С1». Сбивайте дроны и не дайте снести город до земли.", Config.TEAM_DEF)

-- показывать только пока нет команды
task.spawn(function()
	while true do
		task.wait(0.5)
		teamGui.Enabled = (player.Team == nil)
	end
end)

-- ============================================================
-- 2. МОНЕТЫ (правый верхний угол)
-- ============================================================
local coinsGui = mk("Frame", { Size = UDim2.new(0, 210, 0, 44), Position = UDim2.new(1, -224, 0, 12), BackgroundColor3 = Color3.fromRGB(12, 14, 20), BackgroundTransparency = 0.25, BorderSizePixel = 0 }, pg)
mk("UICorner", { CornerRadius = UDim.new(0, 8) }, coinsGui)
mk("Frame", { Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(0, 9, 0.5, -13), BackgroundColor3 = Color3.fromRGB(255, 200, 60), BorderSizePixel = 0 }, coinsGui)
local coinsText = mk("TextLabel", { Size = UDim2.new(1, -50, 1, 0), Position = UDim2.new(0, 44, 0, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "0", TextSize = 22, TextColor3 = Color3.fromRGB(255, 210, 80), TextXAlignment = Enum.TextXAlignment.Left }, coinsGui)

task.spawn(function()
	local ls = player:WaitForChild("leaderstats", 30)
	local coins = ls and ls:WaitForChild("Монеты", 30)
	if coins then
		local function upd() coinsText.Text = tostring(coins.Value) end
		coins.Changed:Connect(upd)
		upd()
	end
end)

-- всплывающие награды
local awardQueue = 0
awardEv.OnClientEvent:Connect(function(amount, reason)
	awardQueue = awardQueue + 1
	local myId = awardQueue
	local label = mk("TextLabel", {
		Size = UDim2.new(0, 320, 0, 34), Position = UDim2.new(1, -340, 0, 64),
		BackgroundColor3 = Color3.fromRGB(20, 24, 16), BackgroundTransparency = 0.2,
		Font = Enum.Font.GothamBold, Text = "+" .. amount .. " · " .. (reason or ""), TextSize = 16,
		TextColor3 = Color3.fromRGB(150, 255, 140), ZIndex = 30,
	}, pg)
	mk("UICorner", { CornerRadius = UDim.new(0, 6) }, label)
	TweenService:Create(label, TweenInfo.new(3, Enum.EasingStyle.Quad), { Position = UDim2.new(1, -340, 0, 64 + myId * 40), TextTransparency = 1, BackgroundTransparency = 1 }):Play()
	game:GetService("Debris"):AddItem(label, 3.2)
end)

-- ============================================================
-- 3. КИЛФИД
-- ============================================================
local feedFrame = mk("Frame", { Size = UDim2.new(0, 380, 0, 200), Position = UDim2.new(1, -396, 0, 110), BackgroundTransparency = 1 }, pg)
mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right }, feedFrame)
killfeedEv.OnClientEvent:Connect(function(msg)
	if not msg then return end
	local label = mk("TextLabel", {
		Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = Color3.fromRGB(10, 12, 18), BackgroundTransparency = 0.35,
		Font = Enum.Font.Gotham, Text = msg, TextSize = 15, TextColor3 = Color3.fromRGB(230, 235, 245),
		TextXAlignment = Enum.TextXAlignment.Right, LayoutOrder = os.clock(), ZIndex = 20,
	}, feedFrame)
	local pad = mk("UIPadding", {}, label)
	pad.PaddingRight = UDim.new(0, 8)
	game:GetService("Debris"):AddItem(label, 6)
	-- ограничение длины ленты
	local children = {}
	for _, c in ipairs(feedFrame:GetChildren()) do
		if c:IsA("TextLabel") then table.insert(children, c) end
	end
	if #children > 6 then children[1]:Destroy() end
end)

-- ============================================================
-- 4. ТАЙМЕР РАУНДА (верх центр)
-- ============================================================
local phaseFrame = mk("Frame", { Size = UDim2.new(0, 320, 0, 42), Position = UDim2.new(0.5, -160, 0, 10), BackgroundColor3 = Color3.fromRGB(10, 13, 18), BackgroundTransparency = 0.35, BorderSizePixel = 0 }, pg)
mk("UICorner", { CornerRadius = UDim.new(0, 8) }, phaseFrame)
local phaseText = mk("TextLabel", { Size = UDim2.new(1, -12, 1, 0), Position = UDim2.new(0, 6, 0, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "", TextSize = 20, TextColor3 = Color3.fromRGB(240, 240, 240) }, phaseFrame)

phaseEv.OnClientEvent:Connect(function(phase, timeLeft, extra)
	if phase == "wait" then
		phaseText.Text = "ОЖИДАНИЕ ИГРОКОВ..."
		phaseText.TextColor3 = Color3.fromRGB(200, 200, 200)
	elseif phase == "starting" then
		phaseText.Text = "ВОЗДУШНАЯ ТРЕВОГА: " .. timeLeft
		phaseText.TextColor3 = Color3.fromRGB(255, 120, 90)
	elseif phase == "battle" then
		local m = math.floor(timeLeft / 60)
		local s = timeLeft % 60
		phaseText.Text = string.format("ДО КОНЦА РАУНДА: %d:%02d", m, s)
		phaseText.TextColor3 = timeLeft < 60 and Color3.fromRGB(255, 90, 70) or Color3.fromRGB(240, 240, 240)
	elseif phase == "results" then
		phaseText.Text = "РАУНД ЗАВЕРШЁН"
		phaseText.TextColor3 = Color3.fromRGB(255, 210, 80)
	elseif phase == "weather" then
		applyWeather(extra)
	end
end)

-- ============================================================
-- 5. ПОГОДА: дождь
-- ============================================================
local rainEmitter = nil
function applyWeather(weather)
	if weather == "rain" and not rainEmitter then
		local camPart = Instance.new("Part")
		camPart.Anchored = true; camPart.CanCollide = false; camPart.Transparency = 1
		camPart.Size = Vector3.new(1, 1, 1)
		camPart.Parent = workspace
		local att = Instance.new("Attachment", camPart)
		rainEmitter = Instance.new("ParticleEmitter", att)
		rainEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		rainEmitter.Color = ColorSequence.new(Color3.fromRGB(160, 190, 230))
		rainEmitter.Rate = 400
		rainEmitter.Lifetime = NumberRange.new(0.6)
		rainEmitter.Speed = NumberRange.new(90)
		rainEmitter.EmissionDirection = Enum.NormalId.Bottom
		rainEmitter.Size = NumberSequence.new(0.35)
		rainEmitter.Transparency = NumberSequence.new(0.4)
		rainEmitter.Parent = att
		local sound = Instance.new("Sound", SoundService)
		sound.SoundId = "rbxasset://sounds/impact_water.mp3"
		sound.Looped = true
		sound.Volume = 0.35
		sound:Play()
		RunService.RenderStepped:Connect(function()
			camPart.CFrame = workspace.CurrentCamera.CFrame * CFrame.new(0, 30, 0)
		end)
	elseif weather == "clear" or weather == "cloudy" or weather == "night" then
		if rainEmitter then rainEmitter.Enabled = false end
	end
end

-- ============================================================
-- 6. СИРЕНА
-- ============================================================
local sirenSound = Instance.new("Sound", SoundService)
sirenSound.SoundId = Config.SOUNDS.Siren
sirenSound.Volume = 0.6
sirenSound.Looped = true
local alarmFrame = mk("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5 }, pg)
local alarmText = mk("TextLabel", { Size = UDim2.new(1, 0, 0, 50), Position = UDim2.new(0, 0, 0.22, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, Text = "⚠ ВОЗДУШНАЯ ТРЕВОГА ⚠", TextSize = 34, TextColor3 = Color3.fromRGB(255, 70, 60), ZIndex = 6 }, alarmFrame)

sirenEv.OnClientEvent:Connect(function(kind)
	if kind == "alarm" then
		sirenSound:Play()
		alarmFrame.BackgroundTransparency = 0.88
		TweenService:Create(alarmFrame, TweenInfo.new(10), { BackgroundTransparency = 1 }):Play()
		task.delay(10, function() sirenSound:Stop() alarmText.Visible = false end)
		alarmText.Visible = true
	elseif kind == "warn" then
		sirenSound:Play()
		alarmFrame.BackgroundTransparency = 0.92
		TweenService:Create(alarmFrame, TweenInfo.new(4), { BackgroundTransparency = 1 }):Play()
		task.delay(4, function() sirenSound:Stop() end)
	end
end)

-- ============================================================
-- 7. МИНИКАРТА-РАДАР (защитники: точки дронов; операторы: свой дрон)
-- ============================================================
local mapSize = 190
local mapFrame = mk("Frame", { Size = UDim2.new(0, mapSize, 0, mapSize), Position = UDim2.new(0, 12, 1, -mapSize - 12), BackgroundColor3 = Color3.fromRGB(4, 10, 6), BackgroundTransparency = 0.25, BorderColor3 = Color3.fromRGB(60, 200, 110), BorderSizePixel = 2 }, pg)
mk("UICorner", { CornerRadius = UDim.new(0, 6) }, mapFrame)
-- сетка
for i = 1, 4 do
	local f = i / 5
	mk("Frame", { Size = UDim2.new(0.002, 0, 1, 0), Position = UDim2.new(f, 0, 0, 0), BackgroundColor3 = Color3.fromRGB(30, 120, 70), BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 2 }, mapFrame)
	mk("Frame", { Size = UDim2.new(1, 0, 0.002, 0), Position = UDim2.new(0, 0, f, 0), BackgroundColor3 = Color3.fromRGB(30, 120, 70), BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 2 }, mapFrame)
end
mk("TextLabel", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Font = Enum.Font.Code, Text = "РАДАР ПВО", TextSize = 12, TextColor3 = Color3.fromRGB(90, 220, 130), ZIndex = 2 }, mapFrame)
local mapDots = {}
for i = 1, 20 do
	local dot = mk("Frame", { Size = UDim2.new(0, 7, 0, 7), BackgroundColor3 = Color3.fromRGB(255, 60, 50), Visible = false, BorderSizePixel = 0, ZIndex = 3 }, mapFrame)
	mk("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
	mapDots[i] = dot
end
local selfDot = mk("Frame", { Size = UDim2.new(0, 8, 0, 8), BackgroundColor3 = Color3.fromRGB(90, 170, 255), BorderSizePixel = 0, ZIndex = 4 }, mapFrame)
mk("UICorner", { CornerRadius = UDim.new(1, 0) }, selfDot)

local blips = {}
radarEv.OnClientEvent:Connect(function(b) blips = b or {} end)

local warnBeep = Instance.new("Sound", SoundService)
warnBeep.SoundId = Config.SOUNDS.Beep
warnBeep.Volume = 0.5

RunService.Heartbeat:Connect(function()
	local isDefender = player.Team and player.Team.Name == Config.TEAM_DEF
	local isOperator = player.Team and player.Team.Name == Config.TEAM_OPS
	mapFrame.Visible = isDefender or (isOperator and true)
	local myPos = nil
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then myPos = root.Position end
	-- свой маркер
	local sx, sz = nil, nil
	if myPos then
		sx = math.clamp((myPos.X + Config.MAP_HALF) / (Config.MAP_HALF * 2), 0, 1)
		sz = math.clamp((myPos.Z + Config.MAP_HALF) / (Config.MAP_HALF * 2), 0, 1)
		selfDot.Visible = true
		selfDot.Position = UDim2.new(sx, -4, sz, -4)
	else
		selfDot.Visible = false
	end
	-- блипы дронов (у защитников — с радара; у операторов — свои дроны из воркспейса)
	local points = {}
	if isDefender then
		points = blips
	else
		for _, model in ipairs(workspace.Drones:GetChildren()) do
			local pp = model.PrimaryPart
			if pp then table.insert(points, { x = pp.Position.X, z = pp.Position.Z, y = pp.Position.Y }) end
		end
	end
	local nearest = nil
	for i, dot in ipairs(mapDots) do
		local p = points[i]
		if p then
			dot.Visible = true
			local fx = math.clamp((p.x + Config.MAP_HALF) / (Config.MAP_HALF * 2), 0, 1)
			local fz = math.clamp((p.z + Config.MAP_HALF) / (Config.MAP_HALF * 2), 0, 1)
			dot.Position = UDim2.new(fx, -3.5, fz, -3.5)
			if myPos then
				local d = (Vector3.new(p.x, p.y, p.z) - myPos).Magnitude
				if not nearest or d < nearest then nearest = d end
			end
		else
			dot.Visible = false
		end
	end
	-- сирена близости (< 50 studs) — раз в 1.5 сек
	if nearest and nearest < 50 then
		if not warnBeep.IsPlaying then warnBeep:Play() end
	end
end)

-- ============================================================
-- 8. ТАБЛО (Tab)
-- ============================================================
local boardGui = mk("ScreenGui", { Name = "Scoreboard", ResetOnSpawn = false, DisplayOrder = 40 }, pg)
local board = mk("Frame", { Size = UDim2.new(0, 640, 0, 480), Position = UDim2.new(0.5, -320, 0.5, -240), BackgroundColor3 = Color3.fromRGB(10, 13, 18), BackgroundTransparency = 0.08, BorderColor3 = Color3.fromRGB(70, 130, 200) }, boardGui)
mk("UICorner", { CornerRadius = UDim.new(0, 10) }, board)
mk("TextLabel", { Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, Text = "«БЕСПИЛОТНИКИ» — ТАБЛО", TextSize = 24, TextColor3 = Color3.fromRGB(255, 210, 80) }, board)
local boardText = mk("TextLabel", { Size = UDim2.new(1, -30, 1, -70), Position = UDim2.new(0, 15, 0, 50), BackgroundTransparency = 1, Font = Enum.Font.Code, Text = "", TextSize = 16, TextColor3 = Color3.fromRGB(220, 230, 240), TextYAlignment = Enum.TextYAlignment.Top, TextXAlignment = Enum.TextXAlignment.Left }, board)
boardGui.Enabled = false

UserInputService.InputBegan:Connect(function(input, gpe)
	if input.KeyCode == Enum.KeyCode.Tab then
		boardGui.Enabled = true
		local ops, defs = {}, {}
		for _, pl in ipairs(Players:GetPlayers()) do
			local ls = pl:FindFirstChild("leaderstats")
			local coins = ls and ls:FindFirstChild("Монеты")
			local score = ls and ls:FindFirstChild("Очки")
			local row = string.format("%-16s  %6d монет  %6d очк.", pl.Name, coins and coins.Value or 0, score and score.Value or 0)
			if pl.Team and pl.Team.Name == Config.TEAM_OPS then
				table.insert(ops, row)
			elseif pl.Team then
				table.insert(defs, row)
			else
				table.insert(defs, "[лобби] " .. pl.Name)
			end
		end
		local t = "== ОПЕРАТОРЫ БПЛА ==\n" .. (#ops > 0 and table.concat(ops, "\n") or "— пусто —")
		t = t .. "\n\n== ЗАЩИТНИКИ ПВО ==\n" .. (#defs > 0 and table.concat(defs, "\n") or "— пусто —")
		boardText.Text = t
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Tab then boardGui.Enabled = false end
end)

-- ============================================================
-- 9. ЭКРАН ИТОГОВ
-- ============================================================
local resultGui = mk("ScreenGui", { Name = "Results", ResetOnSpawn = false, DisplayOrder = 50 }, pg)
local rFrame = mk("Frame", { Size = UDim2.new(0, 560, 0, 420), Position = UDim2.new(0.5, -280, 0.5, -210), BackgroundColor3 = Color3.fromRGB(10, 13, 18), BackgroundTransparency = 0.05, BorderColor3 = Color3.fromRGB(255, 210, 80), BorderSizePixel = 2 }, resultGui)
mk("UICorner", { CornerRadius = UDim.new(0, 12) }, rFrame)
mk("TextLabel", { Size = UDim2.new(1, 0, 0, 56), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, Text = "ИТОГИ РАУНДА", TextSize = 32, TextColor3 = Color3.fromRGB(255, 210, 80) }, rFrame)
local rText = mk("TextLabel", { Size = UDim2.new(1, -40, 1, -130), Position = UDim2.new(0, 20, 0, 60), BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = "", TextSize = 19, TextColor3 = Color3.fromRGB(220, 230, 240), TextYAlignment = Enum.TextYAlignment.Top, TextXAlignment = Enum.TextXAlignment.Left }, rFrame)
local closeBtn = mk("TextButton", { Size = UDim2.new(0, 220, 0, 44), Position = UDim2.new(0.5, -110, 1, -60), Font = Enum.Font.GothamBold, Text = "К МАГАЗИНУ / В ЛОББИ", TextSize = 16, TextColor3 = Color3.fromRGB(255, 255, 255), BackgroundColor3 = Color3.fromRGB(40, 110, 200) }, rFrame)
mk("UICorner", { CornerRadius = UDim.new(0, 8) }, closeBtn)
resultGui.Enabled = false

resultsEv.OnClientEvent:Connect(function(data)
	local coinsRows = {}
	local names = {}
	for name, earned in pairs(data.coins or {}) do
		table.insert(names, name)
	end
	table.sort(names, function(a, b) return (data.coins[a] or 0) > (data.coins[b] or 0) end)
	for i = 1, math.min(5, #names) do
		table.insert(coinsRows, string.format("  %s — +%d монет", names[i], data.coins[names[i]]))
	end
	local t = string.format(
		"РАЗРУШЕНО ГОРОДА: %d%%\nСБИТО ДРОНОВ: %d\n\n",
		data.destPct or 0, data.dronesDown or 0
	)
	t = t .. "MVP ОПЕРАТОРОВ: " .. (data.mvpOps and (data.mvpOps.name .. " (" .. data.mvpOps.score .. " очк.)") or "—") .. "\n"
	t = t .. "MVP ЗАЩИТНИКОВ: " .. (data.mvpDef and (data.mvpDef.name .. " (" .. data.mvpDef.score .. " очк.)") or "—") .. "\n\n"
	t = t .. "ЗАРАБОТАНО ЗА РАУНД:\n" .. (#coinsRows > 0 and table.concat(coinsRows, "\n") or "  —")
	rText.Text = t
	resultGui.Enabled = true
end)

closeBtn.MouseButton1Click:Connect(function()
	resultGui.Enabled = false
end)
