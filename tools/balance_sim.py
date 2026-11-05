#!/usr/bin/env python3
"""Модель баланса Game Studio Tycoon: активный игрок без Robux + офлайн-доход между сессиями.

Читает числа прямо из src/shared/Config (Upgrades, Stages, Economy, Expenses, Employees,
Research, Offline, Rebirth, HitCartridges, AdCampaigns), поэтому после правки конфигов
достаточно перезапустить:  python3 tools/balance_sim.py
Флаги: --quiet — только таблица вех, --variants — ещё медленный игрок и 30 мин в день,
--extras — с контрактами, франшизами, портативкой и стримером (с офиса).
--all — релизный проход (05.11): --extras + события дня, золотой час, налоги, DLC хитов
  (если окупается), см. ASSUMPTIONS ниже; --premium — то же с Roblox Premium (+10%);
--rebirth2 — ещё и второй забег после 1-го Rebirth: звезду покупает жадно (перебор веток).
--drops — с графиком контента (Config/ContentDrops): игрок начинает в день запуска, события дня
  выпадают только вышедшие к этому дню (жанры/темы модель не выбирает — у каждого жанра набора
  запуска есть тема 1.2, допущение topic_fit не меняется).

Это приближение, а не повтор кода сервера. Допущения (см. ASSUMPTIONS ниже):
- парк до гаража ~5 мин; дальше игрок сразу покупает всё, на что хватает денег,
  нанимает лучших доступных сотрудников, ставит им перк «Кранчер», учит исследования;
- оценка — матожидание по шуму критиков (±reviewNoise), баланс жанра ~0.85, хорошая тема,
  QTE в среднем +0.2, сочетания чередует (штраф за повтор почти не ловит);
- цикл игры = разработка + ~24 с на выбор/название/окно релиза; разработка — как
  DevelopmentService (Economy.devSeconds / devFloorSeconds): гараж ~45 с, позже ~25–30 с;
- рекламу «Стримеры» покупает, когда она окупается вдвое; полка хитов заполнена лучшими;
- день = 2 сессии по 45 мин (1.5 ч игры), между ними офлайн 5 ч и 17.5 ч;
- в день: ежедневное задание (15 мин дохода) + в среднем ~9 мин наград за вход.
Не моделируются: выставка, тренды/праздники, воровство хитов, кредиты, прокачка навыков.
"""

import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CFG = ROOT / "src" / "shared" / "Config"

ASSUMPTIONS = {
    "park_minutes": 5.0,  # парк до покупки гаража
    "overhead_s": 24.0,  # выбор жанра/темы, название, окно релиза (QTE идут во время разработки)
    "parallel_handle_s": 20.0,  # минимум секунд на игру, когда идут 2 проекта
    "balance": 0.85,  # попадание в рецепт жанра
    "topic_fit": 1.17,  # средняя «подходящая» тема (1.2 почти всегда, иногда 1.1)
    "qte": 0.2,  # средний эффект QTE за игру (2–4 события, Config/QuickEvents)
    "repeat": 0.1,  # средний штраф за повтор
    "employee_focus": 1.12,  # спец-бонус + стартовый навык по доле фокуса
    "cruncher_perks": 5,  # сколько сотрудников с перком «Кранчер» (−0.1 к времени каждый)
    "session_min": [45, 45],  # сессии за день
    "offline_gaps_h": [5.0, 17.5],  # перерыв после каждой сессии
    "daily_income_minutes": 24.0,  # ежедневное задание 15 + награды за вход ~9 (среднее)
    "max_days": 40,
    # --extras: системы с офиса (этап 2+), которых нет в основной модели
    "extras": False,
    "franchise_avg": 1.09,  # средний множитель франшизы на релиз (часть игр — продолжения, усталость)
    "platform_avg": 1.07,  # портативка: casual/puzzle ×1.2, остальное ~×1
    "streamer_avg": 1.02,  # хайп стримера почти весь тратится сразу (−25 за релиз)
    "contract_every_min": 12.0,  # предложение раз в ~10 мин + выполнение
    "contract_success": 0.8,
    # --all: релизный проход 05.11 — типичный бесплатный игрок до 1-го Rebirth (включает --extras).
    # Не учитываются: сейф ($500k, коды владельца — редко), бонус возвращения (3+ дня без входа),
    # «Игра недели» (топ-10 всех серверов — не типичный игрок), биржа/IPO (IPO $25M дороже
    # 1-го Rebirth), отделка/стили/декор и «Флеш-распродажа» (косметика), наставничество (навыки
    # модель не покупает), «Охота за талантами», пицца, парад маскотов, картриджепад (копейки).
    "all": False,
    "drops": False,  # --drops: события дня по графику контента (Config/ContentDrops), старт в день запуска
    "premium": False,  # Roblox Premium: +10% к релизам (Config/Premium) и +10% офлайн (Social.premium)
    "golden_days_share": 0.5,  # в золотой час (19:00 UTC) играет в половину дней: 2-я сессия с него
    # События дня — раз в час на 15 мин (hh:30). Сессия 45 мин задевает в среднем одно событие и
    # 45 × 15 / 60 = 11.25 мин его окна; события идут по кругу (вес у всех 1)
    "event_overlap_min": 11.25,
    "event_start_min": 25.0,  # с какой минуты сессии идёт окно события
    "investor_chance": 0.8,  # успел к инвестору в числе первых grants игроков сервера
    "bug_catch_per_min": 20.0,  # жуков в минуту, пока ловит (клик раз в ~3 с с перебежками)
    "bug_hunt_min": 8.0,  # сколько минут окна ловит жуков, если лимита на игрока нет
    "bug_hunt_income_loss": 0.5,  # пока ловит, релизов вдвое меньше
    "bug_top_chance": 0.5,  # попал в топ-3 ловцов (тогда — среднее topBonusMinutes)
    "blitz_win_chance": 0.25,  # выиграл блиц-джем (сервер ~8 игроков, участвуют 3–4)
    "critics_fit": 0.6,  # жанр критиков открыт и игрок переключился на него
    "taxes": True,  # налог по этапу (Config/Tax) с дохода релизов, платит вовремя (штраф дороже)
    "hit_updates": True,  # DLC хита покупает, только если буст окупает цену за свои 30 мин
    # --rebirth2: второй забег (исследования остаются, команда распущена, ворота по играм открыты)
    "max_days_run2": 60,
}


