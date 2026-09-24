-- ============================================================
--  MapGenerator — процедурная постройка города 2048x2048.
--  Все здания собираются из модульных Parts с HP (см. Destruction).
-- ============================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)
local Destruction = require(script.Parent.Destruction)

local MapGenerator = {}
MapGenerator.Points = { ZU = {}, Spotlights = {} }
MapGenerator.NightLights = {}   -- огни фонарей (включаются ночью)
MapGenerator.Windows = {}       -- окна жилых домов (ночью светятся)
MapGenerator.TrafficLights = {} -- {parts={...}, axis="NS"|"EW"}
MapGenerator.NPCWaypoints = {}
MapGenerator.DuckSpots = {}

local City -- workspace.City

local ROAD_HALF = 10          -- половина ширины дороги
local FLOOR_H = 10            -- высота этажа
local MAT = {
	Brick = Enum.Material.Brick, Concrete = Enum.Material.Concrete,
	Glass = Enum.Material.Glass, Metal = Enum.Material.Metal,
	Slate = Enum.Material.Slate, Wood = Enum.Material.WoodPlanks,
	Neon = Enum.Material.Neon, Plastic = Enum.Material.SmoothPlastic,
	Asphalt = Enum.Material.Asphalt, Grass = Enum.Material.Grass,
}

local function P(props) return Util.part(props, City) end

local function reg(part, hp, kind, bld, floor)
	if bld then Destruction.AttachPart(part, hp, kind, bld, floor) end
	return part
end

-- ------------------------------------------------------------
-- ТЕРРАИН: трава + река
-- ------------------------------------------------------------
local function buildTerrain()
	local terrain = workspace.Terrain
	terrain:Clear()
	local grassCF = CFrame.new(0, -8, 0)
	terrain:FillBlock(grassCF, Vector3.new(3200, 16, 3200), Enum.Material.Grass)
	-- река: полоса x 128..192, z 256..1024
	local riverCF = CFrame.new(160, -8, 640)
	terrain:FillBlock(riverCF, Vector3.new(64, 16, 768), Enum.Material.Water)
end

-- ------------------------------------------------------------
-- ДОРОГИ, ТРОТУАРЫ, РАЗМЕТКА, СВЕТОФОРЫ, ФОНАРИ
-- ------------------------------------------------------------
local ROADS = {-768, -512, -256, 0, 256, 512, 768}

local function addLamp(x, z, rotY)
	local pole = P({ Size = Vector3.new(0.6, 14, 0.6), CFrame = CFrame.new(x, 7, z) * CFrame.Angles(0, rotY, 0), Color = Color3.fromRGB(70, 72, 76), Material = MAT.Metal })
	local arm = P({ Size = Vector3.new(0.4, 0.4, 3), CFrame = pole.CFrame * CFrame.new(0, 6.8, -1.4), Color = Color3.fromRGB(70, 72, 76), Material = MAT.Metal })
	local head = P({ Size = Vector3.new(1.2, 0.4, 1.6), CFrame = arm.CFrame * CFrame.new(0, -0.3, -1), Color = Color3.fromRGB(50, 50, 52), Material = MAT.Metal })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 210, 140)
	light.Brightness = 0 -- включается ночью
	light.Range = 26
	light.Shadows = false
	light.Parent = head
	table.insert(MapGenerator.NightLights, light)
	reg(pole, 40, "Prop", nil)
end

local function addTrafficLight(x, z, rotY, axis)
	local pole = P({ Size = Vector3.new(0.5, 10, 0.5), CFrame = CFrame.new(x, 5, z) * CFrame.Angles(0, rotY, 0), Color = Color3.fromRGB(40, 42, 44), Material = MAT.Metal })
	local box = P({ Size = Vector3.new(1, 2.6, 0.8), CFrame = pole.CFrame * CFrame.new(0, 4.4, -0.4), Color = Color3.fromRGB(30, 30, 32), Material = MAT.Metal })
	local entry = { axis = axis, bulbs = {} }
	local colors = {
		{ Color3.fromRGB(255, 60, 40), Vector3.new(0, 0.9, 0) },
		{ Color3.fromRGB(255, 200, 40), Vector3.new(0, 0, 0) },
		{ Color3.fromRGB(60, 255, 80), Vector3.new(0, -0.9, 0) },
	}
	for _, c in ipairs(colors) do
		local b = P({ Size = Vector3.new(0.55, 0.55, 0.2), CFrame = box.CFrame * c[2] * CFrame.new(0, 0, -0.35), Color = c[1], Material = MAT.Plastic, Transparency = 0.4 })
		table.insert(entry.bulbs, { part = b, baseColor = c[1] })
	end
	table.insert(MapGenerator.TrafficLights, entry)
end

local function buildRoads()
	local y = 0.15
	for _, x in ipairs(ROADS) do
		local roadZ = { -1024, 1024 }
		-- дорогаnorth-south не пересекает реку в зоне x=256 south of 256
		local z0, z1 = -1024, 1024
		if x == 256 then z1 = 256 - 8 end -- упирается в реку
		if x ~= 160 then
			local len = z1 - z0
			P({ Size = Vector3.new(ROAD_HALF * 2, 0.3, len), CFrame = CFrame.new(x, y, (z0 + z1) / 2), Color = Color3.fromRGB(45, 45, 48), Material = MAT.Asphalt })
			-- тротуары
			P({ Size = Vector3.new(6, 0.7, len), CFrame = CFrame.new(x - ROAD_HALF - 3, 0.35, (z0 + z1) / 2), Color = Color3.fromRGB(140, 138, 132), Material = MAT.Concrete })
			P({ Size = Vector3.new(6, 0.7, len), CFrame = CFrame.new(x + ROAD_HALF + 3, 0.35, (z0 + z1) / 2), Color = Color3.fromRGB(140, 138, 132), Material = MAT.Concrete })
			-- разметка
			if x == 0 then
				for zz = z0 + 16, z1 - 16, 32 do
					P({ Size = Vector3.new(0.4, 0.05, 10), CFrame = CFrame.new(x, y + 0.18, zz), Color = Color3.fromRGB(230, 230, 230), Material = MAT.Plastic, CanCollide = false })
				end
			else
				P({ Size = Vector3.new(0.35, 0.05, len - 20), CFrame = CFrame.new(x, y + 0.18, (z0 + z1) / 2), Color = Color3.fromRGB(200, 170, 60), Material = MAT.Plastic, CanCollide = false })
			end
			P({ Size = Vector3.new(0.3, 0.05, len - 20), CFrame = CFrame.new(x - ROAD_HALF + 1, y + 0.18, (z0 + z1) / 2), Color = Color3.fromRGB(220, 220, 220), Material = MAT.Plastic, CanCollide = false })
			P({ Size = Vector3.new(0.3, 0.05, len - 20), CFrame = CFrame.new(x + ROAD_HALF - 1, y + 0.18, (z0 + z1) / 2), Color = Color3.fromRGB(220, 220, 220), Material = MAT.Plastic, CanCollide = false })
		end
	end
	for _, z in ipairs(ROADS) do
		-- east-west дороги: сегменты левее и правее реки (река x 128..192)
		local segs = { { -1024, 128 }, { 192, 1024 } }
		if z < 256 then segs = { { -1024, 1024 } } end -- река южнее
		for _, s in ipairs(segs) do
			local x0, x1 = s[1], s[2]
			local len = x1 - x0
			P({ Size = Vector3.new(len, 0.3, ROAD_HALF * 2), CFrame = CFrame.new((x0 + x1) / 2, y, z), Color = Color3.fromRGB(45, 45, 48), Material = MAT.Asphalt })
			P({ Size = Vector3.new(len, 0.7, 6), CFrame = CFrame.new((x0 + x1) / 2, 0.35, z - ROAD_HALF - 3), Color = Color3.fromRGB(140, 138, 132), Material = MAT.Concrete })
			P({ Size = Vector3.new(len, 0.7, 6), CFrame = CFrame.new((x0 + x1) / 2, 0.35, z + ROAD_HALF + 3), Color = Color3.fromRGB(140, 138, 132), Material = MAT.Concrete })
			if z == 0 then
				for xx = x0 + 16, x1 - 16, 32 do
					P({ Size = Vector3.new(10, 0.05, 0.4), CFrame = CFrame.new(xx, y + 0.18, z), Color = Color3.fromRGB(230, 230, 230), Material = MAT.Plastic, CanCollide = false })
				end
			else
				P({ Size = Vector3.new(len - 20, 0.05, 0.35), CFrame = CFrame.new((x0 + x1) / 2, y + 0.18, z), Color = Color3.fromRGB(200, 170, 60), Material = MAT.Plastic, CanCollide = false })
			end
		end
	end
	-- пешеходные переходы на главных перекрёстках (оси x=0 и z=0)
	local crossZebra = function(cx, cz, vertical)
		for i = -2, 2 do
			if vertical then
				P({ Size = Vector3.new(1.4, 0.06, 16), CFrame = CFrame.new(cx + i * 2.6, y + 0.2, cz), Color = Color3.fromRGB(235, 235, 235), Material = MAT.Plastic, CanCollide = false })
			else
				P({ Size = Vector3.new(16, 0.06, 1.4), CFrame = CFrame.new(cx, y + 0.2, cz + i * 2.6), Color = Color3.fromRGB(235, 235, 235), Material = MAT.Plastic, CanCollide = false })
			end
		end
	end
	for _, z in ipairs(ROADS) do crossZebra(0 - ROAD_HALF - 5, z, false) crossZebra(0 + ROAD_HALF + 5, z, false) end
	for _, x in ipairs(ROADS) do crossZebra(x, 0 - ROAD_HALF - 5, true) crossZebra(x, 0 + ROAD_HALF + 5, true) end
	-- светофоры на главных перекрёстках
	for _, z in ipairs({-256, 0, 256}) do
		for _, x in ipairs({-256, 0, 256}) do
			addTrafficLight(x - ROAD_HALF - 2, z - ROAD_HALF - 2, math.rad(180), "NS")
			addTrafficLight(x + ROAD_HALF + 2, z + ROAD_HALF + 2, 0, "EW")
		end
	end
	-- фонари вдоль главных дорог
	for _, z in ipairs(ROADS) do
		for xx = -900, 900, 220 do
			addLamp(xx, z - ROAD_HALF - 5, 0)
			addLamp(xx + 110, z + ROAD_HALF + 5, math.rad(180))
		end
	end
	-- точки для NPC (перекрёстки тротуаров)
	for _, x in ipairs(ROADS) do
		for _, z in ipairs(ROADS) do
			table.insert(MapGenerator.NPCWaypoints, Vector3.new(x + ROAD_HALF + 4, 3, z + ROAD_HALF + 4))
		end
	end
