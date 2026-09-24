-- ============================================================
--  WeaponService — оружие защитников и стационарные системы (СЕРВЕР)
-- ============================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)
local Destruction = require(script.Parent.Destruction)

local WeaponService = {}

local Remotes, Economy, DroneService, MapGenerator
local lastShot = {}      -- [player] = os.clock()
local iglaReady = {}     -- [player] = os.clock()
local guns = {}          -- [id] = {model, pivot, seat, prompt, pos, dead, kind, heat, overheatUntil, missiles}
local gunCounter = 0
local nightState = false
local playerFromGun, makeRoofTeleport, buildZU23, buildPantsir -- forward

function WeaponService.SetRemotes(f) Remotes = f end
function WeaponService.SetEconomy(e) Economy = e end
function WeaponService.SetDroneService(d) DroneService = d end
function WeaponService.SetMapGenerator(m) MapGenerator = m end

local function fireRemote(name, player, payload)
	local ev = Remotes and Remotes:FindFirstChild(name)
	if ev then ev:FireClient(player, payload) end
end

local function killfeed(msg)
	-- назначается Main (через хук ниже)
	if WeaponService.KillfeedFn then WeaponService.KillfeedFn(msg) end
end

-- ============================================================
--  ВЫДАЧА ОРУЖИЯ
-- ============================================================
local function makeTool(name, color, size, grip)
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = name
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = size
	handle.Color = color
	handle.Material = Enum.Material.Metal
	handle.CanCollide = false
	handle.Parent = tool
	return tool
end

local function onCharacterAdded(player, char)
	if not player.Team or player.Team.Name ~= Config.TEAM_DEF then return end
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then return end
	hum.WalkSpeed = 16
	-- солдатский вид
	local bodyColors = char:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		local mil = BrickColor.new("Br. yellowish green")
		bodyColors.TorsoColor3 = mil.Color
		bodyColors.LeftArmColor3 = mil.Color
		bodyColors.RightArmColor3 = mil.Color
		bodyColors.LeftLegColor3 = BrickColor.new("Dark olive green").Color
		bodyColors.RightLegColor3 = BrickColor.new("Dark olive green").Color
	end
	-- каска
	local head = char:FindFirstChild("Head")
	if head then
		local helmet = Instance.new("Part")
		helmet.Size = Vector3.new(1.6, 0.8, 1.6)
		helmet.Color = Color3.fromRGB(70, 90, 55)
		helmet.Material = Enum.Material.Metal
		helmet.CanCollide = false
		local weld = Instance.new("Weld")
		weld.Part0 = head; weld.Part1 = helmet
		weld.C0 = CFrame.new(0, 0.5, 0)
		weld.Parent = helmet
		helmet.Parent = char
	end
	-- рождение с максимальным HP (учёт прокачки)
	hum.MaxHealth = 100 + (player:GetAttribute("HPLvl") or 0) * 50
	hum.Health = hum.MaxHealth
	-- инструменты
	local backpack = player:WaitForChild("Backpack", 10)
	if backpack then
		if not backpack:FindFirstChild("AK74M") and not (char:FindFirstChild("AK74M")) then
			makeTool("AK74M", Color3.fromRGB(80, 60, 40), Vector3.new(0.6, 1.2, 3)).Parent = backpack
		end
		if not backpack:FindFirstChild("KORD") then
			makeTool("KORD", Color3.fromRGB(70, 70, 75), Vector3.new(0.8, 1.4, 4.4)).Parent = backpack
		end
		if not backpack:FindFirstChild("IGLA") then
			local t = makeTool("IGLA", Color3.fromRGB(90, 110, 70), Vector3.new(0.9, 0.9, 5))
			t.Name = "IGLA"
			t.Parent = backpack
		end
	end
end

-- замедление от тяжёлого оружия
local function watchToolWeight(player, char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then return end
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			if child.Name == "KORD" then hum.WalkSpeed = 16 * Config.WEAPONS.KORD.SpeedMul
			elseif child.Name == "IGLA" then hum.WalkSpeed = 16 * Config.WEAPONS.IGLA.SpeedMul end
		end
	end)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then hum.WalkSpeed = 16 end
	end)
