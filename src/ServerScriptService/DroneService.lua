-- ============================================================
--  DroneService — запуск и жизнь дронов (СЕРВЕР)
--  Физику дрон ведёт клиент (NetworkOwnership), сервер следит
--  за HP, топливом, камикадзе-детонацией, боеприпасами, радаром.
-- ============================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)
local DroneFactory = require(ReplicatedStorage.Shared.DroneFactory)
local Destruction = require(script.Parent.Destruction)

local DroneService = {}

local Remotes, Economy
local activeDrones = {}  -- [model] = {player, cfg, primary, align, lvel, engine, swarmUnits?, fuelLeft}
local droneByPlayer = {} -- [player] = model
local attackingUnits = {} -- [model] = {target=Vector3, cfg=, leader=}
local lastSiren = 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = {}

local PAD = Config.PAD_POS

-- Хуки (назначает Main)
DroneService.KillfeedFn = function(msg) end

function DroneService.SetRemotes(folder) Remotes = folder end
function DroneService.SetRayExcludes(list) rayParams.FilterDescendantsInstances = list end
function DroneService.SetEconomy(e) Economy = e end

function DroneService.GetDroneInfo(model)
	return activeDrones[model]
end

function DroneService.GetActiveDrones()
	local list = {}
	for model, info in pairs(activeDrones) do
		if model.Parent then table.insert(list, { model = model, info = info }) end
	end
	return list
end

local function fireRemote(name, ...)
	if Remotes then
		local ev = Remotes:FindFirstChild(name)
		if ev then ev:FireClient(...) end
	end
end

-- ------------------------------------------------------------
-- Взрыв дрона / смерть
-- ------------------------------------------------------------
local function removeDrone(model, explodePos, killedByPlayer)
	local info = activeDrones[model]
	if not info then return end
	activeDrones[model] = nil
	droneByPlayer[info.player] = nil
	-- убрать юнитов роя
	if info.swarmUnits then
		for _, u in ipairs(info.swarmUnits) do
			attackingUnits[u] = nil
			if u.Parent then u:Destroy() end
		end
	end
	if info.engine then info.engine:Stop() end
	if model.Parent then
		Debris:AddItem(model, 0.5)
		if explodePos then
			Util.burst(explodePos, { radius = 10, fireCount = 30, smokeCount = 20 })
			Util.sound3d(Config.SOUNDS.Explosion, explodePos, 2, 1, 250, 4)
		end
	end
end

function DroneService.DamageDrone(model, dmg, attacker)
	local info = activeDrones[model]
	if not info or not model.Parent then return end
	local hp = (model:GetAttribute("HP") or 0) - dmg
	model:SetAttribute("HP", math.max(0, hp))
	if attacker and attacker.Parent then
		fireRemote(Config.REM.OperFX, info.player, { type = "hit" })
	end
	if hp <= 0 then
		local pos = info.primary and info.primary.Position or model:GetPivot().Position
		-- засчитать защитнику
		if attacker and attacker:IsA("Player") and attacker.Team and attacker.Team.Name == Config.TEAM_DEF then
			Economy.Add(attacker, info.cfg.Reward, "Сбит дрон: " .. info.cfg.Name)
			Economy.AddScore(attacker, info.cfg.Reward)
			Economy.AddKill(attacker)
			DroneService.KillfeedFn(attacker.Name .. " сбил " .. info.cfg.Name .. " (+" .. info.cfg.Reward .. ")")
		else
			DroneService.KillfeedFn(info.cfg.Name .. " уничтожен")
		end
		fireRemote(Config.REM.OperFX, info.player, { type = "dead" })
		removeDrone(model, pos, attacker)
	end
end

-- хук: взрывы задевают другие дроны
Destruction.OnDroneExplosion = function(pos, radius, damage, player)
	for model, info in pairs(activeDrones) do
		if info.primary and info.primary.Position and model.Parent then
			if (info.primary.Position - pos).Magnitude < radius then
				DroneService.DamageDrone(model, damage * 0.8, player)
			end
		end
	end
end

