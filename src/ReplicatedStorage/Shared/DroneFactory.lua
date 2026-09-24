-- ============================================================
--  DroneFactory — процедурная сборка моделей всех 10 дронов.
--  Модели смотрят носом в -Z (стандартный LookVector).
--  Пропеллеры помечаются атрибутом SpinSpeed (крутит клиент).
-- ============================================================
local DroneFactory = {}

local function box(parent, cf, size, color, material, transparency)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size; p.CFrame = cf
	p.Color = color; p.Material = material or Enum.Material.Metal
	if transparency then p.Transparency = transparency end
	p.Parent = parent
	return p
end

local function ball(parent, cf, d, color, material)
	local p = box(parent, cf, Vector3.new(d, d, d), color, material)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

-- Цилиндр вдоль оси Z
local function tube(parent, cf, diameter, length, color, material)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(length, diameter, diameter)
	p.CFrame = cf * CFrame.Angles(0, math.rad(90), 0) -- ось цилиндра (X) -> Z
	p.Color = color; p.Material = material or Enum.Material.Metal
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Пропеллер: крест лопастей + полупрозрачный диск размытия
local function prop(parent, cf, d, color)
	local propModel = Instance.new("Model")
	propModel.Name = "Prop"
	local hub = box(propModel, cf, Vector3.new(0.3, 0.3, 0.3), color)
	local blade1 = box(propModel, cf * CFrame.Angles(0, math.rad(45), 0), Vector3.new(d, 0.08, 0.45), color)
	local blade2 = box(propModel, cf * CFrame.Angles(0, math.rad(135), 0), Vector3.new(d, 0.08, 0.45), color)
	blade1:SetAttribute("SpinSpeed", 1400)
	blade2:SetAttribute("SpinSpeed", 1400)
	local blur = box(propModel, cf, Vector3.new(d, 0.05, d), color, Enum.Material.Glass, 0.85)
	blur.Name = "BlurDisc"
	blur:SetAttribute("BlurDisc", true)
	propModel.Parent = parent
	return propModel
end

-- Финализация: сварить всё с PrimaryPart
local function finalize(model, primary)
	model.PrimaryPart = primary
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p ~= primary then
			local w = Instance.new("WeldConstraint")
			w.Part0 = primary; w.Part1 = p
			w.Parent = primary
		end
	end
	return model
end

-- ------------------------------------------------------------
local Builders = {}

-- 1. «Пчела» — квадрокоптер 3x3
function Builders.pchela(model, c)
	local body = box(model, CFrame.new(0, 0, 0), Vector3.new(1.6, 0.7, 1.6), Color3.fromRGB(60, 62, 66), Enum.Material.SmoothPlastic)
	local cam = ball(model, CFrame.new(0, -0.55, 0.3), 0.7, Color3.fromRGB(20, 20, 20), Enum.Material.Glass)
	local armLen = 2.6
	for _, sx in ipairs({-1, 1}) do
		for _, sz in ipairs({-1, 1}) do
			local armPos = CFrame.new(sx * armLen / 2, 0.15, sz * armLen / 2) * CFrame.Angles(0, math.rad(45 * sx * sz), 0)
			box(model, CFrame.new(0, 0.15, 0):Lerp(CFrame.new(sx * armLen / 2, 0.15, sz * armLen / 2), 0.5), Vector3.new(2.0, 0.18, 0.18), Color3.fromRGB(40, 40, 40))
			prop(model, armPos * CFrame.new(0, 0.35, 0), 1.5, Color3.fromRGB(25, 25, 25))
		end
	end
	local skid1 = box(model, CFrame.new(-0.5, -0.75, 0), Vector3.new(0.12, 0.5, 1.4), Color3.fromRGB(30, 30, 30))
	local skid2 = box(model, CFrame.new(0.5, -0.75, 0), Vector3.new(0.12, 0.5, 1.4), Color3.fromRGB(30, 30, 30))
	return finalize(model, body)
end