def num(s: str) -> float:
    return float(s.replace("_", ""))


def read(name: str) -> str:
    return (CFG / f"{name}.luau").read_text(encoding="utf-8")


def drop_days(field_name: str) -> dict:
    """Config/ContentDrops: id -> день выхода для поля волны (не в списке — 0)."""
    text = read("ContentDrops")
    days = {}
    for block in re.split(r"\n\t\t\{\n", text)[1:]:
        day = re.search(r"\bday = (\d+)", block)
        ids = re.search(rf"\b{field_name} = \{{([^}}]*)\}}", block)
        if day and ids:
            for item in re.findall(r'"(\w+)"', ids.group(1)):
                days[item] = int(day.group(1))
    return days


def field(text: str, name: str) -> float:
    m = re.search(rf"\b{name}\s*=\s*(-?[\d_.]+)", text)
    assert m, name
    return num(m.group(1))


def num_list(text: str, name: str) -> list:
    m = re.search(rf"\b{name}\s*=\s*\{{([^}}]*)\}}", text)
    assert m, name
    return [num(x) for x in re.findall(r"-?[\d_.]+", m.group(1))]


# ---------- конфиги ----------
def load():
    up_text = read("Upgrades")
    upgrades = []
    head = up_text.split("local function interior")[0]
    for block in re.findall(r"\{\s*\n\s*id = \"[\s\S]*?\n\t\}", head):
        u = {"id": re.search(r'id = "(\w+)"', block).group(1)}
        u["cost"] = num(re.search(r"cost = ([\d_]+)", block).group(1))
        for k in ("pointsPerSecond", "speed", "reviewBonus"):
            m = re.search(rf"{k} = ([\d.]+)", block)
            u[k] = float(m.group(1)) if m else 0.0
        m = re.search(r'requires = "(\w+)"', block)
        u["requires"] = m.group(1) if m else None
        u["desk"] = "desk = true" in block
        u["shell"] = "shellStage = 1" in block
        u["stage"] = 1
        u["move"] = "move = true" in block
        upgrades.append(u)
    desks = {}
    for name in ("OFFICE_DESK", "FLOOR_DESK", "SKY_DESK"):
        desks[name] = field(re.search(rf"local {name} = \{{[^}}]*\}}", up_text).group(0), "pointsPerSecond")
    body = up_text.split("local stageInterior")[1]
    row_re = re.compile(
        r'\{\s*(\d),\s*(nil|"\w+"),\s*"(\w+)",\s*"[^"]*",\s*([\d_]+),\s*"\w+",\s*'
        r"-?[\d.]+,\s*-?[\d.]+,\s*-?[\d.]+,\s*(\w+|\{[^}]*\}),?\s*\}"
    )
    for st, req, uid, cost, extra in row_re.findall(body):
        u = {"id": uid, "cost": num(cost), "stage": int(st), "shell": False, "move": False}
        u["requires"] = None if req == "nil" else req.strip('"')
        if extra in desks:
            u.update(pointsPerSecond=desks[extra], speed=0.0, reviewBonus=0.0, desk=True)
        else:
            def g(k, extra=extra):
                m = re.search(rf"{k} = ([\d.]+)", extra)
                return float(m.group(1)) if m else 0.0

            u.update(pointsPerSecond=0.0, speed=g("speed"), reviewBonus=g("reviewBonus"), desk=False)
        upgrades.append(u)

    st_text = read("Stages")
    stages = []
    for block in re.findall(r"\{\s*\n\s*level = [\s\S]*?\n\t\}", st_text):
        stages.append(
            {
                "level": int(field(block, "level")),
                "id": re.search(r'id = "(\w+)"', block).group(1),
                "cost": field(block, "cost"),
                "games": field(block, "gamesRequired"),
            }
        )

    eco = read("Economy")
    economy = {
        k: field(eco, k)
        for k in (
            "balanceWeight",
            "qualityWeight",
            "qualityLogDivisor",
            "topicFitStrength",
            "reviewNoise",
            "revenueBase",
            "revenuePerPower",
            "maxPowerBonus",
            "maxUpgradeSpeed",
            "studioLevelBonus",
        )
    }
    # Темп разработки (Economy.devSeconds / devFloorSeconds); в старых конфигах их нет — 30 с линейно
    for k, default in (("devSeconds", 30.0), ("devFloorSeconds", 0.0), ("devPointsSeconds", 30.0)):
        m = re.search(rf"\b{k}\s*=\s*([\d_.]+)", eco)
        economy[k] = num(m.group(1)) if m else default
    economy["criticExpectation"] = num_list(eco, "criticExpectation")

    exp = read("Expenses")
    expenses = {
        "salaryBase": field(exp, "salaryBase"),
        "legendaryFactor": field(exp, "legendaryFactor"),
        "rent": num_list(exp, "Expenses.rent"),
    }

    emp_text = read("Employees")
    employees = []
    emp_re = re.compile(
        r'employee\(\s*"(\w+)",\s*"[^"]*",\s*"[^"]*",\s*"[^"]*",\s*"[^"]*",\s*(nil|"\w+"),\s*'
        r"([\d.]+),\s*([\d_]+),\s*(\d)\s*\)"
    )
    for eid, spec, mult, cost, stage in emp_re.findall(emp_text):
        employees.append({"id": eid, "mult": float(mult), "cost": num(cost), "stage": int(stage)})

    res_text = read("Research")
    research = []
    for uid, cost, req, eff in re.findall(
        r'id = "(\w+)",[\s\S]*?cost = (\d+),\s*requires = \{([^}]*)\},\s*effect = \{([^}]*)\}', res_text
    ):
        research.append(
            {"id": uid, "cost": int(cost), "requires": re.findall(r'"(\w+)"', req), "effect": eff}
        )
    publishing_share = field(res_text.split("Research.PUBLISHING")[1], "share")

    off = read("Offline")
    offline = {k: field(off, k) for k in ("minSeconds", "rate", "gameMinutes")}
    offline["maxSeconds"] = eval(re.search(r"maxSeconds = ([\d_ *]+)", off).group(1).replace("_", ""))
    m = re.search(r"expenseShare = ([\d.]+)", off)
    offline["expenseShare"] = float(m.group(1)) if m else 1.0

    reb = read("Rebirth")
    rebirth = {
        "baseCost": field(reb, "baseCost"),
        "bonus": field(reb, "incomeBonusPerRebirth"),
        "requiredUpgrade": re.search(r'requiredUpgrade = "(\w+)"', reb).group(1),
    }

    hits = read("HitCartridges")
    hit = {k: field(hits, k) for k in ("baseIncome", "baseSlots", "slotsPerStage", "maxSlots", "minScore")}

    ads = read("AdCampaigns")
    ad_list = []
    for block in re.findall(r"\{\s*\n\s*id = [\s\S]*?\n\t\}", ads):
        m = re.search(r"cashCost = ([\d_]+)", block)
        if m:
            ad_list.append({"bonus": field(block, "bonus"), "cost": num(m.group(1)), "secs": 15 * 60})

    rewards = read("Rewards")
    contracts_text = read("Contracts")
    de = read("DailyEvents")

    def sub(text, name):
        m = re.search(rf"\b{name} = \{{([\s\S]*?)\n\t\}}", text)
        assert m, name
        return m.group(1)

    daily = {
        "golden_minutes": eval(re.search(r"durationSeconds = ([\d_ *]+)", sub(de, "golden")).group(1)) / 60,
        "golden_mult": field(sub(de, "golden"), "revenueMultiplier"),
        "events": re.findall(r'\{ id = "(\w+)", icon = "[^"]*", weight = [\d.]+ \}', de),
        "event_day": drop_days("dailyEvents"),
        "coffee": field(sub(de, "coffeeRush"), "devSpeed"),
        "investor_minutes": field(sub(de, "investors"), "incomeMinutes"),
        "bug_minutes": field(sub(de, "bugHunt"), "incomeMinutes"),
        "bug_top": num_list(sub(de, "bugHunt"), "topBonusMinutes"),
        "blitz_minutes": field(sub(de, "blitzJam"), "winnerIncomeMinutes"),
        "critics": field(sub(de, "critics"), "reviewBonus"),
    }
    m = re.search(r"maxCatchesPerPlayer = (\d+)", de)
    daily["bug_cap"] = int(m.group(1)) if m else None
    rp = read("RebirthPerks")
    perks = {}
    for bid, body in re.findall(r'id = "(\w+)",\s*icon = "[^"]*",\s*costs = COSTS,\s*levels = \{([\s\S]*?)\n\t\t\},', rp):
        perks[bid] = [
            {k: num(v) for k, v in re.findall(r"(\w+) = ([\d_.]+)", lvl)} for lvl in re.findall(r"\{([^{}]*)\}", body)
        ]
    stocks = read("Stocks")
    hit_update = ("updateBoost", "updateBoostMinutes", "updateScore", "updatePriceMinutes", "updateMinPrice")
    stock_keys = ("minIncomePerMinute", "valuationMinutes", "dividendShare", "dividendMinIncome", "tradeFee")
    return {
        "daily": daily,
        "tax": num_list(read("Tax"), "Tax.rates"),
        "premium": field(read("Premium"), "incomeBonus"),
        "premium_offline": field(read("Social"), "offlineBonus"),
        "rebirth_perks": perks,
        "perk_costs": num_list(rp, "local COSTS"),
        "reward_rebirth": field(rewards, "rebirthBonus"),
        "hit_update": {k: field(hits, k) for k in hit_update},
        "stocks": {k: field(stocks, k) for k in stock_keys},
        "ipo_cost": field(stocks, "cost"),
        "products_rpm": field(read("Products"), "releasesPerMinute"),
        "contracts": {
            "advanceMinutes": field(contracts_text, "advanceMinutes"),
            "bonusMinutes": field(contracts_text, "bonusMinutes"),
            "releasesPerMinute": field(read("Products"), "releasesPerMinute"),
        },
        "upgrades": upgrades,
        "stages": stages,
        "eco": economy,
        "exp": expenses,
        "employees": employees,
        "research": research,
        "publishing": publishing_share,
        "offline": offline,
        "rebirth": rebirth,
        "hit": hit,
        "ads": ad_list,
        "secondsPerGame": field(rewards, "secondsPerGame"),
    }


