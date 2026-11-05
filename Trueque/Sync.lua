local _, ns = ...
local L = ns.L
local B = ns.Board

-- Guild sync by addon messages (prefix "Trueque1", channel GUILD). What travels:
--   Q|1                                   who has posts? (on login and when the board opens)
--   A|id|kind|ref|name|qty|note|at|exp    one of my posts, as an answer to Q
--   N|id|kind|ref|name|qty|note|at|exp    a post I just published
--   X|id                                  a post I closed
-- Free text (name, note) is escaped so "|" and "%" never break a field. Nothing received is ever run: fields
-- are read as text, refs are kept only when they look like a link reference, numbers only when they parse.
-- Trial accounts cannot send addon messages (FL012): they still receive, and get told once.

local S = {}
ns.Sync = S

S.PREFIX = "Trueque1"
S.VERSION = 1
S.MAX_BYTES = 250
local ASK_EVERY = 60

local function escape(s)
	return (tostring(s or ""):gsub("[%%|]", function(c)
		return string.format("%%%02X", c:byte())
	end))
end
local function unescape(s)
	return (tostring(s or ""):gsub("%%(%x%x)", function(h)
		return string.char(tonumber(h, 16))
	end))
end

function S.CanSend()
	if IsTrialAccount and IsTrialAccount() then
		return false
	end
	if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
		return false
	end
	return true
end

local function send(text)
	if not IsInGuild() or not S.CanSend() then
		return false
	end
	local ok = C_ChatInfo.SendAddonMessage(S.PREFIX, text, "GUILD")
	return ok == 0 or ok == true or (Enum and Enum.SendAddonMessageResult and ok == Enum.SendAddonMessageResult.Success)
end

-- A post as a message, kept under MAX_BYTES by trimming the note first and the name second.
function S.Encode(tag, post)
	local note = post.note or ""
	local name = post.name or ""
	local function build()
		return table.concat({
			tag,
			post.id,
			post.kind,
			post.ref or "",
			escape(name),
			post.qty and tostring(post.qty) or "",
			escape(note),
			tostring(post.at),
			tostring(post.exp),
		}, "|")
	end
	local text = build()
	while #text > S.MAX_BYTES and #note > 0 do
		note = note:sub(1, #note - 5)
		text = build()
	end
	while #text > S.MAX_BYTES and #name > 10 do
		name = name:sub(1, #name - 5)
		text = build()
	end
	return text
end

-- A message back into a post, or nil when anything in it is not what a post looks like.
function S.Decode(text)
	local f = {}
	for field in (text .. "|"):gmatch("([^|]*)|") do
		f[#f + 1] = field
	end
	local tag = f[1]
	if tag == "X" then
		return tag, { id = f[2] }
	end
	if (tag ~= "A" and tag ~= "N") or #f < 9 then
		return nil
	end
	local kind = f[3]
	if kind ~= "want" and kind ~= "have" and kind ~= "craft" then
		return nil
	end
	local ref = f[4] ~= "" and f[4] or nil
	if ref and not ns.ValidRef(ref) then
		ref = nil
	end
	local at, exp = tonumber(f[8]), tonumber(f[9])
	if not at or not exp or f[2] == "" then
		return nil
	end
	return tag, {
		id = f[2]:sub(1, 80),
		kind = kind,
		ref = ref,
		name = unescape(f[5]):sub(1, 60),
		qty = tonumber(f[6]),
		note = unescape(f[7]):sub(1, ns.MAX_NOTE),
		at = at,
		exp = exp,
	}
end

function S.Ask()
	return send("Q|" .. S.VERSION)
end

-- Answer a Q with each of my posts.
function S.Answer()
	local n = 0
	for _, post in ipairs(B.Mine()) do
		if send(S.Encode("A", post)) then
			n = n + 1
		end
	end
	return n
end

local lastAsk = 0
function S.AskIfDue()
	local now = ns.Now()
	if now - lastAsk >= ASK_EVERY then
		lastAsk = now
		S.Ask()
	end
end

-- A message from a guildmate.
function S.OnMessage(prefix, text, channel, sender)
	if prefix ~= S.PREFIX or channel ~= "GUILD" then
		return
	end
	if sender == ns.charKey or sender == ns.Short(ns.charKey) then
		return
	end
	if text:match("^Q|") then
		S.Answer()
		return
	end
	local tag, post = S.Decode(text)
	if not tag then
		return
	end
	local board = B.Guild()
	if tag == "X" then
		local gone = board[post.id]
		if gone and gone.by == sender then
			board[post.id] = nil
			ns.Fire("board")
		end
		return
	end
	if post.exp <= ns.Now() then
		return
	end
	post.by = sender
	-- a sender can only fill their own posts: an id already on the board under another name is ignored
	local old = board[post.id]
	if old and old.by ~= sender then
		return
	end
	-- cap per sender, as the sender's own list is capped
	local n = 0
	for id, p in pairs(board) do
		if p.by == sender and id ~= post.id then
			n = n + 1
		end
	end
	if n >= ns.MAX_POSTS then
		return
	end
	board[post.id] = post
	ns.Fire("board")
	B.TellMatches()
end

function S.Register()
	C_ChatInfo.RegisterAddonMessagePrefix(S.PREFIX)
end

-- Once per account: a trial account sees the board but its posts stay home.
function S.TrialNotice()
	if IsTrialAccount and IsTrialAccount() and not ns.db.settings.trialNoticed then
		ns.db.settings.trialNoticed = true
		ns.Print(L.TRIAL)
	end
end

ns.On("published", function(post)
	send(S.Encode("N", post))
end)
ns.On("closed", function(post)
	send("X|" .. post.id)
end)