-- ------------------------------------------------------------
-- Боеприпасы
-- ------------------------------------------------------------
local function spawnBomb(drone, info, opts)
	local primary = info.primary
	local bomb = Instance.new("Part")
	bomb.Size = Vector3.new(1.2, 1.2, 2.2)
	bomb.Color = Color3.fromRGB(70, 70, 60)
	bomb.Material = Enum.Material.Metal
	bomb.CanCollide = false
	bomb.CFrame = primary.CFrame * CFrame.new(0, -2, -2)
	bomb.AssemblyLinearVelocity = primary.AssemblyVelocity * 0.6 + Vector3.new(0, -6, 0)
	bomb.Parent = workspace
	local born = os.clock()
	local life = opts.life or 6
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not bomb.Parent then conn:Disconnect() return end
		if os.clock() - born > life then
			conn:Disconnect()
			Destruction.Explode(bomb.Position, info.cfg.BRadius, info.cfg.BDamage,
				{ player = info.player, fireTime = info.cfg.FireTime, crater = info.cfg.BRadius >= 15 })
			bomb:Destroy()
			return
		end
		local r = workspace:Raycast(bomb.Position, bomb.AssemblyLinearVelocity * dt * 1.5 + Vector3.new(0, -1, 0), rayParams)
		if r and os.clock() - born > 0.25 then
			conn:Disconnect()
			Destruction.Explode(r.Position, info.cfg.BRadius, info.cfg.BDamage,
				{ player = info.player, fireTime = info.cfg.FireTime, crater = info.cfg.BRadius >= 15 })
			bomb:Destroy()
		end
	end)
end

local function spawnDroneMissile(drone, info, dir, opts)
	opts = opts or {}
	local primary = info.primary
	local missile = Instance.new("Part")
	missile.Size = Vector3.new(0.8, 0.8, 3.4)
	missile.Color = Color3.fromRGB(200, 190, 140)
	missile.Material = Enum.Material.Metal
	missile.CanCollide = false
	missile.CFrame = CFrame.lookAt(primary.Position + dir * 6, primary.Position + dir * 20)
	missile.Parent = workspace
	-- трейл
	local a0 = Instance.new("Attachment", missile); a0.Position = Vector3.new(0, 0, 1.6)
	local a1 = Instance.new("Attachment", missile); a1.Position = Vector3.new(0, 0, -1.6)
	local trail = Instance.new("Trail", missile)
	trail.Attachment0 = a0; trail.Attachment1 = a1
	trail.Lifetime = 0.35
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 200, 120))
	trail.LightEmission = 1
	Util.soundOn(missile, Config.SOUNDS.RocketWhoosh, { Volume = 0.8 }):Play()
	local vel = dir * (opts.speed or 180)
	local born = os.clock()
	local life = opts.life or 6
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not missile.Parent then conn:Disconnect() return end
		vel = vel + Vector3.new(0, opts.gravity or -4, 0) * dt
		vel = Util.clampMag(vel, opts.speed or 180)
		local step = vel * dt
		local r = workspace:Raycast(missile.Position, step + dir * 1, rayParams)
		if r then
			conn:Disconnect()
			Destruction.Explode(r.Position, opts.radius, opts.damage,
				{ player = info.player, fireTime = opts.fireTime or 0, crater = true, knockback = opts.knockback })
			missile:Destroy()
			return
		end
		missile.CFrame = CFrame.lookAt(missile.Position + step, missile.Position + step + vel)
		missile.Position = missile.Position + step
		if os.clock() - born > life or missile.Position.Y < 0 then
			conn:Disconnect()
			Destruction.Explode(missile.Position, opts.radius, opts.damage,
				{ player = info.player, fireTime = opts.fireTime or 0, crater = true, knockback = opts.knockback })
			missile:Destroy()
		end
	end)
end

-- ------------------------------------------------------------
-- КАМИКАДЗЕ: серверный контроль столкновений
-- ------------------------------------------------------------
local function kamikazeExplode(model, info)
	local pos = info.primary.Position
	Destruction.Explode(pos, info.cfg.BRadius, info.cfg.BDamage, {
		player = info.player,
		fireTime = info.cfg.FireTime,
		crater = info.cfg.BRadius >= 20,
		knockback = info.cfg.Flags.Knockback,
	})
	if info.cfg.Flags.ShakeAll then
		local shakeEv = Remotes and Remotes:FindFirstChild(Config.REM.Shake)
		if shakeEv then
			for _, pl in ipairs(Players:GetPlayers()) do shakeEv:FireClient(pl, 3) end
		end
	end
	DroneService.KillfeedFn(info.player.Name .. " направил " .. info.cfg.Name .. " в цель")
	removeDrone(model, pos, nil)
	fireRemote(Config.REM.OperFX, info.player, { type = "dead", success = true })
