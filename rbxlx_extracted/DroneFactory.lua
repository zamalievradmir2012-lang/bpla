-- Детальные процедурные модели БПЛА.
-- Все части стоят у нуля и сварены с PrimaryPart: PivotTo двигает аппарат целиком.
-- У PartType.Cylinder ось — локальный X (Size.X = длина).

local DroneFactory = {}

local METAL = Enum.Material.Metal
local PLASTIC = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local GLASS = Enum.Material.Glass

local function part(model, size, cf, color, mat, shape, name)
	local p = Instance.new("Part")
	p.Name = name or "Part"
	p.Size = size
	p.CFrame = cf or CFrame.new()
	p.Color = color
	p.Material = mat or PLASTIC
	p.Anchored = true
	p.CanCollide = false
	p.Massless = true
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	p.Parent = model
	return p
end

local function wedge(model, size, cf, color, mat, name)
	local w = Instance.new("WedgePart")
	w.Name = name or "Wedge"
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Material = mat or PLASTIC
	w.Anchored = true
	w.CanCollide = false
	w.Massless = true
	w.Parent = model
	return w
end

-- цилиндр: длина вдоль локального X переданного cf
local function cyl(model, dia, len, cf, color, mat, name)
	return part(model, Vector3.new(len, dia, dia), cf, color, mat, Enum.PartType.Cylinder, name)
end

local function ball(model, dia, cf, color, mat, name)
	return part(model, Vector3.new(dia, dia, dia), cf, color, mat, Enum.PartType.Ball, name)
end

-- +X цилиндра → вверх (диск винта в горизонтали)
local function faceUp(cf)
	return cf * CFrame.Angles(0, 0, math.rad(90))
end

-- +X цилиндра → нос (-Z)
local function faceNose(cf)
	return cf * CFrame.Angles(0, math.rad(90), 0)
end

local function weldAll(model, primary)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= primary then
			local w = Instance.new("WeldConstraint")
			w.Part0 = primary
			w.Part1 = d
			w.Parent = primary
		end
	end
end

local function finish(model, primary, previewDist)
	primary.Name = "Hull"
	primary.Massless = false
	primary.CustomPhysicalProperties = PhysicalProperties.new(0.22, 0.3, 0.15)
	model.PrimaryPart = primary
	weldAll(model, primary)
	model:SetAttribute("PreviewDist", previewDist or 24)
	return model
end

local function navLight(model, cf, color)
	local bulb = part(model, Vector3.new(0.18, 0.12, 0.18), cf, color, NEON, nil, "NavLight")
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 12
	light.Brightness = 1.6
	light.Parent = bulb
	return bulb
end

local function motor(model, cf, accent)
	cyl(model, 0.46, 0.36, faceUp(cf), accent, METAL, "Motor")
	local disc = cyl(model, 1.85, 0.045, faceUp(cf * CFrame.new(0, 0.22, 0)), Color3.fromRGB(225, 232, 238), PLASTIC, "PropDisc")
	disc.Transparency = 0.42
	local blade = part(model, Vector3.new(1.7, 0.04, 0.16), cf * CFrame.new(0, 0.28, 0), Color3.fromRGB(40, 44, 48), PLASTIC, nil, "Prop")
	blade.Transparency = 0.2
	local blade2 = part(model, Vector3.new(0.16, 0.04, 1.7), cf * CFrame.new(0, 0.3, 0), Color3.fromRGB(40, 44, 48), PLASTIC, nil, "Prop")
	blade2.Transparency = 0.2
end