# ---------- модель ----------
class Sim:
    def __init__(self, c):
        self.c = c
        self.cash = 0.0
        self.t = ASSUMPTIONS["park_minutes"] * 60  # активные секунды
        self.wall = self.t  # реальное время (с офлайном)
        self.games = 0
        self.level = 1
        self.owned = set()
        self.staff = []  # сотрудники (dict)
        self.ri = 0  # очки исследований
        self.research = set()
        self.best = 0
        self.earned = 0.0
        self.ad_until = -1.0
        self.ad_bonus = 0.0
        self.recent_rev = []
        self.hits = []  # оценки картриджей на полке
        self.strike_s = 0.0
        self.offline_total = 0.0
        self.active_income = 0.0
        self.log = []
        self.marks = {}
        # --all / --rebirth2 (без них всё нейтрально)
        self.rebirths = 0
        self.perk = {"devTime": 0.0, "expenses": 0.0, "startCash": 0.0, "offline": 0.0, "hitSlots": 0.0, "researchDiscount": 0.0}
        self.golden_until = -1.0
        self.coffee_until = -1.0
        self.critics_until = -1.0
        self.tax_paid = 0.0
        self.golden_extra = 0.0
        self.event_cash = {}
        self.hit_update_ratio = 0.0  # лучшая окупаемость DLC хита за его 30 мин (цена → буст)
        self.hit_updates = 0

    # --- справочники ---
    def visible(self, u):
        if u["shell"] and self.level > 1:
            return False
        return u["stage"] <= self.level

    def research_mod(self, key):
        total = 0.0
        for n in self.c["research"]:
            if n["id"] in self.research:
                m = re.search(rf"{key} = (-?[\d.]+)", n["effect"])
                if m:
                    total += float(m.group(1))
        return total

    def slots(self):
        return 2 if "second_project" in self.research else 1

    def desks(self):
        """Купленные видимые столы: (pps стола, этап стола)."""
        return [u for u in self.c["upgrades"] if u["id"] in self.owned and u.get("desk") and self.visible(u)]

    def pps(self):
        desks = sorted(self.desks(), key=lambda u: -u["pointsPerSecond"])
        team = sorted(self.staff, key=lambda e: -e["mult"])
        strike = self.strike
        total = 0.0
        for u in self.c["upgrades"]:
            if u["id"] in self.owned and u["pointsPerSecond"] and not u.get("desk"):
                total += u["pointsPerSecond"]
        for i, d in enumerate(desks):
            m = team[i]["mult"] * ASSUMPTIONS["employee_focus"] if i < len(team) and not strike else 1.0
            total += d["pointsPerSecond"] * m
        # стол desk2 гаража после переезда спрятан, но очки даёт (профиль его помнит)
        for u in self.c["upgrades"]:
            if u["id"] in self.owned and u.get("desk") and not self.visible(u):
                total += u["pointsPerSecond"]
        gs = 1 + 0.5 * (self.research_mod("graphicsPoints") + self.research_mod("soundPoints")) / 2
        return total * gs

    def power(self):
        return sum(u["pointsPerSecond"] for u in self.c["upgrades"] if u["id"] in self.owned)

    def duration(self):
        speed = sum(u["speed"] for u in self.c["upgrades"] if u["id"] in self.owned)
        items = min(speed, self.c["eco"]["maxUpgradeSpeed"])
        dev = max(1 + self.research_mod("devTime"), 0.1)
        perks = 1.0
        if not self.strike:
            perks = max(1 - 0.1 * min(len(self.staff), ASSUMPTIONS["cruncher_perks"]), 0.5)
        factor = max(dev * perks * (1 - self.perk["devTime"]), 0.25) * (1 - items)
        e = self.c["eco"]
        # Как DevelopmentService.devDuration: бонусы сокращают только часть сверх devFloorSeconds
        dur = e["devFloorSeconds"] + (e["devSeconds"] - e["devFloorSeconds"]) * factor
        if self.t < self.coffee_until:  # «Кофе-раш»: прогресс ×1.25 (DailyEventService.devSpeed)
            dur /= self.c["daily"]["coffee"]
        return dur

    def review_bonus(self):
        return sum(u["reviewBonus"] for u in self.c["upgrades"] if u["id"] in self.owned)

    def raw_score(self, critics=True):
        e = self.c["eco"]
        p = self.pps() * self.c["eco"]["devPointsSeconds"]
        quality = min(math.log10(1 + p) / e["qualityLogDivisor"], 1)
        raw = 10 * (e["balanceWeight"] * ASSUMPTIONS["balance"] + e["qualityWeight"] * quality)
        raw += (ASSUMPTIONS["topic_fit"] - 1) * e["topicFitStrength"]
        raw += self.review_bonus() + ASSUMPTIONS["qte"] - ASSUMPTIONS["repeat"]
        ce = e["criticExpectation"]
        raw -= ce[min(self.level, len(ce)) - 1]
        if critics and self.t < self.critics_until:  # «Критики в городе»: +1 жанру дня (ожидание по critics_fit)
            raw += self.c["daily"]["critics"] * ASSUMPTIONS["critics_fit"]
        return raw

    def score_dist(self, critics=True):
        """Распределение целой оценки по шуму критиков."""
        raw = self.raw_score(critics)
        noise = self.c["eco"]["reviewNoise"]
        dist = {}
        n = 60
        for i in range(n):
            x = raw - noise + (i + 0.5) * 2 * noise / n
            s = min(max(math.floor(x + 0.5), 1), 10)
            dist[s] = dist.get(s, 0) + 1 / n
        return dist

    def level_mult(self, level=None):
        lv = self.level if level is None else level
        return 1 + self.c["eco"]["studioLevelBonus"] * (lv - 1)

    def rev_multiplier(self):
        e = self.c["eco"]
        power = 1 + min(self.power() * e["revenuePerPower"], e["maxPowerBonus"])
        research = 1 + self.research_mod("revenue")
        reward = 1.05 if self.earned >= 100_000 else 1.0
        ad = 1 + (self.ad_bonus if self.t < self.ad_until else 0)
        extras = 1.0
        if ASSUMPTIONS["extras"] and self.level >= 2:
            extras = ASSUMPTIONS["franchise_avg"] * ASSUMPTIONS["platform_avg"] * ASSUMPTIONS["streamer_avg"]
        allm = 1.0
        if ASSUMPTIONS["all"]:
            if self.t < self.golden_until:
                allm *= self.c["daily"]["golden_mult"]
            if ASSUMPTIONS["premium"]:
                allm *= 1 + self.c["premium"]
        base = self.c["eco"]["revenueBase"] * self.level_mult() * self.rebirth_mult()
        return base * power * research * reward * ad * extras * allm

    def rebirth_mult(self):
        return 1 + self.c["rebirth"]["bonus"] * self.rebirths

    def reward_minute(self):
        """«Минута дохода» наград (RewardFormulas.perMinute)."""
        rb = 1 + self.c["reward_rebirth"] * self.rebirths
        return self.c["eco"]["revenueBase"] * max(self.best, 5) ** 2 * self.level_mult() * rb * 60 / self.c["secondsPerGame"]

    def shop_income_per_min(self):
        """ShopService.incomePerMinute — цена DLC хита, контракты, биржа."""
        per = self.c["eco"]["revenueBase"] * max(self.best, 5) ** 2 * self.level_mult() * self.rebirth_mult()
        return max(per * self.c["products_rpm"], 500)

    def contract_income_per_min(self):
        # Контракт: аванс + бонус в «минутах дохода» ShopService.incomePerMinute (база × 1.6 релиза/мин)
        if not (ASSUMPTIONS["extras"] and self.level >= 2):
            return 0.0
        c = self.c["contracts"]
        base = self.c["eco"]["revenueBase"] * max(self.best, 5) ** 2 * self.level_mult() * c["releasesPerMinute"]
        base *= self.rebirth_mult()
        minutes = c["advanceMinutes"] + c["bonusMinutes"]
        return base * minutes * ASSUMPTIONS["contract_success"] / ASSUMPTIONS["contract_every_min"]

    @property
    def strike(self):
        return False  # игрок держит запас на зарплаты (см. reserve)

    def expenses_per_min(self, level=None):
        lv = self.level if level is None else level
        x = self.c["exp"]
        sal = sum(x["salaryBase"] * e["mult"] ** 2 * (x["legendaryFactor"] if e.get("legendary") else 1) for e in self.staff)
        rent = x["rent"][min(lv, len(x["rent"])) - 1]
        return (sal + rent) * (1 - self.perk["expenses"])

    def hit_income_per_min(self):
        h = self.c["hit"]
        mult = {7: 1, 8: 1.4, 9: 2, 10: 3}
        return sum(h["baseIncome"] * mult[min(int(s), 10)] for s in self.hits)

    def hit_slots(self):
        h = self.c["hit"]
        return min(h["baseSlots"] + h["slotsPerStage"] * (self.level - 1) + self.perk["hitSlots"], h["maxSlots"])

    def hit_update_check(self):
        """DLC хита раз в день на картридж: окупает ли буст ×2 на 30 мин цену (8 минут дохода)."""
        hu = self.c["hit_update"]
        mult = {7: 1, 8: 1.4, 9: 2, 10: 3}
        price = max(hu["updatePriceMinutes"] * self.shop_income_per_min(), hu["updateMinPrice"])
        for i, s in enumerate(self.hits):
            gain = self.c["hit"]["baseIncome"] * mult[min(int(s), 10)] * (hu["updateBoost"] - 1) * hu["updateBoostMinutes"]
            self.hit_update_ratio = max(self.hit_update_ratio, gain / price)
            if ASSUMPTIONS["hit_updates"] and gain >= price and self.cash - price >= self.reserve():
                self.cash += gain - price
                self.hits[i] = min(s + hu["updateScore"], 10)
                self.hit_updates += 1

    # --- покупки ---
    def reserve(self):
        return self.expenses_per_min() * 2

    def next_research(self):
        order = [
            "easy_engine", "marketing", "test_group", "second_project", "graphics_3d",
            "surround_sound", "online_mode", "story_games", "logic", "car_physics",
            "enemy_ai", "publishing", "ai_assistant", "sports_animation",
        ]
        by_id = {n["id"]: n for n in self.c["research"]}
        for rid in order + [n["id"] for n in self.c["research"]]:
            n = by_id.get(rid)
            if n and rid not in self.research and all(r in self.research for r in n["requires"]):
                return n
        return None

    def buy_all(self):
        bought = True
        while bought:
            bought = False
            n = self.next_research()
            if n and self.ri >= n["cost"]:
                self.ri -= n["cost"]
                self.research.add(n["id"])
                bought = True
                continue
            # сотрудник за пустой стол / замена слабейшего
            free = len(self.desks()) - len(self.staff)
            hired_ids = {e["id"] for e in self.staff}
            cands = [
                e for e in self.c["employees"]
                if e["id"] not in hired_ids and e["stage"] <= self.level
                and (e["id"] != "robo" or "ai_assistant" in self.research)
            ]
            cands.sort(key=lambda e: (-e["mult"], e["cost"]))
            if cands:
                best = cands[0]
                weakest = min(self.staff, key=lambda e: e["mult"]) if self.staff else None
                if free > 0 and self.cash - best["cost"] >= self.reserve():
                    self.cash -= best["cost"]
                    self.staff.append(best)
                    bought = True
                    continue
                if (
                    free <= 0 and weakest and best["mult"] > weakest["mult"]
                    and self.cash - best["cost"] >= self.reserve() + 0
                ):
                    self.staff.remove(weakest)
                    self.cash += weakest["cost"] * 0.25
                    self.cash -= best["cost"]
                    self.staff.append(best)
                    bought = True
                    continue
            # реклама
            if self.t >= self.ad_until and self.c["ads"]:
                gpm = self.games_per_min()
                base = self.rev_multiplier() * self.exp_s2() * gpm * 15
                options = [a for a in self.c["ads"] if base * a["bonus"] >= 2 * a["cost"]]
                if options:
                    a = max(options, key=lambda a: base * a["bonus"] - a["cost"])
                    if self.cash - a["cost"] >= self.reserve():
                        self.cash -= a["cost"]
                        self.ad_bonus = a["bonus"]
                        self.ad_until = self.t + a["secs"]
                        bought = True
                        continue
            # апгрейды по цепочке, самый дешёвый доступный
            avail = []
            for u in self.c["upgrades"]:
                if u["id"] in self.owned or not self.visible(u):
                    continue
                if u["requires"] and u["requires"] not in self.owned:
                    continue
                if u["move"] and not self.ready_to_move():
                    continue
                avail.append(u)
            avail.sort(key=lambda u: u["cost"])
            if avail and self.cash - avail[0]["cost"] >= self.reserve():
                u = avail[0]
                self.cash -= u["cost"]
                self.owned.add(u["id"])
                for lv, name in ((2, "office_interior"), (3, "floor_interior"), (4, "top_interior")):
                    if name not in self.marks and self.level == lv and self.interior_complete():
                        self.mark(name)
                if u["move"]:
                    self.level = 2
                    self.mark("office")
                bought = True
                continue
            # переезд на этаж
            nxt = self.c["stages"][self.level] if self.level < len(self.c["stages"]) else None
            if nxt and nxt["cost"] > 0 and self.ready_to_move() and self.games >= nxt["games"]:
                if self.cash - nxt["cost"] >= self.reserve():
                    self.cash -= nxt["cost"]
                    self.level += 1
                    self.mark(nxt["id"])
                    bought = True
                    continue

    def interior_complete(self):
        for u in self.c["upgrades"]:
            if not u["move"] and self.visible(u) and u["id"] not in self.owned:
                return False
        return True

    def ready_to_move(self):
        if not self.interior_complete():
            return False
        stage_desks = [u for u in self.desks() if u["stage"] == self.level]
        if self.level == 1:
            stage_desks = [u for u in self.desks()]
        if not stage_desks:
            return False
        # рассадка: лучшие на верхний этаж — достаточно, чтобы людей хватало на все столы
        return len(self.staff) >= len(self.desks())

    def mark(self, name):
        self.marks[name] = (self.t, self.wall, self.games, self.cash, self.duration(), self.games_per_min() * 60)

    # --- доход ---
    def exp_s2(self):
        return sum(p * s * s for s, p in self.score_dist().items())

    def games_per_min(self):
        dur = self.duration()
        o = ASSUMPTIONS["overhead_s"]
        if self.slots() >= 2:
            per = max((dur + o) / 2, ASSUMPTIONS["parallel_handle_s"])
        else:
            per = dur + o
        return 60 / per

    def play(self, seconds):
        end = self.t + seconds
        while self.t < end:
            self.buy_all()
            gpm = self.games_per_min()
            dt = 60 / gpm
            dist = self.score_dist()
            critics_on = self.t < self.critics_until
            rev = self.rev_multiplier() * sum(p * s * s for s, p in dist.items())
            exp_score = sum(p * s for s, p in dist.items())
            minutes = dt / 60
            self.t += dt
            self.wall += dt
            self.games += 1
            self.ri += exp_score
            # «Лучшая оценка» модели — порог по шуму, а не рекорд из тысяч игр; «Критики» её не двигают,
            # иначе одно окно навсегда поднимало бы офлайн и награды (в игре рекорд и так ~9–10)
            base_dist = self.score_dist(critics=False) if critics_on else dist
            self.best = max(self.best, max(s for s, p in base_dist.items() if p > 0.05))
            hit_score = max(s for s, p in base_dist.items() if p > 0.15)
            slots = self.hit_slots()
            if hit_score >= self.c["hit"]["minScore"]:
                self.hits.append(hit_score)
                self.hits = sorted(self.hits, reverse=True)[: int(slots)]
            self.recent_rev = (self.recent_rev + [rev])[-10:]
            publishing = self.c["publishing"] * sum(self.recent_rev) * minutes if "publishing" in self.research else 0
            income = rev + publishing + (self.hit_income_per_min() + self.contract_income_per_min()) * minutes
            cost = self.expenses_per_min() * minutes
            if ASSUMPTIONS["all"]:
                if self.t - dt < self.golden_until:
                    self.golden_extra += rev * (1 - 1 / self.c["daily"]["golden_mult"])
                if ASSUMPTIONS["taxes"]:  # налог с дохода релизов по ставке этапа (Config/Tax)
                    tax = rev * self.c["tax"][min(self.level, len(self.c["tax"])) - 1]
                    cost += tax
                    self.tax_paid += tax
            self.cash += income - cost
            self.earned += income
            self.active_income += income

    def offline(self, hours):
        o = self.c["offline"]
        secs = hours * 3600
        self.wall += secs
        capped = min(secs, o["maxSeconds"])
        if capped < o["minSeconds"]:
            return
        score = max(self.best, 1)
        per_game = self.c["eco"]["revenueBase"] * score**2 * self.level_mult() * self.rebirth_mult()
        per_game *= 1 + self.perk["offline"]
        if ASSUMPTIONS["all"] and ASSUMPTIONS["premium"]:
            per_game *= 1 + self.c["premium_offline"]
        gross = capped / 60 * per_game / o["gameMinutes"] * o["rate"]
        spent = capped / 60 * self.expenses_per_min() * o["rate"] * o["expenseShare"]
        got = max(gross - spent, 0)
        self.cash += got
        self.offline_total += got

    def daily_bonus(self):
        self.cash += self.reward_minute() * ASSUMPTIONS["daily_income_minutes"]

    def add_event_cash(self, key, amount):
        self.cash += amount
        self.event_cash[key] = self.event_cash.get(key, 0.0) + amount

    def daily_event(self, eid):
        """Событие дня (Config/DailyEvents): окно event_overlap_min минут с текущего момента."""
        d = self.c["daily"]
        a = ASSUMPTIONS
        window = a["event_overlap_min"] * 60
        rm = self.reward_minute()
        if eid == "coffeeRush":
            self.coffee_until = self.t + window
        elif eid == "critics":
            self.critics_until = self.t + window
        elif eid == "investors":
            self.add_event_cash(eid, rm * d["investor_minutes"] * a["investor_chance"])
        elif eid == "bugHunt":
            catches = a["bug_catch_per_min"] * min(a["bug_hunt_min"], a["event_overlap_min"])
            if d["bug_cap"] is not None:
                catches = min(catches, d["bug_cap"])
            hunt_min = catches / a["bug_catch_per_min"]
            top = a["bug_top_chance"] * sum(d["bug_top"]) / len(d["bug_top"])
            loss = hunt_min * a["bug_hunt_income_loss"] * self.active_rate()
            self.add_event_cash(eid, rm * (catches * d["bug_minutes"] + top) - loss)
        elif eid == "blitzJam":
            self.add_event_cash(eid, rm * d["blitz_minutes"] * a["blitz_win_chance"])

    def active_rate(self):
        """Доход активной игры в минуту сейчас (без хитов)."""
        return self.rev_multiplier() * self.exp_s2() * self.games_per_min()


