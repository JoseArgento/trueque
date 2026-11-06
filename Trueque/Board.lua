local _, ns = ...
local L = ns.L

-- The board: my posts (TruequeDB.mine[me]) and the guild's (TruequeDB.board[guild]), with what expires, what
-- matches what, and the whispers a click sends.

local B = {}
ns.Board = B

local counter = 0

function B.Mine()
	return ns.db.mine[ns.charKey]
end

function B.Guild()
	local key = ns.GuildKey()
	if not key then
		return {}
	end
	ns.db.board[key] = ns.db.board[key] or {}
	return ns.db.board[key]
end

-- Publish: kind, the link text (or a plain name), a quantity and a note. Returns the post, or nil and why.
function B.Publish(kind, linkText, qty, note)
	local mine = B.Mine()
	if #mine >= ns.MAX_POSTS then
		return nil, L.TOO_MANY:format(#mine)
	end
	local ref, name = ns.ParseLink(linkText)
	name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then
		return nil, L.NEED_LINK
	end
	counter = counter + 1
	local now = ns.Now()
	local post = {
		id = ns.charKey .. "-" .. now .. "-" .. counter,
		kind = kind,
		ref = ref,
		name = name:sub(1, 60),
		qty = tonumber(qty) and math.max(1, math.floor(tonumber(qty))) or nil,
		note = (note or ""):sub(1, ns.MAX_NOTE),
		by = ns.charKey,
		at = now,
		exp = now + ns.db.settings.days * 86400,
	}
	table.insert(mine, post)
	ns.Fire("published", post)
	return post
end

-- One of mine by id.
function B.Get(id)
	for _, post in ipairs(B.Mine()) do
		if post.id == id then
			return post
		end
	end
end

-- Change one of mine: same id, same date, new kind/link/quantity/note; it is marked edited and the guild
-- hears it again as N|id (same id, so their copy is replaced). Returns the post, or nil and why.
function B.Update(id, kind, linkText, qty, note)
	local post = B.Get(id)
	if not post then
		return nil, L.GONE
	end
	local ref, name = ns.ParseLink(linkText)
	name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then
		return nil, L.NEED_LINK
	end
	post.kind = kind
	post.ref = ref
	post.name = name:sub(1, 60)
	post.qty = tonumber(qty) and math.max(1, math.floor(tonumber(qty))) or nil
	post.note = (note or ""):sub(1, ns.MAX_NOTE)
	post.edited = ns.Now()
	ns.Fire("published", post)
	return post
end

-- Close one of mine ("done"): it leaves my list and the guild hears X|id.
function B.Close(id)
	local mine = B.Mine()
	for i, post in ipairs(mine) do
		if post.id == id then
			table.remove(mine, i)
			ns.Fire("closed", post)
			return post
		end
	end
end

-- Drop what expired, mine and theirs.
function B.Expire(now)
	now = now or ns.Now()
	local mine = B.Mine()
	for i = #mine, 1, -1 do
		if mine[i].exp <= now then
			table.remove(mine, i)
		end
	end
	for _, board in pairs(ns.db.board) do
		for id, post in pairs(board) do
			if type(post) ~= "table" or not post.exp or post.exp <= now then
				board[id] = nil
			end
		end
	end
end

-- Everything on the guild's board (theirs and mine), newest first (so what was just posted is at the top);
-- kind filters, query searches the name and the note.
function B.All(kind, query)
	local out = {}
	query = query and query:lower() or ""
	local function take(post)
		if kind and kind ~= "all" and post.kind ~= kind then
			return
		end
		if query ~= "" and not (post.name:lower():find(query, 1, true) or (post.note or ""):lower():find(query, 1, true)) then
			return
		end
		out[#out + 1] = post
	end
	for _, post in pairs(B.Guild()) do
		take(post)
	end
	for _, post in ipairs(B.Mine()) do
		take(post)
	end
	table.sort(out, function(a, b)
		if a.at ~= b.at then
			return a.at > b.at
		end
		return a.id < b.id
	end)
	return out
end

function B.IsMine(post)
	return post.by == ns.charKey
end

-- Two posts are about the same thing: the same item ID, or (for recipes and plain text) the same name.
local function sameThing(a, b)
	local ia, ib = ns.ItemID(a), ns.ItemID(b)
	if ia and ib then
		return ia == ib
	end
	return a.name:lower() == b.name:lower()
end

-- For one of my posts: the others' posts that answer it. "want" is answered by "have" and "craft";
-- "have" and "craft" are answered by "want".
function B.Matches(post)
	local out = {}
	local function consider(other)
		if other.by ~= post.by and sameThing(post, other) then
			if (post.kind == "want" and other.kind ~= "want") or (post.kind ~= "want" and other.kind == "want") then
				out[#out + 1] = other
			end
		end
	end
	for _, other in pairs(B.Guild()) do
		consider(other)
	end
	for _, other in ipairs(B.Mine()) do
		consider(other)
	end
	table.sort(out, function(a, b)
		return a.at > b.at
	end)
	return out
end

-- Say in chat, once per session per post, when a post of mine got an answer.
local told = {}
function B.TellMatches()
	for _, post in ipairs(B.Mine()) do
		for _, other in ipairs(B.Matches(post)) do
			local key = post.id .. "|" .. other.id
			if not told[key] then
				told[key] = true
				local fmt = other.kind == "have" and L.MATCH_HAVE or other.kind == "craft" and L.MATCH_CRAFT or L.MATCH_WANT
				ns.Print(L.MATCH_LINE:format(fmt:format(ns.Short(other.by), ns.PostLink(other, "chat"))))
			end
		end
	end
end

-- The whisper a click on someone's post sends: "I have it" for their want, "I'm interested" for their have,
-- "could you craft" for their craft. Only ever called from a button's OnClick.
function B.Whisper(post)
	if B.IsMine(post) then
		return nil
	end
	local fmt = post.kind == "want" and L.WHISPER_HAVE or post.kind == "craft" and L.WHISPER_CRAFT or L.WHISPER_WANT
	local text = fmt:format(ns.PostLink(post, "chat"))
	if C_ChatInfo and C_ChatInfo.SendChatMessage then
		C_ChatInfo.SendChatMessage(text, "WHISPER", nil, post.by)
	elseif SendChatMessage then
		SendChatMessage(text, "WHISPER", nil, post.by)
	end
	ns.Print(L.WHISPERED:format(ns.Short(post.by)))
	return text
end
