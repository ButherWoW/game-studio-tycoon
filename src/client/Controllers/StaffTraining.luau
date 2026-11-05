--!strict
-- Обучение навыку в мире (Config/Training): над NPC, который учится, — полоска прогресса
-- с эмодзи навыка и временем до конца, вокруг — искры, в руках — книжка, которая чуть покачивается.
-- Всё на клиенте по атрибутам NPC (сервер StaffService ставит TrainingSkill / TrainingStart /
-- TrainingEnd / TrainingTo и тег StaffTraining): сеть не нагружаем каждый кадр.
-- Производительность: полоска — одна BillboardGui на учащегося (MaxDistance), текст обновляется
-- 4 раза в секунду; искры и книжка — только у MAX_EXTRAS ближайших к камере в EXTRA_DISTANCE
-- и не при «Меньше эффектов» (атрибут игрока LowGraphics). Голову не качаем: части NPC закреплены
-- и двигаются сервером (перерывы StaffLife) — локальный поворот спорил бы с репликацией.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Skills = require(ReplicatedStorage.Shared.Config.Skills)
local Images = require(ReplicatedStorage.Shared.Config.Images)
local StaffPower = require(script.Parent.Parent.StaffPower)
local Ui = require(script.Parent.Parent.Ui)

local TAG = "StaffTraining"
local TEXT_INTERVAL = 0.25 -- как часто обновлять текст и полоску
local EXTRAS_INTERVAL = 1 -- как часто пересчитывать, кому искры и книжку
local MAX_EXTRAS = 6
local EXTRA_DISTANCE = 60
local BAR_DISTANCE = 80
local DONE_GRACE = 3 -- после конца полоска висит полной ещё столько секунд (ждём сервер)
local BOOK_BOB = 0.06
local BOOK_RATE = 2.4
local BAR_COLOR = Color3.fromRGB(110, 170, 255)

local player = Players.LocalPlayer

type Record = {
	npc: Model,
	gui: BillboardGui?,
	fill: Frame?,
	label: TextLabel?,
	extras: { Instance },
	book: BasePart?,
	pages: BasePart?,
	phase: number,
}

local StaffTraining = {}
local records: { [Model]: Record } = {}

local function part(npc: Instance, name: string): BasePart?
	local found = npc:FindFirstChild(name)
	return if found and found:IsA("BasePart") then found else nil
end

local function lowGraphics(): boolean
	return player:GetAttribute("LowGraphics") == true
end

local function clock(seconds: number): string
	local s = math.max(math.ceil(seconds), 0)
	return string.format("%d:%02d", s // 60, s % 60)
end

local function times(npc: Model): (number, number)
	local startAt = tonumber(npc:GetAttribute("TrainingStart")) or 0
	local endAt = tonumber(npc:GetAttribute("TrainingEnd")) or startAt
	return startAt, endAt
end

local function buildBar(record: Record)
	local head = part(record.npc, "Head")
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "TrainingBar"
	gui.Size = UDim2.fromOffset(150, 38)
	-- Выше облачка перерыва и «+1» (StaffFeel, 3 studs): не перекрывают друг друга
	gui.StudsOffset = Vector3.new(0, 4.2, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = BAR_DISTANCE
	gui.ResetOnSpawn = false
	gui.Adornee = head
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Ui.colors.panel
	back.BackgroundTransparency = 0.15
	Ui.corner(back, 10)
	back.Parent = gui
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(6, 2)
	label.Size = UDim2.new(1, -12, 0, 20)
	label.Font = Ui.bodyFont
	label.TextScaled = true
	label.TextColor3 = Ui.colors.text
	label.Text = ""
	label.Parent = back
	local track = Instance.new("Frame")
	track.BackgroundColor3 = Color3.fromRGB(20, 20, 32)
	track.Position = UDim2.new(0, 6, 1, -13)
	track.Size = UDim2.new(1, -12, 0, 8)
	Ui.corner(track, 4)
	track.Parent = back
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = BAR_COLOR
	fill.Size = UDim2.fromScale(0, 1)
	Ui.corner(fill, 4)
	fill.Parent = track
	gui.Parent = head
	record.gui = gui
	record.fill = fill
	record.label = label
end

local function clearExtras(record: Record)
	for _, instance in record.extras do
		instance:Destroy()
	end
	record.extras = {}
	record.book = nil
	record.pages = nil
end

local function bookPart(size: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = material
	return p
end

-- Искры вокруг и книжка в руках
local function buildExtras(record: Record)
	local head = part(record.npc, "Head")
	if not head then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "TrainingSparkles"
	attachment.Position = Vector3.new(0, 0.6, 0)
	local emitter = Instance.new("ParticleEmitter")
	-- Искры Астры (Images.fx.sparkle, V24); 0 — стандартная текстура частиц
	if Images.fx.sparkle > 0 then
		emitter.Texture = "rbxassetid://" .. Images.fx.sparkle
	end
	emitter.Rate = 3
	emitter.Lifetime = NumberRange.new(1.2, 1.8)
	emitter.Speed = NumberRange.new(0.6, 1.4)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 1.2, 0)
	emitter.Size = NumberSequence.new(0.35, 0.1)
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.LightEmission = 0.6
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 225, 120), BAR_COLOR)
	emitter.Parent = attachment
	attachment.Parent = head
	table.insert(record.extras, attachment)

	local book =
		bookPart(Vector3.new(1.1, 0.16, 0.8), Color3.fromRGB(60, 110, 220), Enum.Material.SmoothPlastic)
	book.Name = "TrainingBook"
	local pages =
		bookPart(Vector3.new(1, 0.08, 0.72), Color3.fromRGB(250, 246, 230), Enum.Material.SmoothPlastic)
	pages.Name = "TrainingPages"
	book.Parent = record.npc
	pages.Parent = record.npc
	table.insert(record.extras, book)
	table.insert(record.extras, pages)
	record.book = book
	record.pages = pages
