local ADDON, ns = ...
local L = ns.L
local B = ns.Board
local S = ns.Sync

-- The book (Pergamino.Book, two pages). Bookmark "Board": the guild's posts on the left (filter chips and a
-- search box over the list), the chosen post on the right with its buttons. Bookmark "My posts": the form
-- on the left (kind chips, link field, quantity, note, Publish), my posts on the right with "Done".

local UI = {}
ns.UI = UI
local P = Pergamino
local ROW_H = 40

UI.filter = "all"
UI.query = ""
UI.kind = "want"
UI.selected = nil

-- Tag colours: the kinds borrow the lib's palette (want = link blue, have = green, craft = gold, match = crimson).
local KIND_COLOR = { want = "note", have = "zone", craft = "level", match = "boss" }

-- What a row of the board says (the tests read it; the page draws it).
function UI.RowText(post)
	local head = ns.PostLink(post)
	if post.qty then
		head = head .. " " .. L.QTY:format(post.qty)
	end
	local sub = L.BY:format(ns.Short(post.by)) .. " · " .. L.POSTED_AGO:format(ns.Span(ns.Now() - post.at))
	if post.note and post.note ~= "" then
		sub = post.note .. " · " .. sub
	end
	return head, sub, L[ns.KIND_TAG[post.kind]], #B.Matches(post) > 0
end

-- The board's rows after filter and search, and the count line.
function UI.BoardLines()
	local rows = B.All(UI.filter, UI.query)
	local out = { rows = rows }
	if not ns.GuildKey() then
		out.empty = L.BOARD_NO_GUILD
	elseif #rows == 0 then
		out.empty = L.BOARD_EMPTY
	end
	out.count = #rows == 1 and L.BOARD_COUNT_ONE or L.BOARD_COUNT:format(#rows)
	return out
end

-- The right page for a chosen post.
function UI.Detail(post)
	if not post then
		return nil
	end
	local d = { link = ns.PostLink(post), kind = L[ns.KIND_LABEL[post.kind]], mine = B.IsMine(post) }
	d.sub = L.BY:format(ns.Short(post.by)) .. " · " .. L.POSTED_AGO:format(ns.Span(ns.Now() - post.at)) .. " · "
		.. L.EXPIRES:format(ns.Span(post.exp - ns.Now()))
	if post.qty then
		d.link = d.link .. " " .. L.QTY:format(post.qty)
	end
	d.note = post.note ~= "" and post.note or nil
	d.button = d.mine and L.DONE or (post.kind == "want" and L.I_HAVE_IT or L.INTERESTED)
	d.matches = B.Matches(post)
	return d
end

local function initRow(row, post)
	if not row.head then
		row.tag = P.Tag(row, "", "note")
		row.tag:SetPoint("TOPLEFT", 6, -6)
		row.head = P.Label(row, "", "strong")
		row.head:SetPoint("TOPLEFT", row.tag, "TOPRIGHT", 6, 1)
		row.head:SetPoint("RIGHT", row, "RIGHT", -70, 0)
		row.head:SetWordWrap(false)
		row.sub = P.Label(row, "", "small")
		row.sub:SetPoint("TOPLEFT", row.tag, "BOTTOMLEFT", 0, -3)
		row.sub:SetPoint("RIGHT", row, "RIGHT", -6, 0)
		row.sub:SetWordWrap(false)
		row.match = P.Tag(row, L.TAG_MATCH, KIND_COLOR.match)
		row.match:SetPoint("TOPRIGHT", -6, -6)
	end
	local head, sub, tag, match = UI.RowText(post)
	row.tag:Set(tag, KIND_COLOR[post.kind])
	row.head:SetText(head)
	row.sub:SetText(sub)
	row.match:Set(L.TAG_MATCH, KIND_COLOR.match)
	row.match:SetShown(match)
	if row.selected then
		row.selected:SetShown(UI.selected and UI.selected.id == post.id)
	end
end
UI.InitRow = initRow

local function tabTip(tab)
	GameTooltip:SetOwner(tab, "ANCHOR_LEFT")
	GameTooltip:SetText(tab:GetText())
	GameTooltip:AddLine(L["TIP_" .. string.upper(tab.key)] or "", 1, 1, 1, true)
	GameTooltip:Show()
end