def run(prev=None, perk_levels=None):
    """Забег до Rebirth. prev — итог прошлого забега (второй забег, --rebirth2), perk_levels —
    купленные уровни веток RebirthPerks ({ветка: уровень})."""
    c = load()
    sim = Sim(c)
    sim.owned.add("desk1")
    max_days = ASSUMPTIONS["max_days"]
    if prev is not None:
        # RebirthService: исследования и gamesReleased остаются, этап/апгрейды/команда — сначала,
        # деньги — cashAfter или перк «Стартовый капитал»; полка хитов остаётся
        sim.rebirths = prev.rebirths + 1
        sim.research = {n["id"] for n in c["research"]}
        sim.games = prev.games
        sim.hits = list(prev.hits)
        sim.t = sim.wall = 0.0
        for branch, level in (perk_levels or {}).items():
            if level > 0:
                for k, v in c["rebirth_perks"][branch][level - 1].items():
                    sim.perk[k] += v
        sim.cash = max(100.0, sim.perk["startCash"])
        max_days = ASSUMPTIONS["max_days_run2"]
    goal = c["rebirth"]["baseCost"] * (sim.rebirths + 1)
    rows = []
    day = 0
    events = c["daily"]["events"]
    event_no = 0
    golden_days = 0.0
    # До Rebirth: интерьер 3-го этажа куплен и накоплено Rebirth.cost(rebirths)
    while day < max_days and "rebirth" not in sim.marks:
        day += 1
        if day > 1:  # день 1: награды в парке ограничены (parkCap); после Rebirth — уже забраны
            sim.daily_bonus()
        golden_days += ASSUMPTIONS["golden_days_share"]
        golden_today = golden_days >= 1
        if golden_today:
            golden_days -= 1
        for i, (sess, gap) in enumerate(zip(ASSUMPTIONS["session_min"], ASSUMPTIONS["offline_gaps_h"])):
            session_end = sim.t + sess * 60
            event_at = sim.t + ASSUMPTIONS["event_start_min"] * 60
            if ASSUMPTIONS["all"]:
                if golden_today and i == len(ASSUMPTIONS["session_min"]) - 1:
                    sim.golden_until = sim.t + c["daily"]["golden_minutes"] * 60
                if ASSUMPTIONS["hit_updates"] and i == 0:
                    sim.hit_update_check()
            while sim.t < session_end:
                if ASSUMPTIONS["all"] and event_at is not None and sim.t >= event_at:
                    pool = events
                    if ASSUMPTIONS["drops"]:  # день 1 модели = день запуска (0)
                        pool = [e for e in events if c["daily"]["event_day"].get(e, 0) <= day - 1] or events
                    sim.daily_event(pool[event_no % len(pool)])
                    event_no += 1
                    event_at = None
                sim.play(min(60.0, session_end - sim.t))
                if "rebirth" not in sim.marks and "top_interior" in sim.marks and sim.cash >= goal:
                    sim.mark("rebirth")
                if len(rows) < 2000 and int(sim.t) % 1800 < 60:
                    rows.append(
                        (day, sim.t / 3600, sim.level, sim.games, sim.cash, sim.active_rate(),
                         sim.expenses_per_min(), sim.exp_s2() ** 0.5)
                    )
            sim.offline(gap)
    return sim, rows


