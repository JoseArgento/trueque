local ADDON, ns = ...
local L = ns.L

ns.ADDON = ADDON

-- Saved data (TruequeDB), the same for every character of the account:
--   settings = { days = 7, lang = "auto" | "es" | "en", minimap = true, minimapAngle = deg, point = where the
--                book was left, trialNoticed = true once the trial-account notice was shown }
--   mine  = { [charKey] = { post, ... } }      what each of my characters posted (the author whispers go to them)
--   board = { [guildKey] = { [id] = post } }   what guildmates posted, as received
-- A post: { id, kind = "want" | "have" | "craft", ref = "item:123" | "enchant:123" | "trade:..." | nil,
--           name = plain name, qty = n or nil, note = text, by = "Name-Realm", at = time, exp = time }

local listeners = {}
function ns.On(topic, fn)
	listeners[topic] = listeners[topic] or {}
	table.insert(listeners[topic], fn)
end
function ns.Fire(topic, ...)
	for _, fn in ipairs(listeners[topic] or {}) do
		fn(...)
	end
end

ns.DEFAULT_DAYS = 7
ns.MAX_POSTS = 20
ns.MAX_NOTE = 90
ns.KINDS = { "want", "have", "craft" }
ns.KIND_LABEL = { want = "KIND_WANT", have = "KIND_HAVE", craft = "KIND_CRAFT" }
ns.KIND_TAG = { want = "TAG_WANT", have = "TAG_HAVE", craft = "TAG_CRAFT" }

function ns.InitDB()
	if type(TruequeDB) ~= "table" then
		TruequeDB = {}
	end
	local db = TruequeDB
	db.version = 1
	db.settings = type(db.settings) == "table" and db.settings or {}
	local s = db.settings
	if type(s.days) ~= "number" or s.days < 1 or s.days > 30 then
		s.days = ns.DEFAULT_DAYS
	end
	if s.lang ~= "es" and s.lang ~= "en" then
		s.lang = "auto"
	end
	if s.minimap == nil then
		s.minimap = true
	end
	if type(s.minimapAngle) ~= "number" then
		s.minimapAngle = 190
	end
	db.mine = type(db.mine) == "table" and db.mine or {}
	db.board = type(db.board) == "table" and db.board or {}
	ns.db = db
	ns.charKey = ns.Me()
	db.mine[ns.charKey] = db.mine[ns.charKey] or {}
	ns.ApplyLanguage(s.lang)
	-- the addon's own errors, kept here and shown with /trueque errores (Pergamino.Guard)
	db.errors = type(db.errors) == "table" and db.errors or {}
	ns.guard = Pergamino.Guard(ADDON, db, {
		slash = "/trueque",
		chat = function()
			ns.Print(L.ERR_NOTICE)
		end,
		L = { title = L.ERR_TITLE, empty = L.ERR_EMPTY, clear = L.ERR_CLEAR, copy = L.ERR_COPY },
	})
end

-- "Name-Realm" of this character: the key of my posts and the name guildmates whisper to.
function ns.Me()
	local name, realm = UnitFullName("player")
	realm = realm or GetNormalizedRealmName()
	return name .. "-" .. (realm or "")
end

function ns.GuildKey()
	if not IsInGuild() then
		return nil
	end
	local name, _, _, realm = GetGuildInfo("player")
	if not name then
		return nil
	end
	return name .. "-" .. (realm or GetNormalizedRealmName() or "")
end

function ns.Now()
	return GetServerTime and GetServerTime() or time()
end

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffffd100" .. L.TITLE .. ":|r " .. msg)
end

-- "3 d", "5 h", "12 min"
function ns.Span(seconds)
	seconds = math.max(0, seconds)
	if seconds >= 86400 then
		return L.DAY:format(math.floor(seconds / 86400))
	elseif seconds >= 3600 then
		return L.HOUR:format(math.floor(seconds / 3600))
	end
	return L.MINUTE:format(math.max(1, math.floor(seconds / 60)))
end

