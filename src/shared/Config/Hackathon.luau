--!strict
-- Ночь хакатона: раз в час на 10 минут вся разработка на сервере идёт ×2 быстрее
-- (очков за игру столько же, время вдвое меньше — как кофе). Окно сдвинуто на полчаса
-- от выставки (ExpoService подводит итоги на границе часа): события не накладываются.
-- Время общее для всех серверов (os.time), за минуту до начала — объявление.

local RunService = game:GetService("RunService")

local Debug = require(script.Parent.Debug)

local Hackathon = {
	intervalSeconds = 60 * 60,
	offsetSeconds = 30 * 60, -- начало в hh:30 UTC
	durationSeconds = 10 * 60,
	announceSeconds = 60,
	speedMultiplier = 2,
	-- В Studio чаще и короче, чтобы проверять без ожидания
	studioIntervalSeconds = 6 * 60,
	studioOffsetSeconds = 3 * 60,
	studioDurationSeconds = 2 * 60,
	studioAnnounceSeconds = 30,
}

export type Window = { startsAt: number, endsAt: number, announceSeconds: number }

-- Текущее окно хакатона (идёт сейчас) или ближайшее следующее
function Hackathon.window(now: number?): Window
	local t = now or os.time()
	local studio = RunService:IsStudio()
	if studio and Debug.hackathonForce then
		-- Начало — граница часа, чтобы окно не «начиналось» заново каждую секунду
		local startsAt = t // 3600 * 3600
		return { startsAt = startsAt, endsAt = startsAt + 7200, announceSeconds = 0 }
	end
	local interval = if studio then Hackathon.studioIntervalSeconds else Hackathon.intervalSeconds
	local offset = if studio then Hackathon.studioOffsetSeconds else Hackathon.offsetSeconds
	local duration = if studio then Hackathon.studioDurationSeconds else Hackathon.durationSeconds
	local announce = if studio then Hackathon.studioAnnounceSeconds else Hackathon.announceSeconds
	local startsAt = (t - offset) // interval * interval + offset
	if t >= startsAt + duration then
		startsAt += interval
	end
	return { startsAt = startsAt, endsAt = startsAt + duration, announceSeconds = announce }
end

function Hackathon.active(now: number?): boolean
	local t = now or os.time()
	local w = Hackathon.window(t)
	return t >= w.startsAt and t < w.endsAt
end

return Hackathon