-- ========== квадрокоптер ==========
local function quad(name, body, accent, span)
	local m = Instance.new("Model")
	m.Name = name
	local s = span
	local hull = part(m, Vector3.new(s * 0.38, 0.26, s * 0.5), CFrame.new(), body, PLASTIC, nil, "Hull")
	-- полоса на спине
	part(m, Vector3.new(s * 0.06, 0.04, s * 0.46), CFrame.new(0, 0.15, 0), accent, NEON, nil, "Stripe")
	-- нос
	wedge(m, Vector3.new(s * 0.26, 0.2, s * 0.22), CFrame.new(0, -0.02, -s * 0.34) * CFrame.Angles(0, math.rad(180), 0), body, PLASTIC, "Nose")
	-- подвес камеры
	ball(m, 0.38, CFrame.new(0, -0.28, -s * 0.08), Color3.fromRGB(24, 26, 28), PLASTIC, "Gimbal")
	cyl(m, 0.16, 0.08, faceNose(CFrame.new(0, -0.28, -s * 0.28)), Color3.fromRGB(80, 170, 255), GLASS, "Lens")
	-- антенны
	part(m, Vector3.new(0.05, 0.62, 0.05), CFrame.new(-s * 0.1, 0.4, s * 0.14), accent, NEON, nil, "Antenna")
	part(m, Vector3.new(0.05, 0.48, 0.05), CFrame.new(s * 0.1, 0.36, s * 0.14), accent, NEON, nil, "Antenna")
	local reach = s * 0.78
	for _, sgn in ipairs({ -1, 1 }) do
		for _, sgz in ipairs({ -1, 1 }) do
			local ang = math.atan2(sgz, sgn)
			local armCF = CFrame.new(sgn * reach * 0.46, 0.04, sgz * reach * 0.46) * CFrame.Angles(0, -ang, 0)
			part(m, Vector3.new(reach * 0.9, 0.08, 0.14), armCF, Color3.fromRGB(32, 34, 36), METAL, nil, "Arm")
			motor(m, CFrame.new(sgn * reach * 0.86, 0.12, sgz * reach * 0.86), accent)
		end
	end
	-- лыжи
	for _, sgn in ipairs({ -1, 1 }) do
		part(m, Vector3.new(0.08, 0.06, s * 0.62), CFrame.new(sgn * s * 0.16, -0.42, 0.02), accent, METAL, nil, "Skid")
		part(m, Vector3.new(0.06, 0.28, 0.06), CFrame.new(sgn * s * 0.16, -0.26, -s * 0.18), body, METAL, nil, "Strut")
		part(m, Vector3.new(0.06, 0.28, 0.06), CFrame.new(sgn * s * 0.16, -0.26, s * 0.2), body, METAL, nil, "Strut")
	end
	navLight(m, CFrame.new(0, 0.16, s * 0.22), accent)
	return finish(m, hull, math.max(16, s * 6.5))
end

-- ========== самолёт ==========
local function airplane(name, body, accent, span, fuseLen, twinBoom)
	local m = Instance.new("Model")
	m.Name = name
	local hull = part(m, Vector3.new(span * 0.12, 0.38, fuseLen * 0.48), CFrame.new(0, 0, -fuseLen * 0.02), body, PLASTIC, nil, "Hull")
	wedge(m, Vector3.new(span * 0.1, 0.28, fuseLen * 0.26), CFrame.new(0, -0.02, -fuseLen * 0.36) * CFrame.Angles(0, math.rad(180), 0), body, PLASTIC, "Nose")
	local canopy = part(m, Vector3.new(span * 0.08, 0.18, fuseLen * 0.16), CFrame.new(0, 0.26, -fuseLen * 0.08), Color3.fromRGB(150, 205, 225), GLASS, nil, "Canopy")
	canopy.Transparency = 0.3
	-- крыло большого удлинения
	part(m, Vector3.new(span, 0.07, fuseLen * 0.16), CFrame.new(0, 0.06, 0), body, PLASTIC, nil, "Wing")
	part(m, Vector3.new(span * 0.92, 0.03, 0.08), CFrame.new(0, 0.1, -fuseLen * 0.08), accent, PLASTIC, nil, "WingStripe")
	part(m, Vector3.new(0.08, 0.42, fuseLen * 0.12), CFrame.new(-span * 0.5, 0.24, 0), accent, PLASTIC, nil, "Winglet")
	part(m, Vector3.new(0.08, 0.42, fuseLen * 0.12), CFrame.new(span * 0.5, 0.24, 0), accent, PLASTIC, nil, "Winglet")
	-- тянущий винт
	ball(m, 0.26, CFrame.new(0, 0, -fuseLen * 0.5), accent, METAL, "PropHub")
	part(m, Vector3.new(0.1, span * 0.2, 0.035), CFrame.new(0, 0, -fuseLen * 0.52), Color3.fromRGB(28, 30, 32), PLASTIC, nil, "PropBlade")
	part(m, Vector3.new(span * 0.2, 0.1, 0.035), CFrame.new(0, 0, -fuseLen * 0.54), Color3.fromRGB(28, 30, 32), PLASTIC, nil, "PropBlade")
	if twinBoom then
		for _, sgn in ipairs({ -1, 1 }) do
			part(m, Vector3.new(0.14, 0.14, fuseLen * 0.62), CFrame.new(sgn * span * 0.2, 0.02, fuseLen * 0.28), body, PLASTIC, nil, "Boom")
			part(m, Vector3.new(0.07, 0.62, 0.28), CFrame.new(sgn * span * 0.2, 0.36, fuseLen * 0.54), accent, PLASTIC, nil, "Fin")
		end
		part(m, Vector3.new(span * 0.46, 0.06, 0.2), CFrame.new(0, 0.5, fuseLen * 0.54), body, PLASTIC, nil, "Stab")
	else
		part(m, Vector3.new(0.14, 0.14, fuseLen * 0.42), CFrame.new(0, 0.04, fuseLen * 0.32), body, PLASTIC, nil, "Boom")
		part(m, Vector3.new(0.07, 0.72, 0.3), CFrame.new(0, 0.42, fuseLen * 0.48), accent, PLASTIC, nil, "Fin")
		part(m, Vector3.new(span * 0.36, 0.06, 0.18), CFrame.new(0, 0.62, fuseLen * 0.46), body, PLASTIC, nil, "Stab")
	end
	ball(m, 0.34, CFrame.new(0, -0.3, -fuseLen * 0.02), Color3.fromRGB(22, 24, 26), PLASTIC, "Turret")
	cyl(m, 0.14, 0.1, faceNose(CFrame.new(0, -0.3, -fuseLen * 0.2)), Color3.fromRGB(90, 170, 255), GLASS, "Lens")
	navLight(m, CFrame.new(0, 0.22, fuseLen * 0.16), accent)
	return finish(m, hull, math.max(22, span * 3.2))