end

-- ------------------------------------------------------------
-- РОЙ «Саранча»
-- ------------------------------------------------------------
local function spawnSwarmUnits(player, leaderModel, cfg)
	local units = {}
	local origin = PAD + Vector3.new(0, 6, 0)
	for i = 1, cfg.Ammo do
		local ang = (i / cfg.Ammo) * math.pi * 2
		local pos = origin + Vector3.new(math.cos(ang) * 14, (i % 3) * 3, math.sin(ang) * 14)
		local unit = DroneFactory.buildUnit(workspace.Drones, pos)
		local primary = unit.PrimaryPart
		for _, p in ipairs(unit:GetDescendants()) do
			if p:IsA("BasePart") then p.Anchored = false p.CanCollide = false end
		end
		local att = Instance.new("Attachment", primary)
		local align = Instance.new("AlignOrientation")
		align.Mode = Enum.OrientationAlignmentMode.OneAttachment
		align.Attachment0 = att
		align.MaxTorque = 1e6
		align.Responsiveness = 40
		align.Parent = primary
		local lvel = Instance.new("LinearVelocity")
		lvel.Attachment0 = att
		lvel.MaxForce = 1e6
		lvel.VectorVelocity = Vector3.new()
		lvel.Parent = primary
		pcall(function() primary:SetNetworkOwner(player) end)
		unit:SetAttribute("Unit", true)
		unit:SetAttribute("Owner", player.Name)
		table.insert(units, unit)
	end
	return units
end