end

-- ============================================================
--  СТРЕЛЬБА (АК / Корд)
-- ============================================================
local function handleWeaponFire(player, origin, dir)
	if type(dir) ~= "Vector3" or type(origin) ~= "Vector3" then return end
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	-- какой инструмент?
	local tool = char:FindFirstChildOfClass("Tool")
	if not tool then return end
	local wcfg
	if tool.Name == "AK74M" then wcfg = Config.WEAPONS.AK74M
	elseif tool.Name == "KORD" then wcfg = Config.WEAPONS.KORD end
	if not wcfg then return end
	-- темп стрельбы
	local now = os.clock()
	local minInt = 1 / wcfg.Rate * 0.85
	if lastShot[player] and now - lastShot[player] < minInt then return end
	lastShot[player] = now
	-- валидация точки выстрела
	local head = char:FindFirstChild("Head")
	if not head or (head.Position - origin).Magnitude > 12 then origin = head and head.Position or origin end
	dir = dir.Unit

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { char, workspace.Debris, workspace.FX }

	local result = workspace:Raycast(origin, dir * wcfg.Range, rayParams)
	local hitPos = result and result.Position or (origin + dir * wcfg.Range)

	-- эффекты
	Util.tracer(origin + dir * 2, hitPos, wcfg.Tracer, workspace, 0.12, 0.06)
	Util.muzzleFlash(origin + dir * 2)
	Util.sound3d(Config.SOUNDS.Shot, origin, (tool.Name == "KORD") and 1.2 or 0.6, tool.Name == "KORD" and 0.7 or 1, 200, 2)

	if result then
		-- дрон?
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		while model and not model:GetAttribute("DroneId") do model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model") end
		if model and model:GetAttribute("DroneId") then
			DroneService.DamageDrone(model, wcfg.Damage, player)
			return
		end
		-- часть здания?
		if Destruction.GetInfo(result.Instance) then
			Destruction.DamagePart(result.Instance, tool.Name == "KORD" and 2 or 1, player)
		end
	end
end