local function buildBoard(f)
	local page = f:AddPage("board")
	local left, right = page.left, page.right
	f.boardHead = P.Label(left, L.BOARD_HEAD, "heading")
	f.boardHead:SetPoint("TOPLEFT")
	f.boardCount = P.Label(left, "", "muted", "RIGHT")
	f.boardCount:SetPoint("TOPRIGHT")
	f.boardCount:SetPoint("LEFT", f.boardHead, "RIGHT", 8, 0)

	f.filters = {}
	local prev
	for _, kind in ipairs({ "all", "want", "have", "craft" }) do
		local chip = P.Chip(left, kind == "all" and L.KIND_ALL or L[ns.KIND_LABEL[kind]], function()
			UI.filter = kind
			UI.Refresh()
		end)
		if prev then
			chip:SetPoint("LEFT", prev, "RIGHT", 4, 0)
		else
			chip:SetPoint("TOPLEFT", f.boardHead, "BOTTOMLEFT", 0, -8)
		end
		f.filters[kind] = chip
		prev = chip
	end
	f.search = P.Edit(left, 110, {
		placeholder = L.SEARCH,
		onChange = function(_, text)
			UI.query = text
			UI.Refresh()
		end,
	})
	f.search:SetPoint("TOPRIGHT", f.boardHead, "BOTTOMRIGHT", 0, -8)

	local rule = P.Rule(left)
	rule:SetPoint("TOPLEFT", f.filters.all, "BOTTOMLEFT", 0, -8)
	rule:SetPoint("RIGHT", left, "RIGHT", 0, 0)

	f.empty = P.Label(left, "", "muted", "CENTER")
	f.empty:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 10, -30)
	f.empty:SetPoint("RIGHT", left, "RIGHT", -10, 0)
	f.empty:SetWordWrap(true)

	local holder = P.Panel(left)
	holder:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -8)
	holder:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -14, 0)
	f.list = P.List(holder, ROW_H, initRow, function(post)
		UI.selected = post
		UI.Refresh()
	end)
	f.list.box:SetPoint("TOPLEFT", 2, -2)
	f.list.box:SetPoint("BOTTOMRIGHT", -2, 2)

	-- the right page: the chosen post
	f.pick = P.Label(right, L.PICK, "muted", "CENTER")
	f.pick:SetPoint("CENTER", 0, 40)
	f.pick:SetPoint("LEFT", 20, 0)
	f.pick:SetPoint("RIGHT", -20, 0)
	f.pick:SetWordWrap(true)
	f.dKind = P.Tag(right, "", "note")
	f.dKind:SetPoint("TOPLEFT")
	f.dLink = P.Label(right, "", "big")
	f.dLink:SetPoint("TOPLEFT", f.dKind, "BOTTOMLEFT", 0, -8)
	f.dLink:SetPoint("RIGHT")
	f.dLink:SetWordWrap(true)
	f.dSub = P.Label(right, "", "muted")
	f.dSub:SetPoint("TOPLEFT", f.dLink, "BOTTOMLEFT", 0, -4)
	f.dSub:SetPoint("RIGHT")
	f.dSub:SetWordWrap(true)
	f.dNoteHead = P.Label(right, L.NOTE, "subheading")
	f.dNoteHead:SetPoint("TOPLEFT", f.dSub, "BOTTOMLEFT", 0, -14)
	f.dNote = P.Label(right, "", "body")
	f.dNote:SetPoint("TOPLEFT", f.dNoteHead, "BOTTOMLEFT", 0, -4)
	f.dNote:SetPoint("RIGHT")
	f.dNote:SetWordWrap(true)
	f.dMatches = P.Label(right, "", "body")
	f.dMatches:SetPoint("TOPLEFT", f.dNote, "BOTTOMLEFT", 0, -14)
	f.dMatches:SetPoint("RIGHT")
	f.dMatches:SetWordWrap(true)
	f.dButton = P.Button(right, "", 150, function()
		local post = UI.selected
		if not post then
			return
		end
		if B.IsMine(post) then
			B.Close(post.id)
			ns.Print(L.CLOSED:format(ns.PostLink(post)))
			UI.selected = nil
		else
			B.Whisper(post)
		end
		UI.Refresh()
	end)
	f.dButton:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 0, 0)
	f.dHow = P.Label(right, L.HOW, "link")
	f.dHow:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 0, 4)
	local how = CreateFrame("Frame", nil, right)
	how:SetAllPoints(f.dHow)
	how:EnableMouse(true)
	how:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L.HOW)
		GameTooltip:AddLine(L.HOW_TIP:format(ns.db.settings.days), 1, 1, 1, true)
		GameTooltip:Show()
	end)
	how:SetScript("OnLeave", GameTooltip_Hide)
	f.dHowHit = how
end

