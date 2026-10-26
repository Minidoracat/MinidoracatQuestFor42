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
    function Base:addChild(c) self.children = self.children or {}; self.children[#self.children + 1] = c end
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
    local UI = {
        CAPABILITIES = { textFieldInvalid = true },
        Text = { fit = function(s) return s end, wrap = function(s) return { s } end },
        Button = { new = function(opts) local b = button(opts); b.target, b.onclick = opts.target, opts.onClick; return b end },
        Checkbox = { new = widget({ setLabel = function() end, setChecked = function(self, b) self.opts.checked = b end,
            getChecked = function(self) return self.opts.checked == true end }) },
        TextField = { new = widget({ getText = function(self) return self.text or "" end, setText = function(self, s) self.text = s end,
            setInvalid = function(self, b, m) self.invalid = b and (m or true) or nil end }) },
        Dropdown = { new = widget({ setOptions = function(self, o) self.opts.options = o end,
            setSelected = function(self, id) self.selected = id end, getSelected = function(self) return self.selected end }),
            close = function() end },
        Tabs = { new = widget({ getWidth = function() return 400 end, setSelected = function() end }) },
        ScrollPanel = { new = widget({ contentWidth = function(self) return self.width - 12 end }) },
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

    T.section("horde admin: the tab after towns, defaults, status on open")
    local ti, hi = 0, 0
    for i, id in ipairs(A.TABS) do if id == "towns" then ti = i elseif id == "hordes" then hi = i end end
    T.check(hi == ti + 1, "the hordes tab comes right after towns")
    A.select(P, "hordes")
    T.check(count("horde.status") == 1 and not T.printed("admin layout"), "opening the tab asks horde.status and lays out")
    T.check(field("hordes.from"):getText() == "19:00" and field("hordes.to"):getText() == "23:00"
        and field("hordes.chance"):getText() == "30" and field("hordes.count.1"):getText() == "20" and field("hordes.count.2"):getText() == "40"
        and field("hordes.kinds.vanilla"):getText() == "80" and field("hordes.kinds.runner"):getText() == "20"
        and field("hordes.split"):getSelected() == "share" and field("hordes.enabled"):getChecked() == false,
        "every field shows Catalog.DEFAULTS.hordes")
    T.check(shown("cur") and has(pool()["cur"].lines[1], "IGUI_MQ_Admin_HordeNone") and pool()["now"]:isEnabled(),
        "no horde: says so, Start one now enabled")
    T.check(shown("p:0") and shown("sp:add") and pool()["sp:add"]:isEnabled(), "no spots: the warning inside the list box, the add row")
    T.check(#P.pages.hordes.flow.lists >= 2 and P.pages.hordes.flow.lists[1].key == "l" and P.pages.hordes.flow.lists[2].key == "p",
        "recent results and spots are list boxes")
    A.select(P, "towns")
    A.select(P, "hordes")
    T.check(count("horde.status") == 2, "coming back to the tab asks again (live status)")

    T.section("horde admin: a status payload (active horde, log, a pack kind)")
    local log = {}
    for i = 1, 6 do
        log[i] = { id = 10 - i, name = "Spot" .. i, town = "muldraugh", state = i == 1 and "success" or (i == 2 and "cancelled" or "failed"),
            why = i > 2 and "time" or nil, endedAt = now - i * 3600000, spawned = 30, killed = 20, pool = 150 }
    end
    status = { cur = { id = 3, auto = true, name = "Gas", town = "muldraugh", x = 10620, y = 9810, z = 0, state = "active",
        count = 30, spawned = 30, left = 13, endsAt = now + 600000, startMs = now - 60000,
        mix = { { kind = "vanilla", n = 24, nameKey = "IGUI_MQ_Horde_Kind_vanilla" }, { kind = "mod:brute", n = 6, nameKey = "Brute_Name" } } },
        roll = { day = "2026-10-26", slot = 2, n = 1, max = 2, nextAt = now + 3600000, enabled = true }, log = log,
        kinds = { { id = "vanilla", nameKey = "IGUI_MQ_Horde_Kind_vanilla", builtin = true },
            { id = "runner", nameKey = "IGUI_MQ_Horde_Kind_runner", builtin = true }, { id = "mod:brute", nameKey = "Brute_Name", builtin = false } } }
    press("refresh")
    T.check(count("horde.status") == 3 and shown("stop") and pool()["stop"].opts.title == "IGUI_MQ_Admin_HordeStop"
        and pool()["stop"].style == "danger", "Refresh asks again; an active horde has a danger Stop")
    T.check(has(pool()["cur"].lines[1], "IGUI_MQ_Admin_HordeCurLive|IGUI_MQ_Admin_HordeState_active|") and has(pool()["cur"].lines[1], "|17|30|"),
        "the current line: state, place, cleared 17 / 30")
    T.check(has(pool()["roll"].lines[1], "IGUI_MQ_Admin_HordeToday|1|2|"), "today n / max and the next roll")
    T.check(not pool()["now"]:isEnabled(), "Start one now is off while a horde exists")
    T.check(shown("l5") and not shown("l6") and has(cell("l1", 3), "IGUI_MQ_Admin_HordeRes_success|20|30|150")
        and pool()["l1"].cells[3].token == "success" and has(cell("l2", 3), "IGUI_MQ_Admin_HordeRes_cancelled")
        and has(cell("l3", 3), "IGUI_MQ_Admin_HordeWhy_time") and pool()["l3"].cells[3].token == "errorText"
        and cell("l:th", 1) == "IGUI_MQ_Admin_ColTime", "recent results: a header and 5 rows of the 6, success / cancelled / failed with why")
    T.check(field("hordes.kinds.mod:brute") == nil and options("ks:add")["mod:brute"] == "Brute_Name"
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
    status.cur.state = "announced"
    press("refresh")
    T.check(pool()["stop"].opts.title == "IGUI_MQ_Admin_HordeCancel" and has(pool()["cur"].lines[1], "IGUI_MQ_Admin_HordeCurSoon|")
        and has(pool()["cur"].lines[1], "IGUI_MQ_Horde_Kind_vanilla 24") and has(pool()["cur"].lines[1], "Brute_Name 6"),
        "before it starts the button says Cancel; the admin sees count and mix")
    status.cur = nil
    status.roll.enabled = false
    press("refresh")
    T.check(pool()["now"]:isEnabled() and has(pool()["roll"].lines[1], "IGUI_MQ_Admin_HordeAutoOff"), "no horde: Start a horde; auto off said")
    local lead = pool()["now:lead"]
    T.check(lead:getText() == "15", "the warning field starts at the applied leadMin (15)")
    press("now")
    d = dialogs[#dialogs]
    T.check(d.confirmText == "IGUI_MQ_Admin_HordeNow" and d.text == "IGUI_MQ_Admin_HordeNowAsk|15",
        "Start a horde asks with the warning minutes; the text names the applied settings")
    answer(false)
    T.check(last("horde.now") == nil, "not confirmed: nothing sent")
    press("now")
    answer(true)
    T.check(last("horde.now") ~= nil and last("horde.now").lead == 15 and P.msg == "IGUI_MQ_Admin_HordeStarted"
        and AM.draftCount(P.S.draft) == 0, "confirmed: horde.now with lead 15, no draft change")
    lead:setText("0")
    press("now")
    T.check(dialogs[#dialogs].text == "IGUI_MQ_Admin_HordeNowAskNow", "a warning of 0: the start-now text")
    answer(true)
    T.check(last("horde.now").lead == 0 and pool()["now:lead"]:getText() == "0", "lead 0 sent; the admin's value survives the relayout")
    local asked = #dialogs
    for _, bad in ipairs({ "", "x", "-1", "121", "2.5" }) do
        lead:setText(bad)
        press("now")
        T.check(#dialogs == asked and P.msg == "IGUI_MQ_Admin_ErrRange|0|120" and lead.invalid ~= nil,
            "warning '" .. bad .. "': marked, nothing asked")
    end
    lead:setText("5")
    nowReply = { ok = false, code = "NO_SPOTS" }
    press("now")
    answer(true)
    T.check(P.msg == "IGUI_MQ_Code_NO_SPOTS" and lead.invalid == nil, "a refusal shows the server code; a good value clears the mark")

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
        { "hordes.from", { "0:00", "9:05", "23:59", " 19:30 " }, { "24:00", "12:60", "1200", "7:5", "", "ab:cd" } },
        { "hordes.chance", { "0", "100" }, { "-1", "101", "2.5", "x" } },
        { "hordes.maxPerDay", { "1", "24" }, { "0", "25" } },
        { "hordes.leadMin", { "0", "120" }, { "-1", "121" } },
        { "hordes.waitMin", { "1", "240" }, { "0", "241" } },
        { "hordes.count.1", { "1", "40" }, { "0", "101" } },
        { "hordes.kinds.runner", { "0", "100" }, { "-1", "101", "1.5" } },
        { "hordes.limitMin", { "1", "120" }, { "0", "121" } },
        { "hordes.perZombie", { "0", "1000" }, { "-1", "1001" } },
    }
    for _, c in ipairs(cases) do
        local goodOk, badOk = true, false
        for _, v in ipairs(c[2]) do goodOk = goodOk and okWith(c[1], v) end
        for _, v in ipairs(c[3]) do badOk = badOk or okWith(c[1], v) end
        T.check(goodOk and not badOk, c[1] .. ": bounds accepted, outside rejected")
    end
    T.check(AM.clock(" 19:30 ") == "19:30" and AM.clock("9:05") == "9:05" and AM.clock("24:00") == nil and AM.clock("1:2") == nil,
        "AM.clock keeps the typed text, rejects what the server rejects")
    field("hordes.count.1"):setText("50")
    local before = count("cfg.preview")
    A.onPreview(P)
    T.check(count("cfg.preview") == before and field("hordes.count.1").invalid ~= nil and field("hordes.count.2").invalid ~= nil,
        "count min 50 > max 40: both marked, nothing sent")
    field("hordes.count.1"):setText("25")
    field("hordes.count.2"):setText("45")
    field("hordes.from"):setText("20:00")
    field("hordes.chance"):setText("60")
    field("hordes.maxPerDay"):setText("3")
    field("hordes.kinds.runner"):setText("0")
    pick("ks:add", "mod:brute")
    T.check(field("hordes.kinds.mod:brute"):getText() == "10" and shown("ks:n:mod:brute") and not shown("ks:add") and shown("ks:all")
        and field("hordes.kinds.runner"):getText() == "0", "picked: the kind is a row at 10, typed values stay, nothing left to add")
    field("hordes.split"):setSelected("each")
    field("hordes.enabled"):setChecked(true)
    A.onPreview(P)
    local changes = Q.Util.decode(last("cfg.preview").changes)
    local by = {}
    for _, ch in ipairs(changes) do by[ch.path] = ch.value end
    T.check(by["hordes.from"] == "20:00" and by["hordes.chance"] == 60 and by["hordes.maxPerDay"] == 3 and by["hordes.enabled"] == true
        and by["hordes.count"][1] == 25 and by["hordes.count"][2] == 45 and by["hordes.kinds.runner"] == 0
        and by["hordes.kinds.mod:brute"] == 10 and by["hordes.split"] == "each", "valid values land in the draft and the preview")
    T.check(by["hordes.kinds.vanilla"] == nil and by["hordes.to"] == nil and by["hordes.waitMin"] == nil and #changes == 8,
        "untouched fields (and the pack kind's unset default) add nothing")
    local rows = P.confirm.rows
    local labels = {}
    for _, r in ipairs(rows) do labels[r.label] = r end
    T.check(labels["IGUI_MQ_Admin_F_hordes_kinds - IGUI_MQ_Horde_Kind_runner"] ~= nil
        and labels["IGUI_MQ_Admin_F_hordes_kinds - Brute_Name"] ~= nil, "preview rows name each kind")
    T.check(labels["IGUI_MQ_Admin_F_hordes_count"] ~= nil and labels["IGUI_MQ_Admin_F_hordes_count"].after == "25 / 45"
        and labels["IGUI_MQ_Admin_F_hordes_split"].after == "IGUI_MQ_Admin_HordeSplit_each",
        "count is one row (25 / 45), the split is named")
    A.onConfirmCancel(P)
    A.discard(P)

    T.section("horde admin: the kinds list box (design r11)")
    T.check(shown("ks:n:vanilla") and shown("ks:n:runner") and shown("ks:add") and pool()["ks:add"].opts.placeholder == "IGUI_MQ_Admin_HordeKindAdd",
        "defaults: both built-in kinds are rows, the dropdown says what it does")
    press("ks:r:vanilla")
    T.check(P.S.draft.by["hordes.kinds.vanilla"] == 0 and not shown("ks:n:vanilla") and options("ks:add").vanilla == "IGUI_MQ_Horde_Kind_vanilla"
        and has(P.draftSummary, "IGUI_MQ_Admin_HordeSumKindDel|IGUI_MQ_Horde_Kind_vanilla"),
        "Remove on a built-in kind writes 0 (its default is 80) and puts it back in the dropdown")
    pick("ks:add", "mod:brute")
    T.check(P.S.draft.by["hordes.kinds.mod:brute"] == 10 and has(P.draftSummary, "IGUI_MQ_Admin_HordeSumKindAdd|Brute_Name"),
        "a pick adds the kind at 10 through the draft")
    local n = AM.draftCount(P.S.draft)
    press("ks:r:mod:brute")
    T.check(P.S.draft.by["hordes.kinds.mod:brute"] == nil and AM.draftCount(P.S.draft) == n - 1 and not shown("ks:n:mod:brute")
        and options("ks:add")["mod:brute"] == "Brute_Name", "picked and removed before Apply: the draft forgets it, nothing to send")
    press("ks:r:runner")
    T.check(shown("ks:0") and has(pool()["ks:0"].lines[1], "IGUI_MQ_Admin_HordeKindsNone"), "an empty list says every zombie is a regular one")
    A.onPreview(P)
    changes = Q.Util.decode(last("cfg.preview").changes)
    by = {}
    for _, ch in ipairs(changes) do by[ch.path] = ch end
    T.check(#changes == 2 and by["hordes.kinds.vanilla"].value == 0 and by["hordes.kinds.runner"].value == 0,
        "the preview carries 0 for the built-in kinds, nothing for the kind picked and removed")
    A.onConfirmCancel(P)
    A.discard(P)
    pick("ks:add", "mod:brute")
    press("ks:r:mod:brute")
    T.check(AM.draftCount(P.S.draft) == 0 and P.draftSummary == nil and P.msg == nil,
        "picked and removed with nothing else pending: no summary, no in-the-draft note")
    -- as a cfg.get reply sets them: overrides, then a resync (fields read the server values again)
    P.S.overrides.hordes = { kinds = { ["old:gone"] = 15, ["mod:brute"] = 30 } }
    local keep = P.pages.hordes.data
    P.pages.hordes.data = nil
    A.resync(P)
    T.check(not shown("ks:o:old:gone"), "before horde.status lists the kinds, nothing is called not installed")
    P.pages.hordes.data = keep
    A.layout(P)
    T.check(shown("ks:o:old:gone") and pool()["ks:g:old:gone"].lines[1] == "IGUI_MQ_Admin_HordeKindGone" and pool()["ks:w:old:gone"].lines[1] == "15",
        "a key no mod registers any more: a row marked not installed, with its weight")
    press("ks:r:old:gone")
    T.check(P.S.draft.by["hordes.kinds.old:gone"] == AM.DEL and not shown("ks:o:old:gone"), "its Remove drops the key")
    T.check(shown("ks:n:mod:brute") and field("hordes.kinds.mod:brute"):getText() == "30", "a pack kind applied at 30 is a row")
    press("ks:r:mod:brute")
    T.check(P.S.draft.by["hordes.kinds.mod:brute"] == AM.DEL and not shown("ks:n:mod:brute"), "Remove on an applied pack kind drops its key")
    A.discard(P)
    P.S.overrides.hordes = nil

    T.section("horde admin: spots through the draft")
    before = count("towns.here")
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
    pool()["sp:name"]:setText("School")
    press("sp:add")
    press("pr1")
    spots = AM.get(P.S, "hordes.spots")
    T.check(#spots == 1 and spots[1].name == "School" and has(P.draftSummary, "IGUI_MQ_Admin_HordeSumSpotDel|Gasstation"),
        "Remove drops that spot from the draft")
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
    local hf = P.pages.hordes.flow
    local closed = hf.L == nil and #hf.lists > 0
    for _, L in ipairs(hf.lists) do closed = closed and L.h ~= nil end
    T.check(closed, "the hordes tab closes every list box it opens")
    A.hide()
    A.instance = nil

    -- ===== player side =====
    local kinds = { { id = "vanilla", nameKey = "IGUI_MQ_Horde_Kind_vanilla" }, { id = "runner", nameKey = "IGUI_MQ_Horde_Kind_runner" } }
    local function cur(state, extra)
        local c = { id = 3, name = "Gas", town = "muldraugh", x = 10620, y = 9810, z = 0, state = state, kinds = kinds,
            startMs = now + 15 * 60000, expireAt = now + 75 * 60000, endsAt = now + 600000, spawned = 30, left = 13,
            pool = 150, perZombie = 5, split = "share", limitMin = 15, mine = 9 }
        for k, v in pairs(extra or {}) do c[k] = v end
        return c
    end
    local place = "IGUI_MQ_Horde_Place|Gas|IGUI_MQ_Town_muldraugh"
    local Hd, PD, E = Q.Hud, Q.PageDaily, Q.Entry
    local defs = Cl.defs()

    T.section("horde tracker row")
    local s = { pins = {}, hordes = { cur = cur("active") } }
    local r = Hd.rows(s, defs, now)
    T.check(#r == 1 and r[1].horde and r[1].name == place and r[1].time == "10:00" and r[1].prog == 17 and r[1].target == 30
        and r[1].line == "IGUI_MQ_Horde_HudCleared|17|30", "active: name, time to endsAt, cleared 17 / 30")
    r = Hd.rows({ hordes = { cur = cur("waiting") } }, defs, now)
    T.check(r[1].time == "1:15:00" and r[1].line == "IGUI_MQ_Horde_HudWait|10620|9810" and r[1].target == nil, "waiting: time to expireAt and the spot")
    r = Hd.rows({ hordes = { cur = cur("announced") } }, defs, now)
    T.check(r[1].time == "15:00" and r[1].line == "IGUI_MQ_Horde_HudSoon|10620|9810",
        "announced: time to the start and the 50-tile rule at the spot")
    T.check(#Hd.rows({ hordes = { cur = cur("planned") } }, defs, now) == 0 and #Hd.rows({ hordes = {} }, defs, now) == 0,
        "planned (not announced yet) or no cur: no row")
    T.check(D.countdown(0) == "0:00" and D.countdown(1500) == "0:02" and D.countdown(3723000) == "1:02:03", "countdown text")
    -- the panel's own layout: the horde row is on top, no unpin x, and the count is pins only
    local hp = { x = 0, y = 0, width = 300, height = 10, UI = UI, theme = { colors = colors } }
    function hp:setHeight(h) self.height = h end
    function hp:setX(v) self.x = v end
    function hp:setY(v) self.y = v end
    local cat = Q.Catalog
    local quests = {}
    for i = 1, 4 do quests[i] = { tid = cat.daily[i].tid, target = 10, prog = 1, pts = 5, state = "active" } end
    Cl.state = { pins = { "d1", "d2", "d3", "d4", "w1" }, day = { quests = quests },
        week = { quests = { { tid = cat.weekly[1].tid, target = 10, prog = 1, pts = 5, state = "active" } } }, hordes = { cur = cur("active") } }
    Hd.layout(hp)
    local countText = nil
    for i = 1, hp.n do if has(hp.ops[i].s, "IGUI_MQ_UI_Count|") then countText = hp.ops[i].s end end
    T.check(#hp.rows == 6 and hp.rows[1].horde and #hp.hits == 5 and countText == "IGUI_MQ_UI_Count|5|5" and hp.hordeTime == "10:00",
        "five pins and the horde: six rows, five unpin targets, the title still counts 5 / 5")
    Cl.state = { pins = {}, hordes = { cur = cur("waiting") } }
    T.check(Hd.wanted(), "no pins but a horde: the panel is wanted")
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
    local tok, title, body, right = banner(cur("announced"))
    T.check(tok == D.EXTRA.hordeSoon and title == "IGUI_MQ_Horde_Title_soon|" .. place
        and has(body, "IGUI_MQ_Horde_SoonBanner|IGUI_MQ_Horde_Kind_vanilla") and has(body, "|10620|9810")
        and right == "IGUI_MQ_UI_Left|" .. D.duration(15 * 60000), "announced: place, kinds, the 50-tile rule and the time left")
    tok, title, body, right = banner(cur("waiting"))
    T.check(title == "IGUI_MQ_Horde_Title_wait|" .. place and body == "IGUI_MQ_Horde_WaitBody|10620|9810" and has(right, "IGUI_MQ_UI_Left|"),
        "waiting: where to go and the time left")
    tok, title, body = banner(cur("active"))
    T.check(tok == D.EXTRA.horde and title == "IGUI_MQ_Horde_Title_active|" .. place and body == "IGUI_MQ_Horde_ActiveBody_share|17|30|150",
        "active, share: cleared and the pool split by kills")
    tok, title, body = banner(cur("active", { split = "each" }))
    T.check(body == "IGUI_MQ_Horde_ActiveBody_each|17|30|150", "active, each: every participant gets the pool")
    local lastWin = { id = 3, name = "Gas", town = "muldraugh", state = "success", endedAt = now - 60000, spawned = 30, killed = 30,
        pool = 150, split = "share", mine = 9, got = 45 }
    tok, title, body, right = banner(nil, lastWin)
    T.check(tok == D.EXTRA.success and title == "IGUI_MQ_Horde_Title_win|" .. place and body == "IGUI_MQ_Horde_WinMine_share|9|30"
        and right == "IGUI_MQ_UI_PlusPoints|45", "won, share: my kills and share (45 of 150 = 30%), +45")
    lastWin.split, lastWin.got = "each", 150
    tok, title, body, right = banner(nil, lastWin)
    T.check(body == "IGUI_MQ_Horde_WinMine_each|9" and right == "IGUI_MQ_UI_PlusPoints|150", "won, each: the whole pool")
    lastWin.got, lastWin.mine = nil, 0
    tok, title, body, right = banner(nil, lastWin)
    T.check(body == "IGUI_MQ_Horde_WinOthers|30|30" and right == nil, "won without me: who gets points")
    for _, why in ipairs({ "time", "nobody", "admin", "restart", "spawn" }) do
        tok, title, body, right = banner(nil, { name = "Gas", state = "failed", why = why, endedAt = now - 60000 })
        T.check(tok == "errorText" and title == "IGUI_MQ_Horde_Title_fail|Gas" and body == "IGUI_MQ_Horde_Why_" .. why
            and right == "IGUI_MQ_Horde_NoReward", "failed (" .. why .. "): why, no reward")
    end
    tok, title, body = banner(nil, { name = "Gas", state = "cancelled", endedAt = now - 60000 })
    T.check(title == "IGUI_MQ_Horde_Title_cancel|Gas" and body == "IGUI_MQ_Horde_CancelBody", "cancelled")
    T.check(banner(nil, { name = "Gas", state = "failed", why = "time", endedAt = now - PD.LAST_MS + 1000 }) ~= nil
        and banner(nil, { name = "Gas", state = "failed", why = "time", endedAt = now - PD.LAST_MS }) == nil and banner(nil, nil) == nil,
        "the last result shows for 10 minutes only; nothing without a horde")
    T.check(banner(cur("planned"), lastWin) ~= nil and banner(cur("active"), lastWin) ~= nil
        and select(2, banner(cur("active"), lastWin)) == "IGUI_MQ_Horde_Title_active|" .. place, "a live horde wins over the last result")

    T.section("horde toasts")
    local function toast(t) t.kind = t.kind or "horde"; t.name, t.town = "Gas", "muldraugh"; return E.toastText(t) end
    title, body = toast({ ev = "soon", startMs = now + 15 * 60000, kinds = kinds })
    T.check(title == "IGUI_MQ_Horde_Title_soon|" .. place and has(body, "IGUI_MQ_Horde_SoonBody|15|")
        and has(body, "IGUI_MQ_Horde_Kind_vanilla") and has(body, "IGUI_MQ_Horde_Kind_runner"), "soon: minutes to the start and the kinds, no count")
    title, body = toast({ ev = "soon", startMs = now - 60000, kinds = kinds })
    T.check(has(body, "IGUI_MQ_Horde_SoonBody|1|"), "a late warning still says at least 1 minute")
    title, body = toast({ ev = "remind", startMs = now + 2 * 60000 })
    T.check(title == "IGUI_MQ_Horde_Title_remind|2|" .. place and body == "IGUI_MQ_Horde_Remind", "remind: minutes left; get ready or leave")
    title, body = toast({ ev = "open", startMs = now, kinds = { kinds[2] } })
    T.check(title == "IGUI_MQ_Horde_Title_wait|" .. place and body == "IGUI_MQ_Horde_OpenBody|IGUI_MQ_Horde_Kind_runner", "open: starts now")
    title, body = toast({ ev = "spawn", endsAt = now + 900000, limitMin = 15, spawned = 30, pool = 150, split = "share" })
    T.check(title == "IGUI_MQ_Horde_Title_spawn|" .. place and body == "IGUI_MQ_Horde_SpawnBody_share|15|150", "spawn, share")
    title, body = toast({ ev = "spawn", limitMin = 15, spawned = 30, pool = 150, split = "each" })
    T.check(body == "IGUI_MQ_Horde_SpawnBody_each|15|150", "spawn, each")
    title, body = toast({ ev = "win", spawned = 30, killed = 30, pool = 150, split = "share", n = 4 })
    T.check(title == "IGUI_MQ_Horde_Title_win|" .. place and body == "IGUI_MQ_Horde_WinBody_share|4|150", "win, share")
    title, body = toast({ ev = "win", pool = 150, split = "each", n = 4 })
    T.check(body == "IGUI_MQ_Horde_WinBody_each|4|150", "win, each")
    title, body = toast({ ev = "fail", why = "time", left = 6 })
    T.check(title == "IGUI_MQ_Horde_Title_fail|" .. place and body == "IGUI_MQ_Horde_Why_timeLeft|6", "fail by time names how many were removed")
    for _, why in ipairs({ "nobody", "admin", "restart", "spawn" }) do
        title, body = toast({ ev = "fail", why = why, left = 0 })
        T.check(body == "IGUI_MQ_Horde_Why_" .. why, "fail (" .. why .. ")")
    end
    title, body = toast({ ev = "fail", why = "time", left = 0 })
    T.check(body == "IGUI_MQ_Horde_Why_time", "fail by time with nothing left")
    title, body = toast({ ev = "cancel" })
    T.check(title == "IGUI_MQ_Horde_Title_cancel|" .. place and body == "IGUI_MQ_Horde_CancelBody", "cancel")
    T.check(toast({ ev = "bogus" }) == nil, "an unknown ev shows nothing")
    title, body = toast({ kind = "hordePaid", id = 3, pts = 45, kills = 9, pct = 30 })
    T.check(title == "IGUI_MQ_Horde_Paid|45" and body == "IGUI_MQ_Horde_WinMine_share|9|30", "paid, share: kills and percent")
    title, body = toast({ kind = "hordePaid", id = 3, pts = 150, kills = 9 })
    T.check(title == "IGUI_MQ_Horde_Paid|150" and body == "IGUI_MQ_Horde_WinMine_each|9", "paid, each: no percent")

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