end

local function untrack(npc: Model)
	local record = records[npc]
	if not record then
		return
	end
	records[npc] = nil
	clearExtras(record)
	if record.gui then
		record.gui:Destroy()
	end
end

local function track(instance: Instance)
	if not instance:IsA("Model") or records[instance] then
		return
	end
	local npc = instance :: Model
	local record: Record = { npc = npc, extras = {}, phase = math.random() * math.pi * 2 }
	records[npc] = record
	buildBar(record)
end

local function updateText(now: number)
	for npc, record in records do
		if not npc.Parent then
			untrack(npc)
			continue
		end
		local startAt, endAt = times(npc)
		local total = math.max(endAt - startAt, 1)
		local progress = math.clamp((now - startAt) / total, 0, 1)
		if record.gui then
			record.gui.Enabled = now <= endAt + DONE_GRACE
		end
		if record.fill then
			record.fill.Size = UDim2.fromScale(progress, 1)
		end
		if record.label then
			local key = npc:GetAttribute("TrainingSkill")
			local icon = if Skills.isKey(key) then StaffPower.icons[key :: string] else ""
			local to = tonumber(npc:GetAttribute("TrainingTo")) or 0
			record.label.Text =
				string.format("📘 %s %d → %d · %s", icon, math.max(to - 1, 0), to, clock(endAt - now))
		end
	end
end

-- Искры и книжка — ближайшим к камере, не больше MAX_EXTRAS
local function updateExtras(now: number)
	local camera = workspace.CurrentCamera
	local wanted: { [Model]: boolean } = {}
	if camera and not lowGraphics() then
		local origin = camera.CFrame.Position
		local near: { { npc: Model, distance: number } } = {}
		for npc in records do
			local head = part(npc, "Head")
			local _, endAt = times(npc)
			if head and now <= endAt then
				local distance = (head.Position - origin).Magnitude
				if distance <= EXTRA_DISTANCE then
					table.insert(near, { npc = npc, distance = distance })
				end
			end
		end
		table.sort(near, function(a, b)
			return a.distance < b.distance
		end)
		for i = 1, math.min(#near, MAX_EXTRAS) do
			wanted[near[i].npc] = true
		end
	end
	for npc, record in records do
		local has = #record.extras > 0
		if wanted[npc] and not has then
			buildExtras(record)
		elseif not wanted[npc] and has then
			clearExtras(record)
		end
	end
end

-- Книжка перед грудью, слегка покачивается (каждый кадр, только у тех, у кого она есть)
local function updateBooks(t: number)
	for npc, record in records do
		local book, pages = record.book, record.pages
		local torso = part(npc, "UpperTorso") or part(npc, "Torso")
		if book and pages and torso then
			local bob = math.sin(t * BOOK_RATE + record.phase) * BOOK_BOB
			local tilt = math.sin(t * BOOK_RATE * 0.5 + record.phase) * 0.08
			local cframe = torso.CFrame
				* CFrame.new(0, -0.35 + bob, -0.95)
				* CFrame.Angles(math.rad(-35) + tilt, 0, 0)
			book.CFrame = cframe
			pages.CFrame = cframe * CFrame.new(0, 0.11, 0)
		end
	end
end

function StaffTraining.start()
	for _, instance in CollectionService:GetTagged(TAG) do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance: Instance)
		if instance:IsA("Model") then
			untrack(instance)
		end
	end)
	player:GetAttributeChangedSignal("LowGraphics"):Connect(function()
		if lowGraphics() then
			for _, record in records do
				clearExtras(record)
			end
		end
	end)
	local textAt, extrasAt = 0, 0
	RunService.Heartbeat:Connect(function()
		if next(records) == nil then
			return
		end
		local t = os.clock()
		if t >= textAt then
			textAt = t + TEXT_INTERVAL
			updateText(workspace:GetServerTimeNow())
		end
		if t >= extrasAt then
			extrasAt = t + EXTRAS_INTERVAL
			updateExtras(workspace:GetServerTimeNow())
		end
		updateBooks(t)
	end)
end

return StaffTraining