-- The short name a whisper or a line wants ("Ana" for Ana-Forever on your own realm).
function ns.Short(fullName)
	if Ambiguate then
		return Ambiguate(fullName, "none")
	end
	return (fullName:gsub("%-.*$", ""))
end

-- links ---------------------------------------------------------------------------------------------
-- A post keeps only the reference part of a link ("item:123", "enchant:123", "trade:...") and the plain name:
-- that is what travels in addon messages, and the link is rebuilt on each client. Nothing received is ever
-- used as a link unless it matches one of these shapes.
local REF_PATTERNS = { "^item:%d+$", "^enchant:%d+$", "^trade:[%w%-_:]+$" }
function ns.ValidRef(ref)
	if type(ref) ~= "string" then
		return false
	end
	for _, p in ipairs(REF_PATTERNS) do
		if ref:match(p) then
			return true
		end
	end
	return false
end

-- From a chat link (what InsertLink gives): the ref and the bracketed name. Plain text gives nil, text.
function ns.ParseLink(text)
	if type(text) ~= "string" then
		return nil, ""
	end
	local ref, name = text:match("|H([^|]+)|h%[(.-)%]|h")
	if ref then
		ref = ref:gsub(":+$", "")
		-- an item link is "item:ID:enchant:gem..."; the ID is all a post needs
		local id = ref:match("^item:(%d+)")
		if id then
			ref = "item:" .. id
		end
		if ns.ValidRef(ref) then
			return ref, name
		end
		return nil, name
	end
	return nil, (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function ns.ItemID(post)
	return tonumber(post.ref and post.ref:match("^item:(%d+)"))
end

-- A chat link for a ref and a name: the item's quality colour when the client knows the item, else white.
function ns.RefLink(ref, name)
	name = (name and name ~= "") and name or (ref or "")
	if not ns.ValidRef(ref) then
		return name
	end
	local color = "ffffffff"
	local id = tonumber(ref:match("^item:(%d+)"))
	if id and C_Item and C_Item.GetItemQualityByID then
		-- the ref ("item:123") is an itemInfo the API takes, so the colour of unknown items is plain white
		local q = C_Item.GetItemQualityByID(ref)
		if q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
			color = ITEM_QUALITY_COLORS[q].hex and ITEM_QUALITY_COLORS[q].hex:gsub("^|c", "") or color
		end
	end
	return "|c" .. color .. "|H" .. ref .. "|h[" .. name .. "]|h|r"
end

-- A link to show for a post: the real item link when the client knows the item, else a plain one.
function ns.PostLink(post)
	if post.ref then
		return ns.RefLink(post.ref, post.name)
	end
	return post.name ~= "" and post.name or (post.ref or "")
end

-- Links inside a note travel as "{item:2996:Wool Cloth}" (no "|", so they never break a message); on
-- screen they become real links. Anything that is not a valid ref stays as the plain text it was.
function ns.NoteToken(ref, name)
	return "{" .. ref .. ":" .. (name or ""):gsub("[{}]", "") .. "}"
end

function ns.NoteText(note)
	return (tostring(note or ""):gsub("{(%l+:[%w%-_:]-):([^{}]*)}", function(ref, name)
		if ns.ValidRef(ref) then
			return ns.RefLink(ref, name)
		end
		return "[" .. name .. "]"
	end))
end

-- The note as the player edits it: links as "[Name]", with the refs kept aside to put back on save.
function ns.NoteForEdit(note)
	local links = {}
	local text = (tostring(note or ""):gsub("{(%l+:[%w%-_:]-):([^{}]*)}", function(ref, name)
		if ns.ValidRef(ref) then
			links[name] = ref
		end
		return "[" .. name .. "]"
	end))
	return text, links
end

function ns.NoteFromEdit(text, links)
	return (tostring(text or ""):gsub("%[([^%[%]]+)%]", function(name)
		local ref = links and links[name]
		if ref then
			return ns.NoteToken(ref, name)
		end
		return "[" .. name .. "]"
	end))
end
