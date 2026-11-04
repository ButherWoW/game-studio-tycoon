--!strict
-- Состояние событий компании с сервера (CompanyEventService): активные эффекты с концом действия,
-- страховка, цены. Общий для карточки событий, плашек под HUD и окна «Студия» (страховка).
-- Remotes ждём в своём потоке: окна требуют этот модуль и не должны зависнуть без сервиса.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Texts = require(Shared.Config.Texts)
local Employees = require(Shared.Config.Employees)
local StudioLayout = require(Shared.StudioLayout)
local ClientState = require(script.Parent.ClientState)

export type Effect = { id: string, kind: string, value: number, endsAt: number, item: string? }
export type State = {
	effects: { Effect },
	insuranceEndsAt: number?,
	insurancePrice: number,
	insuranceSeconds: number,
	repairCost: number,
	nextScore: number,
	nextRevenue: number,
}
export type Line = { key: string, vars: { [string]: any }? }

local CompanyEventState = {}
CompanyEventState.state = {
	effects = {},
	insuranceEndsAt = nil,
	insurancePrice = 0,
	insuranceSeconds = 30 * 60,
	repairCost = 0,
	nextScore = 0,
	nextRevenue = 1,
} :: State
CompanyEventState.loaded = false
local changedEvent = Instance.new("BindableEvent")
CompanyEventState.changed = changedEvent.Event

local remotes: { [string]: RemoteEvent }? = nil

local function fire(name: string, ...: any)
	local r = remotes
	if r then
		r[name]:FireServer(...)
	end
end

function CompanyEventState.request()
	fire("CompanyEventStateRequest")
end

function CompanyEventState.buyInsurance()
	fire("BuyInsurance")
end

function CompanyEventState.repair()
	fire("RepairItem")
end

-- Серверное время: часы клиента могут спешить
function CompanyEventState.now(): number
	return workspace:GetServerTimeNow()
end

-- Секунд страховки осталось (0 — нет)
function CompanyEventState.insuranceLeft(): number
	local endsAt = CompanyEventState.state.insuranceEndsAt
	return if endsAt then math.max(endsAt - CompanyEventState.now(), 0) else 0
end

-- Сломанный предмет (потоп), если есть
function CompanyEventState.broken(): Effect?
	for _, effect in CompanyEventState.state.effects do
		if effect.kind == "broken" and effect.endsAt > CompanyEventState.now() then
			return effect
		end
	end
	return nil
end

local function upgradeName(id: string): string
	local upgrade = StudioLayout.get(id)
	if upgrade then
		local key = "upgrade_" .. upgrade.id
		return ClientState.localText(key, upgrade.name, Texts.en[key] or upgrade.name)
	end
	return id
end
CompanyEventState.upgradeName = upgradeName

-- Подставить имена и деньги в переменные строки сервера
function CompanyEventState.vars(raw: { [string]: any }?): { [string]: any }
	local vars = table.clone(raw or {})
	for _, field in { "money", "loss" } do
		if type(vars[field]) == "number" then
			vars[field] = Texts.money(vars[field])
		end
	end
	if type(vars.item) == "string" then
		vars.item = upgradeName(vars.item)
	end
	if type(vars.employee) == "string" then
		local employee = Employees.get(vars.employee)
		vars.name = if employee
			then ClientState.localText("employee_" .. employee.id, employee.name, employee.nameEn)
			else vars.employee
	end
	if type(vars.skill) == "string" then
		vars.skill = ClientState.t("focus_" .. vars.skill)
	end
	return vars
end

function CompanyEventState.lineText(line: Line): string
	return ClientState.t(line.key, CompanyEventState.vars(line.vars))
end

local function listen()
	local CompanyEventRemotes = require(Shared.CompanyEventRemotes)
	remotes = CompanyEventRemotes
	CompanyEventRemotes.CompanyEventState.OnClientEvent:Connect(function(newState: any)
		if type(newState) ~= "table" or type(newState.effects) ~= "table" then
			return
		end
		local effects: { Effect } = {}
		for _, e in newState.effects do
			if type(e) == "table" and type(e.kind) == "string" and type(e.endsAt) == "number" then
				table.insert(effects, {
					id = tostring(e.id),
					kind = e.kind,
					value = tonumber(e.value) or 0,
					endsAt = e.endsAt,
					item = if type(e.item) == "string" then e.item else nil,
				})
			end
		end
		CompanyEventState.state = {
			effects = effects,
			insuranceEndsAt = tonumber(newState.insuranceEndsAt),
			insurancePrice = tonumber(newState.insurancePrice) or 0,
			insuranceSeconds = tonumber(newState.insuranceSeconds) or 30 * 60,
			repairCost = tonumber(newState.repairCost) or 0,
			nextScore = tonumber(newState.nextScore) or 0,
			nextRevenue = tonumber(newState.nextRevenue) or 1,
		}
		CompanyEventState.loaded = true
		changedEvent:Fire()
	end)
	CompanyEventRemotes.CompanyEventStateRequest:FireServer()
end

-- Подписка при первом require (модуль кэшируется — один раз)
task.spawn(listen)

return CompanyEventState
