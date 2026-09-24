-- ============================================================
--  NpcService — мирные жители (гуляют, разбегаются от взрывов)
--  и утки в пруду. Атмосферный элемент.
-- ============================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)
local Destruction = require(script.Parent.Destruction)

local NpcService = {}
local waypoints = {}
local civilians = {}

local SHIRT_COLORS = {
	Color3.fromRGB(120, 130, 150), Color3.fromRGB(160, 120, 100), Color3.fromRGB(100, 140, 110),
	Color3.fromRGB(140, 140, 160), Color3.fromRGB(90, 100, 130), Color3.fromRGB(170, 150, 120),
}

local function makeCivilian(pos)
	local model = Instance.new("Model")
	model.Name = "Житель"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Color = SHIRT_COLORS[math.random(1, #SHIRT_COLORS)]
	root.Material = Enum.Material.SmoothPlastic
	root.TopSurface = Enum.SurfaceType.Smooth
	root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
	root.Parent = model
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.Color = Color3.fromRGB(235, 204, 175)
	head.CanCollide = false
	head.CFrame = root.CFrame * CFrame.new(0, 1.5, 0)
	head.Parent = model
	local legL = Instance.new("Part")
	legL.Size = Vector3.new(0.8, 2, 0.8)
	legL.Color = Color3.fromRGB(60, 60, 80)
	legL.CanCollide = false
	legL.CFrame = root.CFrame * CFrame.new(-0.5, -2, 0)
	legL.Parent = model
	local legR = legL:Clone()
	legR.CFrame = root.CFrame * CFrame.new(0.5, -2, 0)
	legR.Parent = model
	for _, p in ipairs({ head, legL, legR }) do
		local w = Instance.new("WeldConstraint")
		w.Part0 = root; w.Part1 = p
		w.Parent = root
	end
	local hum = Instance.new("Humanoid")
	hum.HipHeight = 2.2
	hum.WalkSpeed = 8
	hum.MaxHealth = 30
	hum.Health = 30
	hum.Parent = model
	model.PrimaryPart = root
	model.Parent = workspace
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = false end
	end
	root:SetNetworkOwner(nil)
	return { model = model, hum = hum, root = root, busy = false }
end

local function wander(civ)
	if not civ.model.Parent or civ.hum.Health <= 0 then return end
	local target = waypoints[math.random(1, #waypoints)]
	-- ищем ближайшие 3 случайных попытки
	for i = 1, 3 do
		local wp = waypoints[math.random(1, #waypoints)]
		if (wp - civ.root.Position).Magnitude < 400 then target = wp break end
	end
	civ.busy = true
	civ.hum:MoveTo(target)
	local t0 = os.clock()
	local conn
	conn = civ.hum.MoveToFinished:Connect(function()
		conn:Disconnect()
		civ.busy = false
	end)
	task.delay(14, function()
		if conn.Connected then conn:Disconnect() end
		civ.busy = false
	end)
end

local function fleeFrom(pos)
	for _, civ in ipairs(civilians) do
		if civ.model.Parent and civ.hum.Health > 0 then
			local d = (civ.root.Position - pos).Magnitude
			if d < 90 then
				-- бежать к самому дальнему путику
				local best, bestD = nil, 0
				for _, wp in ipairs(waypoints) do
					local dd = (wp - pos).Magnitude
					if dd > bestD and (wp - civ.root.Position).Magnitude < 600 then
						best, bestD = wp, dd
					end
				end
				if best then
					civ.hum.WalkSpeed = 18
					civ.hum:MoveTo(best)
					task.delay(6, function()
						if civ.hum then civ.hum.WalkSpeed = 8 end
					end)
				end
			end
		end
	end
end

function NpcService.Init()
	waypoints = MapGenWaypoints()
	-- хук взрывов: жители паникуют и гибнут
	local prev = Destruction.OnExplosion
	Destruction.OnExplosion = function(pos, radius, player)
		if prev then prev(pos, radius, player) end
		fleeFrom(pos)
		for _, civ in ipairs(civilians) do
			if civ.model.Parent and civ.hum.Health > 0 then
				if (civ.root.Position - pos).Magnitude < radius then
					Util.sound3d(Config.SOUNDS.Hurt, civ.root.Position, 1, 1, 80, 3)
					civ.hum.Health = 0
				end
			end
		end
	end

	-- спавн жителей
	task.spawn(function()
		task.wait(3)
		for i = 1, 20 do
			local wp = waypoints[math.random(1, #waypoints)]
			table.insert(civilians, makeCivilian(wp + Vector3.new(math.random(-8, 8), 0, math.random(-8, 8))))
			task.wait(0.2)
		end
	end)

	-- поведение
	task.spawn(function()
		while true do
			task.wait(math.random(3, 7))
			for _, civ in ipairs(civilians) do
				if not civ.busy then wander(civ) end
			end
		end
	end)

	-- убираем погибших и возрождаем новых
	task.spawn(function()
		while true do
			task.wait(10)
			for i = #civilians, 1, -1 do
				local civ = civilians[i]
				if not civ.model.Parent or civ.hum.Health <= 0 then
					if civ.model.Parent then DebrisRemove(civ.model) end
					table.remove(civilians, i)
				end
			end
			while #civilians < 20 do
				local wp = waypoints[math.random(1, #waypoints)]
				table.insert(civilians, makeCivilian(wp))
				task.wait(0.3)
			end
		end
	end)

	spawnDucks()
end

-- прокси чтобы не тянуть MapGenerator циклически
local MapGenRef
function NpcService.SetMapGenerator(m) MapGenRef = m end
function MapGenWaypoints()
	if MapGenRef then return MapGenRef.NPCWaypoints end
	return { Vector3.new(0, 3, 0) }
end

function DebrisRemove(model)
	game:GetService("Debris"):AddItem(model, 1)
	-- человечек «падает» и исчезает
	if model.PrimaryPart then
		model.PrimaryPart.Anchored = false
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = false end
	end
end

-- ------------------------------------------------------------
-- УТКИ В ПРУДУ (анимированные)
-- ------------------------------------------------------------
local function makeDuck(center, phase)
	local model = Instance.new("Model")
	model.Name = "Утка"
	local body = Util.part({ Size = Vector3.new(1.6, 1, 2.2), CFrame = CFrame.new(center), Color = Color3.fromRGB(210, 190, 160), Material = Enum.Material.SmoothPlastic }, model)
	local head = Util.part({ Size = Vector3.new(0.8, 0.8, 0.8), CFrame = CFrame.new(center) * CFrame.new(0, 0.8, -1), Color = Color3.fromRGB(90, 190, 90), Material = Enum.Material.SmoothPlastic }, model)
	local beak = Util.part({ Size = Vector3.new(0.3, 0.25, 0.6), CFrame = CFrame.new(center) * CFrame.new(0, 0.75, -1.6), Color = Color3.fromRGB(240, 170, 40), Material = Enum.Material.SmoothPlastic }, model)
	model.PrimaryPart = body
	model.Parent = workspace
	return { model = model, body = body, center = center, phase = phase }
end

function spawnDucks()
	local spots = MapGenRef and MapGenRef.DuckSpots or {}
	task.spawn(function()
		task.wait(5)
		local ducks = {}
		for i, spot in ipairs(spots) do
			for j = 1, 2 do
				table.insert(ducks, makeDuck(spot + Vector3.new(j * 4 - 2, 1, (i - 1) * 6), (i + j) * 1.7))
			end
		end
		local t = 0
		RunService.Heartbeat:Connect(function(dt)
			t = t + dt
			for _, d in ipairs(ducks) do
				if d.model.Parent then
					local ang = t * 0.5 + d.phase
					local r = 7 + math.sin(t * 0.3 + d.phase) * 3
					local pos = d.center + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
					local cf = CFrame.lookAt(pos, pos + Vector3.new(-math.sin(ang), 0, math.cos(ang)) * 5)
					d.model:PivotTo(cf * CFrame.new(0, math.abs(math.sin(t * 4 + d.phase)) * 0.15, 0))
				end
			end
		end)
	end)
end

-- Пересоздание после нового раунда
function NpcService.Rebuild()
	for _, civ in ipairs(civilians) do
		if civ.model and civ.model.Parent then civ.model:Destroy() end
	end
	civilians = {}
	waypoints = MapGenWaypoints()
	for _, obj in ipairs(workspace:GetChildren()) do
		if obj:IsA("Model") and obj.Name == "Утка" then obj:Destroy() end
	end
	spawnDucks()
end

return NpcService