-- ============================================================
--  ПЗРК / ракеты «Панциря»
-- ============================================================
local function launchManpad(player, targetDrone, fromGunId)
	local cfgMissile
	local origin
	local fromGun = fromGunId
	if fromGun then
		local gun = guns[fromGun]
		if not gun or gun.dead then return end
		local missiles = fromGun:GetAttribute("Missiles") or 0
		if missiles <= 0 then
			fireRemote(Config.REM.OperFX, player, { type = "msg", text = "Ракеты перезаряжаются" })
			return
		end
		fromGun:SetAttribute("Missiles", missiles - 1)
		cfgMissile = { damage = Config.STATIONARY.PANTSIR.Missile.Damage, speed = 250 }
		origin = fromGun:GetPivot().Position + Vector3.new(0, 6, 0)
	else
		local char = player.Character
		if not char then return end
		local tool = char:FindFirstChildOfClass("Tool")
		if not tool or tool.Name ~= "IGLA" then return end
		local now = os.clock()
		local ready = iglaReady[player] or 0
		if now < ready then
			fireRemote(Config.REM.OperFX, player, { type = "msg", text = "ПЗРК перезаряжается: " .. math.ceil(ready - now) .. "с" })
			return
		end
		local reload = player:GetAttribute("FastIgla") and 6 or Config.WEAPONS.IGLA.Reload
		iglaReady[player] = now + reload
		cfgMissile = { damage = Config.WEAPONS.IGLA.Damage, speed = Config.WEAPONS.IGLA.RocketSpeed }
		local head = char:FindFirstChild("Head")
		origin = head and head.Position + Vector3.new(0, 2, 0)
		if not origin then return end
	end
	if not targetDrone or not targetDrone.Parent then return end
	local tInfo = DroneService.GetDroneInfo and DroneService.GetDroneInfo(targetDrone)
	local targetPos = targetDrone:GetPivot().Position
	if (targetPos - origin).Magnitude > 450 then return end

	-- шанс промаха при резком манёвре дрона
	local miss = false
	if tInfo and tInfo.yawRate and tInfo.yawRate > math.rad(90) and math.random() < Config.WEAPONS.IGLA.MissChance then
		miss = true
	end

	Util.sound3d(Config.SOUNDS.RocketLaunch, origin, 1.5, 1, 250, 4)

	local missile = Instance.new("Part")
	missile.Size = Vector3.new(0.7, 0.7, 3)
	missile.Color = Color3.fromRGB(220, 220, 200)
	missile.Material = Enum.Material.Metal
	missile.CanCollide = false
	missile.CFrame = CFrame.lookAt(origin, targetPos)
	missile.Parent = workspace
	local a0 = Instance.new("Attachment", missile); a0.Position = Vector3.new(0, 0, 1.5)
	local a1 = Instance.new("Attachment", missile); a1.Position = Vector3.new(0, 0, -1.5)
	local trail = Instance.new("Trail", missile)
	trail.Attachment0 = a0; trail.Attachment1 = a1
	trail.Lifetime = 0.4
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 220, 150))
	trail.LightEmission = 1
	local light = Instance.new("PointLight", missile)
	light.Color = Color3.fromRGB(255, 200, 120); light.Range = 12; light.Brightness = 3

	local vel = CFrame.lookAt(origin, targetPos).LookVector * 60 -- старт с разгоном
	local born = os.clock()
	local life = 9
	-- тряска/вид ракеты у защитника
	fireRemote(Config.REM.OperFX, player, { type = "missile", missile = missile })

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not missile.Parent then conn:Disconnect() return end
		if os.clock() - born > life then
			conn:Disconnect()
			Destruction.Explode(missile.Position, 8, 10, { player = player })
			missile:Destroy()
			return
		end
		local desired = targetPos
		if targetDrone.Parent and targetDrone.PrimaryPart then
			desired = targetDrone.PrimaryPart.Position
			if miss then desired = desired + Vector3.new(0, 40, 0) end -- ракета обманута
		end
		local toT = (desired - missile.Position)
		if toT.Magnitude < 7 then
			conn:Disconnect()
			-- ПОПАДАНИЕ
			if not miss then
				DroneService.DamageDrone(targetDrone, cfgMissile.damage, player)
			end
			Destruction.Explode(missile.Position, 9, 12, { player = player })
			missile:Destroy()
			return
		end
		-- автонаведение с ограниченной скоростью поворота
		local wanted = toT.Unit * cfgMissile.speed
		vel = Util.clampMag(Util.lerp(vel, wanted, math.clamp(3 * dt, 0, 1)), cfgMissile.speed)
		local step = vel * dt
		local r = workspace:Raycast(missile.Position, step)
		if r and r.Instance and r.Instance:FindFirstAncestor("Drones") then
			conn:Disconnect()
			if not miss then DroneService.DamageDrone(targetDrone, cfgMissile.damage, player) end
			Destruction.Explode(r.Position, 9, 12, { player = player })
			missile:Destroy()
			return
		end
		missile.CFrame = CFrame.lookAt(missile.Position + step, missile.Position + step + vel)
		missile.Position = missile.Position + step
	end)
end

-- ============================================================
--  СТАЦИОНАРНЫЕ СИСТЕМЫ
-- ============================================================
local function seatPlayer(player, gun)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	if gun.dead then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = gun.seat.CFrame + Vector3.new(0, 3, 0)
	end
	task.wait(0.1)
	gun.seat:Sit(hum)
	player:SetAttribute("SeatedGun", gun.id)
	fireRemote(Config.REM.GunState, player, gun.model)
end

local function unseatPlayer(player, gun)
	player:SetAttribute("SeatedGun", nil)
	fireRemote(Config.REM.GunState, player, nil)
end

local function registerDestructibleGun(gun, hp)
	local bld = Destruction.RegisterBuilding("aa", gun.kind == "pantsir" and "Панцирь-С1" or "ЗУ-23-2", gun.pos)
	local platform = gun.model:FindFirstChild("Platform")
	if platform then
		Destruction.AttachPart(platform, hp, "Gun", bld, 1)
	end
