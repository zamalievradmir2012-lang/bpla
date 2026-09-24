-- ============================================================
--  Main — точка входа сервера «БЕСПИЛОТНИКИ»
--  Освещение, команды, лобби+бункер, раунды, погода, день/ночь.
-- ============================================================
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)

-- Сервисы (порядок важен)
local Destruction = require(script.Parent.Destruction)
local MapGenerator = require(script.Parent.MapGenerator)
local Economy = require(script.Parent.Economy)
local DroneService = require(script.Parent.DroneService)
local WeaponService = require(script.Parent.WeaponService)
local NpcService = require(script.Parent.NpcService)

local Main = {}

-- ------------------------------------------------------------
-- 1. LIGHTING (Future, Atmosphere, Bloom, DoF, SunRays)
-- ------------------------------------------------------------
local function setupLighting()
	local ok, err = pcall(function()
	Lighting.Technology = Enum.Technology.Future
	Lighting.Brightness = 2
	Lighting.ClockTime = 12
	Lighting.GeographicLatitude = 52 -- средняя полоса
	Lighting.GlobalShadows = true
	Lighting.ExposureCompensation = 0.05
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6

	local atmo = Instance.new("Atmosphere")
	atmo.Density = 0.3
	atmo.Offset = 0.1
	atmo.Color = Color3.fromRGB(199, 199, 199)
	atmo.Decay = Color3.fromRGB(220, 180, 140) -- тёплый
	atmo.Glare = 0.2
	atmo.Haze = 1.4
	atmo.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Size = 24
	bloom.Threshold = 1.1
	bloom.Parent = Lighting

	local dof = Instance.new("DepthOfFieldEffect")
	dof.FarIntensity = 0.08
	dof.FocusDistance = 80
	dof.InFocusRadius = 300
	dof.NearIntensity = 0.1
	dof.Parent = Lighting

	local sun = Instance.new("SunRaysEffect")
	sun.Intensity = 0.08
	sun.Spread = 0.8
	sun.Parent = Lighting

	-- облака
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.4
		clouds.Density = 0.6
		clouds.Parent = terrain
	end
	end)
	if not ok then
		warn("[БЕСПИЛОТНИКИ] Освещение не настроено, игра продолжается: " .. tostring(err))
	end
end

-- ------------------------------------------------------------
-- 2. REMOTES + КОМАНДЫ
-- ------------------------------------------------------------
local Remotes
local teamOps, teamDef

local function setupRemotesAndTeams()
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
	local adminEv = Instance.new("RemoteEvent")
	adminEv.Name = "AdminCoins"
	adminEv.Parent = Remotes
	for _, name in pairs(Config.REM) do
		if name == Config.REM.LaunchDrone or name == Config.REM.BuyUpgrade then
			local rf = Instance.new("RemoteFunction")
			rf.Name = name
			rf.Parent = Remotes
		else
			local re = Instance.new("RemoteEvent")
			re.Name = name
			re.Parent = Remotes
		end
	end

	teamOps = Instance.new("Team")
	teamOps.Name = Config.TEAM_OPS
	teamOps.TeamColor = BrickColor.new("Bright blue")
	teamOps.AutoAssignable = false
	teamOps.Parent = Teams

	teamDef = Instance.new("Team")
	teamDef.Name = Config.TEAM_DEF
	teamDef.TeamColor = BrickColor.new("Bright red")
	teamDef.AutoAssignable = false
	teamDef.Parent = Teams
end