-- 2. «Упырь» — FPV камикадзе 2x2
function Builders.upyr(model, c)
	local body = box(model, CFrame.new(0, 0, 0), Vector3.new(1.2, 0.4, 1.8), Color3.fromRGB(28, 28, 30), Enum.Material.DiamondPlate)
	for _, sx in ipairs({-1, 1}) do
		for _, sz in ipairs({-1, 1}) do
			box(model, CFrame.new(sx * 1.0, 0, sz * 0.7), Vector3.new(0.9, 0.12, 0.12), Color3.fromRGB(28, 28, 30))
			prop(model, CFrame.new(sx * 1.0, 0.15, sz * 0.7), 1.3, Color3.fromRGB(15, 15, 15))
		end
	end
	local gopro = box(model, CFrame.new(0, 0.28, -0.85), Vector3.new(0.5, 0.5, 0.35), Color3.fromRGB(15, 15, 15), Enum.Material.Glass)
	local lens = ball(model, CFrame.new(0, 0.28, -1.05), 0.35, Color3.fromRGB(90, 130, 255), Enum.Material.Neon)
	local warhead = ball(model, CFrame.new(0, -0.35, 0.1), 0.9, Color3.fromRGB(120, 30, 30))
	return finalize(model, body)
end

-- 3/4. Герань-1 и Герань-2 — дельтадрон с толкающим пропеллером
local function geran(model, c, size, color, accent)
	local L, W, H = size.X, size.Y, size.Z
	local body = tube(model, CFrame.new(0, 0, 0), H, L, color)
	local nose = ball(model, CFrame.new(0, 0, -L / 2), H * 1.05, color)
	-- дельтовидное крыло: два клина
	local wingSpan = W
	local wingL = box(model, CFrame.new(-wingSpan / 4, 0, L * 0.1) * CFrame.Angles(0, math.rad(14), 0), Vector3.new(wingSpan / 2, 0.18, L * 0.55), color)
	local wingR = box(model, CFrame.new(wingSpan / 4, 0, L * 0.1) * CFrame.Angles(0, math.rad(-14), 0), Vector3.new(wingSpan / 2, 0.18, L * 0.55), color)
	-- законцовки вниз (для Герань-2 крупнее)
	box(model, CFrame.new(-wingSpan / 2, -0.5, L * 0.28), Vector3.new(0.15, 1.2, L * 0.3), color)
	box(model, CFrame.new(wingSpan / 2, -0.5, L * 0.28), Vector3.new(0.15, 1.2, L * 0.3), color)
	-- V-образное хвостовое оперение
	local tailL = box(model, CFrame.new(-0.5, H * 0.5, L * 0.42) * CFrame.Angles(math.rad(40), 0, math.rad(10)), Vector3.new(0.12, 1.6, L * 0.3), color)
	local tailR = box(model, CFrame.new(0.5, H * 0.5, L * 0.42) * CFrame.Angles(math.rad(40), 0, math.rad(-10)), Vector3.new(0.12, 1.6, L * 0.3), color)
	-- нижний киль
	box(model, CFrame.new(0, -H * 0.6, L * 0.38), Vector3.new(0.12, 1.2, L * 0.28), color)
	-- толкающий пропеллер сзади
	prop(model, CFrame.new(0, 0, L / 2 + 0.5), H * 2.4, Color3.fromRGB(20, 20, 20))
	-- камуфляжная полоса + военная маркировка (красная звезда-полоса)
	local stripe = box(model, CFrame.new(0, 0.02, -L * 0.05) * CFrame.Angles(0, 0, 0), Vector3.new(W * 0.5, 0.06, 1.2), accent or Color3.fromRGB(70, 30, 30))
	local mark = box(model, CFrame.new(0, 0.05, -L * 0.25), Vector3.new(1.4, 0.06, 0.5), Color3.fromRGB(160, 30, 30))
	return finalize(model, body)
end

function Builders.geran1(model, c) return geran(model, c, Vector3.new(10, 1.4, 8), Color3.fromRGB(58, 68, 48)) end
function Builders.geran2(model, c) return geran(model, c, Vector3.new(14, 1.7, 10), Color3.fromRGB(92, 98, 76)) end

