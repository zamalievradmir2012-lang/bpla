-- ============================================================
--  «БЕСПИЛОТНИКИ» — общий конфиг (сервер + клиент)
-- ============================================================
local Config = {}

Config.GAME_NAME   = "БЕСПИЛОТНИКИ"
Config.MAP_HALF    = 1024      -- город 2048x2048 studs (координаты -1024..1024)
Config.ROUND_TIME  = 600       -- раунд 10 минут
Config.DAY_CYCLE   = 1200      -- полный цикл суток за 20 минут реального времени
Config.RESPAWN_TIME = 5        -- возрождение защитника
Config.MAX_DEBRIS  = 200       -- максимум свободных обломков одновременно
Config.TEAM_CAP    = 10        -- максимум игроков в команде

Config.TEAM_OPS = "Операторы БПЛА"
Config.TEAM_DEF = "Защитники ПВО"

Config.BUNKER_POS = Vector3.new(0, 4, -1250)    -- командный пункт операторов (севернее города)
Config.LOBBY_POS  = Vector3.new(0, 340, -1550)  -- лобби в небе
Config.PAD_POS    = Vector3.new(0, 46, -1250)   -- взлётная площадка на крыше бункера

-- Позиции города для радара/миникарты
Config.CITY_MIN = Vector2.new(-Config.MAP_HALF, -Config.MAP_HALF)
Config.CITY_MAX = Vector2.new(Config.MAP_HALF, Config.MAP_HALF)

-- ------------------------------------------------------------
-- ЗВУКИ: база — встроенные rbxasset:// (работают всегда),
-- маркетплейс-ID можно заменить на свои из Toolbox.
-- ------------------------------------------------------------
Config.SOUNDS = {
	Explosion    = "rbxasset://sounds/collide.wav",
	BigExplosion = "rbxassetid://2233908",           -- мощный взрыв (можно заменить)
	Shot         = "rbxasset://sounds/paintball.wav",
	HeavyShot    = "rbxassetid://10920368",          -- крупнокалиберный выстрел
	RocketLaunch = "rbxasset://sounds/Rocket shot.wav",
	RocketWhoosh = "rbxasset://sounds/Rocket whoosh 01.wav",
	Glass        = "rbxasset://sounds/Glassbreak.wav",
	Siren        = "rbxassetid://10920578",          -- классическая сирена (Wail)
	Motor        = "rbxassetid://10920268",          -- гул мотора (вертолётный)
	Jet          = "rbxasset://sounds/Rocket whoosh 01.wav",
	Collapse     = "rbxassetid://10548112",          -- обрушение (замените на тяжёлый грохот)
	Beep         = "rbxasset://sounds/electronicpingshort.wav",
	Click        = "rbxasset://sounds/clickfast.wav",
	Hurt         = "rbxasset://sounds/uuhhh.wav",
	Spring       = "rbxasset://sounds/short spring sound.wav",
}