-- ------------------------------------------------------------
-- 3. ЛОББИ
-- ------------------------------------------------------------
local lobbySpawn
local function buildLobby()
	local base = Config.LOBBY_POS
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	folder.Parent = workspace

	local plat = Util.part({ Size = Vector3.new(140, 2, 140), CFrame = CFrame.new(base), Color = Color3.fromRGB(60, 62, 70), Material = Enum.Material.Concrete }, folder)
	-- вертолётная площадка
	local pad = Util.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 30, 30), CFrame = CFrame.new(base + Vector3.new(35, 1.3, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(40, 42, 48), Material = Enum.Material.Concrete }, folder)
	local hLetter = Util.part({ Size = Vector3.new(0.1, 10, 3), CFrame = CFrame.new(base + Vector3.new(35, 1.6, 0)) * CFrame.Angles(0, 0, 0), Color = Color3.fromRGB(240, 240, 240), Material = Enum.Material.SmoothPlastic, CanCollide = false }, folder)
	Util.part({ Size = Vector3.new(0.1, 3, 6), CFrame = CFrame.new(base + Vector3.new(35, 1.6, 0)), Color = Color3.fromRGB(240, 240, 240), Material = Enum.Material.SmoothPlastic, CanCollide = false }, folder)
	-- перила
	for _, sx in ipairs({ -1, 1 }) do
		Util.part({ Size = Vector3.new(2, 4, 140), CFrame = CFrame.new(base + Vector3.new(sx * 69, 2.5, 0)), Color = Color3.fromRGB(200, 180, 60), Material = Enum.Material.Metal, Transparency = 0.4 }, folder)
		Util.part({ Size = Vector3.new(140, 4, 2), CFrame = CFrame.new(base + Vector3.new(0, 2.5, sx * 69)), Color = Color3.fromRGB(200, 180, 60), Material = Enum.Material.Metal, Transparency = 0.4 }, folder)
	end
	-- спавн
	lobbySpawn = Instance.new("SpawnLocation")
	lobbySpawn.Size = Vector3.new(12, 1, 12)
	lobbySpawn.Neutral = true
	lobbySpawn.Anchored = true
	lobbySpawn.CFrame = CFrame.new(base + Vector3.new(0, 1.5, -40))
	lobbySpawn.Duration = 0
	lobbySpawn.Parent = folder

	-- стенды с моделями дронов
	local ConfigShared = Config
	for i, drone in ipairs(ConfigShared.DRONES) do
		local standPos = base + Vector3.new(-55 + ((i - 1) % 5) * 22, 0, 35 + math.floor((i - 1) / 5) * 22)
		Util.part({ Size = Vector3.new(8, 6, 8), CFrame = CFrame.new(standPos + Vector3.new(0, 3, 0)), Color = Color3.fromRGB(35, 37, 44), Material = Enum.Material.Metal }, folder)
		local label = Util.part({ Size = Vector3.new(7, 2.4, 0.3), CFrame = CFrame.new(standPos + Vector3.new(0, 7.5, -3.8)), Color = Color3.fromRGB(20, 22, 28), Material = Enum.Material.SmoothPlastic }, folder)
		local sg = Instance.new("SurfaceGui", label)
		sg.Face = Enum.NormalId.Front
		local tl = Instance.new("TextLabel", sg)
		tl.Size = UDim2.new(1, 0, 1, 0)
		tl.BackgroundTransparency = 1
		tl.Font = Enum.Font.GothamBold
		tl.TextScaled = true
		tl.TextColor3 = Color3.fromRGB(120, 220, 255)
		tl.Text = drone.Name .. "\n" .. (drone.Price == 0 and "БЕСПЛАТНО" or (drone.Price .. " монет"))
		local model = require(ReplicatedStorage.Shared.DroneFactory).build(drone.Id)
		if model then
			model:PivotTo(CFrame.new(standPos + Vector3.new(0, 9, 0)) * CFrame.Angles(0, math.rad(35), 0))
			model.Parent = folder
		end
	end

	-- табло лидеров (обновляется сервером)
	local board = Util.part({ Size = Vector3.new(40, 16, 1), CFrame = CFrame.new(base + Vector3.new(0, 10, 66)), Color = Color3.fromRGB(15, 18, 24), Material = Enum.Material.Metal }, folder)
	local sg = Instance.new("SurfaceGui", board)
	sg.Face = Enum.NormalId.Back
	sg.Name = "LeaderboardGui"
	local title = Instance.new("TextLabel", sg)
	title.Size = UDim2.new(1, 0, 0.15, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 210, 80)
	title.Text = "ЛИДЕРЫ — «БЕСПИЛОТНИКИ»"
	local list = Instance.new("TextLabel", sg)
	list.Name = "List"
	list.Position = UDim2.new(0, 0, 0.15, 0)
	list.Size = UDim2.new(1, 0, 0.85, 0)
	list.BackgroundTransparency = 1
	list.Font = Enum.Font.Gotham
	list.TextScaled = true
	list.TextColor3 = Color3.fromRGB(220, 230, 240)
	list.Text = "..."

	-- пады выбора команды
	local function teamPad(offset, team, color, text)
		local padPart = Util.part({ Size = Vector3.new(16, 1, 16), CFrame = CFrame.new(base + offset) * CFrame.Angles(0, math.rad(45), 0), Color = color, Material = Enum.Material.Neon }, folder)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = text
		prompt.ObjectText = "Смена команды"
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 12
		prompt.Parent = padPart
		prompt.Triggered:Connect(function(pl)
			-- проверка баланса
			local count = 0
			for _, p in ipairs(Players:GetPlayers()) do
				if p.Team == team then count = count + 1 end
			end
			if pl.Team ~= team and count >= Config.TEAM_CAP then return end
			pl.Team = team
			pl:LoadCharacter()
		end)
	end
	teamPad(Vector3.new(-30, 1.2, -20), teamOps, Color3.fromRGB(60, 140, 255), "Стать ОПЕРАТОРОМ БПЛА")
	teamPad(Vector3.new(30, 1.2, -20), teamDef, Color3.fromRGB(255, 80, 60), "Стать ЗАЩИТНИКОМ ПВО")

	return folder