end

-- ------------------------------------------------------------
-- МОСТЫ (категория bridge, разрушаемые)
-- ------------------------------------------------------------
local function buildBridge(cx, cz, alongX)
	local bld = Destruction.RegisterBuilding("bridge", "Мост", Vector3.new(cx, 4, cz))
	local dir
	if alongX then dir = CFrame.new(cx, 4, cz) else dir = CFrame.new(cx, 4, cz) * CFrame.Angles(0, math.rad(90), 0) end
	-- опоры (колонны, этаж 0)
	for _, off in ipairs({ -18, 0, 18 }) do
		for _, s in ipairs({ -1, 1 }) do
			local py = P({ Size = Vector3.new(3, 12, 3), CFrame = dir * CFrame.new(off, -4, s * 8), Color = Color3.fromRGB(120, 118, 112), Material = MAT.Concrete })
			reg(py, 300, "Column", bld, 0)
		end
	end
	-- пролётные плиты (этаж 1)
	for i = -2, 2 do
		local deck = P({ Size = Vector3.new(18, 1.6, 24), CFrame = dir * CFrame.new(i * 18, 3.2, 0), Color = Color3.fromRGB(95, 93, 88), Material = MAT.Concrete })
		reg(deck, 200, "Floor", bld, 1)
	end
	-- перила и разметка
	for _, s in ipairs({ -1, 1 }) do
		local rail = P({ Size = Vector3.new(180, 0.4, 0.4), CFrame = dir * CFrame.new(0, 5.2, s * 11.5), Color = Color3.fromRGB(180, 60, 50), Material = MAT.Metal })
		reg(rail, 30, "Prop", bld, 1)
	end
	local line = P({ Size = Vector3.new(180, 0.06, 0.4), CFrame = dir * CFrame.new(0, 4.15, 0), Color = Color3.fromRGB(230, 230, 230), Material = MAT.Plastic, CanCollide = false })
	-- съезды-пандусы к берегам
	for _, s in ipairs({ -1, 1 }) do
		local ramp = Util.wedge({ Size = Vector3.new(24, 3, 30), CFrame = dir * CFrame.new(s * 103, 1.6, 0) * CFrame.Angles(0, 0, s > 0 and math.rad(90) or math.rad(-90)), Color = Color3.fromRGB(95, 93, 88), Material = MAT.Concrete }, City)
	end
	return bld
end