end

local function onGunDestroyed(center)
	-- найти ближайшую пушку и «убить» её
	for id, gun in pairs(guns) do
		if not gun.dead and (gun.pos - center).Magnitude < 40 then
			gun.dead = true
			gun.prompt.Enabled = false
			if gun.turret then gun.turret:Destroy() gun.turret = nil end
			killfeed("Зенитная установка уничтожена! (+" .. Config.BUILDING_REWARD.aa .. " оператору)")
			-- высадить стрелка
			local occ = gun.seat and gun.seat.Occupant
			if occ then
				local pl = Players:GetPlayerFromCharacter(occ.Parent)
				if pl then
					gun.seat:Sit(occ) -- no-op; персонаж выпадет сам при удалении сиденья
				end
			end
		end
	end
end

local function buildZU23(pos, roofAccess)
	gunCounter = gunCounter + 1
	local id = "zu" .. gunCounter
	local model = Instance.new("Model")
	model.Name = "Gun_ZU23_" .. id

	local platform = Util.part({ Name = "Platform", Size = Vector3.new(8, 1, 8), CFrame = CFrame.new(pos), Color = Color3.fromRGB(90, 92, 96), Material = Enum.Material.Metal }, model)
	local pedestal = Util.part({ Size = Vector3.new(2, 3, 2), CFrame = CFrame.new(pos + Vector3.new(0, 2, 0)), Color = Color3.fromRGB(70, 72, 76), Material = Enum.Material.Metal }, model)

	local turret = Instance.new("Model")
	turret.Name = "Turret"
	local pivot = Util.part({ Name = "Pivot", Size = Vector3.new(1.6, 1, 1.6), Transparency = 1, CFrame = CFrame.new(pos + Vector3.new(0, 4, 0)) }, turret)
	turret.PrimaryPart = pivot
	-- спаренные стволы
	for _, sx in ipairs({ -1, 1 }) do
		local barrel = Instance.new("Part")
		barrel.Anchored = true; barrel.CanCollide = false; barrel.CanQuery = false
		barrel.Shape = Enum.PartType.Cylinder
		barrel.Size = Vector3.new(9, 0.5, 0.5)
		barrel.CFrame = pivot.CFrame * CFrame.new(0, 0.6, -3.5) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.new(sx * 0.5, 0, 0)
		barrel.Color = Color3.fromRGB(55, 55, 58); barrel.Material = Enum.Material.Metal
		barrel.Parent = turret
	end
	local cradle = Util.part({ Size = Vector3.new(2.4, 1.2, 4), CFrame = pivot.CFrame * CFrame.new(0, 0.4, -0.5), Color = Color3.fromRGB(60, 90, 60), Material = Enum.Material.Metal }, turret)
	local ammoBox = Util.part({ Size = Vector3.new(2, 1.4, 2.4), CFrame = pivot.CFrame * CFrame.new(0, -0.4, 1.6), Color = Color3.fromRGB(80, 100, 60), Material = Enum.Material.Metal }, turret)
	-- сиденье
	local seat = Instance.new("Seat")
	seat.Size = Vector3.new(2, 0.4, 2)
	seat.Anchored = true
	seat.CanCollide = true
	seat.CFrame = pivot.CFrame * CFrame.new(0, -1.2, 1.2)
	seat.Color = Color3.fromRGB(40, 60, 40)
	seat.Parent = turret
	turret.Parent = model

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Сесть за ЗУ-23-2"
	prompt.ObjectText = "Зенитная установка"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 10
	prompt.Parent = seat

	model.Parent = workspace.City

	local gun = { id = id, model = model, pivot = pivot, turret = turret, seat = seat, prompt = prompt,
		pos = pos, dead = false, kind = "zu23", heat = 0, overheatUntil = 0, shotsInBurst = 0 }
	guns[id] = gun
	registerDestructibleGun(gun, Config.STATIONARY.ZU23.HP)

	prompt.Triggered:Connect(function(pl) seatPlayer(pl, gun) end)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if not seat.Occupant then
			local pl = playerFromGun(gun)
			if pl then unseatPlayer(pl, gun) end
		end
	end)
	-- телепорт на крышу/с крыши
	gun.roofAccess = roofAccess
	if roofAccess then
		makeRoofTeleport(pos, roofAccess)
	end
	return gun