local function swarmAttack(info, targetPos, all)
	local leader = info.primary
	local candidates = {}
	for _, u in ipairs(info.swarmUnits or {}) do
		if u.Parent and not attackingUnits[u] then
			local pp = u.PrimaryPart
			if pp then table.insert(candidates, { unit = u, dist = (pp.Position - targetPos).Magnitude }) end
		end
	end
	if #candidates == 0 then return end
	table.sort(candidates, function(a, b) return a.dist < b.dist end)
	local n = all and #candidates or 1
	for i = 1, math.min(n, #candidates) do
		local unit = candidates[i].unit
		attackingUnits[unit] = { target = targetPos, cfg = info.cfg, leader = leader, player = info.player }
		pcall(function() unit.PrimaryPart:SetNetworkOwner(nil) end)
		local lv = unit.PrimaryPart:FindFirstChildOfClass("LinearVelocity")
		if lv then lv:Destroy() end
		local ao = unit.PrimaryPart:FindFirstChildOfClass("AlignOrientation")
		if ao then ao:Destroy() end
	end
end

-- ------------------------------------------------------------
-- ЗАПУСК ДРОНА
-- ------------------------------------------------------------
function DroneService.Launch(player, droneId)
	local cfg = Config.DRONE_BY_ID[droneId]
	if not cfg then return nil, "Неизвестный дрон" end
	if not player.Team or player.Team.Name ~= Config.TEAM_OPS then return nil, "Вы не оператор" end
	if droneByPlayer[player] and droneByPlayer[player].Parent then return nil, "Дрон уже в воздухе" end
	if cfg.Price > 0 then
		if not Economy.TrySpend(player, cfg.Price) then return nil, "Не хватает монет" end
	end

	local model = DroneFactory.build(droneId)
	if not model then return nil, "Ошибка сборки" end
	model.Name = "Drone_" .. droneId .. "_" .. player.Name
	model:SetAttribute("DroneId", droneId)
	model:SetAttribute("HP", cfg.HP)
	model:SetAttribute("MaxHP", cfg.HP)
	model:SetAttribute("Ammo", cfg.Ammo)
	model:SetAttribute("Fuel", cfg.Fuel or -1)
	model:SetAttribute("Mode", "bombs")
	model:SetAttribute("Loiter", false)
	model:SetAttribute("Formation", "wedge")

	local primary = model.PrimaryPart
	primary.CFrame = CFrame.lookAt(PAD + Vector3.new(0, 8, 0), PAD + Vector3.new(0, 8, 30))
	model.Parent = workspace.Drones

	-- сварка уже есть; рас anchor
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = (p == primary)
		end
	end

	local att = Instance.new("Attachment", primary)
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.MaxTorque = primary.AssemblyMass * 400 + 1e5
	align.Responsiveness = math.clamp(cfg.Turn / 2, 15, 80)
	align.CFrame = primary.CFrame - primary.Position
	align.Parent = primary
	local lvel = Instance.new("LinearVelocity")
	lvel.Attachment0 = att
	lvel.MaxForce = primary.AssemblyMass * 400 + 1e5
	lvel.RelativeTo = Enum.ActuatorRelativeTo.World
	lvel.VectorVelocity = Vector3.new()
	lvel.Parent = primary

	-- звук мотора
	local sId = Config.SOUNDS[cfg.Sound.Key] or Config.SOUNDS.Motor
	local engine = Util.soundOn(primary, sId, {
		Volume = cfg.Sound.Volume, PlaybackSpeed = cfg.Sound.Pitch,
		RollOffMaxDistance = cfg.Sound.MaxDistance, Looped = true,
	})
	engine:Play()

	pcall(function() primary:SetNetworkOwner(player) end)

	local info = {
		player = player, cfg = cfg, primary = primary, align = align, lvel = lvel,
		engine = engine, fuelLeft = cfg.Fuel, yawPrev = 0, yawRate = 0,
	}
	activeDrones[model] = info
	droneByPlayer[player] = model

	if cfg.Kind == "swarm" then
		info.swarmUnits = spawnSwarmUnits(player, model, cfg)
	end

	fireRemote(Config.REM.OperFX, player, { type = "launch", drone = model })
	return model
end

-- ------------------------------------------------------------
-- REMOTES
-- ------------------------------------------------------------
local function bindRemotes()
	local launchRF = Remotes:FindFirstChild(Config.REM.LaunchDrone)
	if launchRF then
		launchRF.OnServerInvoke = function(player, droneId)
			return DroneService.Launch(player, droneId)
		end
	end

	local fireEv = Remotes:FindFirstChild(Config.REM.DroneFire)
	if fireEv then
		fireEv.OnServerEvent:Connect(function(player, origin, dir)
			local model = droneByPlayer[player]
			if not model or not model.Parent then return end
			local info = activeDrones[model]
			if not info or type(dir) ~= "Vector3" then return end
			local ammo = model:GetAttribute("Ammo") or 0
			if ammo <= 0 then return end
			if (info.primary.Position - origin).Magnitude > 40 then return end -- валидация
			dir = dir.Unit
			local cfg = info.cfg
			model:SetAttribute("Ammo", ammo - 1)

			if cfg.Kind == "grenade" then
				spawnBomb(model, info, { life = 5 })
			elseif cfg.Kind == "bomber" then
				spawnBomb(model, info, { life = 6 })
			elseif cfg.Kind == "missile" then
				spawnDroneMissile(model, info, dir, { speed = 180, radius = cfg.BRadius, damage = cfg.BDamage, life = 7, fireTime = 0 })
			elseif cfg.Kind == "heavy" then
				if model:GetAttribute("Mode") == "cruise" then
					spawnDroneMissile(model, info, dir, { speed = 220, radius = 50, damage = 200, life = 8, fireTime = 15, knockback = true })
					model:SetAttribute("Ammo", model:GetAttribute("Ammo") - 0) -- ракеты считаем так же
				else
					spawnBomb(model, info, { life = 6 })
				end
			elseif cfg.Kind == "swarm" then
				-- вычислить точку под прицелом
				local ray = workspace:Raycast(origin, dir * 900)
				local target = ray and ray.Position or (origin + dir * 900)
				swarmAttack(info, target, false)
			end
		end)
	end

	local swarmAllEv = Remotes:FindFirstChild(Config.REM.SwarmAttack)
	if swarmAllEv then
		swarmAllEv.OnServerEvent:Connect(function(player, pos, all)
			local model = droneByPlayer[player]
			local info = model and activeDrones[model]
			if info and info.cfg.Kind == "swarm" and type(pos) == "Vector3" then
				swarmAttack(info, pos, all == true)
			end
		end)
	end

	local formEv = Remotes:FindFirstChild(Config.REM.SwarmFormation)
	if formEv then
		formEv.OnServerEvent:Connect(function(player, mode)
			local model = droneByPlayer[player]
			if model then model:SetAttribute("Formation", mode == "cloud" and "cloud" or "wedge") end
		end)
	end

	local loiterEv = Remotes:FindFirstChild(Config.REM.Loiter)
	if loiterEv then
		loiterEv.OnServerEvent:Connect(function(player, on)
			local model = droneByPlayer[player]
			if model then model:SetAttribute("Loiter", on == true) end
		end)
	end

	local modeEv = Remotes:FindFirstChild(Config.REM.SetMode)
	if modeEv then
		modeEv.OnServerEvent:Connect(function(player, mode)
			local model = droneByPlayer[player]
			if model and activeDrones[model] and activeDrones[model].cfg.Flags.Modes then
				model:SetAttribute("Mode", mode == "cruise" and "cruise" or "bombs")
			end
		end)
	end

	local detonateEv = Remotes:FindFirstChild(Config.REM.Detonate)
	if detonateEv then
		detonateEv.OnServerEvent:Connect(function(player)
			local model = droneByPlayer[player]
			local info = model and activeDrones[model]
			if info and info.cfg.Kind == "kamikaze" then
				kamikazeExplode(model, info)
			end
		end)
	end

	local markerEv = Remotes:FindFirstChild(Config.REM.DropMarker)
	if markerEv then
		markerEv.OnServerEvent:Connect(function(player, pos)
			if type(pos) ~= "Vector3" then return end
			local model = droneByPlayer[player]
			local info = model and activeDrones[model]
			if info and info.cfg.Flags.Marker then
				local mkEv = Remotes:FindFirstChild(Config.REM.MarkerFX)
				for _, pl in ipairs(Players:GetPlayers()) do
					if pl.Team and pl.Team.Name == Config.TEAM_OPS and mkEv then
						mkEv:FireClient(pl, pos)
					end
				end
			end
		end)
	end

	local returnEv = Remotes:FindFirstChild(Config.REM.ReturnDrone)
	if returnEv then
		returnEv.OnServerEvent:Connect(function(player)
			local model = droneByPlayer[player]
			local info = model and activeDrones[model]
			if not info then return end
			local dist = (info.primary.Position - PAD).Magnitude
			if dist < 90 then
				-- посадка: возврат 50% цены
				local refund = math.floor(info.cfg.Price * 0.5)
				if refund > 0 then Economy.Add(player, refund, "Посадка дрона") end
				removeDrone(model, nil, nil)
				fireRemote(Config.REM.OperFX, player, { type = "landed" })
			end
		end)
	end
end

-- ------------------------------------------------------------
-- ОСНОВНОЙ ЦИКЛ: топливо, камикадзе, рой, сирена, радар
-- ------------------------------------------------------------
local function heartbeatLoop(dt)
	-- камикадзе: проверка столкновений
	for model, info in pairs(activeDrones) do
		if not model.Parent then
			removeDrone(model, nil, nil)
		else
			local cfg = info.cfg
			local primary = info.primary
			if cfg.Kind == "kamikaze" then
				local vel = primary.AssemblyLinearVelocity
				local speed = vel.Magnitude
				if speed > 5 then
					local hit = workspace:Raycast(primary.Position, vel.Unit * (speed * dt * 1.6 + 3), rayParams)
					if hit or primary.Position.Y < 1 then
						kamikazeExplode(model, info)
					end
				elseif primary.Position.Y < 1 then
					kamikazeExplode(model, info)
				end
			end
			-- топливо
			if info.fuelLeft then
				info.fuelLeft = info.fuelLeft - dt
				model:SetAttribute("Fuel", math.max(0, math.floor(info.fuelLeft)))
				if info.fuelLeft <= 0 then
					kamikazeExplode(model, info) -- крушение
				end
			end
			-- скорость манёвра (для ПЗРК)
			local yaw = math.atan2(-primary.CFrame.LookVector.X, -primary.CFrame.LookVector.Z)
			local dyaw = math.abs(yaw - info.yawPrev)
			if dyaw > math.pi then dyaw = math.pi * 2 - dyaw end
			info.yawRate = Util.lerp(info.yawRate, dyaw / math.max(dt, 0.01), 0.2)
			info.yawPrev = yaw
			-- дым при повреждении
			local hpFrac = (model:GetAttribute("HP") or 1) / (model:GetAttribute("MaxHP") or 1)
			local emitter = primary:FindFirstChild("DamageSmoke")
			if hpFrac < 0.5 and not emitter then
				emitter = Instance.new("ParticleEmitter")
				emitter.Name = "DamageSmoke"
				emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
				emitter.Color = ColorSequence.new(Color3.fromRGB(40, 40, 40))
				emitter.Rate = 25
				emitter.Lifetime = NumberRange.new(1, 2)
				emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4) })
				emitter.Parent = primary
			end
		end
	end

	-- юниты роя в атаке
	for unit, a in pairs(attackingUnits) do
		if not unit.Parent then
			attackingUnits[unit] = nil
		else
			local pp = unit.PrimaryPart
			if pp then
				local toT = a.target - pp.Position
				if toT.Magnitude < 7 then
					attackingUnits[unit] = nil
					Destruction.Explode(pp.Position, a.cfg.BRadius, a.cfg.BDamage, { player = a.player })
					unit:Destroy()
				else
					pp.AssemblyLinearVelocity = Util.clampMag(toT.Unit * 160, 200)
				end
			end
		end
	end
