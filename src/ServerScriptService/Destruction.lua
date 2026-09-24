-- ============================================================
--  Destruction — мега-разрушения зданий (СЕРВЕР)
--  Каждая разрушаемая Part имеет атрибуты: HP, MH (maxHP), K (kind),
--  и зарегистрирована здесь. Взрыв -> урон -> обломки -> обрушения.
-- ============================================================
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)

local Destruction = {}

-- Хуки (назначаются другими сервисами)
Destruction.OnExplosion = nil          -- fn(pos, radius, player)
Destruction.OnBuildingDestroyed = nil  -- fn(player, category, name, center)
Destruction.OnPartDestroyed = nil      -- fn(player, kind)
Destruction.OnDroneExplosion = nil     -- fn(droneModel, damage, player)
Destruction.Remotes = nil              -- папка RemoteEvents (для Shake)

local buildingsList = {}
local partInfo = {}     -- [part] = {hp, kind, building, floor, alive}
local fires = {}        -- { {part, expire, nextSpread, time} }
local debrisQueue = {}  -- FIFO обломков
local stats = { total = 0, destroyed = 0 }

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
overlapParams.FilterDescendantsInstances = {}

function Destruction.SetExcludes(list) overlapParams.FilterDescendantsInstances = list end

function Destruction.Stats() return stats end

-- ------------------------------------------------------------
-- Регистрация
-- ------------------------------------------------------------
function Destruction.RegisterBuilding(category, name, center)
	local b = {
		category = category, name = name, center = center,
		floors = {}, aliveParts = 0, deadParts = 0,
		collapsed = {}, destroyed = false, lastPlayer = nil,
	}
	table.insert(buildingsList, b)
	return b
end

function Destruction.AttachPart(part, hp, kind, building, floorIndex)
	part:SetAttribute("HP", hp)
	part:SetAttribute("MH", hp)
	part:SetAttribute("K", kind)
	partInfo[part] = { hp = hp, kind = kind, building = building, floor = floorIndex or 0 }
	if building then
		building.aliveParts = building.aliveParts + 1
		local f = building.floors[floorIndex or 0]
		if not f then f = { wallTotal = 0, wallDead = 0, colTotal = 0, colDead = 0 } building.floors[floorIndex or 0] = f end
		if kind == "Wall" then f.wallTotal = f.wallTotal + 1
		elseif kind == "Column" then f.colTotal = f.colTotal + 1 end
	end
	if kind ~= "Shield" then stats.total = stats.total + 1 end
end

function Destruction.GetInfo(part) return partInfo[part] end

-- ------------------------------------------------------------
-- Обломки (лимит 200)
-- ------------------------------------------------------------
local function addDebris(part, life)
	table.insert(debrisQueue, { part = part, t = os.clock() })
	Debris:AddItem(part, life or math.random(8, 12))
	while #debrisQueue > Config.MAX_DEBRIS do
		local old = table.remove(debrisQueue, 1)
		if old.part and old.part.Parent then old.part:Destroy() end
	end
end

local function spawnChunks(part, explosionPos)
	local n = math.random(3, 6)
	for i = 1, n do
		local chunk = Instance.new("Part")
		chunk.Size = Vector3.new(part.Size.X, part.Size.Y, part.Size.Z) * (0.2 + math.random() * 0.25)
		if chunk.Size.Magnitude > 14 then chunk.Size = chunk.Size.Unit * 14 end
		chunk.Material = part.Material
		chunk.Color = part.Color
		chunk.Anchored = false
		chunk.CanCollide = true
		chunk.CFrame = part.CFrame * CFrame.Angles(math.random() * 3, math.random() * 3, math.random() * 3)
		local away = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5)
		if explosionPos then
			local dir = (part.Position - explosionPos)
			if dir.Magnitude > 0.1 then away = away + dir.Unit * 0.8 end
		end
		chunk.AssemblyLinearVelocity = away * math.random(20, 45)
		chunk.Parent = workspace
		addDebris(chunk)
	end
end

-- ------------------------------------------------------------
-- Разрушение отдельной части
-- ------------------------------------------------------------
local function buildingFloorTable(building, floor)
	local f = building.floors[floor]
	if not f then f = { wallTotal = 0, wallDead = 0, colTotal = 0, colDead = 0 } building.floors[floor] = f end
	return f
end

local CheckCollapseFn -- forward declare