end

-- ------------------------------------------------------------
-- 4. БУНКЕР ОПЕРАТОРОВ
-- ------------------------------------------------------------
local function buildBunker()
	local base = Config.BUNKER_POS
	local folder = Instance.new("Folder")
	folder.Name = "Bunker"
	folder.Parent = workspace

	local W, D, H = 80, 60, 38
	Util.part({ Size = Vector3.new(W, 2, D), CFrame = CFrame.new(base), Color = Color3.fromRGB(45, 48, 52), Material = Enum.Material.Concrete }, folder)
	Util.part({ Size = Vector3.new(W, 2, D), CFrame = CFrame.new(base + Vector3.new(0, H, 0)), Color = Color3.fromRGB(38, 40, 44), Material = Enum.Material.Concrete }, folder)
	for _, sx in ipairs({ -1, 1 }) do
		Util.part({ Size = Vector3.new(2, H, D), CFrame = CFrame.new(base + Vector3.new(sx * W / 2, H / 2, 0)), Color = Color3.fromRGB(52, 56, 60), Material = Enum.Material.Concrete }, folder)
	end
	-- северная стена глухая, южная — с дверью, иначе оператор, упавший под пол, не может войти
	Util.part({ Size = Vector3.new(W, H, 2), CFrame = CFrame.new(base + Vector3.new(0, H / 2, -D / 2)), Color = Color3.fromRGB(52, 56, 60), Material = Enum.Material.Concrete }, folder)
	local doorW = 10
	local sideW = (W - doorW) / 2
	Util.part({ Size = Vector3.new(sideW, H, 2), CFrame = CFrame.new(base + Vector3.new(-(doorW / 2 + sideW / 2), H / 2, D / 2)), Color = Color3.fromRGB(52, 56, 60), Material = Enum.Material.Concrete }, folder)
	Util.part({ Size = Vector3.new(sideW, H, 2), CFrame = CFrame.new(base + Vector3.new(doorW / 2 + sideW / 2, H / 2, D / 2)), Color = Color3.fromRGB(52, 56, 60), Material = Enum.Material.Concrete }, folder)
	Util.part({ Size = Vector3.new(doorW, H - 12, 2), CFrame = CFrame.new(base + Vector3.new(0, 12 + (H - 12) / 2, D / 2)), Color = Color3.fromRGB(52, 56, 60), Material = Enum.Material.Concrete }, folder)
	-- бункер за краем террейна: свой остров и дамба к карте, иначе из двери — пустота
	Util.part({ Size = Vector3.new(160, 10, 120), CFrame = CFrame.new(base + Vector3.new(0, -6, 0)), Color = Color3.fromRGB(74, 76, 70), Material = Enum.Material.Slate }, folder)
	Util.part({ Size = Vector3.new(16, 1, 22), CFrame = CFrame.new(base + Vector3.new(0, 0.5, D / 2 + 8)), Color = Color3.fromRGB(96, 98, 94), Material = Enum.Material.Concrete }, folder)
	local rampAng = -math.atan(16 / 490)
	Util.part({ Size = Vector3.new(28, 3, 490), CFrame = CFrame.new(0, 9, -1805) * CFrame.Angles(rampAng, 0, 0), Color = Color3.fromRGB(92, 94, 88), Material = Enum.Material.Ground }, folder)
	-- антенны на крыше
	for i = 1, 3 do
		Util.part({ Size = Vector3.new(0.6, 18, 0.6), CFrame = CFrame.new(base + Vector3.new(-20 + i * 20, H + 9, -20)), Color = Color3.fromRGB(200, 200, 205), Material = Enum.Material.Metal }, folder)
		Util.part({ Size = Vector3.new(4, 0.4, 0.4), CFrame = CFrame.new(base + Vector3.new(-20 + i * 20, H + 16, -20)), Color = Color3.fromRGB(255, 80, 80), Material = Enum.Material.Neon }, folder)
	end
	-- взлётная полоса в открытом небе, не на крыше бункера
	Util.part({ Size = Vector3.new(70, 2, 130), CFrame = CFrame.new(Config.PAD_POS - Vector3.new(0, 1, 0)), Color = Color3.fromRGB(34, 36, 40), Material = Enum.Material.Concrete }, folder)
	Util.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 28, 28), CFrame = CFrame.new(Config.PAD_POS + Vector3.new(0, 0.2, -20)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(80, 220, 120), Material = Enum.Material.Neon, CanCollide = false }, folder)
	for stripe = -2, 2 do
		Util.part({ Size = Vector3.new(1.4, 0.12, 14), CFrame = CFrame.new(Config.PAD_POS + Vector3.new(0, 0.15, stripe * 22)), Color = Color3.fromRGB(230, 230, 220), Material = Enum.Material.Neon, CanCollide = false }, folder)
	end
	for _, px in ipairs({ -24, 24 }) do
		for _, pz in ipairs({ -40, 40 }) do
			Util.part({ Size = Vector3.new(2.4, 54, 2.4), CFrame = CFrame.new(Config.PAD_POS + Vector3.new(px, -28, pz)), Color = Color3.fromRGB(70, 74, 78), Material = Enum.Material.Metal }, folder)
		end
	end
	-- посадочный маяк
	local beacon = Instance.new("Part")
	beacon.Anchored = true; beacon.CanCollide = false; beacon.Transparency = 1
	beacon.Size = Vector3.new(1, 1, 1)
	beacon.Position = Config.PAD_POS + Vector3.new(0, 20, 0)
	local bl = Instance.new("PointLight", beacon)
	bl.Color = Color3.fromRGB(80, 220, 120); bl.Brightness = 4; bl.Range = 40
	beacon.Parent = folder

	-- интерьер: мониторы, столы с картами, сиденья
	for _, off in ipairs({ Vector3.new(0, H - 6, 0), Vector3.new(-20, 8, 0), Vector3.new(20, 8, 10) }) do
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(180, 210, 255)
		light.Brightness = 3
		light.Range = 50
		light.Shadows = false
		local lampPart = Util.part({ Size = Vector3.new(1, 1, 1), Transparency = 1, CanCollide = false, CFrame = CFrame.new(base + off) }, folder)
		light.Parent = lampPart
	end

	for i = 1, 3 do
		local mx = base + Vector3.new(-24 + i * 24, 8, -D / 2 + 4)
		local screen = Util.part({ Size = Vector3.new(14, 9, 0.6), CFrame = CFrame.new(mx + Vector3.new(0, 6, 0)), Color = Color3.fromRGB(10, 14, 12), Material = Enum.Material.Glass }, folder)
		Util.part({ Size = Vector3.new(16, 1, 4), CFrame = CFrame.new(mx + Vector3.new(0, 1, 1)), Color = Color3.fromRGB(60, 64, 70), Material = Enum.Material.Metal }, folder)
		local sg = Instance.new("SurfaceGui", screen)
		sg.Face = Enum.NormalId.Front
		-- рамка
		local frame = Instance.new("Frame", sg)
		frame.Size = UDim2.new(1, 0, 1, 0)
		frame.BackgroundColor3 = Color3.fromRGB(5, 18, 10)
		frame.BorderColor3 = Color3.fromRGB(40, 160, 90)
		frame.BorderSizePixel = 4
		-- сетка радара
		for gx = 1, 5 do
			local line = Instance.new("Frame", sg)
			line.Size = UDim2.new(0.002, 0, 1, 0)
			line.Position = UDim2.new(gx / 6, 0, 0, 0)
			line.BackgroundColor3 = Color3.fromRGB(30, 120, 70)
			line.BorderSizePixel = 0
			local line2 = line:Clone()
			line2.Size = UDim2.new(1, 0, 0.002, 0)
			line2.Position = UDim2.new(0, 0, gx / 6, 0)
			line2.Parent = sg
		end
		local caption = Instance.new("TextLabel", sg)
		caption.Size = UDim2.new(1, 0, 0.18, 0)
		caption.BackgroundTransparency = 1
		caption.Font = Enum.Font.Code
		caption.TextScaled = true
		caption.TextColor3 = Color3.fromRGB(60, 220, 120)
		local captions = { "РАДАР ВОЗДУШНОЙ ОБСТАНОВКИ", "КАНАЛ УПРАВЛЕНИЯ БПЛА", "СПУТНИКОВАЯ СВЯЗКА" }
		caption.Text = captions[i]
	end
	-- стол с картой
	local mapTable = Util.part({ Size = Vector3.new(20, 2, 14), CFrame = CFrame.new(base + Vector3.new(0, 2.5, 10)), Color = Color3.fromRGB(70, 60, 45), Material = Enum.Material.WoodPlanks }, folder)
	local mapSurface = Util.part({ Size = Vector3.new(18, 0.2, 12), CFrame = CFrame.new(base + Vector3.new(0, 3.6, 10)), Color = Color3.fromRGB(200, 190, 160), Material = Enum.Material.SmoothPlastic }, folder)
	local sg2 = Instance.new("SurfaceGui", mapSurface)
	sg2.Face = Enum.NormalId.Top
	local mapLabel = Instance.new("TextLabel", sg2)
	mapLabel.Size = UDim2.new(1, 0, 1, 0)
	mapLabel.BackgroundTransparency = 1
	mapLabel.Font = Enum.Font.Code
	mapLabel.TextScaled = true
	mapLabel.TextColor3 = Color3.fromRGB(120, 60, 40)
	mapLabel.Text = "ГОРОД · СЕКТОР 7 · КВАДРАТ 12-34"
	-- табуреты без Seat: настоящий Seat сразу сажает игрока и магазин не открывается
	for i = 1, 4 do
		Util.part({ Size = Vector3.new(4, 0.8, 4), CFrame = CFrame.new(base + Vector3.new(-15 + i * 10, 1.5, 18)), Color = Color3.fromRGB(30, 34, 40), Material = Enum.Material.Metal }, folder)
	end

	-- командный спавн операторов: стоит НА полу, не внутри плиты
	local opSpawn = Instance.new("SpawnLocation")
	opSpawn.Name = "OperatorSpawn"
	opSpawn.Size = Vector3.new(8, 1, 8)
	opSpawn.Anchored = true
	opSpawn.Neutral = false
	opSpawn.AllowTeamChangeOnTouch = false
	opSpawn.TeamColor = BrickColor.new("Bright blue")
	opSpawn.Duration = 0
	opSpawn.CFrame = CFrame.new(base + Vector3.new(-22, 1.5, -16))
	opSpawn.Color = Color3.fromRGB(60, 140, 255)
	opSpawn.Material = Enum.Material.Neon
	opSpawn.Parent = folder