-- ------------------------------------------------------------
-- ДРОНЫ (от дешёвых к дорогим)
-- Control: "A" = WASD от 3-го лица, "B" = FPV-мышь
-- Kind: grenade | kamikaze | bomber | missile | heavy | swarm
-- ------------------------------------------------------------
Config.DRONES = {
	{
		Id="pchela", Name="«Пчела»", Price=0, Control="A", Kind="grenade",
		Speed=60, Turn=100, HP=60, Ammo=1, BRadius=5, BDamage=30, FireTime=0, Fuel=nil,
		Reward=30, Flags={},
		Sound={Key="Motor", Pitch=2.2, Volume=0.45, MaxDistance=250},
		Desc="Малый гражданский квадрокоптер. 4 пропеллера, камера снизу. Несёт 1 гранату (R=5, 30 HP). После сброса — только разведка.",
	},
	{
		Id="upyr", Name="«Упырь» FPV", Price=200, Control="B", Kind="kamikaze",
		Speed=120, Turn=160, HP=30, Ammo=1, BRadius=10, BDamage=60, FireTime=0, Fuel=120,
		Reward=30, Flags={},
		Sound={Key="Motor", Pitch=2.6, Volume=0.5, MaxDistance=250},
		Desc="Гоночный FPV-дрон-камикадзе. Карбоновый каркас, GoPro, боеголовка снизу. Взрыв при столкновении: R=10, 60 HP, пробивает стены.",
	},
	{
		Id="geran1", Name="«Герань-1»", Price=500, Control="B", Kind="kamikaze",
		Speed=90, Turn=60, HP=40, Ammo=1, BRadius=25, BDamage=100, FireTime=30, Fuel=240,
		Reward=60, Flags={},
		Sound={Key="Motor", Pitch=0.7, Volume=0.85, MaxDistance=300},
		Desc="Одноразовый ударный БПЛА с дельтовидным крылом. Характерное жужжание двухтактного мотора слышно за 150 studs. Взрыв: R=25, 100 HP + пожар 30 c.",
	},
	{
		Id="geran2", Name="«Герань-2» (Shahed-136)", Price=1200, Control="B", Kind="kamikaze",
		Speed=100, Turn=55, HP=60, Ammo=1, BRadius=40, BDamage=150, FireTime=60, Fuel=240,
		Reward=60, Flags={},
		Sound={Key="Motor", Pitch=0.6, Volume=0.9, MaxDistance=300},
		Desc="Улучшенный Shahed-136 с боеголовкой повышенной мощности. Взрыв: R=40, 150 HP, обрушение нескольких этажей, пожар 60 c, воронка.",
	},
	{
		Id="orlan", Name="«Орлан-10»", Price=2000, Control="A", Kind="bomber",
		Speed=80, Turn=70, HP=80, Ammo=2, BRadius=15, BDamage=50, FireTime=0, Fuel=180,
		Reward=60, Flags={Marker=true},
		Sound={Key="Motor", Pitch=1.1, Volume=0.5, MaxDistance=250},
		Desc="Тактический БПЛА с крылом большого удлинения и шар-турелью. 2 малые бомбы (R=15, 50 HP). Клавиша E — режим подвесной камеры с маркером цели. Топливо: 3 мин.",
	},
	{
		Id="lancet", Name="«Ланцет-3»", Price=3500, Control="B", Kind="kamikaze",
		Speed=150, Turn=140, HP=50, Ammo=1, BRadius=20, BDamage=120, FireTime=0, Fuel=180,
		Reward=60, Flags={Loiter=true, Dive=true, ArmorPen=true},
		Sound={Key="Beep", Pitch=3.0, Volume=0.15, MaxDistance=120}, -- электромотор, тихий
		Desc="Барражирующий боеприпас с X-крылом. Тихий электромотор. C — барражирование (кружит, ждёт цель). Пикирование до 200 studs/s. Взрыв: R=20, 120 HP, игнорирует 50% защиты щитов.",
	},
	{
		Id="inohodets", Name="«Иноходец» (Орион)", Price=5000, Control="A", Kind="missile",
		Speed=70, Turn=60, HP=120, Ammo=4, BRadius=20, BDamage=80, FireTime=0, Fuel=300,
		Reward=100, Flags={ReloadPad=true},
		Sound={Key="Motor", Pitch=0.9, Volume=0.5, MaxDistance=250},
		Desc="Тяжёлый MALE-БПЛА, размах 35 studs. 4 управляемые ракеты (R=20, 80 HP). Перезарядка на ВПП базы — 15 c. Топливо: 5 мин.",
	},
	{
		Id="ohotnik", Name="«Охотник» (С-70)", Price=8000, Control="A", Kind="heavy",
		Speed=200, Turn=45, HP=150, Ammo=6, BRadius=35, BDamage=100, FireTime=20, Fuel=nil,
		Reward=100, Flags={Stealth=true, Modes=true},
		Sound={Key="Jet", Pitch=1.0, Volume=0.6, MaxDistance=350},
		Desc="Малозаметное летающее крыло. Реактивный двигатель, 6 тяжёлых бомб (R=35, 100 HP). R — режим 2 крылатых ракет (R=50, 200 HP, сносят здание целиком). На радаре виден только <100 studs.",
	},
	{
		Id="molniya", Name="«Молния»", Price=12000, Control="B", Kind="kamikaze",
		Speed=400, Turn=110, HP=60, Ammo=1, BRadius=70, BDamage=300, FireTime=0, Fuel=90,
		Reward=200, Flags={Knockback=true, ShakeAll=true, Blur=true},
		Sound={Key="Jet", Pitch=2.4, Volume=0.8, MaxDistance=400},
		Desc="Гиперзвуковой камикадзе, 400 studs/s. Практически неперехватываем. Взрыв: R=70, 300 HP, полная уничтожение здания, ударная волна отбрасывает на 50 studs, тряска экрана у всех.",
	},
	{
		Id="sarancha", Name="Рой «Саранча»", Price=15000, Control="A", Kind="swarm",
		Speed=100, Turn=120, HP=60, Ammo=20, BRadius=8, BDamage=25, FireTime=0, Fuel=240,
		Reward=200, Flags={},
		Sound={Key="Motor", Pitch=3.0, Volume=0.6, MaxDistance=300},
		Desc="Рой из 20 дронов-камикадзе под управлением лидера. G — смена строя (клин/облако). ЛКМ — ближайший дрон пикирует на цель (R=8, 25 HP). Удержание ЛКМ — атака всеми. ",
	},
}

Config.DRONE_BY_ID = {}
for _, d in ipairs(Config.DRONES) do Config.DRONE_BY_ID[d.Id] = d end

-- Монеты защитнику за сбитый дрон = d.Reward

