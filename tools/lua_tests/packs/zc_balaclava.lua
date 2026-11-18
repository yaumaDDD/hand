-- ============================================================
-- ZC Arctic Balaclava Appearance Fix v3 (с диагностикой)
-- garrysmod/addons/zc_balaclava/lua/autorun/zc_balaclava.lua
--
-- Проблема была не в disallowinappearance (этого флага у масок
-- вообще не было), а в отсутствующем поле placement — именно
-- по нему фильтруется меню выбора лица. Эта версия:
--   1) патчит через hook "HomigradRun" (стреляет сразу после
--      того, как hg.Accessories реально собран — надёжнее,
--      чем InitPostEntity + произвольные таймеры)
--   2) дублирует патч на InitPostEntity на всякий случай
--   3) печатает в консоль, что именно произошло, чтобы можно
--      было понять, где рвётся цепочка, если снова не заработает
-- ============================================================

if not CLIENT then return end

local PATCHED = false

local function PatchBalaclava(source)
    if PATCHED then return end

    if not hg or not hg.Accessories then
        print("[ZCB] hg.Accessories ещё не существует (источник: " .. source .. ")")
        return
    end

    local found_any = false

    local function Patch(key)
        local acc = hg.Accessories[key]
        if not acc then
            print("[ZCB] Ключ '" .. key .. "' не найден в hg.Accessories!")
            return
        end

        found_any = true
        acc.disallowinappearance = nil
        acc.placement = "face"
        print("[ZCB] '" .. key .. "' пропатчен, placement = '" .. tostring(acc.placement) .. "'")
    end

    Patch("arctic_balaclava")
    Patch("phoenix_balaclava")

    if found_any then
        PATCHED = true
        print("[ZCB] Патч применён успешно (источник: " .. source .. ")")
    else
        print("[ZCB] Ни один из ключей не найден — проверь названия в sh_accessories.lua!")
    end
end

-- Основной, самый ранний и надёжный момент: сразу после того,
-- как zcity-геймод досчитал homigrad и вызвал hook.Run("HomigradRun")
hook.Add("HomigradRun", "ZCB_BalaclavaPatch_Early", function()
    PatchBalaclava("HomigradRun")
end)

-- Подстраховка, если по какой-то причине HomigradRun не сработал
-- (например аддон загрузился раньше геймода) — пробуем ещё раз позже
hook.Add("InitPostEntity", "ZCB_BalaclavaPatch_Late", function()
    PatchBalaclava("InitPostEntity")
    timer.Simple(1, function() PatchBalaclava("timer 1s") end)
    timer.Simple(5, function() PatchBalaclava("timer 5s") end)
end)

-- Если hg уже успел загрузиться ДО этого файла (маловероятно, но
-- дёшево подстраховаться) — пробуем сразу при исполнении файла
PatchBalaclava("file load")

-- Консольная команда, чтобы вручную перезапустить патч и увидеть
-- текущее состояние в любой момент (например открыв консоль в игре)
concommand.Add("zcb_debug", function()
    if not hg or not hg.Accessories then
        print("[ZCB] hg.Accessories отсутствует прямо сейчас")
        return
    end

    for _, key in ipairs({"arctic_balaclava", "phoenix_balaclava"}) do
        local acc = hg.Accessories[key]
        if not acc then
            print("[ZCB] " .. key .. " -> ОТСУТСТВУЕТ в таблице")
        else
            print(string.format(
                "[ZCB] %s -> placement=%s, disallowinappearance=%s, bPointShop=%s",
                key, tostring(acc.placement), tostring(acc.disallowinappearance), tostring(acc.bPointShop)
            ))
        end
    end

    PATCHED = false
    PatchBalaclava("zcb_debug manual")
end)