def fmt_t(sec):
    m = int(round(sec / 60))
    return f"{m // 60}ч{m % 60:02d}м" if m >= 60 else f"{sec / 60:.1f} мин"


def report(sim, rows, quiet=False, rebirth_label="Хватает на 1-й Rebirth"):
    names = [
        ("office", "Офис (1-й этаж)"),
        ("office_interior", "Интерьер 1-го этажа"),
        ("floor", "2-й этаж открыт"),
        ("floor_interior", "Интерьер 2-го этажа"),
        ("skyscraper", "3-й этаж открыт"),
        ("top_interior", "Интерьер 3-го этажа"),
        ("rebirth", rebirth_label),
    ]
    print("Веха                  | игра (актив) | день | игр  | разраб. | игр/ч | деньги после")
    print("----------------------|--------------|------|------|---------|-------|-------------")
    for key, label in names:
        if key in sim.marks:
            t, wall, games, cash, dur, gph = sim.marks[key]
            day = int(wall // (24 * 3600)) + 1
            print(f"{label:<22}| {fmt_t(t):>12} | {day:>4} | {games:>4} | {dur:5.1f} с | {gph:5.0f} | ${cash:,.0f}")
        else:
            print(f"{label:<22}| {'не дошёл':>12} |      |      |")
    print(f"Офлайн-доход всего: ${sim.offline_total:,.0f}; актив: ${sim.active_income:,.0f}")
    if not quiet:
        print("\nдень | игра  | этап | игр  | деньги       | $/мин актив | расходы/мин | ~оценка")
        for r in rows[::2]:
            print(f"{r[0]:>4} | {r[1]:5.1f} | {r[2]:>4} | {r[3]:>4} | ${r[4]:>11,.0f} | {r[5]:>11,.0f} | {r[6]:>11,.0f} | {r[7]:.1f}")


VARIANTS = {
    "медленный игрок (цикл +12 с, темы хуже, без QTE)": dict(
        overhead_s=36.0, parallel_handle_s=28.0, topic_fit=1.1, qte=0.0
    ),
    "30 мин в день, одна сессия": dict(session_min=[30], offline_gaps_h=[23.5], max_days=80),
}


def report_all(sim):
    """Разбивка новых источников (--all)."""
    total = sim.active_income + sim.offline_total
    print(f"Золотой час: +${sim.golden_extra:,.0f} ({sim.golden_extra / total:.1%} всех денег)")
    ev = sum(sim.event_cash.values())
    parts = ", ".join(f"{k} ${v:,.0f}" for k, v in sorted(sim.event_cash.items(), key=lambda kv: -kv[1]))
    print(f"События дня (гранты/жуки/джем): +${ev:,.0f} ({ev / total:.1%}): {parts}")
    print(f"Налоги: −${sim.tax_paid:,.0f} ({sim.tax_paid / total:.1%})")
    print(f"DLC хита: лучшая окупаемость за 30 мин {sim.hit_update_ratio:.2f} (≥1 — покупает), куплено {sim.hit_updates}")


def rebirth2(first):
    """Второй забег: 1 звезда после 1-го Rebirth, ветки перебором (жадный выбор — самый быстрый)."""
    c = load()
    options = [None] + list(c["rebirth_perks"])
    stars = int(first.rebirths + 1)
    results = []
    for branch in options:
        levels = {}
        if branch:
            cost, lv = 0, 0
            while lv < len(c["perk_costs"]) and cost + c["perk_costs"][lv] <= stars:
                cost += c["perk_costs"][lv]
                lv += 1
            levels[branch] = lv
        s2, _ = run(prev=first, perk_levels=levels)
        results.append((s2.marks.get("rebirth", (math.inf,))[0], branch or "без звезды", s2))
    results.sort(key=lambda r: r[0])
    print("\n== 2-й Rebirth (после 1-го, $%s, ×%.1f дохода), звёзд: %d" % (
        f"{c['rebirth']['baseCost'] * 2:,.0f}", 1 + c["rebirth"]["bonus"], stars))
    for t, label, _ in results:
        print(f"  {label:<12} {fmt_t(t) if t < math.inf else 'не дошёл'}")
    best = results[0]
    print(f"Лучшая ветка: {best[1]}")
    report(best[2], [], quiet=True, rebirth_label="Хватает на 2-й Rebirth")
    return best[2]


def sanity(c):
    """Проверки на бесконечные деньги (--all): числа прямо из конфигов."""
    hu, st, d = c["hit_update"], c["stocks"], c["daily"]
    e = c["eco"]
    lv4 = 1 + e["studioLevelBonus"] * 3
    # DLC хита: максимум выгоды — золотой картридж (×3) при самой низкой цене (оценка 5, гараж)
    gain = c["hit"]["baseIncome"] * 3 * (hu["updateBoost"] - 1) * hu["updateBoostMinutes"]
    price = max(hu["updatePriceMinutes"] * max(e["revenueBase"] * 25 * c["products_rpm"], 500), hu["updateMinPrice"])
    print(f"DLC хита: худший случай (золотой хит, гараж, оценка 5) буст ${gain:,.0f} за ${price:,.0f} → {gain / price:.2f}")
    # Дивиденды: 10% компании стоят 0.1 × valuationMinutes минут её дохода, платят 0.1 × dividendShare в минуту
    payback_h = st["valuationMinutes"] / st["dividendShare"] / 60
    print(f"Дивиденды: окупаемость пакета акций ≥ {payback_h:,.0f} ч (оценка компании ×1); свои акции купить нельзя")
    top = e["revenueBase"] * 100 * lv4 * c["products_rpm"]
    print(f"IPO: порог ${st['minIncomePerMinute']:,.0f}/мин, на 3-м этаже без Rebirth максимум ${top:,.0f}/мин (оценка 10)")
    cap = d["bug_cap"]
    print(f"Охота на баги: лимит на игрока {cap if cap is not None else 'НЕТ'} жуков = {cap * d['bug_minutes'] if cap else '∞'} мин дохода + топ до {max(d['bug_top']):.0f} мин")


if __name__ == "__main__":
    ASSUMPTIONS["all"] = "--all" in sys.argv
    ASSUMPTIONS["premium"] = "--premium" in sys.argv
    ASSUMPTIONS["drops"] = "--drops" in sys.argv
    ASSUMPTIONS["extras"] = "--extras" in sys.argv or ASSUMPTIONS["all"]
    s, r = run()
    report(s, r, quiet="--quiet" in sys.argv)
    if ASSUMPTIONS["all"]:
        report_all(s)
        sanity(load())
    if "--rebirth2" in sys.argv:
        s2 = rebirth2(s)
        if ASSUMPTIONS["all"]:
            report_all(s2)
    if "--variants" in sys.argv:
        for label, change in VARIANTS.items():
            saved = {k: ASSUMPTIONS[k] for k in change}
            ASSUMPTIONS.update(change)
            print(f"\n== {label}")
            s, r = run()
            report(s, r, quiet=True)
            ASSUMPTIONS.update(saved)
