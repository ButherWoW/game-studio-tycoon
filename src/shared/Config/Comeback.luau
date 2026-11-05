--!strict
-- Бонус возвращения (7.21, ComebackService): кого не было minAwayDays дней и дольше, при входе
-- получает incomeMinutes минут дохода и coffeeMinutes минут кофе. Окно «С возвращением!» —
-- в очереди окон входа (PopupQueue). Один раз на возвращение: «не было» считается по
-- profile.lastLogout (DataService пишет его при каждом сохранении), бонус ждёт в профиле до «Забрать».

local Comeback = {
	minAwayDays = 3,
	incomeMinutes = 30,
	coffeeMinutes = 15,
}

return Comeback