-- ------------------------------------------------------------
-- ЖИЛОЙ ДОМ (панель/кирпич, 5/9/16 этажей)
-- ------------------------------------------------------------
local function residential(cx, cz, floors, opts)
	opts = opts or {}
	local w, d = opts.w or 34, opts.d or 26
	local color = opts.color or (floors >= 9 and Color3.fromRGB(196, 188, 172) or Color3.fromRGB(188, 134, 108))
	if opts.panel then color = Color3.fromRGB(178, 182, 178) end
	local material = opts.panel and MAT.Concrete or MAT.Brick
	local category = floors >= 9 and "residential_big" or "residential_small"
	local name = opts.name or (floors >= 9 and "Многоэтажка" or "Жилой дом")
	local bld = Destruction.RegisterBuilding(category, name, Vector3.new(cx, floors * FLOOR_H / 2, cz))
	local baseY = 0

	-- фундамент
	reg(P({ Size = Vector3.new(w + 4, 1, d + 4), CFrame = CFrame.new(cx, 0.5, cz), Color = Color3.fromRGB(120, 118, 112), Material = MAT.Concrete }), 400, "Floor", bld, 0)

	-- подъездный козырёк, дверь, почтовые ящики, мусорка
	local doorCF = CFrame.new(cx, 4, cz - d / 2 - 0.6)
	reg(P({ Size = Vector3.new(3, 6, 0.4), CFrame = doorCF, Color = Color3.fromRGB(90, 60, 40), Material = MAT.Wood }), 60, "Wall", bld, 1)
	reg(P({ Size = Vector3.new(6, 0.5, 2.4), CFrame = doorCF * CFrame.new(0, 4, -1.2), Color = Color3.fromRGB(80, 82, 86), Material = MAT.Metal }), 40, "Prop", bld, 1)
	reg(P({ Size = Vector3.new(1.6, 2.2, 0.6), CFrame = doorCF * CFrame.new(3.4, 0.4, -0.8), Color = Color3.fromRGB(70, 90, 60), Material = MAT.Metal }), 30, "Prop", bld, 1)
	local dumpster = P({ Size = Vector3.new(4, 2, 2.4), CFrame = CFrame.new(cx + w / 2 + 4, 1, cz - d / 2 - 2), Color = Color3.fromRGB(50, 80, 60), Material = MAT.Metal })
	reg(dumpster, 40, "Prop", bld, 0)

	for f = 1, floors do
		local y0 = (f - 1) * FLOOR_H
		-- плита этажа
		reg(P({ Size = Vector3.new(w, 1, d), CFrame = CFrame.new(cx, y0 + 9.5, cz), Color = Color3.fromRGB(150, 148, 142), Material = MAT.Concrete }), 120, "Floor", bld, f)
		-- колонны по углам
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				reg(P({ Size = Vector3.new(2, 8, 2), CFrame = CFrame.new(cx + sx * (w / 2 - 1.2), y0 + 5, cz + sz * (d / 2 - 1.2)), Color = color, Material = material }), 200, "Column", bld, f)
			end
		end
		-- фасады (перед/зад): полосы + окна
		for _, side in ipairs({ -1, 1 }) do
			local zc = cz + side * (d / 2)
			local faceCF = CFrame.new(cx, 0, zc)
			-- нижняя и верхняя полосы
			reg(P({ Size = Vector3.new(w, 1.5, 1), CFrame = faceCF * CFrame.new(0, y0 + 1.75, 0), Color = color, Material = material }), 70, "Wall", bld, f)
			reg(P({ Size = Vector3.new(w, 1.5, 1), CFrame = faceCF * CFrame.new(0, y0 + 8.25, 0), Color = color, Material = material }), 70, "Wall", bld, f)
			-- вертикальные простенки и окна
			local nWin = 4
			local winW = 5
			local step = w / (nWin + 1)
			for i = 0, nWin do
				local px = -w / 2 + step * i
				local isDoor = (f == 1 and side == -1 and i == math.floor(nWin / 2))
				if not isDoor then
					reg(P({ Size = Vector3.new(step - winW * 0.55, 5, 1), CFrame = faceCF * CFrame.new(px, y0 + 5, 0), Color = color, Material = material }), 70, "Wall", bld, f)
				end
				if i < nWin then
					local glass = P({ Size = Vector3.new(winW * 0.75, 4, 0.4), CFrame = faceCF * CFrame.new(px + step / 2, y0 + 5, 0), Color = Color3.fromRGB(140, 170, 190), Material = MAT.Glass, Transparency = 0.45 })
					reg(glass, 1, "Window", bld, f)
					table.insert(MapGenerator.Windows, glass)
				end
			end
			-- балконы (не на 1 этаже)
			if f > 1 and math.random() < 0.5 then
				local bx = (math.random() - 0.5) * (w - 12)
				local bsCF = CFrame.new(cx + bx, y0 + 2.6, zc + side * 1.4)
				reg(P({ Size = Vector3.new(5, 0.4, 2.4), CFrame = bsCF, Color = color, Material = MAT.Concrete }), 40, "Prop", bld, f)
				reg(P({ Size = Vector3.new(5, 1, 0.2), CFrame = bsCF * CFrame.new(0, 0.7, side * 1.1), Color = Color3.fromRGB(90, 92, 96), Material = MAT.Metal }), 25, "Prop", bld, f)
			end
		end
		-- боковые глухие стены
		for _, side in ipairs({ -1, 1 }) do
			reg(P({ Size = Vector3.new(1, 8, d - 2), CFrame = CFrame.new(cx + side * (w / 2), y0 + 5, cz), Color = color, Material = material }), 80, "Wall", bld, f)
		end
	end

	-- крыша
	reg(P({ Size = Vector3.new(w, 1, d), CFrame = CFrame.new(cx, floors * FLOOR_H + 0.5, cz), Color = Color3.fromRGB(110, 108, 104), Material = MAT.Concrete }), 150, "Roof", bld, floors + 1)
	-- парапет
	reg(P({ Size = Vector3.new(w, 1.6, 0.8), CFrame = CFrame.new(cx, floors * FLOOR_H + 1.6, cz - d / 2), Color = color, Material = material }), 60, "Wall", bld, floors + 1)
	reg(P({ Size = Vector3.new(w, 1.6, 0.8), CFrame = CFrame.new(cx, floors * FLOOR_H + 1.6, cz + d / 2), Color = color, Material = material }), 60, "Wall", bld, floors + 1)
	-- антенна
	local mast = P({ Size = Vector3.new(0.3, 7, 0.3), CFrame = CFrame.new(cx + w / 4, floors * FLOOR_H + 4, cz), Color = Color3.fromRGB(60, 60, 62), Material = MAT.Metal })
	reg(mast, 20, "Prop", bld, floors + 1)
	-- спутниковые тарелки и кондиционеры на фасадах
	for i = 1, math.floor(floors * 0.7) do
		local ff = math.random(2, floors)
		local side = math.random() < 0.5 and -1 or 1
		local acx = cx + (math.random() - 0.5) * (w - 8)
		local ac = P({ Size = Vector3.new(1.6, 1.2, 1), CFrame = CFrame.new(acx, (ff - 1) * FLOOR_H + 3.5, cz + side * (d / 2 + 0.7)), Color = Color3.fromRGB(168, 170, 172), Material = MAT.Metal })
		reg(ac, 15, "Prop", bld, ff)
		if math.random() < 0.4 then
			local dish = P({ Size = Vector3.new(0.3, 2, 2), CFrame = CFrame.new(acx + 6, (ff - 1) * FLOOR_H + 6, cz + side * (d / 2 + 0.6)) * CFrame.Angles(math.rad(30), 0, 0), Color = Color3.fromRGB(200, 200, 200), Material = MAT.Plastic })
			reg(dish, 10, "Prop", bld, ff)
		end
	end
	-- водосточные трубы
	for _, side in ipairs({ -1, 1 }) do
		local pipe = P({ Size = Vector3.new(0.5, floors * FLOOR_H, 0.5), CFrame = CFrame.new(cx + side * (w / 2 + 0.8), floors * FLOOR_H / 2, cz - d / 2 + 1), Color = Color3.fromRGB(150, 152, 155), Material = MAT.Metal })
		reg(pipe, 15, "Prop", bld, 1)
	end
	-- бельевые верёвки на крыше
	for i = 1, 2 do
		reg(P({ Size = Vector3.new(8, 0.15, 0.15), CFrame = CFrame.new(cx - 6 + i * 6, floors * FLOOR_H + 3.4, cz + 4), Color = Color3.fromRGB(210, 210, 210), Material = MAT.Plastic }), 5, "Prop", bld, floors + 1)
		reg(P({ Size = Vector3.new(0.8, 3.4, 0.8), CFrame = CFrame.new(cx - 10 + i * 6, floors * FLOOR_H + 2.2, cz + 4), Color = Color3.fromRGB(120, 100, 80), Material = MAT.Wood }), 10, "Prop", bld, floors + 1)
	end
	return bld
end

-- ------------------------------------------------------------
-- СТЕКЛЯННАЯ БАШНЯ ЦЕНТРА (10-20 этажей)
-- ------------------------------------------------------------
local function glassTower(cx, cz, floors, opts)
	opts = opts or {}
	local w, d = opts.w or 34, opts.d or 34
	local color = opts.color or Color3.fromRGB(120, 160, 190)
	local bld = Destruction.RegisterBuilding("residential_big", opts.name or "Бизнес-центр", Vector3.new(cx, floors * FLOOR_H / 2, cz))
	reg(P({ Size = Vector3.new(w + 4, 1, d + 4), CFrame = CFrame.new(cx, 0.5, cz), Color = Color3.fromRGB(100, 100, 100), Material = MAT.Concrete }), 400, "Floor", bld, 0)
	for f = 1, floors do
		local y0 = (f - 1) * FLOOR_H
		reg(P({ Size = Vector3.new(w, 1, d), CFrame = CFrame.new(cx, y0 + 9.5, cz), Color = Color3.fromRGB(90, 92, 96), Material = MAT.Concrete }), 140, "Floor", bld, f)
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				reg(P({ Size = Vector3.new(2.4, 8, 2.4), CFrame = CFrame.new(cx + sx * (w / 2 - 1.2), y0 + 5, cz + sz * (d / 2 - 1.2)), Color = Color3.fromRGB(70, 72, 76), Material = MAT.Concrete }), 200, "Column", bld, f)
			end
		end
		for _, side in ipairs({ -1, 1 }) do
			local glassF = P({ Size = Vector3.new(w - 4, 8, 0.6), CFrame = CFrame.new(cx, y0 + 5, cz + side * (d / 2)), Color = color, Material = MAT.Glass, Transparency = 0.35, Reflectance = 0.25 })
			reg(glassF, 4, "Window", bld, f)
			table.insert(MapGenerator.Windows, glassF)
			local glassL = P({ Size = Vector3.new(0.6, 8, d - 4), CFrame = CFrame.new(cx + side * (w / 2), y0 + 5, cz), Color = color, Material = MAT.Glass, Transparency = 0.35, Reflectance = 0.25 })
			reg(glassL, 4, "Window", bld, f)
		end
	end
	reg(P({ Size = Vector3.new(w, 1, d), CFrame = CFrame.new(cx, floors * FLOOR_H + 0.5, cz), Color = Color3.fromRGB(80, 80, 84), Material = MAT.Concrete }), 160, "Roof", bld, floors + 1)
	-- неоновая вывеска
	local sign = P({ Size = Vector3.new(w * 0.6, 3, 0.5), CFrame = CFrame.new(cx, floors * FLOOR_H - 4, cz - d / 2 - 0.6), Color = opts.signColor or Color3.fromRGB(0, 200, 255), Material = MAT.Neon })
	reg(sign, 20, "Prop", bld, floors)
	local sg = Instance.new("SurfaceGui", sign)
	sg.Face = Enum.NormalId.Front
	local tl = Instance.new("TextLabel", sg)
	tl.Size = UDim2.new(1, 0, 1, 0)
	tl.BackgroundTransparency = 1
	tl.Font = Enum.Font.GothamBold
	tl.TextScaled = true
	tl.TextColor3 = Color3.fromRGB(10, 10, 20)
	tl.Text = opts.signText or "CITY"
	return bld
end