end

local function playerFromGun(gun)
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl:GetAttribute("SeatedGun") == gun.id then return pl end
	end
	return nil
end

local function makeRoofTeleport(roofPos, groundPos)
	local padDown = Util.part({ Size = Vector3.new(6, 0.3, 6), CFrame = CFrame.new(roofPos + Vector3.new(10, 0.4, 0)), Color = Color3.fromRGB(60, 200, 120), Material = Enum.Material.Neon }, workspace.City)
	local padUp = Util.part({ Size = Vector3.new(6, 0.3, 6), CFrame = CFrame.new(groundPos + Vector3.new(0, 0.4, 0)), Color = Color3.fromRGB(60, 200, 120), Material = Enum.Material.Neon }, workspace.City)
	local function bind(a, b)
		a.Touched:Connect(function(hit)
			local char = hit.Parent
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and char.PrimaryPart then
				char:PivotTo(CFrame.new(b.Position + Vector3.new(0, 4, 0)))
			end
		end)
	end
	bind(padDown, padUp)
	bind(padUp, padDown)
end

local function buildPantsir(pos)
	gunCounter = gunCounter + 1
	local id = "pantsir"
	local model = Instance.new("Model")
	model.Name = "Gun_Pantsir"
	-- шасси
	local chassis = Util.part({ Name = "Platform", Size = Vector3.new(10, 2, 20), CFrame = CFrame.new(pos + Vector3.new(0, 1.5, 0)), Color = Color3.fromRGB(75, 85, 70), Material = Enum.Material.Metal }, model)
	for _, sx in ipairs({ -1, 1 }) do
		for i = 1, 3 do
			local wheel = Instance.new("Part")
			wheel.Anchored = true; wheel.Shape = Enum.PartType.Cylinder; wheel.CanCollide = false
			wheel.Size = Vector3.new(2, 2.4, 2.4)
			wheel.CFrame = chassis.CFrame * CFrame.new(sx * 5.2, -0.5, 7 - i * 7) * CFrame.Angles(0, 0, math.rad(90))
			wheel.Color = Color3.fromRGB(30, 30, 30); wheel.Parent = model
		end
	end
	-- башня
	local turret = Instance.new("Model")
	turret.Name = "Turret"
	local pivot = Util.part({ Name = "Pivot", Size = Vector3.new(2, 1, 2), Transparency = 1, CFrame = CFrame.new(pos + Vector3.new(0, 6, 0)) }, turret)
	turret.PrimaryPart = pivot
	local body = Util.part({ Size = Vector3.new(7, 3, 8), CFrame = pivot.CFrame * CFrame.new(0, 0.8, 0), Color = Color3.fromRGB(85, 95, 78), Material = Enum.Material.Metal }, turret)
	-- пушки
	for _, sx in ipairs({ -1, 1 }) do
		local gunBlock = Util.part({ Size = Vector3.new(1.6, 1.6, 7), CFrame = pivot.CFrame * CFrame.new(sx * 1.6, 0.6, -5), Color = Color3.fromRGB(50, 55, 50), Material = Enum.Material.Metal }, turret)
	end
	-- ракетные ТПК (2 блока по 6)
	for _, sx in ipairs({ -1, 1 }) do
		for i = 1, 6 do
			local tube = Util.part({ Size = Vector3.new(1.4, 1.4, 7), CFrame = pivot.CFrame * CFrame.new(sx * 3, 1.2 + math.floor((i - 1) / 3) * 1.6, 1 + ((i - 1) % 3) * 1.6 - 1.6), Color = Color3.fromRGB(60, 65, 58), Material = Enum.Material.Metal }, turret)
		end
	end
	-- вращающийся радар
	local radarMast = Util.part({ Size = Vector3.new(0.6, 4, 0.6), CFrame = pivot.CFrame * CFrame.new(0, 3.4, 2.5), Color = Color3.fromRGB(60, 65, 60), Material = Enum.Material.Metal }, turret)
	local radar = Util.part({ Size = Vector3.new(6, 0.3, 2), CFrame = pivot.CFrame * CFrame.new(0, 5.6, 2.5), Color = Color3.fromRGB(70, 75, 70), Material = Enum.Material.Metal }, turret)
	radar:SetAttribute("SpinSpeed", 60)
	local seat = Instance.new("Seat")
	seat.Size = Vector3.new(2.4, 0.4, 2.4)
	seat.Anchored = true
	seat.CFrame = pivot.CFrame * CFrame.new(0, -0.6, 0.4)
	seat.Color = Color3.fromRGB(35, 45, 35)
	seat.Parent = turret
	turret.Parent = model

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Сесть за «Панцирь-С1»"
	prompt.ObjectText = "ЗРПК Панцирь-С1"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 12
	prompt.Parent = seat

	model.Parent = workspace.City

	local gun = { id = id, model = model, pivot = pivot, turret = turret, seat = seat, prompt = prompt,
		pos = pos, dead = false, kind = "pantsir", heat = 0, overheatUntil = 0, shotsInBurst = 0 }
	guns[id] = gun
	model:SetAttribute("Missiles", Config.STATIONARY.PANTSIR.Missile.Count)
	registerDestructibleGun(gun, Config.STATIONARY.PANTSIR.HP)

	prompt.Triggered:Connect(function(pl) seatPlayer(pl, gun) end)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if not seat.Occupant then
			local pl = playerFromGun(gun)
			if pl then unseatPlayer(pl, gun) end
		end
	end)
	-- телепорт на крышу
	makeRoofTeleport(pos, pos - Vector3.new(0, pos.Y - 3, 0))
	return gun
