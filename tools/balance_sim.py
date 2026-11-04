#!/usr/bin/env python3
"""Модель баланса Game Studio Tycoon: активный игрок без Robux + офлайн-доход между сессиями.

Читает числа прямо из src/shared/Config (Upgrades, Stages, Economy, Expenses, Employees,
Research, Offline, Rebirth, HitCartridges, AdCampaigns), поэтому после правки конфигов
достаточно перезапустить:  python3 tools/balance_sim.py
Флаги: --quiet — только таблица вех, --variants — ещё медленный игрок и 30 мин в день.

Это приближение, а не повтор кода сервера. Допущения (см. ASSUMPTIONS ниже):
- парк до гаража ~5 мин; дальше игрок сразу покупает всё, на что хватает денег,
  нанимает лучших доступных сотрудников, ставит им перк «Кранчер», учит исследования;
- оценка — матожидание по шуму критиков (±reviewNoise), баланс жанра ~0.85, хорошая тема,
  QTE в среднем +0.2, сочетания чередует (штраф за повтор почти не ловит);
- цикл игры = разработка + ~24 с на выбор/название/QTE/окно релиза (≈30–40 с в гараже);
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
    "overhead_s": 24.0,  # выбор жанра/темы, название, QTE, окно релиза
    "parallel_handle_s": 20.0,  # минимум секунд на игру, когда идут 2 проекта
    "balance": 0.85,  # попадание в рецепт жанра
    "topic_fit": 1.17,  # средняя «подходящая» тема (1.2 почти всегда, иногда 1.1)
    "qte": 0.2,  # средний эффект QTE (DevelopmentService, другой агент)
    "repeat": 0.1,  # средний штраф за повтор
    "employee_focus": 1.12,  # спец-бонус + стартовый навык по доле фокуса
    "cruncher_perks": 5,  # сколько сотрудников с перком «Кранчер» (−0.1 к времени каждый)
    "session_min": [45, 45],  # сессии за день
    "offline_gaps_h": [5.0, 17.5],  # перерыв после каждой сессии
    "daily_income_minutes": 24.0,  # ежедневное задание 15 + награды за вход ~9 (среднее)
    "max_days": 40,
}


def num(s: str) -> float:
    return float(s.replace("_", ""))


def read(name: str) -> str:
    return (CFG / f"{name}.luau").read_text(encoding="utf-8")


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
    return {
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
        return 30 * max(dev * perks, 0.25) * (1 - items)

    def review_bonus(self):
        return sum(u["reviewBonus"] for u in self.c["upgrades"] if u["id"] in self.owned)

    def raw_score(self):
        e = self.c["eco"]
        p = self.pps() * 30
        quality = min(math.log10(1 + p) / e["qualityLogDivisor"], 1)
        raw = 10 * (e["balanceWeight"] * ASSUMPTIONS["balance"] + e["qualityWeight"] * quality)
        raw += (ASSUMPTIONS["topic_fit"] - 1) * e["topicFitStrength"]
        raw += self.review_bonus() + ASSUMPTIONS["qte"] - ASSUMPTIONS["repeat"]
        ce = e["criticExpectation"]
        raw -= ce[min(self.level, len(ce)) - 1]
        return raw

    def score_dist(self):
        """Распределение целой оценки по шуму критиков."""
        raw = self.raw_score()
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
        return self.c["eco"]["revenueBase"] * self.level_mult() * power * research * reward * ad

    @property
    def strike(self):
        return False  # игрок держит запас на зарплаты (см. reserve)

    def expenses_per_min(self, level=None):
        lv = self.level if level is None else level
        x = self.c["exp"]
        sal = sum(x["salaryBase"] * e["mult"] ** 2 * (x["legendaryFactor"] if e.get("legendary") else 1) for e in self.staff)
        rent = x["rent"][min(lv, len(x["rent"])) - 1]
        return sal + rent

    def hit_income_per_min(self):
        h = self.c["hit"]
        mult = {7: 1, 8: 1.4, 9: 2, 10: 3}
        return sum(h["baseIncome"] * mult[min(s, 10)] for s in self.hits)

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
        self.marks[name] = (self.t, self.wall, self.games, self.cash)

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
            rev = self.rev_multiplier() * sum(p * s * s for s, p in dist.items())
            exp_score = sum(p * s for s, p in dist.items())
            minutes = dt / 60
            self.t += dt
            self.wall += dt
            self.games += 1
            self.ri += exp_score
            self.best = max(self.best, max(s for s, p in dist.items() if p > 0.05))
            hit_score = max(s for s, p in dist.items() if p > 0.15)
            slots = min(self.c["hit"]["baseSlots"] + self.c["hit"]["slotsPerStage"] * (self.level - 1), self.c["hit"]["maxSlots"])
            if hit_score >= self.c["hit"]["minScore"]:
                self.hits.append(hit_score)
                self.hits = sorted(self.hits, reverse=True)[: int(slots)]
            self.recent_rev = (self.recent_rev + [rev])[-10:]
            publishing = self.c["publishing"] * sum(self.recent_rev) * minutes if "publishing" in self.research else 0
            income = rev + publishing + self.hit_income_per_min() * minutes
            cost = self.expenses_per_min() * minutes
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
        per_game = self.c["eco"]["revenueBase"] * score**2 * self.level_mult()
        gross = capped / 60 * per_game / o["gameMinutes"] * o["rate"]
        spent = capped / 60 * self.expenses_per_min() * o["rate"] * o["expenseShare"]
        got = max(gross - spent, 0)
        self.cash += got
        self.offline_total += got

    def daily_bonus(self):
        per_min = self.c["eco"]["revenueBase"] * max(self.best, 5) ** 2 * self.level_mult() * 60 / self.c["secondsPerGame"]
        self.cash += per_min * ASSUMPTIONS["daily_income_minutes"]

    def active_rate(self):
        """Доход активной игры в минуту сейчас (без хитов)."""
        return self.rev_multiplier() * self.exp_s2() * self.games_per_min()


def run():
    c = load()
    sim = Sim(c)
    sim.owned.add("desk1")
    goal = c["rebirth"]["baseCost"]
    rows = []
    day = 0
    # До первого Rebirth: интерьер 3-го этажа куплен и накоплено Rebirth.cost(0)
    while day < ASSUMPTIONS["max_days"] and "rebirth" not in sim.marks:
        day += 1
        if day > 1:  # день 1: награды в парке ограничены StartPark (parkCap)
            sim.daily_bonus()
        for sess, gap in zip(ASSUMPTIONS["session_min"], ASSUMPTIONS["offline_gaps_h"]):
            session_end = sim.t + sess * 60
            while sim.t < session_end:
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


def report(sim, rows, quiet=False):
    names = [
        ("office", "Офис (1-й этаж)"),
        ("office_interior", "Интерьер 1-го этажа"),
        ("floor", "2-й этаж открыт"),
        ("floor_interior", "Интерьер 2-го этажа"),
        ("skyscraper", "3-й этаж открыт"),
        ("top_interior", "Интерьер 3-го этажа"),
        ("rebirth", "Хватает на 1-й Rebirth"),
    ]
    print("Веха                  | игра (актив) | день | игр  | деньги после")
    print("----------------------|--------------|------|------|-------------")
    for key, label in names:
        if key in sim.marks:
            t, wall, games, cash = sim.marks[key]
            day = int(wall // (24 * 3600)) + 1
            print(f"{label:<22}| {fmt_t(t):>12} | {day:>4} | {games:>4} | ${cash:,.0f}")
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


if __name__ == "__main__":
    s, r = run()
    report(s, r, quiet="--quiet" in sys.argv)
    if "--variants" in sys.argv:
        for label, change in VARIANTS.items():
            saved = {k: ASSUMPTIONS[k] for k in change}
            ASSUMPTIONS.update(change)
            print(f"\n== {label}")
            s, r = run()
            report(s, r, quiet=True)
            ASSUMPTIONS.update(saved)