-- ------------------------------------------------------------
-- ПРОМЗОНА
-- ------------------------------------------------------------
local function smokeStack(cf, bld, height)
	local stack = P({ Size = Vector3.new(5, height, 5), CFrame = cf * CFrame.new(0, height / 2, 0), Color = Color3.fromRGB(150, 70, 60), Material = MAT.Brick })
	reg(stack, 300, "Column", bld, 1)
	local top = cf * CFrame.new(0, height + 0.5, 0)
	local att = Instance.new("Attachment", stack)
	att.Position = Vector3.new(0, height / 2, 0)
	local pe = Instance.new("ParticleEmitter", att)
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Color = ColorSequence.new(Color3.fromRGB(160, 160, 165))
	pe.Rate = 8
	pe.Lifetime = NumberRange.new(4, 7)
	pe.Speed = NumberRange.new(3, 6)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 12) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	return stack
end

local function factory(cx, cz)
	local bld = Destruction.RegisterBuilding("industrial", "Завод", Vector3.new(cx, 12, cz))
	local w, d, h = 90, 46, 22
	reg(P({ Size = Vector3.new(w, 1, d), CFrame = CFrame.new(cx, 0.5, cz), Color = Color3.fromRGB(100, 100, 100), Material = MAT.Concrete }), 500, "Floor", bld, 0)
	-- стены из крупных секций
	for _, side in ipairs({ -1, 1 }) do
		for i = -1, 1 do
			reg(P({ Size = Vector3.new(w / 3, h, 1.2), CFrame = CFrame.new(cx + i * w / 3, h / 2 + 1, cz + side * (d / 2)), Color = Color3.fromRGB(125, 100, 80), Material = MAT.Brick }), 150, "Wall", bld, 1)
			reg(P({ Size = Vector3.new(1.2, h, d - 2), CFrame = CFrame.new(cx + side * (w / 2), h / 2 + 1, cz), Color = Color3.fromRGB(125, 100, 80), Material = MAT.Brick }), 150, "Wall", bld, 1)
		end
	end
	-- окна-полосы
	for _, side in ipairs({ -1, 1 }) do
		local strip = P({ Size = Vector3.new(w - 10, 3, 0.5), CFrame = CFrame.new(cx, h * 0.7 + 1, cz + side * (d / 2 + 0.5)), Color = Color3.fromRGB(150, 170, 185), Material = MAT.Glass, Transparency = 0.5 })
		reg(strip, 2, "Window", bld, 1)
	end
	-- многослойная крыша (для обрушения — 3 секции)
	for i = -1, 1 do
		reg(P({ Size = Vector3.new(w / 3, 1, d), CFrame = CFrame.new(cx + i * w / 3, h + 1.5, cz), Color = Color3.fromRGB(105, 105, 108), Material = MAT.CorrodedMetal }), 180, "Roof", bld, 2)
	end
	-- трубы с дымом
	smokeStack(CFrame.new(cx - w / 3, 1, cz - d / 2 + 8), bld, 55)
	smokeStack(CFrame.new(cx - w / 3 + 14, 1, cz - d / 2 + 8), bld, 45)
	-- станки внутри (декор)
	for i = 1, 5 do
		local m = P({ Size = Vector3.new(10, 6, 6), CFrame = CFrame.new(cx - 30 + i * 15, 4, cz), Color = Color3.fromRGB(255, 176, 0), Material = MAT.Metal })
		reg(m, 60, "Prop", bld, 1)
	end
	return bld
end

local function warehouse(cx, cz, alongX)
	local bld = Destruction.RegisterBuilding("industrial", "Ангар", Vector3.new(cx, 10, cz))
	local w, d, h = 60, 36, 18
	local cf = CFrame.new(cx, 0, cz)
	if not alongX then cf = cf * CFrame.Angles(0, math.rad(90), 0) end
	reg(P({ Size = Vector3.new(w, 1, d), CFrame = cf * CFrame.new(0, 0.5, 0), Color = Color3.fromRGB(110, 110, 110), Material = MAT.Concrete }), 400, "Floor", bld, 0)
	for _, side in ipairs({ -1, 1 }) do
		reg(P({ Size = Vector3.new(w, h, 1.2), CFrame = cf * CFrame.new(0, h / 2 + 1, side * (d / 2)), Color = Color3.fromRGB(110, 130, 150), Material = MAT.DiamondPlate }), 140, "Wall", bld, 1)
		for _, sx in ipairs({ -1, 1 }) do
			reg(P({ Size = Vector3.new(1.2, h, d - 2), CFrame = cf * CFrame.new(sx * (w / 2), h / 2 + 1, 0), Color = Color3.fromRGB(110, 130, 150), Material = MAT.DiamondPlate }), 140, "Wall", bld, 1)
		end
	end
	-- рольставни (широкие серые ворота)
	for _, sx in ipairs({ -1, 0, 1 }) do
		local gate = P({ Size = Vector3.new(w / 3 - 2, h - 4, 0.8), CFrame = cf * CFrame.new(sx * w / 3, (h - 4) / 2 + 1, -d / 2 - 0.4), Color = Color3.fromRGB(170, 170, 175), Material = MAT.DiamondPlate })
		reg(gate, 90, "Wall", bld, 1)
	end
	reg(P({ Size = Vector3.new(w, 1, d), CFrame = cf * CFrame.new(0, h + 1.5, 0), Color = Color3.fromRGB(95, 100, 110), Material = MAT.CorrodedMetal }), 170, "Roof", bld, 2)
	return bld
end

local function oilTanks(cx, cz)
	local bld = Destruction.RegisterBuilding("industrial", "Нефтяные цистерны", Vector3.new(cx, 8, cz))
	for i = 1, 4 do
		local ox = cx + ((i - 1) % 2) * 26 - 13
		local oz = cz + math.floor((i - 1) / 2) * 26 - 13
		local tank = Instance.new("Part")
		tank.Anchored = true
		tank.Shape = Enum.PartType.Cylinder
		tank.Size = Vector3.new(16, 22, 22)
		tank.CFrame = CFrame.new(ox, 8, oz) * CFrame.Angles(0, 0, math.rad(90))
		tank.Color = Color3.fromRGB(210, 210, 215)
		tank.Material = MAT.Metal
		tank.Parent = City
		reg(tank, 160, "Column", bld, 1)
		tank:SetAttribute("Boom", true)
		tank:SetAttribute("BoomPower", 45)
	end
	return bld
end

local function crane(cx, cz)
	local bld = Destruction.RegisterBuilding("industrial", "Башенный кран", Vector3.new(cx, 40, cz))
	local mast = P({ Size = Vector3.new(4, 70, 4), CFrame = CFrame.new(cx, 35, cz), Color = Color3.fromRGB(230, 120, 30), Material = MAT.Metal })
	reg(mast, 250, "Column", bld, 1)
	local jib = P({ Size = Vector3.new(80, 2.5, 3), CFrame = CFrame.new(cx + 20, 72, cz), Color = Color3.fromRGB(230, 120, 30), Material = MAT.Metal })
	reg(jib, 120, "Wall", bld, 2)
	local counter = P({ Size = Vector3.new(25, 2.5, 3), CFrame = CFrame.new(cx - 22, 72, cz), Color = Color3.fromRGB(230, 120, 30), Material = MAT.Metal })
	reg(counter, 120, "Wall", bld, 2)
	local cab = P({ Size = Vector3.new(5, 5, 5), CFrame = CFrame.new(cx + 3, 67, cz - 3), Color = Color3.fromRGB(60, 160, 200), Material = MAT.Glass })
	reg(cab, 60, "Prop", bld, 1)
	local cable = P({ Size = Vector3.new(0.2, 18, 0.2), CFrame = CFrame.new(cx + 50, 62, cz), Color = Color3.fromRGB(40, 40, 40), Material = MAT.Metal })
	reg(cable, 10, "Prop", bld, 2)
	local hook = P({ Size = Vector3.new(3, 2, 3), CFrame = CFrame.new(cx + 50, 52, cz), Color = Color3.fromRGB(50, 50, 50), Material = MAT.Metal })
	reg(hook, 10, "Prop", bld, 2)
	return bld
end

local function containers(cx, cz)
	local bld = Destruction.RegisterBuilding("industrial", "Контейнерная площадка", Vector3.new(cx, 6, cz))
	local colors = { Color3.fromRGB(180, 60, 50), Color3.fromRGB(50, 110, 170), Color3.fromRGB(70, 140, 80), Color3.fromRGB(200, 160, 40) }
	for i = 1, 12 do
		local ox = cx + (i % 4) * 24 - 36
		local oz = cz + math.floor(i / 4) * 12
		local stackH = math.random(1, 3)
		for lvl = 1, stackH do
			local c = P({ Size = Vector3.new(22, 8.5, 9), CFrame = CFrame.new(ox, 4.25 + (lvl - 1) * 8.5, oz) * CFrame.Angles(0, (i % 2) * math.rad(90), 0), Color = colors[(i + lvl) % 4 + 1], Material = MAT.Metal })
			reg(c, 70, "Prop", bld, lvl)
		end
	end
	return bld