end

local function fuelAndRadarLoop()
	local accum = 0
	while true do
		task.wait(2)
		-- радар для защитников
		local radarEv = Remotes and Remotes:FindFirstChild(Config.REM.Radar)
		if radarEv then
			for _, pl in ipairs(Players:GetPlayers()) do
				if pl.Team and pl.Team.Name == Config.TEAM_DEF then
					local blips = {}
					local myPos = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
					myPos = myPos and myPos.Position
					for model, info in pairs(activeDrones) do
						if model.Parent and info.primary then
							local pos = info.primary.Position
							local cfg = info.cfg
							if cfg.Flags.Stealth then
								-- «Охотник» виден только < 100 studs
								if myPos and (pos - myPos).Magnitude < 100 then
									table.insert(blips, { x = pos.X, y = pos.Y, z = pos.Z })
								end
							elseif cfg.Id == "molniya" then
								if math.random() < 0.15 then -- мелькает
									table.insert(blips, { x = pos.X, y = pos.Y, z = pos.Z })
								end
							else
								table.insert(blips, { x = pos.X, y = pos.Y, z = pos.Z })
							end
						end
					end
					radarEv:FireClient(pl, blips)
				end
			end
		end
		-- сирена: дрон вошёл в город
		local anyInCity = false
		for model, info in pairs(activeDrones) do
			if model.Parent and info.primary then
				local p = info.primary.Position
				if math.abs(p.X) < Config.MAP_HALF and p.Z > -Config.MAP_HALF and p.Z < Config.MAP_HALF then
					anyInCity = true
				end
			end
		end
		if anyInCity and os.clock() - lastSiren > 90 then
			lastSiren = os.clock()
			local sirenEv = Remotes and Remotes:FindFirstChild(Config.REM.Siren)
			if sirenEv then
				for _, pl in ipairs(Players:GetPlayers()) do sirenEv:FireClient(pl, "warn") end
			end
		end
	end
end

-- мониторинг операторов: смерть/выход → дрон падает
local function monitorOperators()
	while true do
		task.wait(2)
		for model, info in pairs(activeDrones) do
			local pl = info.player
			if not pl.Parent then
				removeDrone(model, info.primary and info.primary.Position, nil)
			else
				local char = pl.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health <= 0 then
					kamikazeExplode(model, info)
				end
			end
		end
	end
end

function DroneService.Init()
	bindRemotes()
	RunService.Heartbeat:Connect(heartbeatLoop)
	task.spawn(fuelAndRadarLoop)
	task.spawn(monitorOperators)
end

return DroneService