local function buildMine(f)
	local page = f:AddPage("mine")
	local left, right = page.left, page.right
	f.mineHead = P.Label(left, L.MINE_HEAD, "heading")
	f.mineHead:SetPoint("TOPLEFT")
	f.kinds = {}
	local prev
	for _, kind in ipairs(ns.KINDS) do
		local chip = P.Chip(left, L[ns.KIND_LABEL[kind]], function()
			UI.kind = kind
			UI.Refresh()
		end)
		if prev then
			chip:SetPoint("LEFT", prev, "RIGHT", 4, 0)
		else
			chip:SetPoint("TOPLEFT", f.mineHead, "BOTTOMLEFT", 0, -10)
		end
		f.kinds[kind] = chip
		prev = chip
	end
	f.link = P.Edit(left, 360, { placeholder = L.LINK_PLACEHOLDER, maxLetters = 200 })
	f.link:SetPoint("TOPLEFT", f.kinds.want, "BOTTOMLEFT", 0, -14)
	f.link:SetPoint("RIGHT", left, "RIGHT", 0, 0)
	f.qty = P.Edit(left, 90, { placeholder = L.QTY_PLACEHOLDER, maxLetters = 5 })
	f.qty:SetPoint("TOPLEFT", f.link, "BOTTOMLEFT", 0, -12)
	if f.qty.SetNumeric then
		f.qty:SetNumeric(true)
	end
	f.note = P.Edit(left, 360, { placeholder = L.NOTE_PLACEHOLDER, maxLetters = ns.MAX_NOTE })
	f.note:SetPoint("TOPLEFT", f.qty, "BOTTOMLEFT", 0, -12)
	f.note:SetPoint("RIGHT", left, "RIGHT", 0, 0)
	f.publish = P.Button(left, L.PUBLISH, 130, function()
		UI.PublishFromForm()
	end)
	f.publish:SetPoint("TOPRIGHT", f.note, "BOTTOMRIGHT", 0, -14)
	f.taller = P.Button(left, L.FROM_TALLER, 260, function()
		ns.Partners.PostMissing()
		UI.Refresh()
	end)
	f.taller:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 0, 0)
	f.mineEmpty = P.Label(left, L.MINE_EMPTY, "muted")
	f.mineEmpty:SetPoint("TOPLEFT", f.publish, "BOTTOMLEFT", 0, -24)
	f.mineEmpty:SetPoint("LEFT", left, "LEFT", 0, 0)
	f.mineEmpty:SetPoint("RIGHT", left, "RIGHT", 0, 0)
	f.mineEmpty:SetWordWrap(true)

	-- shift-click while a field has focus pastes the link (Forever's ChatFrameUtil.InsertLink)
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		hooksecurefunc(ChatFrameUtil, "InsertLink", function(text)
			if text and left:IsVisible() and f.link:HasFocus() then
				f.link:SetValue(text)
			end
		end)
	end

	f.mineList = P.Label(right, L.MINE_LIST, "heading")
	f.mineList:SetPoint("TOPLEFT")
	local holder = P.Panel(right)
	holder:SetPoint("TOPLEFT", f.mineList, "BOTTOMLEFT", 0, -8)
	holder:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -14, 0)
	f.mine = P.List(holder, ROW_H, initRow, function(post, button)
		if button == "RightButton" or button == "LeftButton" then
			B.Close(post.id)
			ns.Print(L.CLOSED:format(ns.PostLink(post)))
			UI.Refresh()
		end
	end)
	f.mine.box:SetPoint("TOPLEFT", 2, -2)
	f.mine.box:SetPoint("BOTTOMRIGHT", -2, 2)
end

local function build()
	local f = P.Book(ADDON .. "Frame", { title = L.TITLE })
	UI.frame = f
	local s = ns.db.settings
	if s.point then
		f:ClearAllPoints()
		f:SetPoint(unpack(s.point))
	end
	f.OnMoved = function(...)
		s.point = { ... }
	end
	for _, key in ipairs({ "board", "mine" }) do
		local tab = f:AddTab(key, L["TAB_" .. string.upper(key)])
		tab:SetScript("OnEnter", tabTip)
		tab:SetScript("OnLeave", GameTooltip_Hide)
	end
	buildBoard(f)
	buildMine(f)
	f.OnTab = function()
		UI.Refresh()
	end
	f:SetScript("OnShow", function()
		B.Expire()
		S.AskIfDue()
		UI.Refresh()
	end)
	f:SelectTab("board")
	return f
end

-- The form's Publish: what the fields hold becomes a post, or the reason goes to chat.
function UI.PublishFromForm()
	local f = UI.frame
	local post, why = B.Publish(UI.kind, f.link:GetText() or "", f.qty:GetText(), f.note:GetText() or "")
	if not post then
		ns.Print(why)
		return nil
	end
	f.link:SetValue("")
	f.qty:SetValue("")
	f.note:SetValue("")
	ns.Print(L.PUBLISHED:format(ns.PostLink(post)))
	UI.Refresh()
	return post
end