-- ------------------------------------------------------------
-- ОРУЖИЕ ЗАЩИТНИКОВ
-- ------------------------------------------------------------
Config.WEAPONS = {
	AK74M = { Name="АК-74М", Damage=5,  Rate=10, Range=100, Mag=30, Reload=2, SpeedMul=1.0,  Tracer=Color3.fromRGB(255,220,120) },
	KORD  = { Name="Корд 6П49", Damage=15, Rate=8, Range=200, Mag=50, Reload=4, SpeedMul=0.5, Tracer=Color3.fromRGB(255,240,90) },
	IGLA  = { Name="ПЗРК «Игла-С»", LockTime=2, Damage=80, RocketSpeed=250, Reload=10, SpeedMul=0.85, MissChance=0.2 },
}

Config.STATIONARY = {
	ZU23    = { Name="ЗУ-23-2", Damage=40, Rate=6, Range=350, HeatShots=30, HeatTime=5, HP=300 },
	PANTSIR = { Name="Панцирь-С1", Cannon={Damage=50, Rate=10, Range=200, HeatShots=25, HeatTime=5},
	            Missile={Damage=120, LockTime=1, Count=8, Reload=15}, HP=600 },
}

-- ------------------------------------------------------------
-- ЭКОНОМИКА
-- ------------------------------------------------------------
Config.BUILDING_REWARD = {
	residential_small = 40, residential_big = 80, industrial = 60,
	aa = 100, bridge = 120, mall = 150,
}
Config.BUILDING_SCORE_NAME = {
	residential_small = "жилой дом", residential_big = "многоэтажка", industrial = "промобъект",
	aa = "зенитная установка", bridge = "мост", mall = "торговый центр",
}
Config.KILL_COINS = 25          -- оператору за убийство защитника
Config.SURVIVAL_COINS = 10      -- защитнику каждые 60 сек выживания
Config.SURVIVAL_PERIOD = 60
Config.CITY_ALIVE_BONUS = 50    -- защитникам, если разрушено < 20% города

Config.UPGRADES = {
	hp     = { Name="Усиленная броня",            Desc="+50 HP (максимум 300)",      Price=500 },
	reload = { Name="Ускоренная перезарядка ПЗРК", Desc="Перезарядка «Иглы»: 10с → 6с", Price=300 },
	shield = { Name="Бронещит",                    Desc="Щит перед собой, впитывает 100 HP", Price=200 },
	repair = { Name="Ремкомплект зенитки",         Desc="Восстановить уничтоженную ЗУ-23-2", Price=400 },
}

-- Точки возрождения защитников в городе
Config.DEF_SPAWNS = {
	Vector3.new(-768, 4, -768), Vector3.new(-256, 4, -256), Vector3.new(-768, 4, 0),
	Vector3.new(0, 4, -512),    Vector3.new(512, 4, -768),  Vector3.new(768, 4, -256),
	Vector3.new(768, 4, 0),     Vector3.new(0, 4, 768),     Vector3.new(-512, 4, 512),
	Vector3.new(384, 4, 256),
}

-- ------------------------------------------------------------
-- ИМЕНА REMOTE-ОБЪЕКТОВ (ReplicatedStorage.Remotes.*)
-- ------------------------------------------------------------
Config.REM = {
	SelectTeam    = "SelectTeam",     -- C→S RE (teamName)
	LaunchDrone   = "LaunchDrone",    -- C→S RF (droneId) → droneModel | nil, err
	ReturnDrone   = "ReturnDrone",    -- C→S RE ()
	DroneFire     = "DroneFire",      -- C→S RE (origin, dir)         -- сброс/пуск
	Detonate      = "Detonate",       -- C→S RE ()                    -- ручной подрыв
	SwarmAttack   = "SwarmAttack",    -- C→S RE (pos, all)
	SwarmFormation= "SwarmFormation", -- C→S RE (mode)
	Loiter        = "Loiter",         -- C→S RE (on)
	SetMode       = "SetMode",        -- C→S RE (mode)                -- «Охотник»
	DropMarker    = "DropMarker",     -- C→S RE (pos)                 -- «Орлан»
	WeaponFire    = "WeaponFire",     -- C→S RE (origin, dir)         -- АК/Корд
	IglaLaunch    = "IglaLaunch",     -- C→S RE (droneModel)
	BuyUpgrade    = "BuyUpgrade",     -- C→S RF (itemId) → ok, msg
	GunAim        = "GunAim",         -- C→S RE (gunModel, dir)
	GunFire       = "GunFire",        -- C→S RE (origin, dir)
	GunLeave      = "GunLeave",       -- C→S RE () -- выйти из прожектора
	-- Сервер → клиент:
	OperFX        = "OperFX",         -- {type="dead"|"hit"|"kill"|"launch", ...}
	Killfeed      = "Killfeed",       -- (msg)
	Radar         = "Radar",          -- (blips) — защитникам, 1 раз в 2 c
	Siren         = "Siren",          -- ("alarm"|"warn")
	Results       = "Results",        -- (data) — экран итогов раунда
	Shake         = "Shake",          -- (power)
	GunState      = "GunState",       -- (gunModel|nil)
	MarkerFX      = "MarkerFX",       -- (pos) — операторам: маркер цели
	Award         = "Award",          -- (amount, reason)
	Phase         = "Phase",          -- (phase, timeLeft, weather)
}

return Config