local function destroyPartNow(part, explosionPos, player)
	local info = partInfo[part]
	if not info then return end
	partInfo[part] = nil
	local building = info.building
	if building then
		building.aliveParts = building.aliveParts - 1
		building.deadParts = building.deadParts + 1
		building.lastPlayer = player or building.lastPlayer
		local f = buildingFloorTable(building, info.floor)
		if info.kind == "Wall" then f.wallDead = f.wallDead + 1
		elseif info.kind == "Column" then f.colDead = f.colDead + 1 end
		stats.destroyed = stats.destroyed + 1
	else
		stats.destroyed = stats.destroyed + 1
	end
	if Destruction.OnPartDestroyed then Destruction.OnPartDestroyed(player, info.kind) end
	-- обломки
	spawnChunks(part, explosionPos)
	Util.burst(part.Position, { radius = math.min(part.Size.Magnitude * 0.5, 8), fireCount = 8, smokeCount = 10 })
	part:Destroy()
	if building and info.kind == "Column" then
		CheckCollapseFn(building, info.floor, player)
	end
end

function Destruction.ShatterWindow(part)
	local info = partInfo[part]
	if not info or info.kind ~= "Window" then return end
	partInfo[part] = nil
	stats.destroyed = stats.destroyed + 1
	if info.building then
		info.building.aliveParts = info.building.aliveParts - 1
		info.building.deadParts = info.building.deadParts + 1
		info.building.lastPlayer = info.building.lastPlayer
	end
	if Destruction.OnPartDestroyed then Destruction.OnPartDestroyed(nil, "Window") end
	-- осколки стекла
	Util.burst(part.Position, { radius = 3, fireCount = 0, smokeCount = 0 })
	local glass = Instance.new("Part")
	glass.Anchored = false; glass.CanCollide = false
	glass.Size = Vector3.new(0.4, 0.4, 0.05)
	glass.Material = Enum.Material.Glass
	glass.Color = Color3.fromRGB(200, 220, 235)
	glass.Transparency = 0.3
	glass.CFrame = part.CFrame
	glass.Parent = workspace
	Util.sound3d(Config.SOUNDS.Glass, part.Position, 0.8, 1, 120, 3)
	Debris:AddItem(glass, 2)
	part:Destroy()
end

-- Урон конкретной части
function Destruction.DamagePart(part, dmg, player, explosionPos)
	local info = partInfo[part]
	if not info then return end
	if info.kind == "Window" then Destruction.ShatterWindow(part) return end
	if info.building then info.building.lastPlayer = player or info.building.lastPlayer end
	info.hp = info.hp - dmg
	part:SetAttribute("HP", math.max(0, math.floor(info.hp)))
	if info.hp <= 0 then
		destroyPartNow(part, explosionPos, player)
	end
end

-- ------------------------------------------------------------
-- Обрушение этажа
-- ------------------------------------------------------------
CheckCollapseFn = function(building, floor, player)
	if building.destroyed then return end
	local f = building.floors[floor]
	if not f then return end
	local wallGone = f.wallTotal > 0 and (f.wallDead / f.wallTotal) >= 0.5
	local colsGone = f.colTotal > 0 and f.colDead >= f.colTotal
	if not (wallGone or colsGone) then return end
	if building.collapsed[floor] then return end
	building.collapsed[floor] = true

	-- всё ВЫШЕ этого этажа падает
	local center = building.center
	local dropCount = 0
	for part, info in pairs(partInfo) do
		if info.building == building and info.floor > floor and part.Parent then
			part.Anchored = false
			part.AssemblyLinearVelocity = Vector3.new((math.random() - 0.5) * 8, -4, (math.random() - 0.5) * 8)
			addDebris(part, math.random(6, 10))
			stats.destroyed = stats.destroyed + 1
			dropCount = dropCount + 1
		end
	end
	-- повторить проверку для этажей выше (каскад)
	for fl in pairs(building.floors) do
		if fl > floor then building.collapsed[fl] = true end
	end

	-- эффекты: грохот + пылевое облако + тряска
	local base = Vector3.new(center.X, 2, center.Z)
	Util.sound3d(Config.SOUNDS.Collapse, base, 2.5, 0.6, 400, 8)
	Util.sound3d(Config.SOUNDS.Explosion, base, 1.5, 0.5, 300, 5)
	for i = 1, 3 do
		task.delay(i * 0.4, function()
			Util.burst(base + Vector3.new((math.random() - 0.5) * 30, math.random() * 6, (math.random() - 0.5) * 30),
				{ radius = 16, fireCount = 0, smokeCount = 40 })
		end)
	end
	if Destruction.Remotes then
		local shakeEv = Destruction.Remotes:FindFirstChild(Config.REM.Shake)
		if shakeEv then
			for _, pl in ipairs(game:GetService("Players"):GetPlayers()) do
				local char = pl.Character
				if char and char.PrimaryPart and (char.PrimaryPart.Position - base).Magnitude < 120 then
					shakeEv:FireClient(pl, 1.2)
				end
			end
		end
	end