end

-- ------------------------------------------------------------
-- 5. СПАВН ИГРОКОВ
-- ------------------------------------------------------------
local function standUp(char, cf)
	local root = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 5)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root then return end
	char:PivotTo(cf)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	if hum then
		hum.Sit = false
		hum.PlatformStand = false
		pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
	end
end

local function onCharacterAdded(player, char)
	task.wait(0.15)
	if not char.Parent then return end
	if player.Team == teamOps then
		-- HRP на 5 studs выше верха пола (пол: центр y=4, верх y=5). Раньше y=7
		-- ставил ноги внутрь плиты, и персонаж проваливался под бункер.
		local stand = CFrame.new(Config.BUNKER_POS + Vector3.new(-22, 6, -16))
		standUp(char, stand)
		task.delay(0.4, function()
			if char.Parent and player.Team == teamOps then standUp(char, stand) end
		end)
	elseif player.Team == teamDef then
		local spawn = Config.DEF_SPAWNS[math.random(1, #Config.DEF_SPAWNS)]
		standUp(char, CFrame.new(spawn + Vector3.new(0, 6, 0)))
	end
end

-- ------------------------------------------------------------
-- 6. ХУКИ ОЧКОВ / КИЛФИДА
-- ------------------------------------------------------------
local function getStat(pl, name)
	local ls = pl:FindFirstChild("leaderstats")
	local v = ls and ls:FindFirstChild(name)
	return v and v.Value or 0
end
local function getScore(pl) return getStat(pl, "Очки") end

local function broadcastKillfeed(msg)
	local ev = Remotes:FindFirstChild(Config.REM.Killfeed)
	if ev then
		for _, pl in ipairs(Players:GetPlayers()) do ev:FireClient(pl, msg) end
	end
end

local function setupHooks()
	DroneService.KillfeedFn = broadcastKillfeed
	WeaponService.KillfeedFn = broadcastKillfeed

	local prevBuilding = Destruction.OnBuildingDestroyed
	Destruction.OnBuildingDestroyed = function(player, category, name, center)
		if prevBuilding then prevBuilding(player, category, name, center) end
		local reward = Config.BUILDING_REWARD[category]
		local nice = Config.BUILDING_SCORE_NAME[category] or name
		if player and player.Parent then
			Economy.Add(player, reward, "Уничтожено: " .. nice)
			Economy.AddScore(player, reward)
		end
		broadcastKillfeed((player and player.Name or "Кто-то") .. " уничтожил: " .. nice .. " (+" .. tostring(reward) .. ")")
	end

	local prevPart = Destruction.OnPartDestroyed
	Destruction.OnPartDestroyed = function(player, kind)
		if prevPart then prevPart(player, kind) end
		if player and player.Parent then Economy.AddScore(player, 1) end
	end

	-- убийство защитника взрывом: +25 оператору
	local humDied = function(victimPlayer, killer)
		if victimPlayer.Team == teamDef and killer and killer:IsA("Player") and killer.Team == teamOps then
			Economy.Add(killer, Config.KILL_COINS, "Уничтожен защитник")
			Economy.AddScore(killer, 10)
			broadcastKillfeed(killer.Name .. " ликвидировал защитника " .. victimPlayer.Name .. " (+" .. Config.KILL_COINS .. ")")
		end
	end
	Players.PlayerAdded:Connect(function(pl)
		pl.CharacterAdded:Connect(function(char)
			local hum = char:WaitForChild("Humanoid", 10)
			if hum then
				hum.Died:Connect(function()
					-- кто взрывом? ищем недавний взрыв через атрибут на игроке (упрощение: последняя жертва взрыва)
					local killerToken = hum:FindFirstChild("LastExplosionKiller")
					if killerToken then
						local killer = Players:FindFirstChild(killerToken.Value)
						if killer then humDied(pl, killer) end
					end
				end)
			end
		end)
	end)

	-- урон игрокам от взрывов с указанием убийцы:
	local prevExplosion = Destruction.OnExplosion
	Destruction.OnExplosion = function(pos, radius, player)
		if prevExplosion then prevExplosion(pos, radius, player) end
		if not (player and player:IsA("Player") and player.Team == teamOps) then return end
		for _, pl in ipairs(Players:GetPlayers()) do
			local char = pl.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if hum and root and hum.Health > 0 and (root.Position - pos).Magnitude < radius then
				local tag = hum:FindFirstChild("LastExplosionKiller") or Instance.new("StringValue")
				tag.Name = "LastExplosionKiller"
				tag.Value = player.Name
				tag.Parent = hum
				task.delay(3, function() if tag.Parent then tag:Destroy() end end)
			end
		end
	end
end

-- ------------------------------------------------------------
-- 7. ДЕНЬ/НОЧЬ + СВЕТОФОРЫ + ОКНА
-- ------------------------------------------------------------
local nightOn = false
local function setNight(on)
	if nightOn == on then return end
	nightOn = on
	-- фонари
	for _, light in ipairs(MapGenerator.NightLights) do
		light.Brightness = on and 1.6 or 0
	end
	-- окна: 60% светятся ночью
	for i, win in ipairs(MapGenerator.Windows) do
		if win.Parent then
			if on then
				if math.random() < 0.6 then
					win.Material = Enum.Material.Neon
					win.Color = Color3.fromRGB(255, 214, 130)
					win.Transparency = 0.15
				end
			else
				win.Material = Enum.Material.Glass
				win.Color = Color3.fromRGB(140, 170, 190)
				win.Transparency = 0.45
			end
		end
	end
	-- прожекторы
	WeaponService.SetSpotlightsNight(on)
end

local trafficPhase = 0
local function trafficTick()
	trafficPhase = 1 - trafficPhase
	for _, tl in ipairs(MapGenerator.TrafficLights) do
		local green = (tl.axis == "NS") == (trafficPhase == 1)
		-- bulbs: 1=red, 2=yellow, 3=green
		for bi, b in ipairs(tl.bulbs) do
			if b.part.Parent then
				if bi == 3 then
					b.part.Material = green and Enum.Material.Neon or Enum.Material.SmoothPlastic
					b.part.Transparency = green and 0 or 0.4
				elseif bi == 1 then
					b.part.Material = (not green) and Enum.Material.Neon or Enum.Material.SmoothPlastic
					b.part.Transparency = (not green) and 0 or 0.4
				else
					b.part.Transparency = 0.4
					b.part.Material = Enum.Material.SmoothPlastic
				end
			end
		end
	end
end

local function startDayNightLoop()
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		-- цикл суток 20 минут
		accum = accum + dt
		if accum >= 1 then
			accum = accum - 1
			local t = Lighting.ClockTime + 24 / Config.DAY_CYCLE
			Lighting.ClockTime = t % 24
			local isNight = Lighting.ClockTime >= 18.5 or Lighting.ClockTime < 5.5
			setNight(isNight)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(10)
			trafficTick()
		end
	end)
end

-- ------------------------------------------------------------
-- 8. ПОГОДА
-- ------------------------------------------------------------
local currentWeather = "clear"
local function pickWeather()
	local weathers = { "clear", "cloudy", "rain", "night" }
	currentWeather = weathers[math.random(1, #weathers)]
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if clouds then
		clouds.Cover = (currentWeather == "clear") and 0.3 or 0.75
	end
	if atmo then
		atmo.Density = (currentWeather == "clear") and 0.3 or 0.42
	end
	if currentWeather == "night" then
		Lighting.ClockTime = 0.5
	end
	local ev = Remotes:FindFirstChild(Config.REM.Phase)
	if ev then
		for _, pl in ipairs(Players:GetPlayers()) do
			ev:FireClient(pl, "weather", 0, currentWeather)
		end
	end
end

-- ------------------------------------------------------------
-- 9. РАУНДЫ
-- ------------------------------------------------------------
local function countTeam(team)
	local n = 0
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Team == team then n = n + 1 end
	end
	return n
end

local function broadcastPhase(phase, timeLeft, extra)
	local ev = Remotes:FindFirstChild(Config.REM.Phase)
	if ev then
		for _, pl in ipairs(Players:GetPlayers()) do
			ev:FireClient(pl, phase, timeLeft, extra)
		end
	end
end

local function alarm(duration)
	local ev = Remotes:FindFirstChild(Config.REM.Siren)
	if ev then
		for _, pl in ipairs(Players:GetPlayers()) do ev:FireClient(pl, "alarm") end
	end
	-- позиционный звук сирены над городом
	Util.sound3d(Config.SOUNDS.Siren, Vector3.new(0, 60, 0), 3, 1, 2000, duration + 2)
end

local function playRound()
	-- ОЖИДАНИЕ
	while countTeam(teamOps) < 1 or countTeam(teamDef) < 1 do
		broadcastPhase("wait", 0)
		task.wait(2)
	end
	-- СТАРТ: сирена 10 секунд
	alarm(10)
	for t = 10, 1, -1 do
		broadcastPhase("starting", t)
		task.wait(1)
	end
	pickWeather()
	Economy.ResetRound()

	-- БОЙ
	local startTime = os.clock()
	local timeLeft = Config.ROUND_TIME
	local timerConn
	timerConn = task.spawn(function()
		while timeLeft > 0 do
			task.wait(1)
			timeLeft = timeLeft - 1
			if timeLeft % 10 == 0 then broadcastPhase("battle", timeLeft) end
		end
	end)
	broadcastPhase("battle", timeLeft)

	-- следим за разрушением города
	while timeLeft > 0 do
		task.wait(3)
		local st = Destruction.Stats()
		if st.total > 100 and (st.destroyed / st.total) > 0.9 then
			break -- город почти полностью разрушен
		end
	end
	broadcastPhase("results", 0)

	-- ИТОГИ
	local st = Destruction.Stats()
	local destPct = st.total > 0 and math.floor(st.destroyed / st.total * 100) or 0
	local dronesDown = 0
	local mvpOps, mvpDef = nil, nil
	for _, pl in ipairs(Players:GetPlayers()) do
		dronesDown = dronesDown + Economy.Kills(pl)
		local score = getScore(pl)
		if pl.Team == teamOps then
			if not mvpOps or score > mvpOps.score then
				mvpOps = { name = pl.Name, score = score }
			end
		elseif pl.Team == teamDef then
			if not mvpDef or score > mvpDef.score then
				mvpDef = { name = pl.Name, score = score }
			end
		end
	end
	-- бонус защитникам за уцелевший город
	if destPct < 20 then
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl.Team == teamDef then
				Economy.Add(pl, Config.CITY_ALIVE_BONUS, "Город устоял")
			end
		end
	end
	local results = {
		destPct = destPct,
		dronesDown = dronesDown,
		mvpOps = mvpOps,
		mvpDef = mvpDef,
		coins = {},
	}
	for _, pl in ipairs(Players:GetPlayers()) do
		results.coins[pl.Name] = Economy.RoundEarned(pl)
	end
	local resultsEv = Remotes:FindFirstChild(Config.REM.Results)
	if resultsEv then
		for _, pl in ipairs(Players:GetPlayers()) do resultsEv:FireClient(pl, results) end
	end
	task.wait(20)

	-- ВОССТАНОВЛЕНИЕ ГОРОДА
	MapGenerator.Rebuild()
	WeaponService.RebuildStationary()
	NpcService.Rebuild()
	Destruction.SetExcludes({ workspace.Debris, workspace.FX, workspace.Drones })
	DroneService.SetRayExcludes({ workspace.Debris, workspace.FX, workspace.Drones, workspace:FindFirstChild("Bunker") })
	Economy.ResetRound()
end

-- ------------------------------------------------------------
local function main()
	Players.RespawnTime = Config.RESPAWN_TIME
	-- Не выключать CharacterAutoLoads. Иначе любая ошибка до LoadCharacter
	-- оставляет Play с застывшей камерой в небе — чат при этом работает.
	Players.CharacterAutoLoads = true
	setupLighting()
	setupRemotesAndTeams()

	-- рабочие папки
	for _, name in ipairs({ "Drones", "Debris", "FX" }) do
		if not workspace:FindFirstChild(name) then
			local f = Instance.new("Folder")
			f.Name = name
			f.Parent = workspace
		end
	end

	-- сервисы, которым карта ещё не нужна
	Destruction.Remotes = Remotes
	DroneService.SetRemotes(Remotes)
	DroneService.SetEconomy(Economy)
	WeaponService.SetRemotes(Remotes)
	WeaponService.SetEconomy(Economy)
	WeaponService.SetDroneService(DroneService)
	WeaponService.SetMapGenerator(MapGenerator)
	Economy.SetRemotes(Remotes)
	Economy.Init()
	NpcService.SetMapGenerator(MapGenerator)

	-- Лобби и бункер ДО города. Пока CharacterAutoLoads = false и персонажа нет,
	-- стандартная камера Play не крутится мышкой — игрок видит застывшее небо.
	buildBunker()
	buildLobby()
	setupHooks()
	WeaponService.BindPlayers()

	local function bindSpawn(pl)
		pl.CharacterAdded:Connect(function(char)
			task.spawn(onCharacterAdded, pl, char)
		end)
	end
	Players.PlayerAdded:Connect(function(pl)
		bindSpawn(pl)
		if Players.CharacterAutoLoads and not pl.Character then
			pl:LoadCharacter()
		end
	end)
	for _, pl in ipairs(Players:GetPlayers()) do
		bindSpawn(pl)
	end

	Players.CharacterAutoLoads = true
	for _, pl in ipairs(Players:GetPlayers()) do
		if not pl.Character then pl:LoadCharacter() end
	end
	print("[БЕСПИЛОТНИКИ] Игрок заспавнен, камера должна слушаться мышь. Город строится...")
	task.wait()

	-- тяжёлая генерация уже не может оставить игрока без персонажа
	MapGenerator.Generate()
	Destruction.SetExcludes({ workspace.Debris, workspace.FX, workspace.Drones })
	DroneService.SetRayExcludes({ workspace.Debris, workspace.FX, workspace.Drones, workspace:FindFirstChild("Bunker") })
	DroneService.Init()
	WeaponService.Init()
	NpcService.Init()
	startDayNightLoop()
	print("[БЕСПИЛОТНИКИ] Город готов")

	-- табло лидеров
	task.spawn(function()
		while true do
			task.wait(15)
			local board = workspace:FindFirstChild("Lobby")
			board = board and board:FindFirstChild("LeaderboardGui", true)
			if board then
				local rows = {}
				local sorted = {}
				for _, pl in ipairs(Players:GetPlayers()) do
					table.insert(sorted, pl)
				end
				table.sort(sorted, function(a, b)
					return getStat(a, "Монеты") > getStat(b, "Монеты")
				end)
				for i = 1, math.min(8, #sorted) do
					local pl = sorted[i]
					table.insert(rows, i .. ". " .. pl.Name .. " — " .. getStat(pl, "Монеты") .. " монет | " .. getStat(pl, "Очки") .. " очк.")
				end
				local listLabel = board:FindFirstChild("List")
				if listLabel then listLabel.Text = table.concat(rows, "\n") end
			end
		end
	end)

	-- командный ремоут
	local selectEv = Remotes:FindFirstChild(Config.REM.SelectTeam)
	selectEv.OnServerEvent:Connect(function(pl, teamName)
		local team = teamName == Config.TEAM_OPS and teamOps or teamDef
		local count = 0
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Team == team then count = count + 1 end
		end
		if pl.Team ~= team and count >= Config.TEAM_CAP then return end
		pl.Team = team
		pl:LoadCharacter()
	end)

	-- главный цикл раундов
	while true do
		playRound()
	end
end

main()