end

local function buildSpotlight(pos)
	local pole = Util.part({ Size = Vector3.new(1, 22, 1), CFrame = CFrame.new(pos + Vector3.new(0, 11, 0)), Color = Color3.fromRGB(80, 82, 86), Material = Enum.Material.Metal }, workspace.City)
	local head = Util.part({ Size = Vector3.new(2.5, 2.5, 3), CFrame = CFrame.new(pos + Vector3.new(0, 22, 0)), Color = Color3.fromRGB(200, 200, 210), Material = Enum.Material.Neon }, workspace.City)
	local spot = Instance.new("SpotLight")
	spot.Angle = 18
	spot.Brightness = 12
	spot.Range = 260
	spot.Color = Color3.fromRGB(255, 245, 220)
	spot.Enabled = false -- включается ночью
	spot.Face = Enum.NormalId.Front
	spot.Parent = head
	head:SetAttribute("Spotlight", true)
	return { pole = pole, head = head, spot = spot, pos = pos }
end

-- наведение стационарных систем
local aimLast = {}
local function handleGunAim(player, gunModel, dir)
	if type(dir) ~= "Vector3" then return end
	local gunId = player:GetAttribute("SeatedGun")
	local gun = gunId and guns[gunId]
	if not gun or gun.model ~= gunModel or gun.dead then return end
	local now = os.clock()
	if aimLast[gunId] and now - aimLast[gunId] < 0.08 then return end
	aimLast[gunId] = now
	dir = dir.Unit
	dir = Vector3.new(dir.X, math.clamp(dir.Y, -0.08, 0.985), dir.Z).Unit
	if gun.turret then
		gun.turret:PivotTo(CFrame.lookAt(gun.pivot.Position, gun.pivot.Position + dir * 10))
	elseif gun.head then -- прожектор
	end
	-- прожекторы
	if gun.kind == "spot" and gun.head then
		gun.head.CFrame = CFrame.lookAt(gun.pos + Vector3.new(0, 22, 0), gun.pos + Vector3.new(0, 22, 0) + dir * 20)
	end
end