end

-- ------------------------------------------------------------
-- Уничтожение здания целиком (бонус)
-- ------------------------------------------------------------
local function checkBuildingDestroyed(building)
	if building.destroyed then return end
	local ratio = building.deadParts / math.max(1, building.deadParts + building.aliveParts)
	local collapsedCount = 0
	for _ in pairs(building.collapsed) do collapsedCount = collapsedCount + 1 end
	local floorCount = 0
	for _ in pairs(building.floors) do floorCount = floorCount + 1 end
	if ratio >= 0.7 or (floorCount > 0 and collapsedCount >= math.max(1, math.floor(floorCount * 0.6))) then
		building.destroyed = true
		if Destruction.OnBuildingDestroyed then
			Destruction.OnBuildingDestroyed(building.lastPlayer, building.category, building.name, building.center)
		end
	end
end
-- периодическая проверка уничтоженных зданий
task.spawn(function()
	while true do
		task.wait(3)
		for _, b in ipairs(buildingsList) do
			if not b.destroyed then checkBuildingDestroyed(b) end
		end
	end
end)

-- ------------------------------------------------------------
-- Воронка
-- ------------------------------------------------------------
local function crater(pos, radius)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = overlapParams.FilterDescendantsInstances
	local hit = workspace:Raycast(pos, Vector3.new(0, -60, 0), rayParams)
	if not hit then return end
	if hit.Instance == workspace.Terrain then
		workspace.Terrain:FillBall(hit.Position + Vector3.new(0, 0.5, 0), math.max(2, radius * 0.35), Enum.Material.Air)
	end
	-- тёмный круг-декаль
	local scorch = Instance.new("Part")
	scorch.Anchored = true; scorch.CanCollide = false; scorch.CanQuery = false
	scorch.Shape = Enum.PartType.Cylinder
	scorch.Size = Vector3.new(0.2, radius * 1.2, radius * 1.2)
	scorch.CFrame = CFrame.new(hit.Position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	scorch.Color = Color3.fromRGB(25, 22, 20)
	scorch.Material = Enum.Material.Slate
	scorch.Parent = workspace
	Debris:AddItem(scorch, 240)
end
Destruction.Crater = crater

-- ------------------------------------------------------------
-- Пожар
-- ------------------------------------------------------------
function Destruction.Ignite(pos, fireTime, player)
	local count = 0
	for _ in pairs(fires) do count = count + 1 end
	if count >= 80 then return end
	local holder = Instance.new("Part")
	holder.Anchored = true; holder.CanCollide = false; holder.CanQuery = false; holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(1, 1, 1)
	holder.Position = pos
	local fire = Instance.new("Fire")
	fire.Size = math.min(14, 4 + fireTime * 0.1)
	fire.Heat = 12
	fire.Parent = holder
	local smoke = Instance.new("Smoke")
	smoke.Size = 8
	smoke.RiseVelocity = 8
	smoke.Opacity = 0.4
	smoke.Parent = holder
	holder.Parent = workspace
	table.insert(fires, { part = holder, expire = os.clock() + fireTime, nextSpread = os.clock() + 5 })
	Debris:AddItem(holder, fireTime + 2)
end

-- тик пожаров
task.spawn(function()
	while true do
		task.wait(1)
		local now = os.clock()
		for i = #fires, 1, -1 do
			local f = fires[i]
			if not f.part.Parent or now > f.expire then
				table.remove(fires, i)
			elseif now >= f.nextSpread then
				f.nextSpread = now + 5
				-- распространение: соседние стеновые секции получают 10 урона
				local params = OverlapParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = overlapParams.FilterDescendantsInstances
				local near = workspace:GetPartBoundsInRadius(f.part.Position, 8, params)
				for _, p in ipairs(near) do
					local info = partInfo[p]
					if info and (info.kind == "Wall" or info.kind == "Column" or info.kind == "Prop") and info.hp > 0 then
						local wasAlive = info.hp
						Destruction.DamagePart(p, 10, nil)
						local after = partInfo[p]
						if not after and wasAlive > 0 then
							-- часть сгорела — загорается дальше
							Destruction.Ignite(p.Position, 20, nil)
						end
					end
				end
			end
		end
	end
end)

-- ------------------------------------------------------------
-- ВТОРИЧНЫЙ ВЗРЫВ (заправки, цистерны, автомобили)
-- ------------------------------------------------------------
local function secondaryBoom(part, player)
	if part:GetAttribute("BoomDone") then return end
	part:SetAttribute("BoomDone", true)
	local pos = part.Position
	local big = part:GetAttribute("BoomPower") or 40
	task.delay(0.9, function()
		-- огненный шар
		local ballPart = Instance.new("Part")
		ballPart.Anchored = true; ballPart.CanCollide = false; ballPart.CanQuery = false
		ballPart.Shape = Enum.PartType.Ball
		ballPart.Material = Enum.Material.Neon
		ballPart.Color = Color3.fromRGB(255, 150, 40)
		ballPart.Size = Vector3.new(1, 1, 1)
		ballPart.Position = pos
		ballPart.Parent = workspace
		local tween = game:GetService("TweenService")
		tween:Create(ballPart, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(big, big, big), Transparency = 1 }):Play()
		Debris:AddItem(ballPart, 1)
		Destruction.Explode(pos, big, 80, { player = player, fireTime = 30, crater = true })
	end)
