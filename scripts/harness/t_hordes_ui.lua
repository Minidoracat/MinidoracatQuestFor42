-- Hordes, client side (contract "horde events"): the admin tab (status, Start one now / Stop, spots, every setting
-- through the draft with the server's ranges), the tracker row, the daily banner, the toasts and the MiniMap
-- providers. The fakes model only what these files call (same shapes as t_admin_ui.lua); removed at the end.
return function(T)
    local saved = { ISUIElement = ISUIElement, ISPanel = ISPanel, getTextManager = getTextManager, UIFont = UIFont,
        getText = getText, getCore = getCore, getTexture = getTexture, MinidoracatMiniMapAPI = MinidoracatMiniMapAPI }

    -- ===== fake engine elements and framework (t_admin_ui.lua) =====
    local Base = {}
    Base.__index = Base
    function Base:initialise() end
    function Base:setX(x) self.x = x end
    function Base:setY(y) self.y = y end
    function Base:getX() return self.x end
    function Base:getY() return self.y end
    function Base:setWidth(w) self.width = w end
    function Base:setHeight(h) self.height = h end
    function Base:getWidth() return self.width end
    function Base:getHeight() return self.height end
    function Base:setVisible(v) self.visible = v end
    function Base:isVisible() return self.visible ~= false end
    function Base:addChild(c) self.children = self.children or {}; self.children[#self.children + 1] = c; c.parent = self end
    function Base:setYScroll(y) self.yscroll = y end
    function Base:setTooltip(s) self.tooltip = s end
    function Base:setEnabled(b) self.enabled = b end
    function Base:isEnabled() return self.enabled ~= false end
    function Base:setWantMouseEvents() end
    local function class(parent)
        local cls = setmetatable({}, { __index = parent })
        cls.__index = cls
        function cls:derive() return class(self) end
        function cls:new(x, y, w, h) return setmetatable({ x = x, y = y, width = w, height = h }, self) end
        return cls
    end
    ISUIElement, ISPanel = class(Base), class(Base)
    UIFont = { Small = "Small", Medium = "Medium" }
    getTextManager = function()
        return { MeasureStringX = function(_, _, s) return #tostring(s) * 7 end, getFontHeight = function() return 14 end }
    end
    getCore = function() return { getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end } end
    local function widget(extra)
        local W = setmetatable(extra or {}, { __index = Base })
        W.__index = W
        return function(opts)
            return setmetatable({ opts = opts, x = opts.x or 0, y = opts.y or 0, width = opts.width or 80, height = opts.height or 20 }, W)
        end
    end
    local button = widget({ setTitle = function(self, s) self.opts.title = s end,
        fitWidth = function(self) self.width = #tostring(self.opts.title) * 7 + 20 end, setStyle = function(self, s) self.style = s end,
        setActive = function(self, b) self.active = b end })
    local dialogs = {}
    local wrapW = {}
    local UI = {
        CAPABILITIES = { textFieldInvalid = true },
        -- wrap splits at "\n" like the framework and records the width each text was given (Flow:text's note cap)
        Text = { fit = function(s) return s end, wrap = function(s, w)
            wrapW[s] = w
            local out = {}
            for line in string.gmatch(s .. "\n", "(.-)\n") do out[#out + 1] = line end
            return out
        end },
        Button = { new = function(opts) local b = button(opts); b.target, b.onclick = opts.target, opts.onClick; return b end },
        Checkbox = { new = widget({ setLabel = function() end, setChecked = function(self, b) self.opts.checked = b end,
            getChecked = function(self) return self.opts.checked == true end }) },
        TextField = { new = widget({ getText = function(self) return self.text or "" end, setText = function(self, s) self.text = s end,
            setInvalid = function(self, b, m) self.invalid = b and (m or true) or nil end }) },
        Dropdown = { new = widget({ setOptions = function(self, o) self.opts.options = o end,
            setSelected = function(self, id) self.selected = id end, getSelected = function(self) return self.selected end }),
            close = function() end },
        Tabs = { new = widget({ getWidth = function() return 400 end, setSelected = function() end }) },
        -- the framework ScrollPanel: Draw.reveal finds it by _scrollPanel up the parents
        ScrollPanel = { new = widget({ contentWidth = function(self) return self.width - 12 end, _scrollPanel = true,
            scrollTo = function(self, el) self.scrolledTo = el end }) },
        Dialog = { show = function(opts) dialogs[#dialogs + 1] = opts end },
    }
    local colors = setmetatable({}, { __index = function(_, k) return { r = 1, g = 1, b = 1, a = 1, token = k } end })
    -- texts read "key|arg1|arg2", so a check sees which key and which values
    getText = function(key, ...)
        local s = key
        for i = 1, select("#", ...) do s = s .. "|" .. tostring((select(i, ...))) end
        return s
    end
    local function has(s, frag) return type(s) == "string" and string.find(s, frag, 1, true) ~= nil end

    local Q = T.bootClient({})
    local A, AM, Cl, D = Q.Admin, Q.AdminModel, Q.Client, Q.Draw
    local now = getTimestampMs()
    T.player({ name = "alice" })

    -- ===== admin tab =====
    local sent = {}
    local function last(op)
        for i = #sent, 1, -1 do if sent[i].op == op then return sent[i] end end
        return nil
    end
    local function count(op)
        local n = 0
        for _, s in ipairs(sent) do if s.op == op then n = n + 1 end end
        return n
    end
    local status = {}
    local nowReply = { id = 7 }
    local replies = {
        ["cfg.get"] = function() return { overrides = {}, history = {}, rev = 1, file = { ok = true, at = now } } end,
        ["cfg.preview"] = function(args)
            local rows = {}
            for i, c in ipairs(Q.Util.decode(args.changes)) do rows[i] = { path = c.path, before = 1, after = c.value } end
            return { rows = rows }
        end,
        ["horde.status"] = function() return T.deepcopy(status) end,
        ["horde.now"] = function() return T.deepcopy(nowReply) end,
        ["horde.stop"] = function() return {} end,
        ["towns.here"] = function() return { x = 10620, y = 9810, z = 0 } end,
    }
    Cl.send = function(cmd, args, cb)
        sent[#sent + 1] = args
        local res = replies[args.op] and replies[args.op](args) or {}
        res.ok, res.op = res.ok ~= false, args.op
        cb(res)
        return "req"
    end
    A.show({ UI = UI, theme = { colors = colors }, parent = ISPanel:new(0, 0, 640, 480), x = 0, y = 0, width = 640, height = 480 })
    local P = A.instance
    local function pool() return P.pages.hordes.flow.pool end
    local function shown(key) local el = pool()[key]; return el ~= nil and el:isVisible() end
    local function press(key) local b = pool()[key]; T.check(b ~= nil and b:isVisible(), "button shown: " .. key); b.onclick(b.target, b) end
    local function answer(ok) local d = dialogs[#dialogs]; dialogs[#dialogs] = nil; d.onResult(ok, "") end
    local function field(key) return pool()["f:" .. key] end
    local function cell(key, i) local r = pool()[key]; return r and r.cells and r.cells[i] and r.cells[i].text end
    local function options(key)
        local out = {}
        for _, o in ipairs(pool()[key] and pool()[key].opts.options or {}) do out[o.id] = o.label end
        return out
    end
    -- a pick in the dropdown, as the framework calls it: onChange(target, id, dropdown)
    local function pick(key, id) local dd = pool()[key]; dd.opts.onChange(dd.opts.target, id, dd) end

    local D0 = "hordes.presets.default"
    local DEF = "IGUI_MQ_Admin_HordePresetDefault"   -- the default preset's shown name (its name is "" in the Catalog)
    -- copies are "<name> 2", "<name> 3": the key is 32 bytes, so the name is cut to make room (AM.MAX_NAME)
    local DEF2, DEF3 = string.sub(DEF, 1, 30) .. " 2", string.sub(DEF, 1, 30) .. " 3"
    local function token(key) local el = pool()[key]; return el and el.color and el.color.token end

    T.section("horde admin: the tab after towns, defaults, sections in the design's order, status on open")
    local ti, hi = 0, 0
    for i, id in ipairs(A.TABS) do if id == "towns" then ti = i elseif id == "hordes" then hi = i end end
    T.check(hi == ti + 1, "the hordes tab comes right after towns")
    A.select(P, "hordes")
    T.check(count("horde.status") == 1 and not T.printed("admin layout"), "opening the tab asks horde.status and lays out")
    local function chipsOn(w)
        local s = ""
        for d = 1, 7 do if pool()["w:d" .. w .. ":" .. d].active then s = s .. d end end
        return s
    end
    T.check(field("hordes.windows.1.from"):getText() == "19:00" and field("hordes.windows.1.to"):getText() == "23:00"
        and field("hordes.windows.1.chance"):getText() == "30" and chipsOn(1) == "1234567"
        and field("hordes.windows.1.leadMin"):getText() == "15" and field("hordes.windows.1.waitMin"):getText() == "60"
        and pool()["w:p1"].selected == "default" and P.pages.hordes.preset == "default"
        and field(D0 .. ".waves.1.base"):getText() == "30" and field(D0 .. ".waves.1.perPlayer"):getText() == "50"
        and field(D0 .. ".kinds.vanilla"):getText() == "80" and field(D0 .. ".kinds.runner"):getText() == "20"
        and field(D0 .. ".points.vanilla"):getText() == "5" and field(D0 .. ".points.runner"):getText() == "8"
        and field(D0 .. ".hp.vanilla"):getText() == "1" and field(D0 .. ".hp.runner"):getText() == "1"
        and field(D0 .. ".restSec"):getText() == "30" and field(D0 .. ".maxAlive"):getText() == "200"
        and field(D0 .. ".limitMin"):getText() == "15" and field(D0 .. ".cap"):getText() == "500"
        and field(D0 .. ".name"):getText() == "" and field("hordes.maxPerDay"):getText() == "1"
        and field("hordes.enabled"):getChecked() == false, "every field shows Catalog.DEFAULTS.hordes; the page edits the default preset")
    local order, prevY, inOrder = { "n", "hs", "hl", "hp", "hw", "hpre", "hv", "hk", "hr" }, -1, true
    for _, k in ipairs(order) do
        inOrder = inOrder and shown(k) and pool()[k].y > prevY
        prevY = pool()[k] and pool()[k].y or prevY
    end
    T.check(inOrder and pool()["h"] == nil and pool()["hpre"].lines[1] == "IGUI_MQ_Admin_HordePresetsHead"
        and pool()["hv"].lines[1] == "IGUI_MQ_Admin_HordeWavesHead|" .. DEF and pool()["hk"].lines[1] == "IGUI_MQ_Admin_HordeKindsHead|" .. DEF
        and pool()["hr"].lines[1] == "IGUI_MQ_Admin_HordeRewardHead|" .. DEF,
        "no page heading; note, status, recent results, spots, windows, presets, then waves / kinds / reward named by the preset")
    T.check(pool()["l:hordes.maxPerDay"].lines[1] == "IGUI_MQ_Admin_F_hordes_maxPerDay" and pool()["l:" .. D0 .. ".cap"].lines[1] == "IGUI_MQ_Admin_F_hordes_cap"
        and pool()["l:" .. D0 .. ".name"].lines[1] == "IGUI_MQ_Admin_F_hordes_name" and pool()["l:hordes.waitMin"] == nil
        and pool()["ks:th"].cells[2].text == "IGUI_MQ_Admin_ColWeight" and pool()["ks:th"].cells[3].text == "IGUI_MQ_Admin_HordeColShare"
        and pool()["ks:th"].cells[4].text == "IGUI_MQ_Admin_HordeColPoints" and pool()["ks:th"].cells[5].text == "IGUI_MQ_Admin_HordeColHp"
        and shown("est") and shown("rn"),
        "preset fields read like their settings; kinds columns weight / share / points / toughness; the cap with its note and estimate")
    T.check(field("hordes.enabled").opts.label == "IGUI_MQ_Admin_F_hordes_enabled" and pool()["l:hordes.enabled"] == nil,
        "Auto hordes is the checkbox's own label: a click on the words toggles it too")
    local estEl = pool()["est"]
    T.check(estEl.lines[1] == "IGUI_MQ_Admin_HordeEstHead|" .. DEF and #estEl.lines == 2 and estEl.firstFont == nil,
        "the estimate box's first line names the preset, in the box's own font")
    local hf = P.pages.hordes.flow
    T.check(wrapW["IGUI_MQ_Admin_HordeNote"] == 30 * 14 and wrapW[estEl.lines[1] .. "\n" .. estEl.lines[2]] == hf.width - 2 * A.PAD - 16,
        "a plain note wraps at 30 font heights at most; a boxed text keeps the full width")
    -- headings (Medium) and the bottom bar's message keep the full width (review r1 C3)
    local longMsg = "a long bar message " .. string.rep("x", 90)
    A.say(P, longMsg, "errorText")
    T.check(wrapW["IGUI_MQ_Admin_HordePresetsHead"] == hf.width - 2 * A.PAD and wrapW[longMsg] == P.barFlow.width - 2 * A.PAD
        and wrapW[longMsg] > 30 * 14, "a heading and the bottom bar's message are not held to the note width")
    A.say(P, nil)
    -- only the hordes tab asks for the narrow notes: Basic keeps its one-line notes on one screen (DE, FR and ES needed
    -- a scroll at 1080p when every page had the cap, quest-ui-*-1028d)
    local bf = P.pages.basic.flow
    bf:begin(hf.width)
    bf:text("n", "IGUI_MQ_Admin_BasicNote", "textMuted")
    T.check(wrapW["IGUI_MQ_Admin_BasicNote"] == hf.width - 2 * A.PAD and hf.width - 2 * A.PAD > 30 * 14,
        "another tab's note keeps the full width")
    T.check(shown("cur") and has(pool()["cur"].lines[1], "IGUI_MQ_Admin_HordeNone") and pool()["now"]:isEnabled(),
        "no horde: says so, Start one now enabled")
    T.check(shown("p:0") and shown("sp:add") and pool()["sp:add"]:isEnabled() and pool()["sp:add"].style == "normal",
        "no spots: the warning inside the list box; the add button is not the gold one")
    T.check(#hf.lists >= 2 and hf.lists[1].key == "l" and hf.lists[2].key == "p", "recent results and spots are list boxes")
    local keepData = P.pages.hordes.data
    P.pages.hordes.data = nil
    A.layout(P)
    T.check(shown("hl") and not shown("l:th") and shown("l:0") and pool()["l:0"].lines[1] == "IGUI_MQ_Admin_Loading",
        "recent results while loading: the box says loading, the column header waits for the results")
    P.pages.hordes.data = keepData
    A.layout(P)
    T.check(shown("l:th") and pool()["l:0"].lines[1] == "IGUI_MQ_Admin_HordeLogNone", "loaded: the header, and no results said in the box")
    A.select(P, "towns")
    A.select(P, "hordes")
    T.check(count("horde.status") == 2, "coming back to the tab asks again (live status)")

    T.section("horde admin: a status payload (wave 2 of 3, log with waves, a pack kind, the cull line, the preset)")
    local log = {}
    for i = 1, 6 do
        log[i] = { id = 10 - i, name = "Spot" .. i, town = "muldraugh", state = i == 1 and "success" or (i == 2 and "cancelled" or "failed"),
            why = i > 2 and "time" or nil, endedAt = now - i * 3600000, waves = 3, cleared = i == 1 and 3 or 2, spawned = 300,
            killed = 280, pool = 500, capped = i == 1 }
    end
    local threeWaves = { { base = 20, perPlayer = 50 }, { base = 30, perPlayer = 50 }, { base = 50, perPlayer = 100 } }
    status = { cur = { id = 3, auto = true, name = "Gas", town = "muldraugh", x = 10620, y = 9810, z = 0, state = "active",
        wave = 2, waves = threeWaves, size = 30, killed = 17, left = 13, endsAt = now + 600000, startMs = now - 60000,
        expireAt = now + 3600000, nextAt = now + 24000, weights = { vanilla = 70, ["mod:brute"] = 30, runner = 0 }, preset = "Hard" },
        roll = { n = 1, max = 2, nextAt = now + 3600000, enabled = true }, log = log, cull = 300,
        kinds = { { id = "vanilla", nameKey = "IGUI_MQ_Horde_Kind_vanilla", builtin = true },
            { id = "runner", nameKey = "IGUI_MQ_Horde_Kind_runner", builtin = true }, { id = "mod:brute", nameKey = "Brute_Name", builtin = false } } }
    press("refresh")
    T.check(count("horde.status") == 3 and shown("stop") and pool()["stop"].opts.title == "IGUI_MQ_Admin_HordeStop"
        and pool()["stop"].style == "danger", "Refresh asks again; an active horde has a danger Stop")
    T.check(pool()["stop"].x + pool()["stop"].width == hf.width - A.PAD, "the Stop button keeps the row's end")
    T.check(has(pool()["cur"].lines[1], "IGUI_MQ_Admin_HordeCurActive|IGUI_MQ_Admin_HordeState_active|") and has(pool()["cur"].lines[1], "|2|3|17|30|"),
        "the current line: state, place, wave 2 / 3, cleared 17 / 30")
    T.check(has(pool()["roll"].lines[1], "IGUI_MQ_Admin_HordeToday|1|2|"), "today n / max and the next roll")
    T.check(shown("cull") and pool()["cull"].lines[1] == "IGUI_MQ_Admin_HordeCull|300", "the sandbox cull line under the max alive field")
    T.check(not pool()["now"]:isEnabled(), "Start one now is off while a horde exists")
    T.check(shown("l5") and not shown("l6") and cell("l1", 3) == "IGUI_MQ_Admin_HordeResWin|3|3|280|500IGUI_MQ_Admin_HordeCapped"
        and pool()["l1"].cells[3].token == "success" and has(cell("l2", 3), "IGUI_MQ_Admin_HordeRes_cancelled")
        and cell("l3", 3) == "IGUI_MQ_Admin_HordeResFail|IGUI_MQ_Admin_HordeWhy_time|2|3|500" and pool()["l3"].cells[3].token == "errorText"
        and cell("l:th", 1) == "IGUI_MQ_Admin_ColTime", "recent results: 5 of 6, cleared waves / waves, the pool, capped marked")
    T.check(field(D0 .. ".kinds.mod:brute") == nil and options("ks:add")["mod:brute"] == "Brute_Name"
        and options("ks:add").vanilla == nil and options("ks:add").runner == nil,
        "a pack kind (no weight yet) waits in the dropdown, named by its nameKey; the weighted kinds are rows")
    press("stop")
    local d = dialogs[#dialogs]
    T.check(d.danger and d.confirmText == "IGUI_MQ_Admin_HordeStop" and has(d.text, "IGUI_MQ_Admin_HordeStopAsk|"), "Stop asks first, danger")
    answer(false)
    T.check(last("horde.stop") == nil, "cancelling the dialog sends nothing")
    press("stop")
    answer(true)
    T.check(last("horde.stop").id == 3 and count("horde.status") == 4 and P.msg == "IGUI_MQ_Admin_HordeStopped",
        "horde.stop with the id, then the status again")
    status.cur.state = "rest"
    press("refresh")
    T.check(has(pool()["cur"].lines[1], "IGUI_MQ_Admin_HordeCurRest|IGUI_MQ_Admin_HordeState_rest|")
        and has(pool()["cur"].lines[1], "|2|3|" .. A.time(status.cur.nextAt))
        and pool()["stop"].opts.title == "IGUI_MQ_Admin_HordeStop", "rest: wave 2 / 3 cleared, the clock time of the next; Stop")
    status.cur.state, status.cur.wave = "waiting", 3
    press("refresh")
    T.check(has(pool()["cur"].lines[1], "IGUI_MQ_Admin_HordeCurWaiting|IGUI_MQ_Admin_HordeState_waiting|") and has(pool()["cur"].lines[1], "|3|3|"),
        "waiting: the wave it waits for")
    status.cur.state, status.cur.wave = "announced", 1
    press("refresh")
    T.check(pool()["stop"].opts.title == "IGUI_MQ_Admin_HordeCancel" and has(pool()["cur"].lines[1], "IGUI_MQ_Admin_HordeCurPlan|")
        and has(pool()["cur"].lines[1], "|3|IGUI_MQ_Horde_Kind_vanillaIGUI_MQ_UI_ListSepBrute_Name|Hard"),
        "before it starts the button says Cancel; the admin sees the waves, the kinds with a weight and the preset")
    T.check(pool()["stop"].x + pool()["stop"].width == hf.width - A.PAD, "Cancel keeps the row's end too")
    press("stop")
    T.check(dialogs[#dialogs].confirmText == "IGUI_MQ_Admin_HordeCancel" and dialogs[#dialogs].cancelText == "IGUI_MQ_Admin_HordeKeep"
        and d.cancelText == "UI_Cancel", "Cancel this horde: the way out says Keep, not Cancel too (Stop keeps Cancel)")
    answer(false)
    status.cur.preset = nil
    press("refresh")
    T.check(has(pool()["cur"].lines[1], "|" .. DEF), "a horde planned before presets (no preset) reads as the default one")
    status.cur = nil
    status.roll.enabled = false
    press("refresh")
    T.check(pool()["now"]:isEnabled() and has(pool()["roll"].lines[1], "IGUI_MQ_Admin_HordeAutoOff"), "no horde: Start a horde; auto off said")
    local lead, wait = pool()["now:lead"], pool()["now:wait"]
    T.check(lead:getText() == "15" and wait:getText() == "60" and pool()["now:pre"].selected == "default" and options("now:pre").default == DEF,
        "Start a horde: the default preset, warning 15 and wait 60 (a new window's values)")
    press("now")
    d = dialogs[#dialogs]
    T.check(d.confirmText == "IGUI_MQ_Admin_HordeNow" and d.text == "IGUI_MQ_Admin_HordeNowAsk|" .. DEF .. "|15",
        "Start a horde asks with the preset and the warning minutes")
    answer(false)
    T.check(last("horde.now") == nil, "not confirmed: nothing sent")
    press("now")
    answer(true)
    local hn = last("horde.now")
    T.check(hn ~= nil and hn.lead == 15 and hn.wait == 60 and hn.preset == "default" and P.msg == "IGUI_MQ_Admin_HordeStarted"
        and AM.draftCount(P.S.draft) == 0, "confirmed: horde.now { lead 15, wait 60, preset default }, no draft change")
    lead:setText("0")
    wait:setText("30")
    press("now")
    T.check(dialogs[#dialogs].text == "IGUI_MQ_Admin_HordeNowAskNow|" .. DEF, "a warning of 0: the start-now text, with the preset")
    answer(true)
    T.check(last("horde.now").lead == 0 and last("horde.now").wait == 30 and pool()["now:lead"]:getText() == "0"
        and pool()["now:wait"]:getText() == "30", "lead 0 and wait 30 sent; the admin's values survive the relayout")
    local asked = #dialogs
    for _, bad in ipairs({ { lead, "", "IGUI_MQ_Admin_ErrNumber|0|120" }, { lead, "x", "IGUI_MQ_Admin_ErrNumber|0|120" },
        { lead, "-1", "IGUI_MQ_Admin_ErrWhole|0|120" }, { lead, "121", "IGUI_MQ_Admin_ErrWhole|0|120" }, { lead, "2.5", "IGUI_MQ_Admin_ErrWhole|0|120" },
        { wait, "0", "IGUI_MQ_Admin_ErrWhole|1|240" }, { wait, "241", "IGUI_MQ_Admin_ErrWhole|1|240" } }) do
        local keep = bad[1]:getText()
        bad[1]:setText(bad[2])
        P.pages.hordes.sp.scrolledTo = nil
        press("now")
        T.check(#dialogs == asked and P.msg == "IGUI_MQ_Admin_FixErrorsWhy|" .. bad[3] and bad[1].invalid ~= nil
            and P.pages.hordes.sp.scrolledTo == bad[1], (bad[1] == lead and "warning" or "wait") .. " '" .. bad[2]
            .. "': marked, the bar says why and the page scrolls to it, nothing asked")
        bad[1]:setText(keep)
    end
    lead:setText("5")
    nowReply = { ok = false, code = "NO_SPOTS" }
    press("now")
    T.check(P.msg == nil, "a good value: the old error leaves the bar when the dialog opens")
    answer(true)
    T.check(P.msg == "IGUI_MQ_Code_NO_SPOTS" and lead.invalid == nil and wait.invalid == nil, "a refusal shows the server code; good values clear the marks")
    nowReply = { id = 7 }

    T.section("horde admin: fields check like the server table")
    local pg = P.pages.hordes
    local function okWith(key, text)
        local el = field(key)
        local keep = el:getText()
        el:setText(text)
        local good = A.collect(P, pg) ~= nil
        local marked = el.invalid ~= nil
        el:setText(keep)
        A.collect(P, pg)
        return good and not marked
    end
    local cases = {
        { "hordes.windows.1.from", { "0:00", "9:05", "23:59", " 19:30 " }, { "24:00", "12:60", "1200", "7:5", "", "ab:cd" } },
        { "hordes.windows.1.to", { "0:00", "23:59" }, { "24:00", "" } },
        { "hordes.windows.1.chance", { "0", "100" }, { "-1", "101", "2.5", "x" } },
        { "hordes.windows.1.leadMin", { "0", "120" }, { "-1", "121", "1.5" } },
        { "hordes.windows.1.waitMin", { "1", "240" }, { "0", "241" } },
        { "hordes.maxPerDay", { "1", "24" }, { "0", "25" } },
        { D0 .. ".waves.1.base", { "1", "9999" }, { "0", "10000", "1.5" } },
        { D0 .. ".waves.1.perPlayer", { "0", "1000" }, { "-1", "1001" } },
        { D0 .. ".restSec", { "0", "600" }, { "-1", "601" } },
        { D0 .. ".limitMin", { "1", "120" }, { "0", "121" } },
        { D0 .. ".maxAlive", { "10", "2000" }, { "9", "2001" } },
        { D0 .. ".kinds.runner", { "0", "100" }, { "-1", "101", "1.5" } },
        { D0 .. ".points.runner", { "0", "1000" }, { "-1", "1001" } },
        { D0 .. ".hp.runner", { "0.1", "1.5", "10" }, { "0.05", "0", "10.5", "x" } },
        { D0 .. ".cap", { "1", "1000000" }, { "0", "1000001" } },
    }
    for _, c in ipairs(cases) do
        local goodOk, badOk = true, false
        for _, v in ipairs(c[2]) do goodOk = goodOk and okWith(c[1], v) end
        for _, v in ipairs(c[3]) do badOk = badOk or okWith(c[1], v) end
        T.check(goodOk and not badOk, c[1] .. ": bounds accepted, outside rejected")
    end
    T.check(AM.clock(" 19:30 ") == "19:30" and AM.clock("9:05") == "9:05" and AM.clock("24:00") == nil and AM.clock("1:2") == nil,
        "AM.clock keeps the typed text, rejects what the server rejects")
    -- a decimal field reads "," as the decimal point, the exchange rate too; an integer field drops it as a thousands
    -- separator (review r1 C4, r2: the rate read "0,5" as 5)
    T.check(AM.check("0,5", "hordeHp") == 0.5 and AM.check("1,25", "eventMult") == 1.25 and AM.check("1,000", "hordeCap") == 1000
        and AM.check("0,5", "rate") == 0.5 and AM.check("1.5", "hordeHp") == 1.5,
        "0,5 is half a toughness and half a coin; 1,000 is a thousand points")

    T.section("horde admin: a bad field is named in the bar and scrolled to; a good edit clears it (review H2, M1)")
    local sp = pg.sp
    sp.scrolledTo = nil
    field(D0 .. ".cap"):setText("0")
    field(D0 .. ".waves.1.base"):setText("1.5")
    A.onPreview(P)
    T.check(P.msgToken == "errorText" and has(P.msg, "IGUI_MQ_Admin_FixErrorsWhy|IGUI_MQ_Admin_ErrWhole|1|")
        and sp.scrolledTo == field(D0 .. ".waves.1.base"),
        "Apply with two bad fields: the bar gives the topmost one's message (waves above the cap) and scrolls to it")
    sp.scrolledTo = nil
    press("w:add")
    T.check(#AM.get(P.S, "hordes.windows") == 1 and has(P.msg, "IGUI_MQ_Admin_FixErrorsWhy|IGUI_MQ_Admin_ErrWhole|1|")
        and sp.scrolledTo == field(D0 .. ".waves.1.base"), "Add a window with a bad field: nothing added, the bar and the scroll go to it")
    field(D0 .. ".waves.1.base"):setText("30")
    field(D0 .. ".cap"):setText("500")
    press("w:add")
    T.check(#AM.get(P.S, "hordes.windows") == 2 and P.msg == "IGUI_MQ_Admin_InDraft" and P.msgToken == "textMuted",
        "fixed, then Add: the bar says it is in the draft, the error is gone")
    press("w:r2")
    T.check(AM.draftCount(P.S.draft) == 0 and P.msg == nil, "removed again, nothing pending: the bar is empty")
    A.discard(P)
    field("hordes.windows.1.from"):setText("20:00")
    field("hordes.windows.1.chance"):setText("60")
    field("hordes.windows.1.leadMin"):setText("5")
    field("hordes.windows.1.waitMin"):setText("90")
    field("hordes.maxPerDay"):setText("3")
    field(D0 .. ".waves.1.base"):setText("25")
    field(D0 .. ".kinds.runner"):setText("0")
    field(D0 .. ".hp.runner"):setText("1.5")
    field(D0 .. ".cap"):setText("800")
    pick("ks:add", "mod:brute")
    T.check(field(D0 .. ".kinds.mod:brute"):getText() == "10" and field(D0 .. ".points.mod:brute"):getText() == "5"
        and field(D0 .. ".hp.mod:brute"):getText() == "1" and shown("ks:n:mod:brute") and not shown("ks:add") and shown("ks:all")
        and field(D0 .. ".kinds.runner"):getText() == "0",
        "picked: the kind is a row at weight 10, the regular zombie's 5 points and 1x toughness; typed values stay")
    field("hordes.enabled"):setChecked(true)
    A.onPreview(P)
    local changes = Q.Util.decode(last("cfg.preview").changes)
    local by = {}
    for _, ch in ipairs(changes) do by[ch.path] = ch.value end
    local w1, v1 = by["hordes.windows"] and by["hordes.windows"][1], by[D0 .. ".waves"] and by[D0 .. ".waves"][1]
    T.check(w1 and #by["hordes.windows"] == 1 and w1.from == "20:00" and w1.to == "23:00" and w1.chance == 60 and w1.days == "1234567"
        and w1.preset == "default" and w1.leadMin == 5 and w1.waitMin == 90
        and v1 and #by[D0 .. ".waves"] == 1 and v1.base == 25 and v1.perPlayer == 50,
        "a window's warning and wait read and write hordes.windows.<i>.leadMin / .waitMin; windows and waves go whole")
    T.check(by["hordes.maxPerDay"] == 3 and by["hordes.enabled"] == true and by[D0 .. ".kinds.runner"] == 0 and by[D0 .. ".hp.runner"] == 1.5
        and by[D0 .. ".kinds.mod:brute"] == 10 and by[D0 .. ".points.mod:brute"] == 5 and by[D0 .. ".cap"] == 800,
        "valid values land in the draft and the preview, a decimal toughness too; the picked kind brings its points key")
    T.check(by[D0 .. ".kinds.vanilla"] == nil and by[D0 .. ".points.vanilla"] == nil and by[D0 .. ".hp.vanilla"] == nil
        and by[D0 .. ".hp.mod:brute"] == nil and #changes == 9, "untouched fields add nothing; a toughness left at 1 stays unset")
    local labels = {}
    for _, r in ipairs(P.confirm.rows) do labels[r.label] = r end
    local PR = "IGUI_MQ_Admin_HordePresetRow|" .. DEF .. "|"
    T.check(labels[PR .. "IGUI_MQ_Admin_F_hordes_kinds - IGUI_MQ_Horde_Kind_runner"] ~= nil
        and labels[PR .. "IGUI_MQ_Admin_F_hordes_kinds - Brute_Name"] ~= nil and labels[PR .. "IGUI_MQ_Admin_F_hordes_points - Brute_Name"] ~= nil
        and labels[PR .. "IGUI_MQ_Admin_F_hordes_hp - IGUI_MQ_Horde_Kind_runner"] ~= nil and labels[PR .. "IGUI_MQ_Admin_F_hordes_cap"] ~= nil,
        "preview rows name the preset, then the field (and the kind)")
    T.check(labels["IGUI_MQ_Admin_F_hordes_windows"].after == "IGUI_MQ_Admin_HordeWindowText|20:00|23:00|60|IGUI_MQ_Admin_HordeEveryDay|" .. DEF .. "|5|90"
        and labels[PR .. "IGUI_MQ_Admin_F_hordes_waves"].after == "IGUI_MQ_Admin_HordeWaveText|25|50",
        "windows (with preset, warning and wait) and waves read as one line each")
    T.check(A.hordeValue(P, "hordes.windows", { { days = "67", from = "14:00", to = "23:00", chance = 20, preset = "default", leadMin = 10, waitMin = 30 } })
        == "IGUI_MQ_Admin_HordeWindowText|14:00|23:00|20|IGUI_MQ_UI_Weekday_6IGUI_MQ_UI_ListSepIGUI_MQ_UI_Weekday_7|" .. DEF .. "|10|30",
        "a weekend window names its days")
    A.onConfirmCancel(P)
    A.discard(P)

    T.section("horde admin: windows (claim 3; a preset, warning and wait per window)")
    T.check(not pool()["w:r1"]:isEnabled() and pool()["w:add"]:isEnabled() and pool()["w:max"].lines[1] == "IGUI_MQ_Admin_HordeWindowsMax|8"
        and token("w:max") == "textMuted", "one window: its Remove is off (at least one), Add on, the limit said quietly")
    field("hordes.windows.1.chance"):setText("45")
    press("w:add")
    local wins = AM.get(P.S, "hordes.windows")
    T.check(#wins == 2 and wins[1].chance == 45 and wins[2].days == "1234567" and wins[2].preset == "default" and wins[2].leadMin == 15
        and wins[2].waitMin == 60 and field("hordes.windows.1.chance"):getText() == "45"
        and field("hordes.windows.2.from"):getText() == "19:00" and pool()["w:r1"]:isEnabled(),
        "Add: what was typed stays, the new window starts at the default (default preset, 15 / 60 min), Remove comes on")
    for _ = 1, 8 do press("w:add") end
    T.check(#AM.get(P.S, "hordes.windows") == AM.MAX_WINDOWS and not pool()["w:add"]:isEnabled() and token("w:max") == "warning",
        "8 windows: Add is off, the limit in the warning colour")
    press("w:r1")
    wins = AM.get(P.S, "hordes.windows")
    T.check(#wins == 7 and wins[1].chance == 30, "Remove drops that window")
    A.discard(P)
    for dd = 1, 7 do press("w:d1:" .. dd) end
    T.check(AM.get(P.S, "hordes.windows")[1].days == "" and chipsOn(1) == "" and shown("w:e1")
        and pool()["w:e1"].lines[1] == "IGUI_MQ_Admin_HordeErrDays", "every day off: the window shows the error")
    local previews = count("cfg.preview")
    A.onPreview(P)
    T.check(count("cfg.preview") == previews and P.msg == "IGUI_MQ_Admin_HordeErrDays", "a window without a day stops Apply")
    press("w:d1:6")
    press("w:d1:7")
    T.check(AM.get(P.S, "hordes.windows")[1].days == "67" and chipsOn(1) == "67" and not shown("w:e1"), "weekend only: days 67, no error")
    A.onPreview(P)
    T.check(count("cfg.preview") == previews + 1, "with a day the preview goes out")
    A.onConfirmCancel(P)
    for dd = 1, 5 do press("w:d1:" .. dd) end
    T.check(P.S.draft.by["hordes.windows"] == nil, "toggled back to every day: the window is the applied one again, out of the draft")
    A.discard(P)

    T.section("horde admin: waves, share and the estimate (design numbers)")
    T.check(not pool()["v:r1"]:isEnabled() and pool()["v:add"]:isEnabled() and pool()["v:1:1"].lines[1] == "30"
        and pool()["v:4:1"].lines[1] == "75", "one wave: Remove off; previews 1 player 30, 4 players 75 (base 30, +50%)")
    T.check(pool()["vn"].y > pool()["v:add"].y, "the waves note sits under the Add a wave row")
    AM.draftSet(P.S.draft, D0 .. ".waves", T.deepcopy(threeWaves))
    AM.draftSet(P.S.draft, D0 .. ".kinds.vanilla", 70)
    AM.draftSet(P.S.draft, D0 .. ".kinds.runner", 50)
    AM.draftSet(P.S.draft, D0 .. ".points.vanilla", 1)
    AM.draftSet(P.S.draft, D0 .. ".points.runner", 2)
    A.resync(P)
    T.check(pool()["v:1:1"].lines[1] == "20" and pool()["v:4:1"].lines[1] == "50" and pool()["v:1:2"].lines[1] == "30"
        and pool()["v:4:2"].lines[1] == "75" and pool()["v:4:3"].lines[1] == "200", "wave previews: 20/50, 30/75, 50/200")
    T.check(pool()["ks:s:vanilla"].lines[1] == "IGUI_MQ_Admin_HordePct|58" and pool()["ks:s:runner"].lines[1] == "IGUI_MQ_Admin_HordePct|42",
        "weights 70 and 50: shares 58% and 42%")
    local est = pool()["est"].lines
    T.check(est[1] == "IGUI_MQ_Admin_HordeEstHead|" .. DEF and est[2] == "IGUI_MQ_Admin_HordeEst1|1|140   IGUI_MQ_Admin_HordeEst|4|459   IGUI_MQ_Admin_HordeEstCap|8|500"
        and pool()["v:th"].cells[4].text == "IGUI_MQ_Admin_HordeColPlayers1|1" and pool()["v:th"].cells[5].text == "IGUI_MQ_Admin_HordeColPlayers|4",
        "estimate: 1 player 140, 4 players 459, 8 players capped at 500")
    T.check(A.hordeEstimate(P, pg, { { id = "vanilla" }, { id = "runner" } }, 8) == 884, "8 players before the cap: 884")
    -- a pack kind with a weight but no points of its own pays the regular points as typed (Hordes.lua does the same)
    AM.draftSet(P.S.draft, D0 .. ".kinds.mod:brute", 50)
    A.layout(P)
    local brute = { { id = "mod:brute" } }
    local estBefore = A.hordeEstimate(P, pg, brute, 1)
    field(D0 .. ".points.vanilla"):setText("3")
    A.layout(P)
    T.check(estBefore == 100 and A.hordeEstimate(P, pg, brute, 1) == 300 and field(D0 .. ".points.mod:brute"):getText() == "1",
        "an unset pack kind's points follow the regular points as typed (100 -> 300 over 100 zombies)")
    field(D0 .. ".points.vanilla"):setText("1")
    AM.draftUnset(P.S.draft, D0 .. ".kinds.mod:brute")
    A.layout(P)
    field(D0 .. ".waves.1.base"):setText("40")
    field(D0 .. ".kinds.runner"):setText("70")
    A.layout(P)
    T.check(pool()["v:1:1"].lines[1] == "40" and pool()["ks:s:runner"].lines[1] == "IGUI_MQ_Admin_HordePct|50"
        and field(D0 .. ".waves.1.base").onChange ~= nil, "previews and shares follow the typed values (fields relayout on change)")
    field(D0 .. ".kinds.runner"):setText("0")
    field(D0 .. ".kinds.vanilla"):setText("0")
    A.layout(P)
    T.check(pool()["ks:s:runner"].lines[1] == "IGUI_MQ_Admin_HordePct|0" and shown("ks:n:runner"), "every weight 0: 0%, the rows stay until applied")
    A.discard(P)
    AM.draftSet(P.S.draft, D0 .. ".waves", T.deepcopy(threeWaves))
    A.resync(P)
    press("v:add")
    local waves = AM.get(P.S, D0 .. ".waves")
    T.check(#waves == 4 and waves[4].base == 50 and waves[4].perPlayer == 100, "Add a wave copies the last row")
    for _ = 1, 8 do press("v:add") end
    T.check(#AM.get(P.S, D0 .. ".waves") == AM.MAX_WAVES and not pool()["v:add"]:isEnabled() and pool()["v:max"].lines[1] == "IGUI_MQ_Admin_HordeWavesMax|10"
        and token("v:max") == "warning", "10 waves: Add is off, the limit in the warning colour")
    press("v:r1")
    waves = AM.get(P.S, D0 .. ".waves")
    T.check(#waves == 9 and waves[1].base == 30 and token("v:max") == "textMuted", "Remove drops that wave")
    A.discard(P)

    T.section("horde admin: the kinds list box (design r11, points and toughness per kind)")
    T.check(shown("ks:n:vanilla") and shown("ks:n:runner") and shown("ks:add") and pool()["ks:add"].opts.placeholder == "IGUI_MQ_Admin_HordeKindAdd",
        "defaults: both built-in kinds are rows, the dropdown says what it does")
    field(D0 .. ".points.vanilla"):setText("6")
    pick("ks:add", "mod:brute")
    T.check(P.S.draft.by[D0 .. ".points.mod:brute"] == 6 and P.S.draft.by[D0 .. ".points.vanilla"] == nil
        and field(D0 .. ".points.vanilla"):getText() == "6",
        "a pick copies the regular points as typed (6); the typed field stays typed, not folded")
    A.discard(P)
    press("ks:r:vanilla")
    T.check(P.S.draft.by[D0 .. ".kinds.vanilla"] == 0 and P.S.draft.by[D0 .. ".points.vanilla"] == nil and not shown("ks:n:vanilla")
        and options("ks:add").vanilla == "IGUI_MQ_Horde_Kind_vanilla" and has(P.draftSummary, "IGUI_MQ_Admin_HordeSumKindDel|IGUI_MQ_Horde_Kind_vanilla"),
        "Remove on a built-in kind writes 0 (its default is 80), keeps its points, puts it back in the dropdown")
    AM.draftSet(P.S.draft, D0 .. ".points.vanilla", 7)
    pick("ks:add", "mod:brute")
    T.check(P.S.draft.by[D0 .. ".kinds.mod:brute"] == 10 and P.S.draft.by[D0 .. ".points.mod:brute"] == 7
        and field(D0 .. ".points.mod:brute"):getText() == "7" and has(P.draftSummary, "IGUI_MQ_Admin_HordeSumKindAdd|Brute_Name"),
        "a pick adds the kind at weight 10 and the draft's regular points (7)")
    AM.draftUnset(P.S.draft, D0 .. ".points.vanilla")
    local n = AM.draftCount(P.S.draft)
    press("ks:r:mod:brute")
    T.check(P.S.draft.by[D0 .. ".kinds.mod:brute"] == nil and P.S.draft.by[D0 .. ".points.mod:brute"] == nil and AM.draftCount(P.S.draft) == n - 2
        and not shown("ks:n:mod:brute") and options("ks:add")["mod:brute"] == "Brute_Name",
        "picked and removed before Apply: the draft forgets weight and points, nothing to send")
    press("ks:r:runner")
    T.check(shown("ks:0") and has(pool()["ks:0"].lines[1], "IGUI_MQ_Admin_HordeKindsNone"), "an empty list says every zombie is a regular one")
    A.onPreview(P)
    changes = Q.Util.decode(last("cfg.preview").changes)
    by = {}
    for _, ch in ipairs(changes) do by[ch.path] = ch end
    T.check(#changes == 2 and by[D0 .. ".kinds.vanilla"].value == 0 and by[D0 .. ".kinds.runner"].value == 0,
        "the preview carries 0 for the built-in kinds, nothing for the kind picked and removed")
    A.onConfirmCancel(P)
    A.discard(P)
    pick("ks:add", "mod:brute")
    press("ks:r:mod:brute")
    T.check(AM.draftCount(P.S.draft) == 0 and P.draftSummary == nil and P.msg == nil,
        "picked and removed with nothing else pending: no summary, no in-the-draft note")
    -- as a cfg.get reply sets them: overrides, then a resync (fields read the server values again)
    P.S.overrides.hordes = { presets = { default = { kinds = { ["old:gone"] = 15, ["mod:brute"] = 30 },
        points = { ["old:gone"] = 4, ["mod:brute"] = 12 }, hp = { ["mod:brute"] = 2.5 } } } }
    local keep = P.pages.hordes.data
    P.pages.hordes.data = nil
    A.resync(P)
    T.check(not shown("ks:o:old:gone"), "before horde.status lists the kinds, nothing is called not installed")
    P.pages.hordes.data = keep
    A.layout(P)
    T.check(shown("ks:o:old:gone") and pool()["ks:g:old:gone"].lines[1] == "IGUI_MQ_Admin_HordeKindGone" and pool()["ks:w:old:gone"].lines[1] == "15",
        "a key no mod registers any more: a row marked not installed, with its weight")
    press("ks:r:old:gone")
    T.check(P.S.draft.by[D0 .. ".kinds.old:gone"] == AM.DEL and P.S.draft.by[D0 .. ".points.old:gone"] == AM.DEL and not shown("ks:o:old:gone"),
        "its Remove drops the weight and points keys")
    T.check(shown("ks:n:mod:brute") and field(D0 .. ".kinds.mod:brute"):getText() == "30" and field(D0 .. ".points.mod:brute"):getText() == "12"
        and field(D0 .. ".hp.mod:brute"):getText() == "2.5", "a pack kind applied at 30 / 12 points / 2.5x is a row")
    press("ks:r:mod:brute")
    T.check(P.S.draft.by[D0 .. ".kinds.mod:brute"] == AM.DEL and P.S.draft.by[D0 .. ".points.mod:brute"] == AM.DEL
        and P.S.draft.by[D0 .. ".hp.mod:brute"] == AM.DEL and not shown("ks:n:mod:brute"),
        "Remove on an applied pack kind drops weight, points and toughness")
    A.discard(P)
    P.S.overrides.hordes = nil

    T.section("horde admin: presets (plan-presets-1028)")
    A.resync(P)
    T.check(options("pre:pick").default == DEF and pool()["pre:pick"].selected == "default" and not pool()["pre:del"]:isEnabled()
        and pool()["pre:copy"]:isEnabled() and token("pre:max") == "textMuted"
        and pool()["pre:u"].lines[1] == "IGUI_MQ_Admin_HordePresetUsed|IGUI_MQ_Admin_HordeWindowShort|IGUI_MQ_Admin_HordeEveryDay|19:00|23:00",
        "the default preset: picked, cannot be deleted, can be copied, the windows using it listed")
    -- applied settings first: the copy takes the merged values (an override of the default preset and the Catalog)
    P.S.overrides.hordes = { presets = { default = { limitMin = 25, kinds = { runner = 0 }, hp = { vanilla = 2 } } } }
    A.resync(P)
    field(D0 .. ".restSec"):setText("45")
    press("pre:copy")
    local p2 = AM.get(P.S, "hordes.presets.p2")
    T.check(pg.preset == "p2" and P.S.draft.by["hordes.presets.p2"] ~= nil and p2.name == DEF2 and p2.limitMin == 25 and p2.restSec == 45
        and p2.maxAlive == 200 and p2.cap == 500 and p2.kinds.vanilla == 80 and p2.kinds.runner == 0 and p2.points.runner == 8
        and p2.hp.vanilla == 2 and p2.hp.runner == nil and #p2.waves == 1 and p2.waves[1].base == 30,
        "Copy: id p2, named '<name> 2', every field as the source plays it (applied overrides, the Catalog, what was typed)")
    T.check(P.msg == "IGUI_MQ_Admin_InDraft" and has(P.draftSummary, "IGUI_MQ_Admin_HordeSumPresetAdd|" .. DEF2)
        and pool()["pre:pick"].selected == "p2" and pool()["hv"].lines[1] == "IGUI_MQ_Admin_HordeWavesHead|" .. DEF2
        and pool()["pre:del"]:isEnabled() and pool()["pre:u"].lines[1] == "IGUI_MQ_Admin_HordePresetUnused",
        "the page switches to the copy, in the draft; no window uses it yet")
    T.check(field("hordes.presets.p2.limitMin"):getText() == "25" and field("hordes.presets.p2.name"):getText() == DEF2
        and not shown("f:" .. D0 .. ".limitMin"), "its fields are on the page, the default preset's are not")
    -- edits on the copy go into it: waves, kinds, reward and a field, each on the preset's own path
    field("hordes.presets.p2.limitMin"):setText("20")
    field("hordes.presets.p2.cap"):setText("800")
    press("v:add")
    pick("ks:add", "mod:brute")
    field("hordes.presets.p2.hp.vanilla"):setText("3")
    pick("pre:pick", "default")
    p2 = AM.get(P.S, "hordes.presets.p2")
    T.check(pg.preset == "default" and p2.limitMin == 20 and p2.cap == 800 and #p2.waves == 2 and p2.kinds["mod:brute"] == 10
        and AM.get(P.S, D0 .. ".limitMin") == 25 and #AM.get(P.S, D0 .. ".waves") == 1 and AM.get(P.S, D0 .. ".kinds.mod:brute") == nil
        and AM.get(P.S, D0 .. ".cap") == 500 and field(D0 .. ".limitMin"):getText() == "25" and field(D0 .. ".restSec"):getText() == "45",
        "switching folds the typed values into the preset shown; waves, kinds, reward and fields read and write that preset only")
    T.check(AM.draftCount(P.S.draft) == 2 and P.S.draft.by["hordes.presets.p2.limitMin"] == nil,
        "edits under a copied preset stay inside its one draft entry (plus the default's typed rest)")
    -- the copy goes as one whole set, with the hp typed on it
    A.onPreview(P)
    changes = Q.Util.decode(last("cfg.preview").changes)
    by = {}
    for _, ch in ipairs(changes) do by[ch.path] = ch end
    T.check(by["hordes.presets.p2"] and by["hordes.presets.p2"].op == "set" and by["hordes.presets.p2"].value.hp.vanilla == 3
        and by["hordes.presets.p2"].value.limitMin == 20 and by[D0 .. ".restSec"].value == 45,
        "Apply sends the new preset as one set, with what was typed on it")
    labels = {}
    for _, r in ipairs(P.confirm.rows) do labels[r.label] = r end
    T.check(labels["IGUI_MQ_Admin_HordePresetAddRow|" .. DEF2] ~= nil and labels[PR .. "IGUI_MQ_Admin_F_hordes_restSec"] ~= nil,
        "the preview says New preset with its name, and names the preset of a field")
    A.onConfirmCancel(P)
    -- a second copy of the default preset: the next free id, the next free name
    press("pre:copy")
    T.check(pg.preset == "p3" and AM.get(P.S, "hordes.presets.p3.name") == DEF3, "a second copy: p3, '<name> 3' ('<name> 2' is taken)")
    -- Start a horde lists the applied presets only
    T.check(options("now:pre").p2 == nil and options("now:pre").p3 == nil and options("now:pre").default == DEF,
        "Start a horde does not offer presets that are only in the draft")
    P.S.overrides.hordes.presets.hard = { name = "Hard", waves = { { base = 50, perPlayer = 50 } }, kinds = { runner = 100 }, points = { runner = 9 },
        hp = {}, limitMin = 10, restSec = 30, maxAlive = 200, cap = 900 }
    A.layout(P)
    T.check(options("now:pre").hard == "Hard" and options("pre:pick").hard == "Hard", "an applied preset is offered to Start a horde")
    pick("now:pre", "hard")
    press("now")
    T.check(dialogs[#dialogs].text == "IGUI_MQ_Admin_HordeNowAsk|Hard|5", "Start a horde asks with the picked preset's name")
    answer(true)
    T.check(last("horde.now").preset == "hard" and last("horde.now").lead == 5 and last("horde.now").wait == 30, "horde.now sends lead, wait, preset")
    pick("now:pre", "default")
    -- a window picks a preset; the presets section lists the windows on it
    pick("w:p1", "p2")
    T.check(AM.get(P.S, "hordes.windows")[1].preset == "p2" and pool()["w:p1"].selected == "p2", "a window's dropdown writes its preset")
    pick("pre:pick", "p2")
    T.check(has(pool()["pre:u"].lines[1], "IGUI_MQ_Admin_HordePresetUsed|IGUI_MQ_Admin_HordeWindowShort|"), "the copy lists the window now on it")
    -- delete a preset a window uses: asked first, the windows go back to the default one
    press("pre:del")
    d = dialogs[#dialogs]
    T.check(d.danger and d.title == "IGUI_MQ_Admin_HordePresetDelTitle|" .. DEF2 and d.confirmText == "IGUI_MQ_Admin_HordePresetDel"
        and d.cancelText == "IGUI_MQ_Admin_Keep" and has(d.text, "IGUI_MQ_Admin_HordePresetDelAsk1|1\nIGUI_MQ_Admin_HordeWindowShort|")
        and has(d.text, "IGUI_MQ_Admin_AfterApply"), "Delete asks first (danger): the windows that move to the default, apply to take effect")
    answer(false)
    T.check(AM.get(P.S, "hordes.presets.p2") ~= nil and AM.get(P.S, "hordes.windows")[1].preset == "p2", "Keep: nothing changes")
    press("pre:del")
    answer(true)
    T.check(AM.get(P.S, "hordes.presets.p2") == nil and P.S.draft.by["hordes.presets.p2"] == nil and AM.get(P.S, "hordes.windows")[1].preset == "default"
        and pg.preset == "default" and options("pre:pick").p2 == nil and has(P.draftSummary, "IGUI_MQ_Admin_HordeSumPresetDel|" .. DEF2),
        "deleted: its window uses the default preset, the draft-only preset just leaves the draft, the page shows the default")
    -- an applied preset gets a del, and the edits made under it go
    pick("pre:pick", "hard")
    field("hordes.presets.hard.cap"):setText("950")
    pick("pre:pick", "default")
    T.check(P.S.draft.by["hordes.presets.hard.cap"] == 950, "an edit on an applied preset is its own path")
    pick("pre:pick", "hard")
    press("pre:del")
    T.check(dialogs[#dialogs].text == "IGUI_MQ_Admin_HordePresetUnused\n\nIGUI_MQ_Admin_AfterApply", "no window on it: the dialog says so")
    answer(true)
    T.check(P.S.draft.by["hordes.presets.hard"] == AM.DEL and P.S.draft.by["hordes.presets.hard.cap"] == nil and options("pre:pick").hard == nil,
        "an applied preset: a del change; the edit under it is dropped")
    -- names: blank or the same as another preset's shown name stops Apply on that preset
    pick("pre:pick", "p3")
    field("hordes.presets.p3.name"):setText("  ")
    previews = count("cfg.preview")
    pick("pre:pick", "default")
    A.onPreview(P)
    T.check(count("cfg.preview") == previews and P.msg == "IGUI_MQ_Admin_HordeErrPresetName" and pg.preset == "p3"
        and field("hordes.presets.p3.name").invalid ~= nil, "a blank name stops Apply; the page shows that preset with its name marked")
    field("hordes.presets.p3.name"):setText(DEF)
    A.onPreview(P)
    T.check(count("cfg.preview") == previews and P.msg == "IGUI_MQ_Admin_HordeErrPresetSame|" .. DEF,
        "a name that reads like another preset (the default one's shown name) stops Apply")
    field("hordes.presets.p3.name"):setText("Night")
    A.onPreview(P)
    T.check(count("cfg.preview") == previews + 1 and AM.get(P.S, "hordes.presets.p3.name") == "Night"
        and field("hordes.presets.p3.name").invalid == nil, "a free name: the preview goes out, the name loses its mark")
    A.onConfirmCancel(P)
    -- 8 presets: copy off, the limit in the warning colour
    for _ = 1, 8 do press("pre:copy") end
    local nIds = 0
    for _ in pairs(options("pre:pick")) do nIds = nIds + 1 end
    T.check(nIds == Q.Contract.LIMIT.MAX_PRESETS and not pool()["pre:copy"]:isEnabled() and token("pre:max") == "warning"
        and pool()["pre:max"].lines[1] == "IGUI_MQ_Admin_HordePresetsMax|8", "8 presets: Copy is off, the limit in the warning colour")
    A.discard(P)
    T.check(pg.preset == "default" and pool()["pre:pick"].selected == "default", "discarded: a draft-only preset gone, the page is back on the default one")
    P.S.overrides.hordes = nil
    A.resync(P)
    -- an applied, complete preset other than the default (the server fills and checks it): removing a built-in kind
    -- writes 0 like on the default one, never a del that would leave the preset without the key (review r1 C1)
    P.S.overrides.hordes = { presets = { p2 = { name = "Night2", waves = { { base = 10, perPlayer = 0 } },
        kinds = { vanilla = 60, runner = 40 }, points = { vanilla = 5, runner = 8 }, hp = {}, limitMin = 15, restSec = 30,
        maxAlive = 200, cap = 500 } } }
    A.resync(P)
    pick("pre:pick", "p2")
    press("ks:r:vanilla")
    press("ks:r:runner")
    T.check(P.S.draft.by["hordes.presets.p2.kinds.vanilla"] == 0 and P.S.draft.by["hordes.presets.p2.kinds.runner"] == 0
        and P.S.draft.by["hordes.presets.p2.points.vanilla"] == nil and P.S.draft.by["hordes.presets.p2.points.runner"] == nil,
        "an applied p2 losing its regular and runner zombies: weights 0 in the draft, points kept, no del")
    A.discard(P)
    -- deleted in the draft, an applied preset is still named by its applied name (the preview's before side, r1 C5)
    pick("pre:pick", "p2")
    press("pre:del")
    answer(true)
    T.check(P.S.draft.by["hordes.presets.p2"] == AM.DEL and A.hordePresetName(P, "p2") == "Night2",
        "a preset deleted in the draft keeps its applied name for the preview")
    A.discard(P)
    -- a name blanked (the check stops Apply, the blank stays in the draft) and typed back: nothing is left to apply
    -- (quest-ui-*-1028e: the bar said Apply (1) and the confirm view opened)
    pick("pre:pick", "p2")
    field("hordes.presets.p2.name"):setText("")
    A.onPreview(P)
    local blocked = P.msg == "IGUI_MQ_Admin_HordeErrPresetName" and AM.draftCount(P.S.draft) == 1
    field("hordes.presets.p2.name"):setText("Night2")
    A.onPreview(P)
    T.check(blocked and AM.draftCount(P.S.draft) == 0 and P.msg == "IGUI_MQ_Admin_NoChanges" and P.confirm == nil,
        "a name blanked and typed back: nothing left to apply")
    P.S.overrides.hordes = nil
    A.resync(P)
    -- the server's refusals name the window or say the limit
    T.check(A.codeText(P, { code = "BAD_CONFIG", detail = { why = "preset", path = "hordes.windows.2.preset" } })
        == "IGUI_MQ_Admin_BadConfig|IGUI_MQ_Admin_F_hordes_windows 2|IGUI_MQ_Admin_Why_preset"
        and A.codeText(P, { code = "BAD_CONFIG", detail = { why = "presets" } }) == "IGUI_MQ_Admin_Why_presets",
        "a window on a missing preset names the window and how to fix it; too many presets says the limit")
    T.check(A.pathLabel(P, "hordes.presets.default.kinds.runner") == PR .. "IGUI_MQ_Admin_F_hordes_kinds - IGUI_MQ_Horde_Kind_runner"
        and A.hordeRow(P, { path = "hordes.presets.p5", before = { name = "Old" } }, "x").label == "IGUI_MQ_Admin_HordePresetDelRow|Old",
        "a refused or previewed preset path names the preset; a deleted preset reads Delete preset")

    T.section("horde admin: spots through the draft, the Map button")
    local before = count("towns.here")
    press("sp:add")
    T.check(count("towns.here") == before and P.msg == "IGUI_MQ_Admin_ErrName" and pool()["sp:name"].invalid ~= nil,
        "no name: nothing asked, the name is marked")
    pool()["sp:name"]:setText("  Gas\tstation ")
    press("sp:add")
    local spots = AM.get(P.S, "hordes.spots")
    T.check(count("towns.here") == before + 1 and #spots == 1 and spots[1].name == "Gasstation" and spots[1].x == 10620
        and spots[1].y == 9810 and spots[1].z == 0 and pool()["sp:name"]:getText() == "",
        "towns.here adds { name, x, y, z } to hordes.spots (control chars and spaces trimmed)")
    T.check(has(P.draftSummary, "IGUI_MQ_Admin_HordeSumSpotAdd|Gasstation") and shown("pl1") and not shown("p:0"),
        "the summary names it, the list shows it")
    local shownBefore = #T.mapShown
    T.check(shown("pm1") and pool()["pm1"].opts.title == "IGUI_MQ_UI_Map" and pool()["pm1"].tooltip == "IGUI_MQ_UI_ShowOnMap",
        "a spot row has a Map button")
    press("pm1")
    local m = T.mapShown[#T.mapShown]
    T.check(#T.mapShown == shownBefore + 1 and m.x == 10620 and m.y == 9810 and m.zoom == 16, "Map opens the world map on the spot")
    T.mapAllowed = false
    A.layout(P)
    T.check(not shown("pm1") and shown("pr1"), "the server turned the map off: no Map button, Remove stays")
    T.mapAllowed = true
    pool()["sp:name"]:setText("School")
    press("sp:add")
    press("pr1")
    d = dialogs[#dialogs]
    T.check(d.danger and d.title == "IGUI_MQ_Admin_HordeSpotDelTitle|Gasstation" and d.confirmText == "IGUI_MQ_Admin_HordeSpotDel"
        and d.cancelText == "IGUI_MQ_Admin_Keep" and d.text == "IGUI_MQ_Admin_HordeSpotDelAsk\n\nIGUI_MQ_Admin_AfterApply"
        and #AM.get(P.S, "hordes.spots") == 2, "Remove asks first (danger): coming back means walking there again")
    answer(false)
    T.check(#AM.get(P.S, "hordes.spots") == 2, "Keep: the spot stays")
    press("pr1")
    answer(true)
    spots = AM.get(P.S, "hordes.spots")
    T.check(#spots == 1 and spots[1].name == "School" and has(P.draftSummary, "IGUI_MQ_Admin_HordeSumSpotDel|Gasstation"),
        "confirmed: Remove drops that spot from the draft")
    -- 2026-10-26 playtest: Start a horde pressed three times with the spot only in the draft got "add a spot first"
    -- while the list showed it
    local sentNow, askedNow = count("horde.now"), #dialogs
    press("now")
    T.check(P.msg == "IGUI_MQ_Admin_HordeSpotsUnapplied" and count("horde.now") == sentNow and #dialogs == askedNow,
        "Start a horde with the spots only in the draft: says to apply first, nothing asked or sent")
    P.S.overrides.hordes = { spots = { { name = "Gas", x = 10620, y = 9810, z = 0 } } }
    press("now")
    T.check(#dialogs == askedNow + 1 and dialogs[#dialogs].confirmText == "IGUI_MQ_Admin_HordeNow",
        "an applied spot plus one more in the draft: Start a horde asks as usual")
    answer(false)
    P.S.overrides.hordes = nil
    local full = {}
    for i = 1, AM.MAX_SPOTS do full[i] = { name = "s" .. i, x = i, y = i, z = 0 } end
    AM.draftSet(P.S.draft, "hordes.spots", full)
    A.layout(P)
    T.check(not pool()["sp:add"]:isEnabled() and shown("pmax"), "32 spots: the add button is off and says why")
    A.onPreview(P)
    changes = Q.Util.decode(last("cfg.preview").changes)
    T.check(#changes == 1 and changes[1].path == "hordes.spots" and #changes[1].value == 32, "spots are one whole-set change")
    A.onConfirmCancel(P)
    A.discard(P)
    T.check(A.summaryText("horde.now 7 Gas station") == "IGUI_MQ_Admin_HordeHistNow|Gas station"
        and A.summaryText("horde.stop 7") == "IGUI_MQ_Admin_HordeHistStop|#7", "history rows of horde.now / horde.stop are translated")
    T.check(not T.printed("admin layout"), "no layout error on the hordes tab")
    local closed = hf.L == nil and #hf.lists > 0
    for _, L in ipairs(hf.lists) do closed = closed and L.h ~= nil end
    T.check(closed, "the hordes tab closes every list box it opens")
    T.section("admin ui: settings changed elsewhere (catalog push, reopen, CONFIG_CHANGED, undo)")
    -- 2026-10-28: config.json moved the horde spots while an open panel kept listing the old ones, and a spot removed
    -- there would have sent the old list back
    local function spotsAt(rev, list, extra)
        return function()
            local o = { hordes = { spots = T.deepcopy(list) } }
            for k, v in pairs(extra or {}) do o.hordes[k] = T.deepcopy(v) end
            return { overrides = o, history = {}, rev = rev, file = { ok = true, at = now } }
        end
    end
    -- what Client.H.catalog does: keep the latest push, then tell the listeners
    local function push(rev, overrides)
        Cl.catalog = { rev = rev, overrides = overrides }
        Cl.emit("catalog", Cl.catalog)
    end
    local function spotName(i) local l = pool()["pl" .. i]; return l ~= nil and l:isVisible() and l.lines and l.lines[1] or nil end
    local oldS = { { name = "Old", x = 1, y = 1, z = 0 } }
    local newS = { { name = "New", x = 2, y = 2, z = 0 }, { name = "New2", x = 3, y = 3, z = 0 } }
    local function hz(spots, extra)
        local h = { spots = T.deepcopy(spots), maxPerDay = 2, enabled = false }
        for k, v in pairs(extra or {}) do h[k] = v end
        return { hordes = h }
    end
    local rest = { maxPerDay = 2, enabled = false }
    local okPreview = replies["cfg.preview"]
    replies["cfg.get"] = spotsAt(5, oldS)
    A.onReload(P)
    T.check(P.rev == 5 and P.baseRev == 5 and P.historyRev == 5 and spotName(1) == "Old", "loaded at rev 5: the old spot")
    push(6, { hordes = { spots = T.deepcopy(newS) } })
    T.check(P.rev == 6 and P.baseRev == 6 and P.historyRev == 5 and spotName(1) == "New" and spotName(2) == "New2",
        "a write elsewhere (the catalog push, rev 6): the open panel lists the new spots at once; its history list stays on rev 5")
    push(6, { hordes = { spots = T.deepcopy(oldS) } })
    T.check(spotName(1) == "New", "a push of the rev already shown changes nothing")
    field("hordes.maxPerDay"):setText("4")
    push(7, hz(newS))
    T.check(P.rev == 7 and P.baseRev == 6 and AM.get(P.S, "hordes.maxPerDay") == 4 and field("hordes.maxPerDay"):getText() == "4",
        "a value being typed survives a push; the push set that same path, so the draft stays on rev 6")
    A.discard(P)
    T.check(P.baseRev == 7, "discarded: the next draft starts on the settings shown")
    field("hordes.maxPerDay"):setText("3")
    push(8, hz(newS))
    T.check(P.rev == 8 and P.baseRev == 8 and AM.get(P.S, "hordes.maxPerDay") == 3,
        "a push that leaves the draft's paths alone: the draft moves on to rev 8 (review r1: a write elsewhere cost the whole draft)")
    A.discard(P)
    press("pr1")
    answer(true)
    push(9, hz(oldS))
    local draftSpots = AM.get(P.S, "hordes.spots")
    T.check(P.rev == 9 and P.baseRev == 8 and #draftSpots == 1 and draftSpots[1].name == "New2",
        "a spot removed, then a write to the spots: the draft (the whole list as it was on rev 8) stays on rev 8")
    local gets = count("cfg.get")
    replies["cfg.preview"] = function() return { ok = false, code = "CONFIG_CHANGED", rev = 9 } end
    replies["cfg.get"] = spotsAt(9, oldS, rest)
    A.onPreview(P)
    T.check(last("cfg.preview").rev == 8 and AM.draftCount(P.S.draft) == 0 and P.confirm == nil and count("cfg.get") == gets + 1
        and has(P.msg, "IGUI_MQ_Admin_DraftDropped1") and spotName(1) == "Old" and not spotName(2) and P.baseRev == 9,
        "its Apply carries rev 8 and is refused: the draft goes, the panel reloads the spots in effect, the bar says an edit went")
    replies["cfg.preview"] = okPreview
    field("hordes.maxPerDay"):setText("5")
    A.onPreview(P)
    T.check(P.confirm ~= nil and P.confirm.rev == 9 and last("cfg.preview").rev == 9, "a fresh draft previews on rev 9")
    push(10, hz(newS))
    T.check(P.confirm ~= nil and P.rev == 10 and P.baseRev == 10 and P.confirm.rev == 10,
        "a push under the confirm view that leaves its changes alone: taken, the view and the draft move to rev 10 (review r1, r2)")
    replies["cfg.apply"] = function() return { historyId = 10, rev = 11 } end
    replies["cfg.get"] = spotsAt(11, newS, { maxPerDay = 5, enabled = false })
    A.onConfirmApply(P)
    T.check(last("cfg.apply").rev == 10 and P.confirm == nil and AM.draftCount(P.S.draft) == 0 and P.rev == 11,
        "so its first Apply carries rev 10 and goes through (review r2: it was refused once)")
    field("hordes.maxPerDay"):setText("6")
    A.onPreview(P)
    push(12, hz(newS, { maxPerDay = 7 }))
    T.check(P.confirm ~= nil and P.rev == 12 and P.baseRev == 11 and P.confirm.rev == 11,
        "a write to the draft's own path under the confirm view: the view and the draft stay on rev 11")
    replies["cfg.apply"] = function() return { ok = false, code = "CONFIG_CHANGED", rev = 12 } end
    replies["cfg.get"] = spotsAt(12, newS, { maxPerDay = 7, enabled = false })
    A.onConfirmApply(P)
    T.check(AM.draftCount(P.S.draft) == 0 and field("hordes.maxPerDay"):getText() == "7" and has(P.msg, "IGUI_MQ_Admin_DraftDropped1"),
        "so its Apply is refused and the draft goes; the bar says so (review r2: it only said try again)")
    -- a change not from the draft (a suggestion) whose path a write sets: refused, while the draft beside it stays
    local function withRate(fn, rate) return function() local r = fn(); r.overrides.exchange = { rate = rate }; return r end end
    field("hordes.maxPerDay"):setText("8")
    A.fold(P)
    A.previewChanges(P, { { op = "set", path = "exchange.rate", value = 1 } }, "x", {})
    T.check(P.confirm ~= nil and P.confirm.rev == 12 and last("cfg.preview").rev == 12, "a change not from the draft previews on the settings shown")
    local o13 = hz(newS, { maxPerDay = 7 })
    o13.exchange = { rate = 7.25 }
    push(13, o13)
    T.check(P.rev == 13 and P.baseRev == 13 and P.confirm.rev == 12, "a write to its path: the view stays on rev 12, the draft beside it moves on")
    replies["cfg.apply"] = function() return { ok = false, code = "CONFIG_CHANGED", rev = 13 } end
    replies["cfg.get"] = withRate(spotsAt(13, newS, { maxPerDay = 7, enabled = false }), 7.25)
    A.onConfirmApply(P)
    T.check(last("cfg.apply").rev == 12 and AM.get(P.S, "hordes.maxPerDay") == 8 and has(P.msg, "CONFIG_CHANGED")
        and not has(P.msg, "DraftDropped"), "its Apply is refused; the draft, on rev 13, stays and the bar says try again")
    -- this panel's own writes, the push before the reply as the server sends them: the draft moves on when they leave its
    -- paths alone, not when they set them (review r1: an undo putting the spots back, then the draft's old list applied)
    replies["cfg.apply"] = function()
        local o = hz(newS, { maxPerDay = 7 })
        o.exchange = { rate = 1 }
        push(14, o)
        return { historyId = 14, rev = 14 }
    end
    replies["cfg.get"] = withRate(spotsAt(14, newS, { maxPerDay = 7, enabled = false }), 1)
    A.previewChanges(P, { { op = "set", path = "exchange.rate", value = 1 } }, "x", {})
    A.onConfirmApply(P)
    T.check(P.rev == 14 and P.baseRev == 14 and AM.draftCount(P.S.draft) == 1 and P.historyRev == 14,
        "its own Apply left the draft's path alone: the draft moves to rev 14")
    A.discard(P)
    press("pr1")
    answer(true)
    replies["cfg.undo"] = function() push(15, hz(oldS, { maxPerDay = 7 })); return { historyId = 15, rev = 15 } end
    replies["cfg.get"] = spotsAt(15, oldS, { maxPerDay = 7, enabled = false })
    A.onUndo(P, { entry = { id = 4, at = now, summary = "s" } })
    answer(true)
    T.check(last("cfg.undo").rev == 14 and P.rev == 15 and P.baseRev == 14,
        "an undo of its own that sets the spots back: the spot draft stays on rev 14 (applied, the removed spot came back)")
    A.onPreview(P)
    T.check(last("cfg.preview").rev == 14, "so its Apply carries rev 14, which the server refuses")
    A.onConfirmCancel(P)
    A.discard(P)
    push(16, hz(newS, { maxPerDay = 7 }))
    gets = count("cfg.get")
    replies["cfg.undo"] = function() return { ok = false, code = "CONFIG_CHANGED", rev = 16 } end
    replies["cfg.get"] = spotsAt(16, newS, { maxPerDay = 7, enabled = false })
    A.onUndo(P, { entry = { id = 4, at = now, summary = "s" } })
    answer(true)
    T.check(last("cfg.undo").rev == 15 and has(P.msg, "CONFIG_CHANGED") and count("cfg.get") == gets + 1 and P.historyRev == 16,
        "an undo from a list loaded before a push carries the list's rev (15, not the 16 shown): refused, the list reloads")
    -- Remove on a spot asks first; a push while the dialog is open relays the rows under it (review r2)
    local other = { name = "Other", x = 9, y = 9, z = 0 }
    press("pr1")
    push(17, hz({ other, newS[1], newS[2] }, { maxPerDay = 7 }))
    answer(true)
    local ds = AM.get(P.S, "hordes.spots")
    T.check(#ds == 2 and ds[1].name == "Other" and ds[2].name == "New2",
        "a push while the Remove dialog is open: the spot asked about goes, not the one now in its row")
    A.discard(P)
    press("pr2")
    push(18, hz({ newS[2] }, { maxPerDay = 7 }))
    answer(true)
    T.check(AM.draftCount(P.S.draft) == 0, "the spot asked about was removed elsewhere meanwhile: nothing changes")
    -- a field invalid: the push waits; a button that edits a list by its row works on the rows shown (review r2: a push
    -- taken under the click moved the rows, and the wrong window went)
    local W1 = { days = "1234567", from = "19:00", to = "23:00", chance = 40, preset = "default", leadMin = 15, waitMin = 60 }
    local W2 = { days = "67", from = "20:00", to = "22:00", chance = 30, preset = "default", leadMin = 15, waitMin = 60 }
    push(19, hz({ newS[2] }, { maxPerDay = 7, windows = { W1, W2 } }))
    field("hordes.maxPerDay"):setText("x")
    push(20, hz({ newS[2] }, { maxPerDay = 7, windows = { W2 } }))
    T.check(P.rev == 19 and field("hordes.maxPerDay"):getText() == "x", "a field invalid: the push waits, nothing reloads under the typing")
    field("hordes.maxPerDay"):setText("8")
    press("w:r2")
    local dw = AM.get(P.S, "hordes.windows")
    T.check(P.rev == 19 and #dw == 1 and dw[1].chance == 40, "fixed, then Remove on the second window: the window shown goes")
    replies["cfg.preview"] = function() return { ok = false, code = "CONFIG_CHANGED", rev = 20 } end
    replies["cfg.get"] = spotsAt(20, { newS[2] }, { maxPerDay = 7, enabled = false, windows = { W2 } })
    A.onPreview(P)
    T.check(P.rev == 20 and last("cfg.preview").rev == 19 and AM.draftCount(P.S.draft) == 0 and has(P.msg, "IGUI_MQ_Admin_DraftDropped|2"),
        "then Apply takes the waiting push first: the windows changed under the draft, so its 2 edits go and the bar says so")
    replies["cfg.preview"] = okPreview
    field("hordes.maxPerDay"):setText("x")
    push(21, hz({ newS[2] }, { maxPerDay = 7, windows = { W1 } }))
    field("hordes.maxPerDay"):setText("8")
    A.select(P, "basic")
    T.check(P.rev == 21 and P.baseRev == 21 and AM.get(P.S, "hordes.maxPerDay") == 8,
        "fixed, then a tab switch: the waiting push is taken, the draft's path alone, so the draft moves on")
    A.select(P, "hordes")
    A.discard(P)
    local pid = P.pages.hordes.preset or "default"
    local hpKey = "hordes.presets." .. pid .. ".hp.vanilla"
    push(22, hz({ newS[2] }, { maxPerDay = 7, presets = { [pid] = { hp = { vanilla = 1.125 } } } }))
    T.check(field(hpKey) ~= nil and field(hpKey):getText() == "1.125" and A.fold(P) and AM.draftCount(P.S.draft) == 0,
        "a toughness of 1.125 shows as itself (review r2: it showed 1.13); left as it is, a fold adds no edit")
    field(hpKey):setText("1.13")
    A.fold(P)
    T.check(AM.get(P.S, hpKey) == 1.13, "1.13 typed over it is an edit (review r2: it read as untouched)")
    A.discard(P)
    push(23, hz({ newS[2] }, { maxPerDay = 7, presets = { [pid] = { hp = { vanilla = 1.23456 } } } }))
    T.check(field(hpKey):getText() == "1.2346" and A.fold(P) and AM.draftCount(P.S.draft) == 0,
        "past 4 places it shows rounded; left as it is, still no edit (review r1)")
    replies["cfg.get"] = function() return { ok = false, code = "NO_REPLY" } end
    A.onReload(P)
    T.check(has(P.msg, "IGUI_MQ_Admin_NoReply") and P.rev == 23,
        "a reload that fails with settings shown: the bar says so (review r1: nothing showed)")
    -- after a refusal its reason stays in front of a failed reload's: what the refusal dropped is said there (review r2)
    A.say(P, A.count("IGUI_MQ_Admin_DraftDropped", 1), "errorText")
    A.loadConfig(P)
    T.check(has(P.msg, "IGUI_MQ_Admin_DraftDropped1") and has(P.msg, "IGUI_MQ_Admin_NoReply"),
        "a reload failing after a refusal: the bar keeps the refusal and adds the failure")
    replies["cfg.get"] = spotsAt(22, newS)
    A.onReload(P)
    T.check(P.rev == 23 and spotName(1) == "New2" and P.historyRev == 22,
        "a cfg.get reply older than a push already taken: the push follows it, the reply's history list stays (at its rev)")
    -- the client kept a push newer than a reply on its way (sent before a write it did not see; the panel hidden)
    Cl.catalog = { rev = 25, overrides = hz(oldS, { maxPerDay = 7 }) }
    replies["cfg.get"] = spotsAt(24, newS)
    A.onReload(P)
    T.check(P.rev == 25 and spotName(1) == "Old", "a cfg.get reply older than the client's latest push: that push follows it (review r2)")
    A.hide()
    push(26, { hordes = { spots = T.deepcopy(newS) } })
    T.check(P.rev == 25, "hidden: the push waits")
    gets = count("cfg.get")
    A.show(P.host)
    T.check(P.rev == 26 and spotName(1) == "New" and count("cfg.get") == gets,
        "reopened right after a cfg.get: the push from while hidden shows; no cfg.get the server's cooldown would drop")
    A.hide()
    local t0 = T.now
    T.advance(2 * Q.Contract.LIMIT.COOLDOWN_MS)
    replies["cfg.get"] = spotsAt(27, oldS)
    A.show(P.host)
    T.check(count("cfg.get") == gets + 1 and P.rev == 27 and spotName(1) == "Old",
        "reopened later: settings, history and config.json state are fetched again")
    T.now = t0
    -- a field invalid while a push leaves the draft alone: fixed, then Apply takes the push first, on its rev (review r1)
    field("hordes.maxPerDay"):setText("x")
    push(28, { hordes = { spots = T.deepcopy(oldS), enabled = true } })
    field("hordes.maxPerDay"):setText("9")
    A.onPreview(P)
    T.check(P.rev == 28 and P.baseRev == 28 and last("cfg.preview").rev == 28,
        "fixed, then Apply: the waiting push is taken first and the preview carries rev 28")
    A.onConfirmCancel(P)
    A.discard(P)
    replies["cfg.apply"], replies["cfg.undo"] = nil, nil
    Cl.catalog = nil
    Cl.invalidate()
    A.hide()
    A.instance = nil

    -- ===== player side (hordes v2: waves, rest, labelled countdowns, the Map button) =====
    local kinds = { { id = "vanilla", nameKey = "IGUI_MQ_Horde_Kind_vanilla" }, { id = "runner", nameKey = "IGUI_MQ_Horde_Kind_runner" } }
    local function cur(state, extra)
        local c = { id = 3, name = "Gas", town = "muldraugh", x = 10620, y = 9810, z = 0, state = state, kinds = kinds,
            startMs = now + 15 * 60000, expireAt = now + 75 * 60000, endsAt = now + 600000, nextAt = now + 24000,
            wave = 1, waves = 1, size = 30, left = 13, killed = 17, limitMin = 15, mine = 9, got = 0, joined = 12 }
        for k, v in pairs(extra or {}) do c[k] = v end
        return c
    end
    local place = "IGUI_MQ_Horde_Place|Gas|IGUI_MQ_Town_muldraugh"
    local Hd, PD, E = Q.Hud, Q.PageDaily, Q.Entry
    local defs = Cl.defs()
    local worldMap = ISWorldMap
    T.mapAllowed, T.mapShown = true, {}
    local function row(state, extra) return Hd.rows({ hordes = { cur = cur(state, extra) } }, defs, now)[1] end

    T.section("horde tracker row")
    local r = Hd.rows({ pins = {}, hordes = { cur = cur("active") } }, defs, now)
    T.check(#r == 1 and r[1].horde and r[1].name == place and r[1].time == "IGUI_MQ_UI_Left|10:00" and r[1].prog == 17
        and r[1].target == 30 and r[1].line == "IGUI_MQ_Horde_HudActive|12|17|30" and r[1].mapX == 10620 and r[1].hordeId == 3,
        "active: the place, 'left' to endsAt, who joined (1+ kill) and cleared / wave size, a Map button (plan-horde-result 1)")
    r = row("waiting")
    T.check(r.name == place and r.time == "IGUI_MQ_Horde_WaitLeft|1:15:00" and r.line == "IGUI_MQ_Horde_HudWait|10620|9810"
        and r.target == nil and r.mapX == 10620 and r.mapY == 9810, "waiting: 'waiting' to expireAt (not 'left'), the spot first, Map button")
    r = row("announced", { waves = 3 })
    T.check(r.name == place and r.time == "IGUI_MQ_Horde_StartsIn|15:00" and r.line == "IGUI_MQ_Horde_HudSoon|10620|9810"
        and r.mapX == 10620, "announced: no wave prefix, 'starts in' countdown, the spot first, Map button")
    r = row("rest", { wave = 2, waves = 3, left = 0 })
    T.check(r.name == "IGUI_MQ_Horde_WaveDone|2|3|Gas" and r.time == "IGUI_MQ_Horde_NextIn|0:24"
        and r.line == "IGUI_MQ_Horde_HudRest|3" and r.target == nil and r.mapX == 10620,
        "rest: 'wave 2/3 cleared', 'next wave in' countdown, the next wave comes from the edges, Map button")
    T.check(row("waiting", { wave = 1, waves = 3 }).name == "IGUI_MQ_Horde_Wave|1|3|Gas"
        and row("active", { wave = 2, waves = 3 }).name == "IGUI_MQ_Horde_Wave|2|3|Gas"
        and row("waiting", { waves = 1 }).name == place and row("active", { waves = nil }).name == place,
        "'Wave W/N' and the spot without its town in front only when N > 1")
    T.mapAllowed = false
    T.check(row("announced").mapX == nil and row("waiting").mapX == nil and row("rest", { waves = 2 }).mapX == nil,
        "the sandbox turns the world map off: no Map button")
    T.mapAllowed, ISWorldMap = true, nil
    T.check(row("waiting").mapX == nil and D.mapAllowed() == false and D.showOnMap(0, 1, 2) == false and #T.mapShown == 0,
        "no ISWorldMap: no button, showOnMap refuses")
    ISWorldMap = worldMap
    T.check(#Hd.rows({ hordes = { cur = cur("planned") } }, defs, now) == 0 and #Hd.rows({ hordes = {} }, defs, now) == 0,
        "planned (not announced yet) or no cur: no row")
    T.check(D.countdown(0) == "0:00" and D.countdown(1500) == "0:02" and D.countdown(3723000) == "1:02:03", "countdown text")
    -- line 2 keeps the coordinates when a long language cuts it (design 5.2): %1, %2 open the text in every language
    local notFirst = {}
    for _, lang in ipairs({ "AR", "CH", "CN", "DE", "EN", "ES", "ES_CL", "ES_MX", "FR", "JP", "KO", "PL", "PT", "PTBR", "RU", "TR" }) do
        local f = io.open(T.MEDIA .. "/shared/Translate/" .. lang .. "/IG_UI.json", "r")
        local src = f and f:read("a") or ""
        if f then f:close() end
        for _, key in ipairs({ "IGUI_MQ_Horde_HudSoon", "IGUI_MQ_Horde_HudWait" }) do
            local v = string.match(src, '"' .. key .. '"%s*:%s*"([^"]*)"')
            if v == nil or string.find(v, "^%%1, %%2") == nil then notFirst[#notFirst + 1] = lang .. " " .. key end
        end
    end
    T.check(#notFirst == 0, "tracker line 2 starts with the coordinates in all 16 languages " .. table.concat(notFirst, ", "))

    -- the panel's own layout: the horde row is on top, no unpin x, and the count is pins only
    local hp = { x = 0, y = 0, width = 300, height = 10, UI = UI, theme = { colors = colors } }
    function hp:setHeight(h) self.height = h end
    function hp:setX(v) self.x = v end
    function hp:setY(v) self.y = v end
    local function drewOp(s)
        for i = 1, hp.n do if hp.ops[i].s == s then return hp.ops[i] end end
        return nil
    end
    local cat = Q.Catalog
    local quests = {}
    for i = 1, 4 do quests[i] = { tid = cat.daily[i].tid, target = 10, prog = 1, pts = 5, state = "active" } end
    Cl.state = { pins = { "d1", "d2", "d3", "d4", "w1" }, day = { quests = quests },
        week = { quests = { { tid = cat.weekly[1].tid, target = 10, prog = 1, pts = 5, state = "active" } } }, hordes = { cur = cur("active") } }
    Hd.layout(hp)
    local countText = nil
    for i = 1, hp.n do if has(hp.ops[i].s, "IGUI_MQ_UI_Count|") then countText = hp.ops[i].s end end
    T.check(#hp.rows == 6 and hp.rows[1].horde and #hp.hits == 5 and countText == "IGUI_MQ_UI_Count|5|5"
        and hp.hordeTime == "IGUI_MQ_UI_Left|10:00" and hp.mapHit ~= nil and drewOp("IGUI_MQ_UI_Map") ~= nil,
        "five pins and an active horde: six rows, five unpin targets, the title still counts 5 / 5, a Map button")
    local function barOnLine2()
        for i = 1, hp.n do
            local o = hp.ops[i]
            if o.k == 8 and o.y > Hd.titleH() + D.chipH() and o.y < hp.mapHit.y1 then return o end
        end
        return nil
    end
    local narrow = hp.width
    hp.width = 400   -- the harness font is wide (7 px a char): 300 px leave no 24 px for the bar
    Hd.layout(hp)
    local barOp, cntOp = barOnLine2(), drewOp("IGUI_MQ_Horde_HudActive|12|17|30")   -- right-aligned: x is its right edge
    T.check(cntOp ~= nil and cntOp.x <= hp.mapHit.x0 - 6 and barOp ~= nil and barOp.x == Hd.PAD
        and barOp.x + barOp.w + 8 <= cntOp.x - cntOp.w, "active line 2: the count left of the Map button, the bar takes what is left")
    hp.width = 150
    Hd.layout(hp)
    local cut = drewOp("IGUI_MQ_Horde_HudActive|12|17|30")
    T.check(barOnLine2() == nil and cut ~= nil and cut.k == 3 and cut.x == Hd.PAD and hp.mapHit ~= nil,
        "a narrow panel: the count cut from the left edge (not right-aligned past it), no bar, the Map button (C5)")
    hp.width = narrow
    Cl.state.hordes = { cur = cur("waiting") }
    Hd.layout(hp)
    local m, label = hp.mapHit, drewOp("IGUI_MQ_UI_Map")
    local tip = nil
    for _, t in ipairs(hp.tips) do if t.text == "IGUI_MQ_UI_ShowOnMap" then tip = t end end
    T.check(#hp.hits == 5 and m ~= nil and label ~= nil and m.x1 == hp.width - Hd.PAD and label.y > Hd.titleH() + D.chipH()
        and tip ~= nil and tip.x == m.x0 and tip.y == label.y - 1,
        "waiting: a Map button at the right of line 2 with its hover text; still five unpin targets")
    local hx = hp.hideHit
    T.check(m.y1 - m.y0 >= 24 and m.y1 <= hp.hits[1].y0 and hx ~= nil and hx.y1 <= m.y0,
        "the Map hit box is 24 px tall, between the horde x above and the next row's unpin below (review 4)")
    local lineOp = drewOp("IGUI_MQ_Horde_HudWait|10620|9810")
    T.check(lineOp ~= nil and lineOp.x == Hd.PAD and lineOp.y == label.y, "line 2: the spot text left of the button")
    T.check(Hd.onMouseDown(hp, m.x0 + 2, m.y0 + 2) == true and #T.mapShown == 1 and T.mapShown[1].playerNum == 0
        and T.mapShown[1].x == 10620 and T.mapShown[1].y == 9810 and T.mapShown[1].zoom == 16,
        "a click on Map opens the world map on the spot")
    T.mapAllowed = false
    Hd.layout(hp)
    T.check(hp.mapHit == nil and drewOp("IGUI_MQ_UI_Map") == nil and #hp.hits == 5, "map not allowed: the button is gone")
    T.mapAllowed, T.mapShown = true, {}
    Cl.state = { pins = {}, hordes = { cur = cur("waiting") } }
    T.check(Hd.wanted(), "no pins but a horde: the panel is wanted")
    Cl.state.hordes = { cur = cur("rest", { waves = 2 }) }
    T.check(Hd.wanted(), "a horde resting between waves keeps the panel")
    Cl.state.hordes = { cur = nil, last = { state = "success" } }
    T.check(not Hd.wanted() and #Hd.rows(Cl.state, defs, now) == 0, "cur gone: no row, no panel without pins")
    Hd.show = false
    Cl.state.hordes = { cur = cur("active") }
    T.check(not Hd.wanted(), "the MOD option still hides it")
    Hd.show = true

    T.section("horde banner on the daily page")
    local function banner(h, l, at)
        return PD.hordeBanner({ hordes = { cur = h, last = l } }, at or now)
    end
    local ann = cur("announced", { waves = 3 })
    local tok, title, body, right, spot = banner(ann)
    T.check(tok == D.EXTRA.hordeSoon and title == "IGUI_MQ_Horde_Title_soon|" .. place
        and has(body, "IGUI_MQ_Horde_SoonBanner|IGUI_MQ_Horde_Kind_vanilla") and has(body, "|10620|9810")
        and right == "IGUI_MQ_Horde_StartsIn|" .. D.duration(15 * 60000) and spot == ann,
        "announced: place, kinds, the 30-tile rule, a 'starts in' countdown (not 'left') and the spot for the Map button")
    tok, title, body, right, spot = banner(cur("waiting", { waves = 3 }))
    T.check(title == "IGUI_MQ_Horde_Title_wait|IGUI_MQ_Horde_Wave|1|3|" .. place and body == "IGUI_MQ_Horde_WaitBody|10620|9810"
        and has(right, "IGUI_MQ_Horde_WaitLeft|") and spot ~= nil, "waiting: wave 1/3, where to go, 'waiting' (not 'left'), Map")
    tok, title, body, right, spot = banner(cur("active", { wave = 2, waves = 3 }))
    T.check(tok == D.EXTRA.horde and title == "IGUI_MQ_Horde_Title_active|IGUI_MQ_Horde_Wave|2|3|" .. place
        and body == "IGUI_MQ_Horde_ActiveBody|17|30|9" and right == "IGUI_MQ_UI_Left|" .. D.duration(600000) and spot ~= nil,
        "active: wave 2/3, cleared / wave size and my kills, no pool, Map (plan-horde-result 1)")
    tok, title, body, right, spot = banner(cur("rest", { wave = 2, waves = 3, left = 0 }))
    T.check(tok == D.EXTRA.hordeSoon and title == "IGUI_MQ_Horde_Title_rest|2|3|" .. place
        and body == "IGUI_MQ_Horde_RestBody|3|10620|9810" and right == "IGUI_MQ_Horde_NextIn|" .. D.duration(24000)
        and spot ~= nil, "rest: wave 2/3 cleared, the next wave and where, 'next wave in', Map")
    T.mapAllowed = false
    T.check(select(5, banner(ann)) == nil, "map not allowed: no spot for a button")
    T.mapAllowed = true
    local lastWin = { id = 3, name = "Gas", town = "muldraugh", state = "success", endedAt = now - 60000, waves = 3, cleared = 3,
        spawned = 325, killed = 325, pool = 500, capped = false, mine = 92, got = 130 }
    tok, title, body, right, spot = banner(nil, lastWin)
    T.check(tok == D.EXTRA.success and title == "IGUI_MQ_Horde_Title_win|" .. place and body == "IGUI_MQ_Horde_WinMine|3|3|92"
        and right == "IGUI_MQ_UI_PlusPoints|130" and spot == nil, "won: waves cleared, my kills, +points, no Map")
    lastWin.capped = true
    T.check(select(3, banner(nil, lastWin)) == "IGUI_MQ_Horde_Join|IGUI_MQ_Horde_WinMine|3|3|92|IGUI_MQ_Horde_Capped",
        "won over the cap: the shares-scaled note")
    lastWin.got, lastWin.mine = nil, 0
    tok, title, body, right = banner(nil, lastWin)
    T.check(body == "IGUI_MQ_Horde_WinOthers|3|3|325" and right == nil, "won without me: who gets points")
    local lastFail = { name = "Gas", state = "failed", why = "time", endedAt = now - 60000, waves = 3, cleared = 2, pool = 130,
        capped = false, mine = 31, got = 44 }
    tok, title, body, right = banner(nil, lastFail)
    T.check(tok == "errorText" and title == "IGUI_MQ_Horde_Title_fail|Gas"
        and body == "IGUI_MQ_Horde_Join|IGUI_MQ_Horde_FailWave|3|IGUI_MQ_Horde_Why_time|IGUI_MQ_Horde_FailPaid|2|130"
        and right == "IGUI_MQ_UI_PlusPoints|44", "failed in wave 3: why, the 2 cleared waves still pay, +my points")
    for _, why in ipairs({ "time", "nobody", "admin", "restart", "spawn" }) do
        tok, title, body, right = banner(nil, { name = "Gas", state = "failed", why = why, endedAt = now - 60000, waves = 1, cleared = 0 })
        T.check(tok == "errorText" and title == "IGUI_MQ_Horde_Title_fail|Gas" and body == "IGUI_MQ_Horde_Why_" .. why
            and right == "IGUI_MQ_Horde_NoReward", "failed (" .. why .. ") with one wave: why, no reward")
    end
    tok, title, body = banner(nil, { name = "Gas", state = "cancelled", endedAt = now - 60000 })
    T.check(title == "IGUI_MQ_Horde_Title_cancel|Gas" and body == "IGUI_MQ_Horde_CancelBody", "cancelled")
    T.check(banner(nil, { name = "Gas", state = "failed", why = "time", endedAt = now - PD.LAST_MS + 1000 }) ~= nil
        and banner(nil, { name = "Gas", state = "failed", why = "time", endedAt = now - PD.LAST_MS }) == nil and banner(nil, nil) == nil,
        "the last result shows for 10 minutes only; nothing without a horde")
    T.check(banner(cur("planned"), lastWin) ~= nil and select(2, banner(cur("active"), lastWin)) == "IGUI_MQ_Horde_Title_active|" .. place,
        "a live horde wins over the last result")
    -- the banner block (daily and Hordes pages): pooled Map and tracker toggle buttons at the bottom right
    local par = setmetatable({}, { __index = Base })
    local pg = { UI = UI, theme = { colors = colors }, pool = D.pool(par) }
    local bb = D.begin({ UI = UI, theme = pg.theme })
    pg.pool:begin()
    local ny = PD.hordeBlock(pg, bb, 10, 20, 400, { hordes = { cur = cur("waiting") } })
    pg.pool:finish()
    local mb, hb = pg.pool.items.hordeMap, pg.pool.items.hordeHud
    T.check(mb ~= nil and mb.visible ~= false and mb.opts.title == "IGUI_MQ_UI_Map" and mb.tooltip == "IGUI_MQ_UI_ShowOnMap"
        and hb ~= nil and hb.opts.title == "IGUI_MQ_Horde_HideHud" and hb.x == 10 + 400 - 10 - hb.width
        and mb.x == hb.x - 6 - mb.width and mb.y == hb.y and mb.y + mb.height + 6 + D.GAP == ny,
        "waiting: Map, then Hide from tracker, inside the banner at the bottom right")
    mb.onclick(mb.target, mb)
    T.check(#T.mapShown == 1 and T.mapShown[1].x == 10620 and T.mapShown[1].y == 9810 and T.mapShown[1].playerNum == 0,
        "the banner's Map opens the world map on the spot")
    pg.pool:begin()
    T.check(PD.hordeBlock(pg, bb, 10, 20, 400, { hordes = { cur = cur("active") } }) ~= nil, "active: the banner")
    pg.pool:finish()
    T.check(mb.visible ~= false and hb.visible ~= false, "active: the Map button and the toggle (plan-horde-result 1)")
    T.mapAllowed = false
    pg.pool:begin()
    PD.hordeBlock(pg, bb, 10, 20, 400, { hordes = { cur = cur("active") } })
    pg.pool:finish()
    T.check(mb.visible == false and hb.visible ~= false and hb.x == 10 + 400 - 10 - hb.width, "map not allowed: the toggle alone")
    T.mapAllowed = true
    pg.pool:begin()
    PD.hordeBlock(pg, bb, 10, 20, 400, { hordes = { cur = nil, last = lastWin } })
    pg.pool:finish()
    T.check(mb.visible == false and hb.visible == false, "an ended horde: no Map, no toggle")
    T.check(PD.hordeBlock(pg, bb, 10, 20, 400, { hordes = {} }) == nil, "no horde: no banner")
    T.mapShown = {}

    T.section("horde toasts")
    local function toast(t) t.kind = t.kind or "horde"; t.name, t.town = "Gas", "muldraugh"; return E.toastText(t) end
    title, body = toast({ ev = "soon", startMs = now + 15 * 60000, kinds = kinds, waves = 3 })
    T.check(title == "IGUI_MQ_Horde_Title_soon|" .. place and has(body, "IGUI_MQ_Horde_SoonBody|15|")
        and has(body, "IGUI_MQ_Horde_Kind_vanilla") and has(body, "IGUI_MQ_Horde_Kind_runner") and has(body, "|3"),
        "soon: minutes to the start, the kinds (no count) and the waves")
    title, body = toast({ ev = "soon", startMs = now - 60000, kinds = kinds, waves = 1 })
    T.check(has(body, "IGUI_MQ_Horde_SoonBody|1|"), "a late warning still says at least 1 minute")
    title, body = toast({ ev = "remind", startMs = now + 2 * 60000 })
    T.check(title == "IGUI_MQ_Horde_Title_remind|2|" .. place and body == "IGUI_MQ_Horde_Remind", "remind: minutes left; get ready or leave")
    title, body = toast({ ev = "open", startMs = now, kinds = { kinds[2] }, waves = 2 })
    T.check(title == "IGUI_MQ_Horde_Title_wait|" .. place and body == "IGUI_MQ_Horde_OpenBody|IGUI_MQ_Horde_Kind_runner|2",
        "open: starts now, the kinds and the waves")
    title, body = toast({ ev = "spawn", wave = 1, waves = 1, size = 75, endsAt = now + 900000, limitMin = 15 })
    T.check(title == "IGUI_MQ_Horde_Title_spawn|" .. place and body == "IGUI_MQ_Horde_SpawnBody|15|75", "spawn: limit and size")
    title = toast({ ev = "spawn", wave = 2, waves = 3, size = 75, limitMin = 15 })
    T.check(title == "IGUI_MQ_Horde_Title_spawn|IGUI_MQ_Horde_Wave|2|3|" .. place, "spawn of wave 2/3")
    local nextAt = Cl.serverNow() + 30000
    title, body = toast({ ev = "rest", wave = 2, waves = 3, nextAt = nextAt })
    T.check(title == "IGUI_MQ_Horde_Title_rest|2|3|" .. place and body == "IGUI_MQ_Horde_RestToast|3|0:30",
        "rest: wave 2/3 cleared, wave 3 in 0:30")
    title, body = toast({ ev = "win", waves = 3, spawned = 325, killed = 325, pool = 500, capped = false, n = 4 })
    T.check(title == "IGUI_MQ_Horde_Title_win|" .. place and body == "IGUI_MQ_Horde_WinBody|3|325|4|500", "win: waves, zombies, players, paid")
    title, body = toast({ ev = "win", waves = 3, spawned = 325, pool = 500, capped = true, n = 8 })
    T.check(body == "IGUI_MQ_Horde_Join|IGUI_MQ_Horde_WinBody|3|325|8|500|IGUI_MQ_Horde_Capped", "win over the cap")
    title, body = toast({ ev = "fail", why = "time", wave = 3, waves = 3, cleared = 2, pool = 130, capped = false })
    T.check(title == "IGUI_MQ_Horde_Title_fail|" .. place
        and body == "IGUI_MQ_Horde_Join|IGUI_MQ_Horde_FailWave|3|IGUI_MQ_Horde_Why_time|IGUI_MQ_Horde_FailPaid|2|130",
        "fail in wave 3: why, the cleared waves pay")
    title, body = toast({ ev = "fail", why = "time", wave = 3, waves = 3, cleared = 2, pool = 500, capped = true })
    T.check(body == "IGUI_MQ_Horde_Join|IGUI_MQ_Horde_Join|IGUI_MQ_Horde_FailWave|3|IGUI_MQ_Horde_Why_time|IGUI_MQ_Horde_FailPaid|2|500|IGUI_MQ_Horde_Capped",
        "fail over the cap")
    for _, why in ipairs({ "time", "nobody", "admin", "restart", "spawn" }) do
        title, body = toast({ ev = "fail", why = why, wave = 1, waves = 1, cleared = 0, pool = 0 })
        T.check(body == "IGUI_MQ_Horde_Why_" .. why, "fail (" .. why .. "), one wave, nothing paid")
    end
    title, body = toast({ ev = "cancel" })
    T.check(title == "IGUI_MQ_Horde_Title_cancel|" .. place and body == "IGUI_MQ_Horde_CancelBody", "cancel")
    T.check(toast({ ev = "bogus" }) == nil, "an unknown ev shows nothing")
    title, body = toast({ kind = "hordePaid", id = 3, pts = 45, kills = 9, capped = false })
    T.check(title == "IGUI_MQ_Horde_Paid|45" and body == "IGUI_MQ_Horde_PaidBody|9", "paid: points and my kills")
    title, body = toast({ kind = "hordePaid", id = 3, pts = 63, kills = 92, capped = true })
    T.check(title == "IGUI_MQ_Horde_Paid|63" and body == "IGUI_MQ_Horde_Join|IGUI_MQ_Horde_PaidBody|92|IGUI_MQ_Horde_Capped",
        "paid over the cap: the shares-scaled note")

    T.section("horde MiniMap providers")
    local M = Q.HordeMap
    MinidoracatMiniMapAPI = nil
    T.check(M.register() == false and not M.registered, "no MiniMap: nothing registered")
    getTexture = function(path) return { path = path } end
    Cl.state = { v = 1 }
    M.refresh()
    T.check(M.zoneProvider() == M.NONE and #M.NONE == 0 and M.markerProvider(0) == nil, "no horde: empty zones, no markers")
    Cl.receive("delta", { hordes = { cur = cur("announced"), last = nil } })
    local z1, m1 = M.zoneProvider(), M.markerProvider(0)
    local rc = z1[1] and z1[1].rects[1]
    local soonTitle = "IGUI_MQ_Horde_Title_soon|" .. place
    T.check(#z1 == 1 and rc.x1 == 10610 and rc.x2 == 10630 and rc.y1 == 9800 and rc.y2 == 9820 and z1[1].name == soonTitle
        and m1.markers[1].x == 10620 and m1.markers[1].label == soonTitle and m1.markers[1].texture.path == M.TEX
        and M.markerProvider(1) == nil,
        "a delta with an announced horde: zone +-10 around the spot, marker on it (first player), labelled with its state")
    Cl.receive("delta", { hordes = { cur = cur("announced", { left = 5 }) } })
    T.check(M.zoneProvider() == z1 and M.markerProvider(0) == m1, "same view: the very same cached tables")
    Cl.receive("delta", { hordes = { cur = cur("active") } })
    T.check(M.zoneProvider() ~= z1 and M.markerProvider(0).revision > m1.revision
        and M.markerProvider(0).markers[1].label == "IGUI_MQ_Horde_Title_active|" .. place
        and M.zoneProvider()[1].name == "IGUI_MQ_Horde_Title_active|" .. place,
        "state changed: rebuilt, the label says it runs (not only the red; review 1)")
    Cl.receive("delta", { hordes = { cur = cur("rest", { wave = 1, waves = 3 }) } })
    T.check(M.zoneProvider() ~= M.NONE and M.markerProvider(0).markers[1].x == 10620,
        "rest between waves: the spot stays on the map")
    Cl.receive("delta", { hordes = { cur = nil, last = lastWin } })
    T.check(M.zoneProvider() == M.NONE and M.markerProvider(0) == nil, "horde over: nothing on the map")
    local reg = {}
    MinidoracatMiniMapAPI = { zoneApiVersion = 1, markerApiVersion = 3,
        registerZoneProvider = function(owner, fn) reg.zone = { owner, fn } end,
        registerMarkerProvider = function(owner, fn) reg.marker = { owner, fn } end }
    T.check(M.register() == true and reg.zone[1] == "MinidoracatQuestFor42" and reg.zone[2] == M.zoneProvider
        and reg.marker[2] == M.markerProvider, "MiniMap present: zone and marker providers registered")

    -- ===== plan-horde-result 1029: the x (this horde only), quiet toasts, death / MVP toasts, results, View results =====
    local shownToasts = {}
    local realToast, realSend, realUI = D.toast, Cl.send, MinidoracatUI
    D.toast = function(title, msg, border) shownToasts[#shownToasts + 1] = { title = title, msg = msg, border = border } end
    local sends = {}
    Cl.send = function(cmd, args) sends[#sends + 1] = { cmd = cmd, args = args }; return "rq" end

    T.section("horde x: takes this horde off the panel, the next one shows again")
    Cl.state = { pins = { "d1" }, day = { quests = quests }, hordes = { cur = cur("active") } }
    Hd.layout(hp)
    local hx = hp.hideHit
    local hideTip, timeOp = nil, drewOp("IGUI_MQ_UI_Left|10:00")
    for _, t in ipairs(hp.tips) do if t.text == "IGUI_MQ_Horde_Hide" then hideTip = t end end
    T.check(hx ~= nil and hx.id == 3 and hx.x1 - hx.x0 >= 20 and hx.y1 - hx.y0 == D.chipH() and hideTip ~= nil
        and hideTip.x == hx.x0 and timeOp ~= nil and timeOp.x <= hx.x0 - 4,
        "an active row: the x at the right of line 1 (20 px x the line), its hover text, the countdown left of it")
    T.check(drewOp("IGUI_MQ_Horde_Tag").c == D.EXTRA.horde and timeOp.c == D.EXTRA.horde, "active: chip and countdown in the horde red")
    Cl.state.hordes = { cur = cur("waiting") }
    Hd.layout(hp)
    T.check(drewOp("IGUI_MQ_Horde_Tag").c == D.EXTRA.hordeSoon and drewOp("IGUI_MQ_Horde_WaitLeft|1:15:00").c == D.EXTRA.hordeSoon,
        "waiting: chip and countdown in the orange, red only while it runs (review 3)")
    T.check(Hd.onMouseDown(hp, hp.hideHit.x0 + 2, hp.hideHit.y0 + 2) == true and Cl.hordeHidden == 3
        and Hd.rows(Cl.state, defs, now)[1].horde == nil and #T.mapShown == 0, "a click on the x hides horde 3: no horde row")
    Hd.layout(hp)
    T.check(hp.hideHit == nil and hp.mapHit == nil and #hp.hits == 1, "laid out again: the pin stays, the horde row is gone")
    Cl.state.pins = {}
    T.check(not Hd.wanted(), "no pins and the only horde hidden: no panel")
    Cl.state.hordes = { cur = cur("announced", { id = 4 }) }
    T.check(Hd.wanted() and Hd.rows(Cl.state, defs, now)[1].hordeId == 4, "the next horde (id 4) shows again")
    -- the banner toggle (daily and Hordes pages)
    Cl.state.hordes = { cur = cur("active") }
    pg.pool:begin()
    PD.hordeBlock(pg, bb, 10, 20, 400, Cl.state)
    pg.pool:finish()
    T.check(hb.visible ~= false and hb.opts.title == "IGUI_MQ_Horde_ShowHud", "hidden: the banner offers Show in tracker")
    hb.onclick(hb.target, hb)
    T.check(Cl.hordeHidden == nil and Hd.rows(Cl.state, defs, now)[1].hordeId == 3, "Show in tracker: the row is back")
    pg.pool:begin()
    PD.hordeBlock(pg, bb, 10, 20, 400, Cl.state)
    pg.pool:finish()
    hb.onclick(hb.target, hb)
    T.check(hb.opts.title == "IGUI_MQ_Horde_HideHud" and Cl.hordeHidden == 3, "Hide from tracker: hidden again")

    T.section("a hidden horde's server-wide toasts stay quiet; remind, paid and other hordes still show")
    local function shows(t)
        local n = #shownToasts
        t.name, t.town = "Gas", "muldraugh"
        E.onToast(t)
        return #shownToasts > n
    end
    T.check(not shows({ kind = "horde", ev = "spawn", id = 3, wave = 1, waves = 1, size = 30, limitMin = 15 })
        and not shows({ kind = "horde", ev = "death", id = 3, names = { "bob" }, anon = 0, wave = 1, waves = 1 })
        and not shows({ kind = "horde", ev = "win", id = 3, waves = 1 }) and not shows({ kind = "horde", ev = "mvp", id = 3, names = { "kate" }, kills = 9 }),
        "horde 3 hidden: spawn, death, win and MVP do not show")
    T.check(shows({ kind = "horde", ev = "remind", id = 3, startMs = now + 120000 }), "remind still shows: the safety warning")
    T.check(shows({ kind = "hordePaid", id = 3, pts = 5, kills = 2 }) and shows({ kind = "horde", ev = "soon", id = 4, startMs = now + 60000, waves = 1 }),
        "the personal reward and the next horde's toasts still show")
    Cl.hordeHidden = nil
    T.check(shows({ kind = "horde", ev = "spawn", id = 3, wave = 1, waves = 1, size = 30, limitMin = 15 }), "shown again: its toasts show")

    T.section("death and MVP toasts")
    title, body, right = toast({ ev = "death", names = { "bob" }, anon = 0, wave = 2, waves = 3 })
    T.check(title == "IGUI_MQ_Horde_Title_death|bob" and body == "IGUI_MQ_Horde_DeathBody|" .. place .. "|2|3" and right == nil,
        "one death: the name, the place and wave 2/3, a plain grey frame")
    title = toast({ ev = "death", names = {}, anon = 1, wave = 1, waves = 1 })
    T.check(title == "IGUI_MQ_Horde_Title_death|IGUI_MQ_UI_Anonymous", "an anonymous player: 'anonymous', no name")
    title, body = toast({ ev = "death", names = { "bob", "amy" }, anon = 1, wave = 2, waves = 3 })
    T.check(title == "IGUI_MQ_Horde_Title_deathN|3"
        and body == "IGUI_MQ_Horde_DeathBodyN|bobIGUI_MQ_UI_ListSepamyIGUI_MQ_UI_ListSepIGUI_MQ_UI_Anonymous|" .. place .. "|2|3",
        "deaths merged: the count, the names and the anonymous one, the place and the wave")
    title, body, right = toast({ ev = "mvp", names = { "kate" }, anon = 0, kills = 162 })
    T.check(title == "IGUI_MQ_Horde_Title_mvp|kate" and body == "IGUI_MQ_Horde_MvpBody|162" and right == D.EXTRA.gold, "MVP: name, kills, gold")
    title, body = toast({ ev = "mvp", names = { "kate" }, anon = 1, kills = 90 })
    T.check(title == "IGUI_MQ_Horde_Title_mvp|kateIGUI_MQ_UI_ListSepIGUI_MQ_UI_Anonymous" and body == "IGUI_MQ_Horde_MvpBodyTie|90",
        "a tie: every MVP, 'each'")

    T.section("results: pushed ones wait until the player is safe, asked ones open at once")
    local R = Q.HordeResult
    local winUI = setmetatable({ API_MAJOR = 1, API_REVISION = 99,
        CAPABILITIES = { window = true, controls = true, scrollPanel = true },
        Theme = { create = function() return { colors = colors } end }, Icons = { draw = function() return true end },
        Window = { new = widget({ contentTop = function() return 24 end, close = function(self) self.visible = false end,
            addToUIManager = function(self) self.added = true end, bringToTop = function() end }) } }, { __index = UI })
    MinidoracatUI = { v1 = winUI }
    local alice = getSpecificPlayer(0)
    local function result(extra)
        local s = { id = 8, name = "Gas", town = "muldraugh", state = "success", spawnAt = now - 14 * 60000, endedAt = now,
            waves = 3, cleared = 3, spawned = 40, killed = 40, pool = 100, capped = true, joined = 3, me = 2,
            rows = { { r = 1, n = "kate", k = 20, p = 50, mvp = true }, { r = 2, n = "alice", k = 15, p = 37 },
                { r = 3, anon = true, k = 5, p = 13, dead = true } },
            deaths = { { anon = true, wave = 2 } } }
        for k, v in pairs(extra or {}) do s[k] = v end
        return s
    end
    local function opened() return R.win ~= nil and R.win:isVisible() end
    local t0 = T.now
    local function tick(sec) T.now = t0 + sec * 1000; R.tick(T.now) end
    T.cellZombies = {}
    local near = T.zombie({ x = alice.x + 12, y = alice.y + 12, cell = true })
    T.zombie({ x = alice.x + 25, y = alice.y, cell = true })   -- 25 tiles: does not count
    Cl.state = { pins = {}, hordes = {} }
    local pushed = result({ push = true })
    Cl.receive("hordeResult", pushed)
    T.check(R.pending == pushed and not opened(), "pushed at the end: it waits, no window")
    local rr = Hd.rows(Cl.state, defs, now)[1]
    T.check(Hd.wanted() and rr ~= nil and rr.result == pushed and rr.name == "IGUI_MQ_Horde_HudDone_success|" .. place
        and rr.line == "IGUI_MQ_Horde_HudResultWait", "the panel shows the wait row: cleared, the place, opens once safe")
    Hd.layout(hp)
    T.check(hp.resultHit ~= nil and drewOp("IGUI_MQ_Horde_ResultBtn") ~= nil and drewOp("IGUI_MQ_Horde_Tag").c == D.EXTRA.success
        and hp.hideHit == nil, "the wait row: a green chip and a Results button, no x")
    for s = 1, 5 do tick(s) end
    T.check(R.pending == pushed and not opened() and R.calm == 0, "a live zombie 17 tiles away: still waiting after 5 s")
    near.dead = true
    tick(6); tick(7)
    near.dead = false
    tick(8)
    near.dead = true
    tick(9); tick(10)
    T.check(R.pending == pushed and not opened(), "2 safe seconds, a zombie, 2 safe seconds: still waiting (3 in a row)")
    tick(10.5)
    T.check(not opened(), "checks run once a second")
    tick(11)
    T.check(opened() and R.s == pushed and R.pending == nil and Hd.rows(Cl.state, defs, now)[1] == nil,
        "3 safe seconds in a row (the corpse does not count): the window opens, the wait row is gone")
    R.close()
    T.check(not opened(), "Close closes it")
    -- 10 minutes, death
    t0 = T.now
    near.dead = false
    Cl.receive("hordeResult", result({ push = true }))
    tick(R.KEEP_MS / 1000 - 1)
    T.check(R.pending ~= nil, "still waiting just before 10 minutes")
    tick(R.KEEP_MS / 1000)
    T.check(R.pending == nil and not opened(), "10 minutes: dropped without opening (the Hordes page still has it)")
    t0 = T.now
    Cl.receive("hordeResult", result({ push = true }))
    alice.dead = true
    tick(1)
    T.check(R.pending == nil and not opened(), "the player died: dropped")
    alice.dead = false
    do
    -- C1: an automatic open takes the keys and the gamepad (Window onShown): it waits for a free screen, a gamepad
    -- player gets a toast
    local joy = getJoypadData
    near.dead = true
    getJoypadData = function() return {} end
    t0 = T.now
    local nt = #shownToasts
    Cl.receive("hordeResult", result({ push = true }))
    tick(1); tick(2); tick(3)
    T.check(not opened() and R.pending == nil and #shownToasts == nt + 1 and shownToasts[nt + 1].title == "IGUI_MQ_Horde_ResultTitle"
        and shownToasts[nt + 1].msg == "IGUI_MQ_Horde_ResultHead_success|" .. place,
        "a gamepad player, safe 3 s: one toast instead of the window, the results dropped (review C1)")
    getJoypadData = joy
    local other = { shown = true }
    function other:isReallyVisible() return self.shown end
    winUI.Focus = { activeRoot = other }
    t0 = T.now
    Cl.receive("hordeResult", result({ push = true }))
    for s = 1, 5 do tick(s) end
    T.check(not opened() and R.pending ~= nil, "another framework window holds the keys: safe 5 s, still waiting")
    Hd.layout(hp)
    T.check(hp.resultHit ~= nil, "meanwhile the panel's Results button is there")
    other.shown = false
    tick(6)
    T.check(opened() and R.pending == nil, "that window closed: the next check opens it")
    R.close()
    winUI.Focus.activeRoot = R.win
    local qwin = Q.Window.visible
    Q.Window.visible = function() return true end
    t0 = T.now
    Cl.receive("hordeResult", result({ push = true }))
    for s = 1, 4 do tick(s) end
    T.check(not opened() and R.pending ~= nil, "the Quest window open (the results window itself the last root): waiting")
    tick(R.KEEP_MS / 1000)
    T.check(not opened() and R.pending == nil, "still busy after 10 minutes: dropped")
    Q.Window.visible = qwin
    t0 = T.now
    Cl.receive("hordeResult", result({ push = true }))
    tick(1); tick(2); tick(3)
    T.check(opened(), "a free screen, no gamepad: opens")
    R.close()
    winUI.Focus = nil
    near.dead = false
    end
    -- the Results button on the panel opens it at once
    t0 = T.now
    Cl.receive("hordeResult", result({ push = true }))
    Hd.layout(hp)
    T.check(Hd.onMouseDown(hp, hp.resultHit.x0 + 2, hp.resultHit.y0 + 2) == true and opened() and R.pending == nil,
        "the panel's Results button opens it with a zombie near")
    R.close()
    -- asked from the Hordes page: no push, opens at once next to a live zombie
    local asked = result({ id = 7 })
    Cl.receive("hordeResult", asked)
    T.check(opened() and R.s == asked and R.pending == nil, "asked for (no push): opens at once, no safety wait")

    T.section("results window content")
    local function listText(s)
        for i = 1, R.list.n do if R.list.ops[i].s == s then return R.list.ops[i] end end
        return nil
    end
    local function sumText(s)
        for i = 1, R.canvas.n do if R.canvas.ops[i].s == s then return R.canvas.ops[i] end end
        return nil
    end
    T.check(sumText("IGUI_MQ_Horde_ResultHead_success|" .. place) ~= nil
        and sumText("IGUI_MQ_Horde_ResultMeta|" .. D.dateTime(now) .. "|3|3|14") ~= nil
        and sumText("3") ~= nil and sumText("40") ~= nil and sumText("100") ~= nil and sumText("IGUI_MQ_Horde_ResultCapped") ~= nil,
        "head, end time / waves / 14 minutes, joined / kills / paid, the cap note")
    T.check(sumText("IGUI_MQ_Horde_MvpTag") ~= nil and sumText("kate") ~= nil and sumText("IGUI_MQ_Horde_MvpKills|20") ~= nil
        and sumText("IGUI_MQ_Horde_DiedWave|IGUI_MQ_UI_Anonymous|2") ~= nil, "the MVP as a tag with kills, the deaths by wave")
    local meOp = listText("IGUI_MQ_Horde_You|alice")
    local frame = nil
    for i = 1, R.list.n do local o = R.list.ops[i]; if o.k == 2 and o.c.token == "accent" then frame = o end end
    T.check(meOp ~= nil and frame ~= nil and frame.y < meOp.y and frame.y + frame.h > meOp.y, "my row: '(you)' and a frame, not only a color")
    T.check(listText("IGUI_MQ_UI_Anonymous") ~= nil and listText("IGUI_MQ_Horde_Died") ~= nil and listText("IGUI_MQ_Horde_MvpTag") ~= nil,
        "the anonymous row has no name, the dead one says Died, the MVP has its tag")
    T.check(sumText("IGUI_MQ_Horde_NoKillsYou") == nil and sumText("IGUI_MQ_Horde_ResultMore|0") == nil and R.sp.height == 3 * (D.fontH() + 8),
        "3 rows: no scroll hint, the list as tall as its rows")
    local many = {}
    for i = 1, 14 do many[i] = { r = i, n = "p" .. i, k = 30 - i, p = 1 } end
    many[15] = { r = 140, n = "alice", k = 0, p = 0 }
    Cl.receive("hordeResult", result({ rows = many, me = 15 }))
    T.check(sumText("IGUI_MQ_Horde_ResultMore|5") ~= nil and R.sp.height == R.ROWS * (D.fontH() + 8) and R.list.height == 15 * (D.fontH() + 8)
        and listText("140") ~= nil and listText("IGUI_MQ_Horde_You|alice") ~= nil,
        "15 rows: 10 shown, the rest scroll with '5 more', my row past the top 100 keeps its rank")
    local notIn = result({ rows = { { r = 1, anon = true, a = "zed", k = 3, p = 2 } } })
    notIn.me = nil   -- no kill: the server sends no me
    Cl.receive("hordeResult", notIn)
    T.check(sumText("IGUI_MQ_Horde_NoKillsYou") ~= nil and listText("IGUI_MQ_UI_AnonReal|zed") ~= nil,
        "not in it: 'no kills'; an admin sees the anonymous account")
    -- the window follows the font: CatLang's Small is 20 px high and DE "Gezahlte Punkte" needs 125 px there
    local function tileLabelW()
        local label = nil
        for i = 1, R.canvas.n do if R.canvas.ops[i].s == "IGUI_MQ_Horde_ResultPaid" then label = R.canvas.ops[i] end end
        for i = 1, R.canvas.n do
            local o = R.canvas.ops[i]
            if label ~= nil and o.k == 2 and o.x == label.x - 8 and o.y < label.y and o.y + o.h > label.y then return o.w - 16 end
        end
        return nil
    end
    T.check(R.win.width == 400 and tileLabelW() == math.floor((400 - 28 - 2 * D.GAP) / 3) - 16, "a 14 px font: 400 wide")
    local tm = getTextManager
    getTextManager = function()
        return { MeasureStringX = function(_, _, s) return #tostring(s) * 7 end, getFontHeight = function() return 20 end }
    end
    Cl.receive("hordeResult", result())
    T.check(R.win.width == 500 and R.sp.width == 500 - 28 and (tileLabelW() or 0) >= 125,
        "a 20 px font (CatLang): 500 wide, each tile label gets 125 px and more")
    getTextManager = tm
    Cl.receive("hordeResult", result())
    T.check(R.win.width == 400, "the font back at 14 px: 400 again on the next open")
    do
    -- C2: Esc is taken on its press and closes on its release, so the release does not reach the pause menu
    local kb = Keyboard
    Keyboard = { KEY_ESCAPE = 1 }
    T.check(R.win.added and R.win.onEscape(R.win) == true and opened(), "Esc pressed: taken (true), the window stays open")
    R.win:onKeyRelease(28)
    T.check(opened(), "another key released: still open")
    R.win:onKeyRelease(1)
    T.check(not opened() and not R.escHeld, "Esc released: closed (review C2)")
    Keyboard = kb
    -- C4: 50 deaths: 10 names and "+40"; the window stays on a 768 / 400 px high screen
    local core = getCore
    local function screen(w, h)
        getCore = function() return { getScreenWidth = function() return w end, getScreenHeight = function() return h end } end
    end
    local dead50, many15 = {}, {}
    for i = 1, 50 do dead50[i] = { n = "d" .. i, wave = 2 } end
    for i = 1, 15 do many15[i] = { r = i, n = "p" .. i, k = 30 - i, p = 1 } end
    local named, plus = 0, nil
    screen(1366, 768)
    Cl.receive("hordeResult", result({ deaths = dead50, rows = many15 }))
    for i = 1, R.canvas.n do
        local s = R.canvas.ops[i].s
        if type(s) == "string" then
            for _ in string.gmatch(s, "IGUI_MQ_Horde_DiedWave|") do named = named + 1 end
            if has(s, "+40") then plus = s end
        end
    end
    T.check(named == 10 and plus ~= nil and R.win.y + R.win.height <= 768 and R.sp.height == R.ROWS * (D.fontH() + 8),
        "50 deaths on a 768 px screen: 10 names then +40, the window inside it, 10 rows")
    screen(1366, 400)
    R.layout()
    local rh = D.fontH() + 8
    T.check(R.win.y + R.win.height <= 400 and R.win.y >= 0 and R.sp.height < R.ROWS * rh and R.sp.height >= R.MIN_ROWS * rh
        and sumText("IGUI_MQ_Horde_ResultMore|" .. math.floor(15 - R.sp.height / rh)) ~= nil,
        "a 400 px screen: fewer rows (3 at least), the rest 'more below', the window and Close inside it")
    -- C3: the tracker is never narrower than 0.3.1's min(360, 20 x font)
    local tmgr = getTextManager
    local function font(h)
        getTextManager = function()
            return { MeasureStringX = function(_, _, s) return #tostring(s) * 7 end, getFontHeight = function() return h end }
        end
    end
    font(16); screen(1024, 768)
    local w1024 = Hd.width()
    font(20); screen(1366, 768)
    local w1366 = Hd.width()
    font(20); screen(1920, 1080)
    local w1920 = Hd.width()
    T.check(w1024 == 320 and w1366 == 360 and w1920 == 480,
        "tracker width: 1024 at 16 px 320 (0.3.1), 1366 at 20 px 360 (0.3.1), 1920 at 20 px 480 (wider; review C3)")
    getTextManager, getCore = tmgr, core
    R.close()
    end
    Cl.receive("result", { ok = false, command = "hordeResult", code = "NOT_FOUND" })
    T.check(shownToasts[#shownToasts].title == "IGUI_MQ_Horde_ResultGone", "asked for one no longer kept: 'only the last 20'")
    MinidoracatUI = nil
    local n0 = #shownToasts
    Cl.receive("hordeResult", result())
    T.check(#shownToasts == n0 + 1 and shownToasts[n0 + 1].title == "IGUI_MQ_Horde_ResultTitle"
        and shownToasts[n0 + 1].msg == "IGUI_MQ_Horde_ResultHead_success|" .. place and not opened(),
        "no framework: one toast instead of the window")

    T.section("Hordes page: View results only where somebody joined; no 'none yet' while loading")
    local hpg = { UI = UI, theme = { colors = colors }, parent = ISPanel:new(0, 0, 640, 480), width = 640, height = 480 }
    D.scrollPage(hpg)
    local PH = Q.PageHordes
    local function pageText(s)
        for i = 1, hpg.canvas.n do if hpg.canvas.ops[i].s == s then return hpg.canvas.ops[i] end end
        return nil
    end
    Cl.state = { hordes = { on = true } }
    Cl.records, Cl.recordsError = nil, nil
    PH.layout(hpg)
    T.check(pageText("IGUI_MQ_UI_HordesEmpty") == nil and pageText("IGUI_MQ_UI_HordesRecent") == nil and pageText("IGUI_MQ_UI_Loading") ~= nil,
        "loading: the totals say so, no 'no horde has ended yet' (review 5)")
    Cl.recordsError = "NO_REPLY"
    PH.layout(hpg)
    T.check(pageText("IGUI_MQ_UI_HordesEmpty") == nil and pageText("IGUI_MQ_UI_RecordsError") ~= nil, "failed: the error, still no 'none yet'")
    Cl.records, Cl.recordsError = { rows = {}, hordes = {} }, nil
    PH.layout(hpg)
    T.check(pageText("IGUI_MQ_UI_HordesEmpty") ~= nil, "loaded and empty: 'no horde has ended yet'")
    Cl.records = { rows = {}, hordes = {
        { id = 8, name = "Gas", town = "muldraugh", state = "success", endedAt = now, waves = 3, cleared = 3, mine = 0, got = 0, joined = 3 },
        { id = 6, name = "Gas", town = "muldraugh", state = "cancelled", endedAt = now - 1, waves = 1, cleared = 0, joined = 0 },
        { id = 5, name = "Gas", town = "muldraugh", state = "failed", why = "nobody", endedAt = now - 2, waves = 1, cleared = 0 } } }
    PH.layout(hpg)
    local vb = hpg.pool.items["res:1"]
    T.check(vb ~= nil and vb.visible ~= false and vb.opts.title == "IGUI_MQ_UI_ViewResult" and vb.internal == 8
        and (hpg.pool.items["res:2"] == nil or hpg.pool.items["res:2"].visible == false)
        and (hpg.pool.items["res:3"] == nil or hpg.pool.items["res:3"].visible == false),
        "View results on the one somebody joined (I did not: anyone may look), none where nobody killed")
    sends = {}
    vb.onclick(vb.target, vb)
    T.check(#sends == 1 and sends[1].cmd == "hordeResult" and sends[1].args.id == 8, "pressed: asks the server for horde 8")

    D.toast, Cl.send, MinidoracatUI = realToast, realSend, realUI

    M.registered = nil
    for k, v in pairs(saved) do _G[k] = v end
end