end

local function railway(cx, cz)
	-- путь вдоль X
	local ballast = P({ Size = Vector3.new(900, 0.6, 10), CFrame = CFrame.new(cx, 0.4, cz), Color = Color3.fromRGB(110, 105, 95), Material = MAT.Slate })
	for x = cx - 440, cx + 440, 24 do
		P({ Size = Vector3.new(3, 0.4, 10), CFrame = CFrame.new(x, 0.8, cz), Color = Color3.fromRGB(90, 70, 55), Material = MAT.Wood, CanCollide = false })
	end
	P({ Size = Vector3.new(900, 0.4, 0.6), CFrame = CFrame.new(cx, 1.1, cz - 2.4), Color = Color3.fromRGB(90, 92, 96), Material = MAT.Metal, CanCollide = false })
	P({ Size = Vector3.new(900, 0.4, 0.6), CFrame = CFrame.new(cx, 1.1, cz + 2.4), Color = Color3.fromRGB(90, 92, 96), Material = MAT.Metal, CanCollide = false })
	-- товарные вагоны
	for i = 1, 6 do
		local wx = cx + i * 34 - 100
		local wagon = P({ Size = Vector3.new(28, 10, 11), CFrame = CFrame.new(wx, 6.5, cz), Color = (i % 2 == 0) and Color3.fromRGB(120, 60, 50) or Color3.fromRGB(70, 90, 110), Material = MAT.Metal })
		wagon:SetAttribute("Boom", false)
		wagon:SetAttribute("HP", 90)
		wagon:SetAttribute("MH", 90)
		wagon:SetAttribute("K", "Prop")
	end
end

local function gasStation(cx, cz)
	local bld = Destruction.RegisterBuilding("industrial", "Заправочная станция", Vector3.new(cx, 6, cz))
	-- навес
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			reg(P({ Size = Vector3.new(1.4, 14, 1.4), CFrame = CFrame.new(cx + sx * 14, 7, cz + sz * 9), Color = Color3.fromRGB(230, 230, 230), Material = MAT.Metal }), 120, "Column", bld, 1)
		end
	end
	reg(P({ Size = Vector3.new(36, 1.5, 26), CFrame = CFrame.new(cx, 15, cz), Color = Color3.fromRGB(200, 40, 40), Material = MAT.Metal }), 110, "Roof", bld, 2)
	-- колонки
	for _, sx in ipairs({ -1, 1 }) do
		local pump = P({ Size = Vector3.new(3, 6, 2), CFrame = CFrame.new(cx + sx * 6, 3, cz), Color = Color3.fromRGB(240, 240, 240), Material = MAT.Metal })
		reg(pump, 50, "Prop", bld, 1)
		pump:SetAttribute("Boom", true)
		pump:SetAttribute("BoomPower", 22)
	end
	-- магазинчик
	local shop = P({ Size = Vector3.new(18, 8, 12), CFrame = CFrame.new(cx + 30, 4, cz + 14), Color = Color3.fromRGB(235, 235, 235), Material = MAT.Concrete })
	reg(shop, 130, "Wall", bld, 1)
	return bld
end

-- ------------------------------------------------------------
-- ОСОБЫЕ ЗДАНИЯ
-- ------------------------------------------------------------
local function hospital(cx, cz)
	local bld = residential(cx, cz, 12, { panel = true, color = Color3.fromRGB(230, 230, 232), name = "Больница" })
	bld.category = "residential_big"
	-- красный крест на крыше
	local h1 = P({ Size = Vector3.new(10, 1, 3), CFrame = CFrame.new(cx, 12 * FLOOR_H + 2.2, cz), Color = Color3.fromRGB(220, 30, 30), Material = MAT.Neon })
	local h2 = P({ Size = Vector3.new(3, 1, 10), CFrame = CFrame.new(cx, 12 * FLOOR_H + 2.2, cz), Color = Color3.fromRGB(220, 30, 30), Material = MAT.Neon })
	reg(h1, 15, "Prop", bld, 13)
	reg(h2, 15, "Prop", bld, 13)
	-- вертолётная площадка
	local pad = P({ Size = Vector3.new(24, 0.5, 24), CFrame = CFrame.new(cx, 12 * FLOOR_H + 1.3, cz + 22), Color = Color3.fromRGB(60, 60, 64), Material = MAT.Concrete })
	reg(pad, 100, "Floor", bld, 13)
	return bld
end

local function fireStation(cx, cz)
	local bld = Destruction.RegisterBuilding("residential_small", "Пожарная часть", Vector3.new(cx, 8, cz))
	local w, d, h = 56, 30, 16
	reg(P({ Size = Vector3.new(w + 4, 1, d + 4), CFrame = CFrame.new(cx, 0.5, cz), Color = Color3.fromRGB(110, 110, 110), Material = MAT.Concrete }), 300, "Floor", bld, 0)
	for _, side in ipairs({ -1, 1 }) do
		reg(P({ Size = Vector3.new(w, h, 1.2), CFrame = CFrame.new(cx, h / 2 + 1, cz + side * (d / 2)), Color = Color3.fromRGB(200, 60, 50), Material = MAT.Brick }), 140, "Wall", bld, 1)
		for _, sx in ipairs({ -1, 1 }) do
			reg(P({ Size = Vector3.new(1.2, h, d), CFrame = CFrame.new(cx + sx * (w / 2), h / 2 + 1, cz), Color = Color3.fromRGB(200, 60, 50), Material = MAT.Brick }), 140, "Wall", bld, 1)
		end
	end
	-- открытые ворота (проёмы)
	for _, sx in ipairs({ -1, 0, 1 }) do
		reg(P({ Size = Vector3.new(1.2, h - 5, 8), CFrame = CFrame.new(cx + sx * 16, (h - 5) / 2 + 1, cz - d / 2), Color = Color3.fromRGB(180, 55, 45), Material = MAT.Brick }), 130, "Wall", bld, 1)
	end
	reg(P({ Size = Vector3.new(w, 1, d), CFrame = CFrame.new(cx, h + 1.5, cz), Color = Color3.fromRGB(120, 60, 55), Material = MAT.Concrete }), 150, "Roof", bld, 2)
	-- пожарная машина внутри
	local truckBody = P({ Size = Vector3.new(22, 7, 9), CFrame = CFrame.new(cx, 5, cz + 4), Color = Color3.fromRGB(210, 30, 30), Material = MAT.Metal })
	reg(truckBody, 80, "Prop", bld, 1)
	local cab = P({ Size = Vector3.new(6, 5.5, 8.5), CFrame = CFrame.new(cx + 12, 5.5, cz + 4), Color = Color3.fromRGB(210, 30, 30), Material = MAT.Metal })
	reg(cab, 60, "Prop", bld, 1)
	local siren = P({ Size = Vector3.new(1.5, 0.8, 2), CFrame = CFrame.new(cx + 12, 9, cz + 4), Color = Color3.fromRGB(255, 60, 60), Material = MAT.Neon })
	return bld
end

local function policeStation(cx, cz)
	local bld = Destruction.RegisterBuilding("residential_small", "Полицейский участок", Vector3.new(cx, 8, cz))
	local w, d, h = 44, 30, 18
	reg(P({ Size = Vector3.new(w + 4, 1, d + 4), CFrame = CFrame.new(cx, 0.5, cz), Color = Color3.fromRGB(110, 110, 110), Material = MAT.Concrete }), 300, "Floor", bld, 0)
	for _, side in ipairs({ -1, 1 }) do
		reg(P({ Size = Vector3.new(w, h, 1.2), CFrame = CFrame.new(cx, h / 2 + 1, cz + side * (d / 2)), Color = Color3.fromRGB(90, 105, 130), Material = MAT.Brick }), 140, "Wall", bld, 1)
		for _, sx in ipairs({ -1, 1 }) do
			reg(P({ Size = Vector3.new(1.2, h, d), CFrame = CFrame.new(cx + sx * (w / 2), h / 2 + 1, cz), Color = Color3.fromRGB(90, 105, 130), Material = MAT.Brick }), 140, "Wall", bld, 1)
		end
	end
	local winStrip = P({ Size = Vector3.new(w - 8, 2.4, 0.5), CFrame = CFrame.new(cx, 10, cz - d / 2 - 0.5), Color = Color3.fromRGB(150, 170, 185), Material = MAT.Glass, Transparency = 0.5 })
	reg(winStrip, 2, "Window", bld, 1)
	reg(P({ Size = Vector3.new(w, 1, d), CFrame = CFrame.new(cx, h + 1.5, cz), Color = Color3.fromRGB(70, 85, 110), Material = MAT.Concrete }), 150, "Roof", bld, 2)
	-- мигалка
	local beacon = P({ Size = Vector3.new(1.6, 1, 1.6), CFrame = CFrame.new(cx, h + 2.6, cz - 8), Color = Color3.fromRGB(60, 100, 255), Material = MAT.Neon })
	return bld