end

-- ========== дельта (Герань) ==========
local function geran(name, body, accent, scale)
	scale = scale or 1
	local m = Instance.new("Model")
	m.Name = name
	local function S(v)
		return v * scale
	end
	local hull = part(m, Vector3.new(S(1.5), S(0.32), S(2.2)), CFrame.new(0, 0, S(-0.3)), body, PLASTIC, nil, "Hull")
	wedge(m, Vector3.new(S(3.2), S(0.14), S(2.5)), CFrame.new(S(-1.5), S(0.02), S(0.25)) * CFrame.Angles(0, math.rad(76), 0), body, PLASTIC, "WingL")
	wedge(m, Vector3.new(S(3.2), S(0.14), S(2.5)), CFrame.new(S(1.5), S(0.02), S(0.25)) * CFrame.Angles(0, math.rad(-76), 0), body, PLASTIC, "WingR")
	-- кромка крыла
	part(m, Vector3.new(S(4.6), S(0.04), S(0.12)), CFrame.new(0, S(0.08), S(-0.55)), accent, PLASTIC, nil, "Leading")
	wedge(m, Vector3.new(S(0.1), S(0.7), S(0.85)), CFrame.new(0, S(0.42), S(1.05)), accent, PLASTIC, "Fin")
	cyl(m, S(0.5), S(0.65), faceNose(CFrame.new(0, 0, S(1.45))), Color3.fromRGB(36, 38, 40), METAL, "Engine")
	cyl(m, S(0.28), S(0.2), faceNose(CFrame.new(0, 0, S(1.85))), accent, METAL, "Nozzle")
	ball(m, S(0.62), CFrame.new(0, S(-0.04), S(-1.4)), Color3.fromRGB(48, 50, 46), METAL, "Warhead")
	part(m, Vector3.new(S(0.14), S(0.14), S(0.28)), CFrame.new(0, 0, S(-1.78)), accent, NEON, nil, "Fuze")
	navLight(m, CFrame.new(0, S(0.2), S(0.4)), accent)
	return finish(m, hull, 18 * scale)
end

-- ========== Ланцет: X-крыло ==========
local function lancet(name, body, accent)
	local m = Instance.new("Model")
	m.Name = name
	local hull = part(m, Vector3.new(0.38, 0.38, 3.1), CFrame.new(), body, PLASTIC, nil, "Hull")
	wedge(m, Vector3.new(0.3, 0.3, 0.75), CFrame.new(0, 0, -1.85) * CFrame.Angles(0, math.rad(180), 0), accent, PLASTIC, "Nose")
	cyl(m, 0.16, 0.12, faceNose(CFrame.new(0, 0, -2.2)), Color3.fromRGB(40, 40, 36), GLASS, "Seeker")
	for _, ang in ipairs({ 42, -42, 138, -138 }) do
		local cf = CFrame.new(0, 0, 0.1) * CFrame.Angles(0, 0, math.rad(ang)) * CFrame.new(0.95, 0, 0)
		part(m, Vector3.new(1.55, 0.05, 0.5), cf, body, PLASTIC, nil, "XWing")
	end
	for _, ang in ipairs({ 45, -45, 135, -135 }) do
		local cf = CFrame.new(0, 0, 1.2) * CFrame.Angles(0, 0, math.rad(ang)) * CFrame.new(0.42, 0, 0)
		part(m, Vector3.new(0.7, 0.045, 0.38), cf, accent, PLASTIC, nil, "Tail")
	end
	cyl(m, 0.26, 0.36, faceNose(CFrame.new(0, 0, 1.7)), Color3.fromRGB(28, 30, 32), METAL, "Pusher")
	navLight(m, CFrame.new(0, 0.22, 0.2), accent)
	return finish(m, hull, 18)