-- 5. «Орлан-10» — самолёт с прямым крылом, толкающий винт
function Builders.orlan(model, c)
	local color = Color3.fromRGB(158, 163, 168)
	local body = tube(model, CFrame.new(0, 0, 0), 2.2, 12, color)
	local nose = ball(model, CFrame.new(0, 0, -6), 2.3, color)
	local turret = ball(model, CFrame.new(0, -1.2, -4.5), 1.3, Color3.fromRGB(30, 30, 30), Enum.Material.Glass)
	local wing = box(model, CFrame.new(0, 0.4, 1), Vector3.new(20, 0.25, 2.6), color)
	box(model, CFrame.new(-9.5, 0.8, 1), Vector3.new(1.2, 0.8, 2.2), color)
	box(model, CFrame.new(9.5, 0.8, 1), Vector3.new(1.2, 0.8, 2.2), color)
	local tailL = box(model, CFrame.new(-1, 1.2, 5.5) * CFrame.Angles(math.rad(45), 0, 0), Vector3.new(0.15, 2.4, 1.6), color)
	local tailR = box(model, CFrame.new(1, 1.2, 5.5) * CFrame.Angles(math.rad(45), 0, 0), Vector3.new(0.15, 2.4, 1.6), color)
	prop(model, CFrame.new(0, 0, 6.6), 3.4, Color3.fromRGB(25, 25, 25))
	box(model, CFrame.new(0, -1.6, 0.5), Vector3.new(0.2, 1.2, 5), color) -- лыжа шасси
	return finalize(model, body)
end

-- 6. «Ланцет-3» — X-крыло, серебристый
function Builders.lancet(model, c)
	local color = Color3.fromRGB(198, 200, 205)
	local body = tube(model, CFrame.new(0, 0, 0), 1.3, 6, color, Enum.Material.SmoothPlastic)
	local nose = ball(model, CFrame.new(0, 0, -3), 1.4, Color3.fromRGB(25, 30, 35), Enum.Material.Glass)
	for i, ang in ipairs({45, 135, 225, 315}) do
		local dir = CFrame.Angles(0, math.rad(ang), 0)
		local fin = box(model, CFrame.new(0, 0, 0.8) * dir * CFrame.new(2.2, 0, 0) * CFrame.Angles(0, 0, math.rad(-8)), Vector3.new(4.4, 0.14, 1.6), color)
	end
	prop(model, CFrame.new(0, 0, 3.3), 2.2, Color3.fromRGB(60, 60, 60))
	return finalize(model, body)
end

-- 7. «Иноходец» (Орион) — большой MALE-БПЛА
function Builders.inohodets(model, c)
	local color = Color3.fromRGB(218, 218, 212)
	local body = tube(model, CFrame.new(0, 0, 0), 2.6, 18, color)
	local nose = ball(model, CFrame.new(0, 0, -9), 2.8, color)
	local turret = ball(model, CFrame.new(0, -1.5, -6.5), 1.6, Color3.fromRGB(30, 30, 30), Enum.Material.Glass)
	local wing = box(model, CFrame.new(0, 0.5, 1.5), Vector3.new(35, 0.3, 3.4), color)
	for _, sx in ipairs({-1, 1}) do
		for _, off in ipairs({4, 10}) do
			-- пилоны с ракетами
			box(model, CFrame.new(sx * off, -0.9, 1.5), Vector3.new(0.25, 1.0, 0.25), color)
			local rocket = tube(model, CFrame.new(sx * off, -1.7, 1.5), 0.6, 3.4, Color3.fromRGB(200, 190, 120))
		end
		box(model, CFrame.new(sx * 16, 1.0, 1.5), Vector3.new(1.5, 0.9, 2.6), color)
	end
	local tailL = box(model, CFrame.new(-1.2, 1.6, 8) * CFrame.Angles(math.rad(45), 0, 0), Vector3.new(0.18, 3.2, 2.2), color)
	local tailR = box(model, CFrame.new(1.2, 1.6, 8) * CFrame.Angles(math.rad(45), 0, 0), Vector3.new(0.18, 3.2, 2.2), color)
	prop(model, CFrame.new(0, 0, 9.6), 4.6, Color3.fromRGB(25, 25, 25))
	return finalize(model, body)
end

-- 8. «Охотник» — летающее крыло (B-2 стиль)
function Builders.ohotnik(model, c)
	local color = Color3.fromRGB(45, 48, 52)
	local body = box(model, CFrame.new(0, 0, 0), Vector3.new(16, 1.6, 12), color, Enum.Material.SmoothPlastic)
	local wingL = box(model, CFrame.new(-11, 0, 3) * CFrame.Angles(0, math.rad(28), 0), Vector3.new(17, 1.2, 9), color, Enum.Material.SmoothPlastic)
	local wingR = box(model, CFrame.new(11, 0, 3) * CFrame.Angles(0, math.rad(-28), 0), Vector3.new(17, 1.2, 9), color, Enum.Material.SmoothPlastic)
	-- воздухозаборник сверху
	box(model, CFrame.new(0, 1.1, -1), Vector3.new(5, 0.8, 4), Color3.fromRGB(30, 32, 35))
	-- сопло сзади
	local nozzle = tube(model, CFrame.new(0, 0, 6.2), 3, 2, Color3.fromRGB(20, 20, 22))
	local glow = box(model, CFrame.new(0, 0, 7.2), Vector3.new(2.4, 2.4, 0.3), Color3.fromRGB(255, 120, 50), Enum.Material.Neon)
	glow.Name = "JetGlow"
	return finalize(model, body)