end

local function school(cx, cz)
	local bld = Destruction.RegisterBuilding("residential_small", "Школа", Vector3.new(cx, 8, cz))
	local w, d, h = 80, 30, 15
	reg(P({ Size = Vector3.new(w + 4, 1, d + 4), CFrame = CFrame.new(cx, 0.5, cz), Color = Color3.fromRGB(110, 110, 110), Material = MAT.Concrete }), 350, "Floor", bld, 0)
	for _, side in ipairs({ -1, 1 }) do
		for i = -1, 1 do
			reg(P({ Size = Vector3.new(w / 3 - 2, h, 1.2), CFrame = CFrame.new(cx + i * w / 3, h / 2 + 1, cz + side * (d / 2)), Color = Color3.fromRGB(220, 200, 160), Material = MAT.Brick }), 120, "Wall", bld, 1)
			for wi = -2, 2 do
				local glass = P({ Size = Vector3.new(5, 4, 0.4), CFrame = CFrame.new(cx + i * w / 3 + wi * 7, h * 0.6 + 1, cz + side * (d / 2 + 0.4)), Color = Color3.fromRGB(150, 175, 195), Material = MAT.Glass, Transparency = 0.45 })
				reg(glass, 1, "Window", bld, 1)
			end
		end
		for _, sx in ipairs({ -1, 1 }) do
			reg(P({ Size = Vector3.new(1.2, h, d), CFrame = CFrame.new(cx + sx * (w / 2), h / 2 + 1, cz), Color = Color3.fromRGB(220, 200, 160), Material = MAT.Brick }), 120, "Wall", bld, 1)
		end
	end
	reg(P({ Size = Vector3.new(w, 1, d), CFrame = CFrame.new(cx, h + 1.5, cz), Color = Color3.fromRGB(150, 80, 60), Material = MAT.Concrete }), 150, "Roof", bld, 2)
	-- ограждение территории
	for i = -1, 1, 2 do
		reg(P({ Size = Vector3.new(w + 40, 3, 0.5), CFrame = CFrame.new(cx, 1.5, cz + i * (d / 2 + 16)), Color = Color3.fromRGB(60, 130, 70), Material = MAT.Metal }), 30, "Prop", bld, 0)
	end
	return bld
end

local function mall(cx, cz)
	local bld = Destruction.RegisterBuilding("mall", "Торговый центр", Vector3.new(cx, 12, cz))
	local w, d, h = 100, 64, 24
	reg(P({ Size = Vector3.new(w + 6, 1, d + 6), CFrame = CFrame.new(cx, 0.5, cz), Color = Color3.fromRGB(110, 110, 110), Material = MAT.Concrete }), 500, "Floor", bld, 0)
	for _, side in ipairs({ -1, 1 }) do
		for i = -1, 1 do
			reg(P({ Size = Vector3.new(w / 3, h, 1.4), CFrame = CFrame.new(cx + i * w / 3, h / 2 + 1, cz + side * (d / 2)), Color = Color3.fromRGB(200, 198, 194), Material = MAT.Concrete }), 160, "Wall", bld, 1)
		end
		reg(P({ Size = Vector3.new(1.4, h, d - 4), CFrame = CFrame.new(cx + side * (w / 2), h / 2 + 1, cz), Color = Color3.fromRGB(200, 198, 194), Material = MAT.Concrete }), 160, "Wall", bld, 1)
	end
	-- стеклянный вход
	local glassFront = P({ Size = Vector3.new(w - 8, h - 6, 0.6), CFrame = CFrame.new(cx, (h - 6) / 2 + 1, cz - d / 2 - 0.8), Color = Color3.fromRGB(120, 170, 210), Material = MAT.Glass, Transparency = 0.35, Reflectance = 0.2 })
	reg(glassFront, 4, "Window", bld, 1)
	reg(P({ Size = Vector3.new(w, 1, d), CFrame = CFrame.new(cx, h + 1.5, cz), Color = Color3.fromRGB(120, 118, 120), Material = MAT.Concrete }), 200, "Roof", bld, 2)
	-- неоновые вывески
	local signs = {
		{ "MEGA", Color3.fromRGB(255, 60, 160) },
		{ "SALE", Color3.fromRGB(60, 255, 120) },
		{ "ФОКУС", Color3.fromRGB(60, 160, 255) },
	}
	for i, s in ipairs(signs) do
		local sign = P({ Size = Vector3.new(20, 5, 0.6), CFrame = CFrame.new(cx - 30 + i * 30, h + 5, cz - d / 2 - 1), Color = s[2], Material = MAT.Neon })
		reg(sign, 25, "Prop", bld, 2)
		local sg = Instance.new("SurfaceGui", sign)
		sg.Face = Enum.NormalId.Front
		local tl = Instance.new("TextLabel", sg)
		tl.Size = UDim2.new(1, 0, 1, 0)
		tl.BackgroundTransparency = 1
		tl.Font = Enum.Font.GothamBlack
		tl.TextScaled = true
		tl.TextColor3 = Color3.fromRGB(15, 15, 25)
		tl.Text = s[1]
	end
	return bld
end

-- ------------------------------------------------------------
-- ПАРК, ПЛОЩАДЬ, ФОНТАН, ПАМЯТНИК
-- ------------------------------------------------------------
local function tree(cx, cz, kind)
	if kind == "spruce" then
		P({ Size = Vector3.new(1.4, 6, 1.4), CFrame = CFrame.new(cx, 3, cz), Color = Color3.fromRGB(90, 62, 40), Material = MAT.Wood })
		for i = 1, 3 do
			local w = 9 - i * 2.2
			P({ Size = Vector3.new(w, 3.4, w), CFrame = CFrame.new(cx, 5.6 + i * 2.6, cz), Color = Color3.fromRGB(40, 105 + i * 10, 50), Material = MAT.Grass })
		end
	elseif kind == "birch" then
		P({ Size = Vector3.new(1, 10, 1), CFrame = CFrame.new(cx, 5, cz), Color = Color3.fromRGB(225, 225, 220), Material = MAT.Wood })
		P({ Size = Vector3.new(7, 5, 7), CFrame = CFrame.new(cx, 11.5, cz), Color = Color3.fromRGB(90, 150, 70), Material = MAT.Grass })
	else
		P({ Size = Vector3.new(1.6, 8, 1.6), CFrame = CFrame.new(cx, 4, cz), Color = Color3.fromRGB(100, 72, 48), Material = MAT.Wood })
		P({ Size = Vector3.new(9, 6, 9), CFrame = CFrame.new(cx, 10.5, cz), Color = Color3.fromRGB(70, 140, 60), Material = MAT.Grass })
		P({ Size = Vector3.new(6, 4, 6), CFrame = CFrame.new(cx + 2, 14, cz - 1), Color = Color3.fromRGB(110, 150, 60), Material = MAT.Grass })
	end
end

local function bench(cx, cz, rot)
	local cf = CFrame.new(cx, 1.2, cz) * CFrame.Angles(0, rot, 0)
	P({ Size = Vector3.new(6, 0.3, 2), CFrame = cf, Color = Color3.fromRGB(110, 80, 55), Material = MAT.Wood })
	P({ Size = Vector3.new(6, 2, 0.3), CFrame = cf * CFrame.new(0, 1, 1), Color = Color3.fromRGB(110, 80, 55), Material = MAT.Wood })
end

