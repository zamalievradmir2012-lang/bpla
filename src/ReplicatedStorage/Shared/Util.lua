-- ============================================================
--  Util — общие помощники (сервер + клиент)
-- ============================================================
local Util = {}
local Debris = game:GetService("Debris")

-- Создание инстанса с массовой установкой свойств
function Util.new(className, props, parent)
	local inst = Instance.new(className)
	if props then
		for k, v in pairs(props) do
			if k ~= "Parent" then inst[k] = v end
		end
	end
	inst.Parent = parent
	return inst
end

-- Быстрое создание Part
function Util.part(props, parent)
	props = props or {}
	props.ClassName = nil
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	p.Parent = parent
	return p
end

function Util.wedge(props, parent)
	local w = Instance.new("WedgePart")
	w.Anchored = true
	for k, v in pairs(props) do w[k] = v end
	w.Parent = parent
	return w
end

-- Part-цилиндр (ось Y), повёрнутый вдоль dir (unit)
function Util.cylinder(diameter, length, color, material, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(length, diameter, diameter)
	p.Color = color
	p.Material = material or Enum.Material.Metal
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- 3D-звук в точке (сервер или клиент)
function Util.sound3d(soundId, position, volume, pitch, maxDist, lifetime)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.Position = position
	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.Volume = volume or 1
	s.PlaybackSpeed = pitch or 1
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMaxDistance = maxDist or 300
	s.Parent = part
	part.Parent = workspace
	s:Play()
	Debris:AddItem(part, lifetime or 6)
	return s
end

-- Постоянный источник звука на Part
function Util.soundOn(part, soundId, props)
	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMaxDistance = 300
	if props then for k, v in pairs(props) do s[k] = v end end
	s.Parent = part
	return s
end

-- Трейсер выстрела: тонкая неоновая линия
function Util.tracer(from, to, color, parent, thickness, life)
	local dist = (to - from).Magnitude
	if dist < 0.5 then return end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.25
	p.Size = Vector3.new(thickness or 0.15, thickness or 0.15, dist)
	p.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -dist / 2)
	p.Parent = parent or workspace
	Debris:AddItem(p, life or 0.07)
	return p
end

-- Вспышка дула
function Util.muzzleFlash(pos, parent)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 100)
	light.Brightness = 6
	light.Range = 14
	light.Shadows = false
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.Transparency = 1; p.Size = Vector3.new(0.5, 0.5, 0.5); p.Position = pos
	light.Parent = p
	local att = Instance.new("Attachment"); att.Parent = p
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 210, 120))
	pe.LightEmission = 1
	pe.Lifetime = NumberRange.new(0.05, 0.1)
	pe.Speed = NumberRange.new(6)
	pe.SpreadAngle = Vector2.new(35, 35)
	pe.Size = NumberSequence.new(0.6)
	pe.Enabled = false
	pe.Parent = att
	p.Parent = parent or workspace
	pe:Emit(8)
	Debris:AddItem(p, 0.12)
end

-- Вспышка экрана взрыва (ParticleEmitter разовый)
function Util.burst(pos, opts)
	opts = opts or {}
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.Transparency = 1; p.Size = Vector3.new(1, 1, 1); p.Position = pos
	local att = Instance.new("Attachment"); att.Parent = p

	local fire = Instance.new("ParticleEmitter")
	fire.Texture = "rbxasset://textures/particles/fire_main.dds"
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 170, 60), Color3.fromRGB(120, 60, 20))
	fire.LightEmission = 1
	fire.Lifetime = NumberRange.new(0.4, 1.0)
	fire.Speed = NumberRange.new((opts.radius or 10) * 0.8, (opts.radius or 10) * 1.6)
	fire.SpreadAngle = Vector2.new(180, 180)
	fire.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, (opts.radius or 10) * 0.35), NumberSequenceKeypoint.new(1, 0.5)})
	fire.Enabled = false
	fire.Parent = att

	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(70, 70, 70))
	smoke.Lifetime = NumberRange.new(2, 4)
	smoke.Speed = NumberRange.new(4, 12)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, (opts.radius or 10) * 0.3), NumberSequenceKeypoint.new(1, (opts.radius or 10) * 1.2)})
	smoke.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1)})
	smoke.Enabled = false
	smoke.Parent = att

	p.Parent = opts.parent or workspace
	fire:Emit(opts.fireCount or 40)
	smoke:Emit(opts.smokeCount or 25)
	Debris:AddItem(p, 6)
	return p
end

function Util.lerp(a, b, t) return a + (b - a) * t end

function Util.clampMag(v, max) 
	if v.Magnitude > max then return v.Unit * max end
	return v
end

-- Поверхность земли в точке (Raycast вниз)
local downRay = RaycastParams.new()
downRay.FilterType = Enum.RaycastFilterType.Exclude
downRay.FilterDescendantsInstances = {}
function Util.setGroundExclude(list) downRay.FilterDescendantsInstances = list end
function Util.groundAt(pos, exclude)
	if exclude then downRay.FilterDescendantsInstances = exclude end
	local r = workspace:Raycast(pos + Vector3.new(0, 50, 0), Vector3.new(0, -300, 0), downRay)
	if r then return r.Position, r.Instance end
	return pos, nil
end

return Util