end

-- ========== Охотник: летающее крыло ==========
local function ohotnik()
	local m = Instance.new("Model")
	m.Name = "Охотник"
	local body = Color3.fromRGB(38, 40, 44)
	local accent = Color3.fromRGB(170, 174, 180)
	local hull = part(m, Vector3.new(2.2, 0.42, 4.2), CFrame.new(0, 0, -0.4), body, PLASTIC, nil, "Hull")
	wedge(m, Vector3.new(6.4, 0.2, 3.6), CFrame.new(-3.2, 0.02, 0.2) * CFrame.Angles(0, math.rad(68), 0), body, PLASTIC, "WingL")
	wedge(m, Vector3.new(6.4, 0.2, 3.6), CFrame.new(3.2, 0.02, 0.2) * CFrame.Angles(0, math.rad(-68), 0), body, PLASTIC, "WingR")
	-- зубцы задней кромки
	for _, x in ipairs({ -4.2, -2.4, 2.4, 4.2 }) do
		wedge(m, Vector3.new(1.1, 0.1, 0.7), CFrame.new(x, 0.02, 1.55), Color3.fromRGB(28, 30, 32), PLASTIC, "Saw")
	end
	local slit = part(m, Vector3.new(0.7, 0.12, 0.9), CFrame.new(0, 0.28, -1.1), Color3.fromRGB(20, 28, 36), GLASS, nil, "Cockpit")
	slit.Transparency = 0.35
	-- два сопла
	for _, sgn in ipairs({ -1, 1 }) do
		cyl(m, 0.55, 0.8, faceNose(CFrame.new(sgn * 0.7, 0, 1.9)), Color3.fromRGB(24, 26, 28), METAL, "Intake")
		local glow = cyl(m, 0.28, 0.12, faceNose(CFrame.new(sgn * 0.7, 0, 2.3)), Color3.fromRGB(255, 140, 60), NEON, "Exhaust")
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 140, 60)
		light.Range = 10
		light.Brightness = 1.2
		light.Parent = glow
	end
	navLight(m, CFrame.new(0, 0.24, -1.6), accent)
	return finish(m, hull, 32)
end

-- ========== Молния: длинная игла ==========
local function molniya()
	local m = Instance.new("Model")
	m.Name = "Молния"
	local body = Color3.fromRGB(210, 214, 220)
	local accent = Color3.fromRGB(40, 170, 255)
	local hull = part(m, Vector3.new(0.42, 0.42, 5.4), CFrame.new(), body, METAL, nil, "Hull")
	wedge(m, Vector3.new(0.32, 0.32, 1.4), CFrame.new(0, 0, -3.3) * CFrame.Angles(0, math.rad(180), 0), body, METAL, "Nose")
	part(m, Vector3.new(0.08, 0.08, 4.2), CFrame.new(0, 0.24, -0.2), accent, NEON, nil, "Spine")
	-- маленькие крылья
	part(m, Vector3.new(2.6, 0.05, 0.7), CFrame.new(0, 0, 0.4), body, METAL, nil, "Wing")
	part(m, Vector3.new(1.3, 0.04, 0.4), CFrame.new(0, 0, 2.1), accent, METAL, nil, "TailWing")
	part(m, Vector3.new(0.05, 0.7, 0.45), CFrame.new(0, 0.3, 2.15), accent, METAL, nil, "Fin")
	local exhaust = cyl(m, 0.28, 0.35, faceNose(CFrame.new(0, 0, 2.9)), Color3.fromRGB(80, 200, 255), NEON, "Exhaust")
	local light = Instance.new("PointLight")
	light.Color = accent
	light.Range = 16
	light.Brightness = 2
	light.Parent = exhaust
	return finish(m, hull, 26)