-- стрельба стационарок
local function handleGunFire(player, origin, dir)
	if type(dir) ~= "Vector3" or type(origin) ~= "Vector3" then return end
	local gunId = player:GetAttribute("SeatedGun")
	local gun = gunId and guns[gunId]
	if not gun or gun.dead then return end
	local now = os.clock()
	if now < gun.overheatUntil then return end

	local scfg
	if gun.kind == "zu23" then scfg = Config.STATIONARY.ZU23
	else scfg = Config.STATIONARY.PANTSIR.Cannon end

	local minInt = 1 / scfg.Rate * 0.85
	if gun.lastShot and now - gun.lastShot < minInt then return end
	gun.lastShot = now

	dir = dir.Unit
	local muzzle = gun.pivot.Position + dir * 6
	-- перегрев
	gun.heat = gun.heat + 1
	if gun.heat >= scfg.HeatShots then
		gun.heat = 0
		gun.overheatUntil = now + scfg.HeatTime
		gun.model:SetAttribute("OverheatUntil", gun.overheatUntil)
	end
	gun.model:SetAttribute("Heat", gun.heat)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local excl = { workspace.Debris, workspace.FX, gun.model }
	if player.Character then table.insert(excl, player.Character) end
	rayParams.FilterDescendantsInstances = excl
	local range = scfg.Range
	local result = workspace:Raycast(muzzle, dir * range, rayParams)
	local hitPos = result and result.Position or (muzzle + dir * range)
	Util.tracer(muzzle, hitPos, Color3.fromRGB(255, 80, 60), workspace, 0.3, 0.08)
	Util.sound3d(Config.SOUNDS.HeavyShot, muzzle, 1.6, gun.kind == "zu23" and 0.85 or 0.75, 350, 2)

	if result then
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		while model and not model:GetAttribute("DroneId") do model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model") end
		if model and model:GetAttribute("DroneId") then
			DroneService.DamageDrone(model, scfg.Damage, player)
		elseif Destruction.GetInfo(result.Instance) then
			Destruction.DamagePart(result.Instance, 4, player)
		end
	end
end