local function park(cx, cz)
	-- дорожки
	P({ Size = Vector3.new(200, 0.25, 10), CFrame = CFrame.new(cx, 0.25, cz), Color = Color3.fromRGB(190, 180, 160), Material = MAT.Concrete, CanCollide = false })
	P({ Size = Vector3.new(10, 0.25, 200), CFrame = CFrame.new(cx, 0.25, cz), Color = Color3.fromRGB(190, 180, 160), Material = MAT.Concrete, CanCollide = false })
	-- пруд
	local pond = P({ Size = Vector3.new(46, 0.8, 34), CFrame = CFrame.new(cx + 55, 0.45, cz + 55), Color = Color3.fromRGB(60, 120, 170), Material = MAT.Glass, Transparency = 0.25 })
	pond.Name = "Pond"
	table.insert(MapGenerator.DuckSpots, Vector3.new(cx + 55, 2, cz + 55))
	-- деревья
	local rnd = Random.new(42)
	for i = 1, 34 do
		local ang = rnd:NextNumber() * math.pi * 2
		local r = 30 + rnd:NextNumber() * 65
		local tx = cx + math.cos(ang) * r
		local tz = cz + math.sin(ang) * r
		if math.abs(tx - (cx + 55)) > 30 or math.abs(tz - (cz + 55)) > 26 then
			local kinds = { "birch", "spruce", "maple" }
			tree(tx, tz, kinds[rnd:NextInteger(1, 3)])
		end
	end
	-- лавочки + фонари
	for i = 1, 6 do
		bench(cx - 60 + i * 22, cz - 10, 0)
		addLamp(cx - 60 + i * 22, cz + 10, math.rad(180))
	end
end

local function plaza(cx, cz)
	-- мощение
	P({ Size = Vector3.new(170, 0.3, 170), CFrame = CFrame.new(cx, 0.28, cz), Color = Color3.fromRGB(175, 172, 165), Material = MAT.Concrete, CanCollide = false })
	-- фонтан
	local basin = Instance.new("Part")
	basin.Anchored = true
	basin.Shape = Enum.PartType.Cylinder
	basin.Size = Vector3.new(2.2, 30, 30)
	basin.CFrame = CFrame.new(cx, 1.1, cz) * CFrame.Angles(0, 0, math.rad(90))
	basin.Color = Color3.fromRGB(160, 158, 150)
	basin.Material = MAT.Concrete
	basin.Parent = City
	local water = P({ Size = Vector3.new(1.8, 26, 26), CFrame = CFrame.new(cx, 1.15, cz) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(70, 150, 210), Material = MAT.Glass, Transparency = 0.35, CanCollide = false })
	local column = P({ Size = Vector3.new(2.5, 6, 2.5), CFrame = CFrame.new(cx, 4, cz), Color = Color3.fromRGB(170, 168, 160), Material = MAT.Concrete })
	local top = P({ Size = Vector3.new(6, 0.8, 6), CFrame = CFrame.new(cx, 7.2, cz), Color = Color3.fromRGB(170, 168, 160), Material = MAT.Concrete })
	local att = Instance.new("Attachment", top)
	local jets = Instance.new("ParticleEmitter", att)
	jets.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	jets.Color = ColorSequence.new(Color3.fromRGB(150, 210, 255))
	jets.Rate = 30
	jets.Lifetime = NumberRange.new(0.8, 1.2)
	jets.Speed = NumberRange.new(10, 14)
	jets.SpreadAngle = Vector2.new(25, 25)
	jets.Acceleration = Vector3.new(0, -25, 0)
	jets.Size = NumberSequence.new(0.5)
	-- памятник
	local mx = cx - 50
	local pedestal = P({ Size = Vector3.new(10, 4, 10), CFrame = CFrame.new(mx, 2.2, cz), Color = Color3.fromRGB(130, 128, 122), Material = MAT.Concrete })
	local torso = P({ Size = Vector3.new(3.4, 6, 2.2), CFrame = CFrame.new(mx, 7.4, cz), Color = Color3.fromRGB(70, 85, 60), Material = MAT.Metal })
	local head = Instance.new("Part")
	head.Anchored = true; head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.8, 1.8, 1.8); head.CFrame = CFrame.new(mx, 11.2, cz)
	head.Color = Color3.fromRGB(70, 85, 60); head.Material = MAT.Metal; head.Parent = City
	local arm = P({ Size = Vector3.new(4.5, 0.9, 0.9), CFrame = CFrame.new(mx + 1.5, 9.5, cz) * CFrame.Angles(0, 0, math.rad(-40)), Color = Color3.fromRGB(70, 85, 60), Material = MAT.Metal })
	-- клумбы
	for i = 1, 4 do
		P({ Size = Vector3.new(14, 1, 14), CFrame = CFrame.new(cx + 55, 0.8, cz - 55 + i * 0), Color = Color3.fromRGB(80, 60, 50), Material = MAT.Slate })
		P({ Size = Vector3.new(12, 0.8, 12), CFrame = CFrame.new(cx + 55, 1.5, cz - 55), Color = Color3.fromRGB(70, 150, 60), Material = MAT.Grass })
		for j = 1, 8 do
			P({ Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(cx + 50 + math.random() * 10, 2.2, cz - 60 + math.random() * 10), Color = Color3.fromRGB(255, math.random(80, 200), math.random(80, 200)), Material = MAT.Plastic })
		end
	end
	for i = 1, 4 do bench(cx + math.random(-60, 60), cz + 70, math.rad(180)) end
	addLamp(cx - 70, cz - 70, 0)
	addLamp(cx + 70, cz + 70, 0)
end

local function cafes(cx, cz)
	-- летние веранды кафе у центральных башен
	local bld = Destruction.RegisterBuilding("residential_small", "Кафе", Vector3.new(cx, 5, cz))
	local body = P({ Size = Vector3.new(26, 10, 20), CFrame = CFrame.new(cx, 5, cz), Color = Color3.fromRGB(90, 70, 60), Material = MAT.Wood })
	reg(body, 110, "Wall", bld, 1)
	local roof = P({ Size = Vector3.new(28, 1, 22), CFrame = CFrame.new(cx, 10.5, cz), Color = Color3.fromRGB(60, 50, 45), Material = MAT.Wood })
	reg(roof, 90, "Roof", bld, 2)
	-- веранда: навес на столбах + столики
	local canopy = P({ Size = Vector3.new(30, 0.4, 12), CFrame = CFrame.new(cx, 7, cz - 16), Color = Color3.fromRGB(120, 60, 50), Material = MAT.Wood })
	reg(canopy, 60, "Roof", bld, 1)
	for _, sx in ipairs({ -1, 1 }) do
		reg(P({ Size = Vector3.new(0.5, 7, 0.5), CFrame = CFrame.new(cx + sx * 14, 3.5, cz - 21), Color = Color3.fromRGB(80, 60, 50), Material = MAT.Wood }), 30, "Column", bld, 1)
	end
	for i = 1, 4 do
		P({ Size = Vector3.new(4, 0.3, 4), CFrame = CFrame.new(cx - 12 + i * 8, 1.2, cz - 16), Color = Color3.fromRGB(230, 225, 215), Material = MAT.Plastic })
		P({ Size = Vector3.new(0.4, 1.2, 0.4), CFrame = CFrame.new(cx - 12 + i * 8, 0.6, cz - 16), Color = Color3.fromRGB(120, 120, 120), Material = MAT.Metal })
	end
	return bld
end

local function car(cf, color)
	local bld = Destruction.RegisterBuilding("industrial", "Автомобиль", cf.Position)
	local body = P({ Size = Vector3.new(6, 1.6, 12.5), CFrame = cf * CFrame.new(0, 1.6, 0), Color = color, Material = MAT.Plastic })
	reg(body, 45, "Prop", bld, 1)
	local cabin = P({ Size = Vector3.new(5.4, 1.6, 6), CFrame = cf * CFrame.new(0, 3, 0.6), Color = color, Material = MAT.Plastic })
	reg(cabin, 35, "Prop", bld, 1)
	local glass = P({ Size = Vector3.new(5.2, 1.2, 5.6), CFrame = cf * CFrame.new(0, 3.1, 0.6), Color = Color3.fromRGB(130, 170, 200), Material = MAT.Glass, Transparency = 0.4, CanCollide = false })
	reg(glass, 1, "Window", bld, 1)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local wheel = Instance.new("Part")
			wheel.Anchored = true; wheel.Shape = Enum.PartType.Cylinder
			wheel.Size = Vector3.new(1.2, 2, 2)
			wheel.CFrame = cf * CFrame.new(sx * 2.9, 1, sz * 4) * CFrame.Angles(0, 0, math.rad(90))
			wheel.Color = Color3.fromRGB(25, 25, 25); wheel.Material = MAT.Plastic; wheel.Parent = City
		end
	end
	body:SetAttribute("Boom", true)
	body:SetAttribute("BoomPower", 12)
	return bld
end