end

-- ------------------------------------------------------------
-- ГЛАВНЫЙ ВЗРЫВ
-- ------------------------------------------------------------
function Destruction.Explode(pos, radius, damage, opts)
	opts = opts or {}
	local player = opts.player

	-- визуал
	Util.burst(pos, { radius = math.min(radius, 25), fireCount = math.floor(radius * 2), smokeCount = math.floor(radius) })
	Util.sound3d(Config.SOUNDS.Explosion, pos, 3, 0.8 + math.random() * 0.2, 400, 6)
	if radius >= 25 then
		Util.sound3d(Config.SOUNDS.BigExplosion, pos, 3, 0.7, 500, 8)
	end
	local flash = Instance.new("PointLight")
	flash.Color = Color3.fromRGB(255, 180, 80)
	flash.Brightness = 10
	flash.Range = radius * 2
	flash.Shadows = false
	local fp = Instance.new("Part")
	fp.Anchored = true; fp.CanCollide = false; fp.CanQuery = false; fp.Transparency = 1
	fp.Size = Vector3.new(1, 1, 1); fp.Position = pos; fp.Parent = workspace
	flash.Parent = fp
	Debris:AddItem(fp, 0.4)

	-- урон дронам поблизости
	if Destruction.OnDroneExplosion then
		Destruction.OnDroneExplosion(pos, radius, damage, player)
	end

	-- тряска всем в радиусе
	if Destruction.Remotes then
		local shakeEv = Destruction.Remotes:FindFirstChild(Config.REM.Shake)
		if shakeEv then
			for _, pl in ipairs(game:GetService("Players"):GetPlayers()) do
				local char = pl.Character
				if char and char.PrimaryPart and (char.PrimaryPart.Position - pos).Magnitude < radius + 80 then
					shakeEv:FireClient(pl, math.min(2, radius / 30))
				end
			end
		end
	end

	-- урон игрокам (защитникам и всем)
	for _, pl in ipairs(game:GetService("Players"):GetPlayers()) do
		local char = pl.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 then
			local d = (hrp.Position - pos).Magnitude
			if d < radius then
				local dmg = damage * (1 - 0.7 * d / radius)
				if opts.armorPen then dmg = dmg * 1.25 end
				hum:TakeDamage(dmg)
				if opts.knockback then
					local away = (hrp.Position - pos)
					if away.Magnitude < 0.5 then away = Vector3.new(0, 1, 0) end
					hrp.AssemblyLinearVelocity = away.Unit * 50 + Vector3.new(0, 30, 0)
				end
			end
		end
	end

	-- урон частям зданий
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = overlapParams.FilterDescendantsInstances
	local parts = workspace:GetPartBoundsInRadius(pos, radius, params)
	local hitBuildings = {}
	for _, p in ipairs(parts) do
		local info = partInfo[p]
		if info then
			if info.kind == "Window" then
				Destruction.ShatterWindow(p)
			else
				Destruction.DamagePart(p, damage, player, pos)
			end
			if info.building then table.insert(hitBuildings, info.building) end
		elseif p:GetAttribute("Boom") and not p:GetAttribute("BoomDone") then
			secondaryBoom(p, player)
		end
	end
	for _, b in ipairs(hitBuildings) do checkBuildingDestroyed(b) end

	-- пожар и воронка
	if opts.fireTime and opts.fireTime > 0 then
		Destruction.Ignite(pos + Vector3.new(0, 2, 0), opts.fireTime, player)
	end
	if opts.crater then crater(pos, radius) end

	if Destruction.OnExplosion then Destruction.OnExplosion(pos, radius, player) end
end

-- ------------------------------------------------------------
function Destruction.Reset()
	partInfo = {}
	fires = {}
	debrisQueue = {}
	buildingsList = {}
	stats = { total = 0, destroyed = 0 }
end

return Destruction