-- ============================================================
--  ЩИТ / РЕМОНТ
-- ============================================================
local function deployShield(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local shield = Util.part({ Size = Vector3.new(10, 9, 0.8), CFrame = root.CFrame * CFrame.new(0, 2, -6), Color = Color3.fromRGB(90, 160, 255), Material = Enum.Material.ForceField, Transparency = 0.35 }, workspace)
	Destruction.AttachPart(shield, 100, "Shield", nil)
	Debris:AddItem(shield, 120)
end

local function repairGun(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return false, "Нет персонажа" end
	local best, bestDist = nil, 200
	for id, gun in pairs(guns) do
		if gun.dead and gun.kind == "zu23" then
			local d = (root.Position - gun.pos).Magnitude
			if d < bestDist then best = gun bestDist = d end
		end
	end
	if not best then return false, "Рядом нет уничтоженной ЗУ-23 (нужна < 200 studs)" end
	-- пересоздать установку
	best.model:Destroy()
	guns[best.id] = nil
	buildZU23(best.pos, best.roofAccess)
	killfeed(player.Name .. " восстановил ЗУ-23-2")
	return true, "Зенитка восстановлена"
end

-- ============================================================
-- ============================================================
--  Постройка стационарных систем (вызывается при Init и Rebuild)
-- ============================================================
local function buildStationary()
	-- стационарные системы из точек карты
	local pts = MapGenerator.Points
	if pts.Pantsir then
		buildPantsir(pts.Pantsir + Vector3.new(12, 0, 12))
	end
	local zuRoofAccess = {
		[1] = Vector3.new(384, 3, -384 + 60),   -- башня «Восток»: земля рядом
		[2] = Vector3.new(896, 3, -128 + 40),
		[3] = Vector3.new(-512, 3, 512 + 60),
	}
	for i, zpos in ipairs(pts.ZU) do
		buildZU23(zpos, zuRoofAccess[i])
	end

	-- прожекторы
	WeaponService.Spotlights = {}
	for _, spos in ipairs(pts.Spotlights) do
		local sl = buildSpotlight(spos)
		sl.kind = "spot"
		sl.id = "spot" .. tostring(spos)
		guns[sl.id] = sl
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Управлять прожектором"
		prompt.ObjectText = "Прожектор"
		prompt.HoldDuration = 0.2
		prompt.MaxActivationDistance = 10
		prompt.Parent = sl.head
		sl.prompt = prompt
		prompt.Triggered:Connect(function(pl)
			local char = pl.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then
				pl:SetAttribute("SeatedGun", sl.id)
				fireRemote(Config.REM.GunState, pl, sl.head)
				task.wait(0.05)
				-- «сидим» у прожектора
				local root = char:FindFirstChild("HumanoidRootPart")
				if root then
					root.Anchored = true
					root.CFrame = CFrame.new(sl.pos + Vector3.new(0, 3, 6))
				end
				sl.player = pl
			end
		end)
	end

	WeaponService.SetSpotlightsNight(nightState)
end

function WeaponService.Init()
	-- персонажи
	Players.PlayerAdded:Connect(function(pl)
		pl.CharacterAdded:Connect(function(char)
			task.spawn(onCharacterAdded, pl, char)
			watchToolWeight(pl, char)
		end)
	end)
	for _, pl in ipairs(Players:GetPlayers()) do
		pl.CharacterAdded:Connect(function(char)
			task.spawn(onCharacterAdded, pl, char)
			watchToolWeight(pl, char)
		end)
	end

	-- ремоуты
	local wf = Remotes:FindFirstChild(Config.REM.WeaponFire)
	if wf then wf.OnServerEvent:Connect(handleWeaponFire) end
	local ga = Remotes:FindFirstChild(Config.REM.GunAim)
	if ga then ga.OnServerEvent:Connect(handleGunAim) end
	local gf = Remotes:FindFirstChild(Config.REM.GunFire)
	if gf then gf.OnServerEvent:Connect(handleGunFire) end
	local gl = Remotes:FindFirstChild(Config.REM.GunLeave)
	if gl then
		gl.OnServerEvent:Connect(function(player)
			local gunId = player:GetAttribute("SeatedGun")
			local gun = gunId and guns[gunId]
			if gun and gun.kind == "spot" and gun.player == player then
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if root then
					root.Anchored = false
					root.CFrame = CFrame.new(gun.pos + Vector3.new(0, 3, 12))
				end
				gun.player = nil
				player:SetAttribute("SeatedGun", nil)
				fireRemote(Config.REM.GunState, player, nil)
			end
		end)
	end
	local il = Remotes:FindFirstChild(Config.REM.IglaLaunch)
	if il then
		il.OnServerEvent:Connect(function(player, targetDrone)
			local gunId = player:GetAttribute("SeatedGun")
			local gun = gunId and guns[gunId]
			if gun and gun.kind == "pantsir" then
				launchManpad(player, targetDrone, gunId)
			else
				launchManpad(player, targetDrone, nil)
			end
		end)
	end

	buildStationary()
	-- перезарядка ракет Панциря
	task.spawn(function()
		while true do
			task.wait(15)
			for id, gun in pairs(guns) do
				if gun.kind == "pantsir" and gun.model.Parent then
					local m = gun.model:GetAttribute("Missiles") or 0
					if m < Config.STATIONARY.PANTSIR.Missile.Count then
						gun.model:SetAttribute("Missiles", m + 1)
					end
				end
			end
		end
	end)

	-- хук уничтожения зениток
	local prevHook = Destruction.OnBuildingDestroyed
	Destruction.OnBuildingDestroyed = function(player, category, name, center)
		if prevHook then prevHook(player, category, name, center) end
		if category == "aa" then onGunDestroyed(center) end
	end

	-- прокачка
	Economy.SetShieldHandler(deployShield)
	Economy.SetRepairHandler(repairGun)
end

-- доступ прожекторов к ночному режиму
function WeaponService.SetSpotlightsNight(on)
	nightState = on
	for id, gun in pairs(guns) do
		if gun.kind == "spot" and gun.spot then
			gun.spot.Enabled = on
		end
	end
end

-- Пересоздание стационарных систем после пересборки города
function WeaponService.RebuildStationary()
	guns = {}
	buildStationary()
end

return WeaponService