end

local function weldExtra(hull, piece)
	local w = Instance.new("WeldConstraint")
	w.Part0 = hull
	w.Part1 = piece
	w.Parent = hull
end

local BUILDERS = {
	pchela = function()
		local m = quad("Пчела", Color3.fromRGB(232, 190, 48), Color3.fromRGB(40, 42, 46), 2.6)
		local hull = m.PrimaryPart
		local grenade = ball(m, 0.36, CFrame.new(0, -0.22, 0.35), Color3.fromRGB(70, 90, 48), METAL, "Grenade")
		weldExtra(hull, grenade)
		return m
	end,
	upyr = function()
		local m = quad("Упырь", Color3.fromRGB(22, 24, 26), Color3.fromRGB(70, 220, 90), 1.7)
		local hull = m.PrimaryPart
		local wh = ball(m, 0.42, CFrame.new(0, -0.2, -0.55), Color3.fromRGB(140, 90, 40), METAL, "Warhead")
		weldExtra(hull, wh)
		local cam = part(m, Vector3.new(0.22, 0.16, 0.12), CFrame.new(0, 0.16, -0.45), Color3.fromRGB(20, 20, 22), PLASTIC, nil, "GoPro")
		weldExtra(hull, cam)
		return m
	end,
	geran1 = function()
		return geran("Герань-1", Color3.fromRGB(214, 214, 206), Color3.fromRGB(50, 52, 48), 1.55)
	end,
	geran2 = function()
		return geran("Герань-2", Color3.fromRGB(232, 228, 214), Color3.fromRGB(28, 28, 30), 2.35)
	end,
	orlan = function()
		return airplane("Орлан-10", Color3.fromRGB(236, 236, 230), Color3.fromRGB(36, 78, 160), 8.2, 3.4, false)
	end,
	lancet = function()
		local m = lancet("Ланцет-3", Color3.fromRGB(168, 176, 148), Color3.fromRGB(86, 104, 58))
		m:SetAttribute("PreviewDist", 20)
		return m
	end,
	inohodets = function()
		local m = airplane("Иноходец", Color3.fromRGB(78, 84, 72), Color3.fromRGB(196, 168, 74), 14, 7.2, true)
		local hull = m.PrimaryPart
		for _, x in ipairs({ -3.2, -1.5, 1.5, 3.2 }) do
			local rack = part(m, Vector3.new(0.1, 0.4, 0.1), CFrame.new(x, -0.34, 0), Color3.fromRGB(40, 42, 40), METAL, nil, "Pylon")
			local missile = part(m, Vector3.new(0.26, 0.26, 1.5), CFrame.new(x, -0.62, -0.15), Color3.fromRGB(92, 98, 78), PLASTIC, nil, "Missile")
			local seeker = part(m, Vector3.new(0.16, 0.16, 0.28), CFrame.new(x, -0.62, -1.0), Color3.fromRGB(196, 168, 74), PLASTIC, nil, "Seeker")
			weldExtra(hull, rack)
			weldExtra(hull, missile)
			weldExtra(hull, seeker)
		end
		local dish = cyl(m, 0.85, 0.1, faceUp(CFrame.new(0, 0.55, 0.6)), Color3.fromRGB(214, 216, 220), METAL, "Satcom")
		weldExtra(hull, dish)
		m:SetAttribute("PreviewDist", 34)
		return m
	end,
	ohotnik = ohotnik,
	molniya = molniya,
	sarancha = function()
		return quad("Саранча", Color3.fromRGB(74, 82, 46), Color3.fromRGB(190, 200, 60), 1.25)
	end,
	-- ===== НОВЫЕ БПЛА =====
	-- «Термит» — FPV-камикадзе с термобарическим зарядом
	termit = function()
		local m = quad("Термит", Color3.fromRGB(46, 32, 22), Color3.fromRGB(255, 120, 40), 1.85)
		local hull = m.PrimaryPart
		local tank = cyl(m, 0.52, 0.95, faceNose(CFrame.new(0, -0.24, -0.5)), Color3.fromRGB(150, 60, 30), METAL, "ThermoTank")
		weldExtra(hull, tank)
		local cap = ball(m, 0.52, CFrame.new(0, -0.24, -1.0), Color3.fromRGB(96, 42, 24), METAL, "ThermoCap")
		weldExtra(hull, cap)
		local stripe = part(m, Vector3.new(0.54, 0.1, 0.12), CFrame.new(0, -0.24, -0.35), Color3.fromRGB(255, 170, 60), NEON, nil, "Hazard")
		weldExtra(hull, stripe)
		return m
	end,
	-- «Стриж» — скоростной реактивный разведчик-целеуказатель
	strizh = function()
		local m = airplane("Стриж", Color3.fromRGB(64, 84, 104), Color3.fromRGB(120, 220, 255), 6.4, 4.8, false)
		local hull = m.PrimaryPart
		for _, x in ipairs({ -1.7, 1.7 }) do
			local mis = cyl(m, 0.3, 1.5, faceNose(CFrame.new(x, -0.34, 0.25)), Color3.fromRGB(184, 186, 192), METAL, "Missile")
			weldExtra(hull, mis)
			local nose = ball(m, 0.3, CFrame.new(x, -0.34, -0.55), Color3.fromRGB(220, 90, 60), PLASTIC, "MissileNose")
			weldExtra(hull, nose)
		end
		local optics = ball(m, 0.32, CFrame.new(0, -0.3, -1.5), Color3.fromRGB(20, 22, 26), GLASS, "Optics")
		weldExtra(hull, optics)
		m:SetAttribute("PreviewDist", 22)
		return m
	end,
	-- «Улей» — тяжёлый восьмивинтовой бомбовоз
	uley = function()
		local m = Instance.new("Model")
		m.Name = "Улей"
		local body = Color3.fromRGB(58, 62, 48)
		local accent = Color3.fromRGB(255, 200, 60)
		local hull = part(m, Vector3.new(2.2, 0.7, 3), CFrame.new(), body, PLASTIC, nil, "Hull")
		part(m, Vector3.new(0.16, 0.06, 2.6), CFrame.new(0, 0.4, 0), accent, NEON, nil, "Stripe")
		ball(m, 0.6, CFrame.new(0, -0.55, -0.6), Color3.fromRGB(24, 26, 28), PLASTIC, "Gimbal")
		cyl(m, 0.22, 0.12, faceNose(CFrame.new(0, -0.55, -0.98)), Color3.fromRGB(80, 170, 255), GLASS, "Lens")
		-- 8 лучей с моторами
		for i = 1, 8 do
			local ang = math.rad((i - 0.5) * 45)
			local dx, dz = math.cos(ang) * 2.5, math.sin(ang) * 2.5
			part(m, Vector3.new(2.7, 0.12, 0.2), CFrame.new(dx * 0.5, 0.12, dz * 0.5) * CFrame.Angles(0, -ang, 0), Color3.fromRGB(32, 34, 36), METAL, nil, "Arm")
			motor(m, CFrame.new(dx, 0.22, dz), accent)
		end
		-- бомбовая кассета
		for i = 1, 4 do
			local bomb = cyl(m, 0.36, 1.15, faceNose(CFrame.new(-0.9 + (i - 1) * 0.6, -0.75, 0.45)), Color3.fromRGB(64, 70, 52), METAL, "Bomb")
			weldExtra(hull, bomb)
		end
		-- шасси
		for _, sgn in ipairs({ -1, 1 }) do
			part(m, Vector3.new(0.12, 0.1, 2.7), CFrame.new(sgn * 0.95, -1.05, 0), body, METAL, nil, "Skid")
			part(m, Vector3.new(0.1, 0.55, 0.1), CFrame.new(sgn * 0.95, -0.72, -0.95), body, METAL, nil, "Strut")
			part(m, Vector3.new(0.1, 0.55, 0.1), CFrame.new(sgn * 0.95, -0.72, 0.95), body, METAL, nil, "Strut")
		end
		navLight(m, CFrame.new(0, 0.52, 1.35), accent)
		return finish(m, hull, 26)
	end,
}

function DroneFactory.build(droneId, parent, cf)
	local fn = BUILDERS[droneId] or BUILDERS.pchela
	local model = fn()
	model.Name = "Drone_" .. tostring(droneId)
	model:SetAttribute("DroneId", droneId)
	if cf then model:PivotTo(cf) end
	if parent then model.Parent = parent end
	return model
end

function DroneFactory.buildUnit(parent, position)
	local model = BUILDERS.sarancha()
	model.Name = "SwarmUnit"
	model:SetAttribute("DroneId", "sarancha")
	model:PivotTo(CFrame.new(position))
	if parent then model.Parent = parent end
	return model
end

return DroneFactory
