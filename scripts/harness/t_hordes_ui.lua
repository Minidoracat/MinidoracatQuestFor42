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
    -- a decimal field below 1000 reads "," as the decimal point; elsewhere it stays a thousands separator (review r1 C4)
    T.check(AM.check("0,5", "hordeHp") == 0.5 and AM.check("1,25", "eventMult") == 1.25 and AM.check("1,000", "hordeCap") == 1000
        and AM.check("1,000", "rate") == 1000 and AM.check("1.5", "hordeHp") == 1.5,
        "0,5 is half a toughness; 1,000 is a thousand points")

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
    A.hide()
    A.instance = nil

    -- ===== player side (hordes v2: waves, rest, labelled countdowns, the Map button) =====
    local kinds = { { id = "vanilla", nameKey = "IGUI_MQ_Horde_Kind_vanilla" }, { id = "runner", nameKey = "IGUI_MQ_Horde_Kind_runner" } }
    local function cur(state, extra)
        local c = { id = 3, name = "Gas", town = "muldraugh", x = 10620, y = 9810, z = 0, state = state, kinds = kinds,
            startMs = now + 15 * 60000, expireAt = now + 75 * 60000, endsAt = now + 600000, nextAt = now + 24000,
            wave = 1, waves = 1, size = 30, left = 13, killed = 17, limitMin = 15, mine = 9, got = 0 }
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
        and r[1].target == 30 and r[1].line == "IGUI_MQ_Horde_HudCleared|17|30" and r[1].mapX == nil,
        "active: the place, 'left' to endsAt, cleared 17 / wave size 30, no Map button")
    r = row("waiting")
    T.check(r.name == place and r.time == "IGUI_MQ_UI_Left|1:15:00" and r.line == "IGUI_MQ_Horde_HudWait|10620|9810"
        and r.target == nil and r.mapX == 10620 and r.mapY == 9810, "waiting: 'left' to expireAt, the spot first, Map button")
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
        and hp.hordeTime == "IGUI_MQ_UI_Left|10:00" and hp.mapHit == nil and drewOp("IGUI_MQ_UI_Map") == nil,
        "five pins and an active horde: six rows, five unpin targets, the title still counts 5 / 5, no Map button")
    Cl.state.hordes = { cur = cur("waiting") }
    Hd.layout(hp)
    local m, label = hp.mapHit, drewOp("IGUI_MQ_UI_Map")
    local tip = nil
    for _, t in ipairs(hp.tips) do if t.text == "IGUI_MQ_UI_ShowOnMap" then tip = t end end
    T.check(#hp.hits == 5 and m ~= nil and label ~= nil and m.x1 == hp.width - Hd.PAD and label.y > Hd.titleH() + D.chipH()
        and tip ~= nil and tip.x == m.x0 and tip.y == m.y0,
        "waiting: a Map button at the right of line 2 with its hover text; still five unpin targets")
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
        and has(right, "IGUI_MQ_UI_Left|") and spot ~= nil, "waiting: wave 1/3, where to go, the time left, Map")
    tok, title, body, right, spot = banner(cur("active", { wave = 2, waves = 3 }))
    T.check(tok == D.EXTRA.horde and title == "IGUI_MQ_Horde_Title_active|IGUI_MQ_Horde_Wave|2|3|" .. place
        and body == "IGUI_MQ_Horde_ActiveBody|17|30|9" and right == "IGUI_MQ_UI_Left|" .. D.duration(600000) and spot == nil,
        "active: wave 2/3, cleared / wave size and my kills, no pool, no Map")
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
    -- the banner block (daily and Hordes pages): a pooled Map button at the bottom right while the spot matters
    local par = setmetatable({}, { __index = Base })
    local pg = { UI = UI, theme = { colors = colors }, pool = D.pool(par) }
    local bb = D.begin({ UI = UI, theme = pg.theme })
    pg.pool:begin()
    local ny = PD.hordeBlock(pg, bb, 10, 20, 400, { hordes = { cur = cur("waiting") } })
    pg.pool:finish()
    local mb = pg.pool.items.hordeMap
    T.check(mb ~= nil and mb.visible ~= false and mb.opts.title == "IGUI_MQ_UI_Map" and mb.tooltip == "IGUI_MQ_UI_ShowOnMap"
        and mb.x == 10 + 400 - 10 - mb.width and mb.y + mb.height + 6 + D.GAP == ny, "waiting: Map button inside the banner, bottom right")
    mb.onclick(mb.target, mb)
    T.check(#T.mapShown == 1 and T.mapShown[1].x == 10620 and T.mapShown[1].y == 9810 and T.mapShown[1].playerNum == 0,
        "the banner's Map opens the world map on the spot")
    pg.pool:begin()
    T.check(PD.hordeBlock(pg, bb, 10, 20, 400, { hordes = { cur = cur("active") } }) ~= nil, "active: the banner")
    pg.pool:finish()
    T.check(mb.visible == false, "active: no Map button")
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
    T.check(#z1 == 1 and rc.x1 == 10610 and rc.x2 == 10630 and rc.y1 == 9800 and rc.y2 == 9820 and z1[1].name == place
        and m1.markers[1].x == 10620 and m1.markers[1].texture.path == M.TEX and M.markerProvider(1) == nil,
        "a delta with an announced horde: zone +-10 around the spot, marker on it (first player)")
    Cl.receive("delta", { hordes = { cur = cur("announced", { left = 5 }) } })
    T.check(M.zoneProvider() == z1 and M.markerProvider(0) == m1, "same view: the very same cached tables")
    Cl.receive("delta", { hordes = { cur = cur("active") } })
    T.check(M.zoneProvider() ~= z1 and M.markerProvider(0).revision > m1.revision, "state changed: rebuilt")
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

    M.registered = nil
    for k, v in pairs(saved) do _G[k] = v end
end