local function playground(cx, cz)
	-- качели
	P({ Size = Vector3.new(0.5, 8, 0.5), CFrame = CFrame.new(cx - 3, 4, cz), Color = Color3.fromRGB(200, 80, 60), Material = MAT.Metal })
	P({ Size = Vector3.new(0.5, 8, 0.5), CFrame = CFrame.new(cx + 3, 4, cz), Color = Color3.fromRGB(200, 80, 60), Material = MAT.Metal })
	P({ Size = Vector3.new(8, 0.5, 0.5), CFrame = CFrame.new(cx, 8, cz), Color = Color3.fromRGB(200, 80, 60), Material = MAT.Metal })
	for _, sx in ipairs({ -1, 1 }) do
		P({ Size = Vector3.new(0.15, 6, 0.15), CFrame = CFrame.new(cx + sx * 1.5, 5, cz), Color = Color3.fromRGB(60, 60, 60), Material = MAT.Metal })
		P({ Size = Vector3.new(1.6, 0.4, 0.8), CFrame = CFrame.new(cx + sx * 1.5, 2, cz), Color = Color3.fromRGB(50, 120, 200), Material = MAT.Plastic })
	end
	-- горка
	P({ Size = Vector3.new(6, 6, 6), CFrame = CFrame.new(cx + 14, 3, cz), Color = Color3.fromRGB(220, 150, 60), Material = MAT.Plastic })
	Util.wedge({ Size = Vector3.new(6, 5, 14), CFrame = CFrame.new(cx + 14, 2.5, cz + 10) * CFrame.Angles(0, math.rad(180), 0), Color = Color3.fromRGB(80, 180, 220), Material = MAT.Plastic }, City)
	-- песочница
	P({ Size = Vector3.new(12, 0.8, 12), CFrame = CFrame.new(cx - 16, 0.4, cz), Color = Color3.fromRGB(225, 200, 150), Material = MAT.Sand })
	for _, sx in ipairs({ -1, 1 }) do
		P({ Size = Vector3.new(12, 1.2, 0.8), CFrame = CFrame.new(cx - 16, 1, cz + sx * 6), Color = Color3.fromRGB(140, 100, 70), Material = MAT.Wood })
		P({ Size = Vector3.new(0.8, 1.2, 12), CFrame = CFrame.new(cx - 16 + sx * 6, 1, cz), Color = Color3.fromRGB(140, 100, 70), Material = MAT.Wood })
	end
end

-- ------------------------------------------------------------
-- ЗАСЕЛЕННОСТЬ КВАРТАЛОВ
-- ------------------------------------------------------------
local RES_COLORS = {
	Color3.fromRGB(188, 134, 108), Color3.fromRGB(196, 188, 172),
	Color3.fromRGB(178, 182, 178), Color3.fromRGB(200, 170, 140),
}
local CAR_COLORS = {
	Color3.fromRGB(200, 60, 50), Color3.fromRGB(60, 90, 180), Color3.fromRGB(230, 230, 230),
	Color3.fromRGB(50, 50, 55), Color3.fromRGB(90, 160, 90), Color3.fromRGB(220, 160, 40),
}

local function courtyard(x, z)
	playground(x + 45, z + 40)
	for i = 1, 3 do
		bench(x - 30 + i * 25, z + 55, 0)
	end
	P({ Size = Vector3.new(4, 2, 2.4), CFrame = CFrame.new(x - 55, 1, z - 50), Color = Color3.fromRGB(50, 80, 60), Material = MAT.Metal })
	P({ Size = Vector3.new(4, 2, 2.4), CFrame = CFrame.new(x - 50, 1, z - 50), Color = Color3.fromRGB(80, 80, 40), Material = MAT.Metal })
	-- припаркованные машины вдоль дороги (юг квартала)
	local n = math.random(2, 3)
	for i = 1, n do
		car(CFrame.new(x - 40 + i * 30, 0.3, z + 80) * CFrame.Angles(0, math.rad(90 + math.random(-4, 4)), 0), CAR_COLORS[math.random(1, #CAR_COLORS)])
	end
	tree(x - 70, z + 20, "maple")
	tree(x + 70, z - 20, "birch")
end

local function buildQuadrants()
	-- СЗ: жилые кварталы
	residential(-640, -640, 16, { color = RES_COLORS[1] })
	residential(-384, -640, 9, { panel = true })
	residential(-128, -640, 5, { color = RES_COLORS[2] })
	residential(-640, -384, 9, { color = RES_COLORS[4] })
	residential(-384, -384, 16, { panel = true })
	residential(-128, -384, 9, { color = RES_COLORS[1] })
	residential(-640, -128, 5, { color = RES_COLORS[2] })
	residential(-384, -128, 9, { color = RES_COLORS[4] })
	residential(-128, -128, 5, { panel = true })
	courtyard(-640, -640) courtyard(-384, -384) courtyard(-128, -128)
	school(-896, -384)
	residential(-640, -896, 9, { panel = true })
	residential(-128, -896, 5, { color = RES_COLORS[1] })
	fireStation(-896, -640)

	-- СВ: центр (стеклянные башни)
	glassTower(384, -640, 16, { name = "Башня «Восток»", signText = "VOSTOK", signColor = Color3.fromRGB(0, 200, 255) })
	glassTower(640, -640, 12, { name = "Башня «Меркурий»", signText = "MERCURY", signColor = Color3.fromRGB(255, 90, 60) })
	glassTower(384, -384, 20, { name = "Башня «Гранит»", signText = "GRANIT", signColor = Color3.fromRGB(160, 255, 80) }) -- самая высокая: Панцирь
	glassTower(640, -384, 14, { name = "Башня «Нефть»", signText = "OIL", signColor = Color3.fromRGB(255, 220, 60) })
	glassTower(384, -128, 10, { name = "Отель «Небо»", signText = "HOTEL", signColor = Color3.fromRGB(200, 80, 255) })
	glassTower(640, -128, 12, { name = "Офис «Орбита»", signText = "ORBITA", signColor = Color3.fromRGB(80, 255, 220) })
	courtyard(640, -640)
	mall(896, -384)
	hospital(896, -128)
	gasStation(128, -896)
	cafes(580, 60)
	residential(384, -896, 5, { panel = true })
	residential(640, -896, 9, { color = RES_COLORS[1] })

	-- ЮЗ: промышленная зона
	factory(-512, 512)
	warehouse(-256, 384, true)
	warehouse(-128, 640, false)
	oilTanks(-640, 896)
	crane(-384, 640)
	containers(-384, 440)
	railway(-576, 960)
	warehouse(-896, 128, true)
	residential(-640, 128, 5, { panel = true })
	residential(-640, 384, 9, { color = RES_COLORS[2] })

	-- ЮВ: площадь + южные жилые кварталы
	plaza(384, 384)
	residential(384, 640, 5, { color = RES_COLORS[1] })
	residential(640, 640, 9, { panel = true })
	residential(896, 640, 5, { color = RES_COLORS[2] })
	residential(384, 896, 9, { color = RES_COLORS[4] })
	residential(640, 896, 5, { panel = true })
	policeStation(896, 128)
	courtyard(640, 640)

	-- Парк между центром и рекой
	park(128, -384)

	-- Мосты через реку (река x 128..192, z 256..1024)
	buildBridge(160, 256, false)
	buildBridge(160, 512, false)
	buildBridge(160, 768, false)
end

-- Точки размещения стационарного оружия (заполняет WeaponService)
local function computePoints()
	MapGenerator.Points.Pantsir = Vector3.new(384, 20 * FLOOR_H + 2, -384) -- крыша башни «Гранит»
	MapGenerator.Points.ZU = {
		Vector3.new(384, 16 * FLOOR_H + 2, -640),
		Vector3.new(896, 121.5, -128),
		Vector3.new(-512, 24, 512),      -- крыша завода
		Vector3.new(440, 3, 430),        -- площадь
		Vector3.new(60, 3, -440),        -- парк
	}
	MapGenerator.Points.Spotlights = {
		Vector3.new(-920, 4, -920), Vector3.new(920, 4, -920),
		Vector3.new(-920, 4, 920), Vector3.new(920, 4, 920),
	}
end

-- ------------------------------------------------------------
function MapGenerator.Generate()
	City = Instance.new("Folder")
	City.Name = "City"
	City.Parent = workspace

	buildTerrain()
	buildRoads()
	buildQuadrants()
	computePoints()
end

function MapGenerator.Rebuild()
	local old = workspace:FindFirstChild("City")
	if old then old:Destroy() end
	Destruction.Reset()
	MapGenerator.NightLights = {}
	MapGenerator.Windows = {}
	MapGenerator.TrafficLights = {}
	MapGenerator.NPCWaypoints = {}
	MapGenerator.DuckSpots = {}
	MapGenerator.Points = { ZU = {}, Spotlights = {} }
	MapGenerator.Generate()
end

return MapGenerator