function UI.ApplyTexts()
	local f = UI.frame
	if not f then
		return
	end
	f:SetTitle(L.TITLE)
	for key, tab in pairs(f.tabs) do
		tab:SetText(L["TAB_" .. string.upper(key)])
	end
	f.boardHead:SetText(L.BOARD_HEAD)
	f.mineHead:SetText(L.MINE_HEAD)
	f.mineList:SetText(L.MINE_LIST)
	f.pick:SetText(L.PICK)
	f.dNoteHead:SetText(L.NOTE)
	f.dHow:SetText(L.HOW)
	f.publish:SetText(L.PUBLISH)
	f.taller:SetText(L.FROM_TALLER)
	f.mineEmpty:SetText(L.MINE_EMPTY)
	f.link:SetPlaceholder(L.LINK_PLACEHOLDER)
	f.qty:SetPlaceholder(L.QTY_PLACEHOLDER)
	f.note:SetPlaceholder(L.NOTE_PLACEHOLDER)
	f.search:SetPlaceholder(L.SEARCH)
	for kind, chip in pairs(f.filters) do
		chip:SetText(kind == "all" and L.KIND_ALL or L[ns.KIND_LABEL[kind]])
		chip:Fit()
	end
	for kind, chip in pairs(f.kinds) do
		chip:SetText(L[ns.KIND_LABEL[kind]])
		chip:Fit()
	end
	UI.Refresh()
end

function UI.Refresh()
	local f = UI.frame
	if not f or not f:IsShown() then
		return
	end
	if f.selected == "board" then
		local lines = UI.BoardLines()
		f.boardCount:SetText(lines.count)
		for kind, chip in pairs(f.filters) do
			chip:SetPressed(kind == UI.filter)
		end
		f.empty:SetText(lines.empty or "")
		f.empty:SetShown(lines.empty ~= nil)
		f.list:SetData(lines.rows, true)
		-- the chosen post may be gone (closed, expired)
		if UI.selected then
			local still
			for _, post in ipairs(lines.rows) do
				if post.id == UI.selected.id then
					still = post
				end
			end
			UI.selected = still
		end
		local d = UI.Detail(UI.selected)
		f.pick:SetShown(d == nil)
		for _, w in ipairs({ f.dKind, f.dLink, f.dSub, f.dNoteHead, f.dNote, f.dMatches, f.dButton }) do
			w:SetShown(d ~= nil)
		end
		if d then
			f.dKind:Set(d.kind, KIND_COLOR[UI.selected.kind])
			f.dLink:SetText(d.link)
			f.dSub:SetText(d.sub)
			f.dNoteHead:SetShown(d.note ~= nil)
			f.dNote:SetText(d.note or "")
			local lines2 = {}
			for _, other in ipairs(d.matches) do
				local fmt = other.kind == "have" and L.MATCH_HAVE or other.kind == "craft" and L.MATCH_CRAFT or L.MATCH_WANT
				lines2[#lines2 + 1] = fmt:format(ns.Short(other.by), ns.PostLink(other))
			end
			f.dMatches:SetText(table.concat(lines2, "\n"))
			f.dButton:SetText(d.button)
		end
	else
		for kind, chip in pairs(f.kinds) do
			chip:SetPressed(kind == UI.kind)
		end
		local mine = {}
		for i = #B.Mine(), 1, -1 do
			mine[#mine + 1] = B.Mine()[i]
		end
		f.mine:SetData(mine, true)
		f.mineEmpty:SetShown(#mine == 0)
		f.taller:SetShown(ns.Partners.HasTaller())
	end
end

function UI.Toggle(tab)
	local f = UI.frame or build()
	if tab then
		f:SelectTab(tab)
		f:Show()
	else
		f:SetShown(not f:IsShown())
	end
end

-- The addon's own errors (Pergamino.Guard), on a card to copy them into an issue.
function UI.Errors()
	if not UI.errorsCard then
		local card = P.Card(ADDON .. "ErrorsCard", 460, 360, L.ERR_TITLE)
		card.page = ns.guard.Page(card.body)
		UI.errorsCard = card
	end
	UI.errorsCard.page.Refresh()
	UI.errorsCard:Show()
	return UI.errorsCard
end

-- The minimap button (Pergamino's), kept in the settings: shown or not, and where around the minimap.
function UI.Minimap()
	local s = ns.db.settings
	if not UI.minimap then
		UI.minimap = P.MinimapButton(ADDON .. "MinimapButton", {
			icon = "Interface\\AddOns\\" .. ADDON .. "\\Media\\icon",
			angle = s.minimapAngle,
			shown = s.minimap,
			onClick = function(button)
				if button == "RightButton" then
					UI.Toggle("mine")
				else
					UI.Toggle()
				end
			end,
			onMove = function(angle)
				s.minimapAngle = angle
			end,
			tooltip = function(tip)
				tip:SetText(L.TITLE)
				tip:AddLine(L.MINIMAP_TIP, 1, 1, 1)
			end,
		})
	end
	UI.minimap:SetShown(s.minimap)
	return UI.minimap
end

ns.On("board", UI.Refresh)
ns.On("language", UI.ApplyTexts)