end

-- 9. «Молния» — гиперзвуковой дрот
function Builders.molniya(model, c)
	local color = Color3.fromRGB(18, 18, 20)
	local body = tube(model, CFrame.new(0, 0, 0), 2.4, 10, color, Enum.Material.SmoothPlastic)
	local nose = ball(model, CFrame.new(0, 0, -5), 2.5, color, Enum.Material.SmoothPlastic)
	local wingL = box(model, CFrame.new(-2.6, 0, 2.5) * CFrame.Angles(0, math.rad(55), 0), Vector3.new(5, 0.16, 2.2), color)
	local wingR = box(model, CFrame.new(2.6, 0, 2.5) * CFrame.Angles(0, math.rad(-55), 0), Vector3.new(5, 0.16, 2.2), color)
	-- красные светящиеся полосы
	local stripeL = box(model, CFrame.new(-1.25, 0, -1), Vector3.new(0.2, 0.3, 7), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
	local stripeR = box(model, CFrame.new(1.25, 0, -1), Vector3.new(0.2, 0.3, 7), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
	-- светящееся сопло
	local nozzle = box(model, CFrame.new(0, 0, 5.4), Vector3.new(2.2, 2.2, 0.6), Color3.fromRGB(255, 60, 60), Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 60, 60); light.Brightness = 4; light.Range = 18
	light.Parent = nozzle
	return finalize(model, body)
end

-- 10. Рой «Саранча» — лидер роя
function Builders.sarancha(model, c)
	local body = box(model, CFrame.new(0, 0, 0), Vector3.new(1.4, 0.5, 1.4), Color3.fromRGB(50, 52, 40), Enum.Material.Metal)
	for _, sx in ipairs({-1, 1}) do
		for _, sz in ipairs({-1, 1}) do
			box(model, CFrame.new(sx * 1.1, 0.1, sz * 1.1), Vector3.new(1.2, 0.12, 0.12), Color3.fromRGB(35, 35, 35))
			prop(model, CFrame.new(sx * 1.1, 0.3, sz * 1.1), 1.5, Color3.fromRGB(25, 25, 25))
		end
	end
	local led = box(model, CFrame.new(0, 0.4, 0), Vector3.new(0.3, 0.15, 0.3), Color3.fromRGB(255, 60, 60), Enum.Material.Neon)
	led.Name = "BlinkLED"
	led:SetAttribute("Blink", true)
	local antenna = box(model, CFrame.new(0, 0.9, 0.5), Vector3.new(0.08, 0.9, 0.08), Color3.fromRGB(20, 20, 20))
	return finalize(model, body)
end

-- Крошечный дрон роя (юнит) — 1x1
function DroneFactory.buildUnit(parent, position)
	local model = Instance.new("Model")
	model.Name = "SwarmUnit"
	local body = box(model, CFrame.new(position), Vector3.new(0.9, 0.25, 0.9), Color3.fromRGB(45, 45, 38), Enum.Material.Metal)
	for _, sx in ipairs({-1, 1}) do
		for _, sz in ipairs({-1, 1}) do
			prop(model, CFrame.new(position + Vector3.new(sx * 0.7, 0.2, sz * 0.7)), 0.9, Color3.fromRGB(20, 20, 20))
		end
	end
	local led = box(model, CFrame.new(position + Vector3.new(0, 0.25, 0)), Vector3.new(0.22, 0.1, 0.22), Color3.fromRGB(255, 60, 60), Enum.Material.Neon)
	led:SetAttribute("Blink", true)
	finalize(model, body)
	model.Parent = parent
	return model
end

-- Главная функция сборки
function DroneFactory.build(droneId)
	local builder = Builders[droneId]
	if not builder then return nil end
	local model = Instance.new("Model")
	model.Name = "Drone_" .. droneId
	builder(model)
	return model
end

return DroneFactory
