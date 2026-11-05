local _, ns = ...
local L = ns.L
local B = ns.Board

-- Taller, when it is there: its shopping list becomes "want" posts, one per missing material.
-- Taller_API is Taller's small public table; everything is behind pcall so a Taller that changes never
-- breaks Trueque.

local T = {}
ns.Partners = T

-- Taller's table, read by name so a client without Taller has nothing to resolve.
local function api()
	local t = rawget(_G, "Taller_API")
	if type(t) == "table" and type(t.ShoppingList) == "function" then
		return t
	end
end

function T.HasTaller()
	return api() ~= nil
end

-- The missing materials: { { item = id, name = text, missing = n }, ... }, or an empty list.
function T.Missing()
	local t = api()
	if not t then
		return {}
	end
	local ok, list = pcall(t.ShoppingList)
	if not ok or type(list) ~= "table" then
		return {}
	end
	local out = {}
	for _, row in ipairs(list) do
		if type(row) == "table" and tonumber(row.missing) and row.missing > 0 and tonumber(row.item) then
			out[#out + 1] = { item = row.item, name = tostring(row.name or ("item " .. row.item)), missing = row.missing }
		end
	end
	return out
end

-- Post what Taller says is missing, skipping what I already posted. Returns how many were posted.
function T.PostMissing()
	local missing = T.Missing()
	if #missing == 0 then
		ns.Print(L.FROM_TALLER_NONE)
		return 0
	end
	local have = {}
	for _, post in ipairs(B.Mine()) do
		if post.kind == "want" and ns.ItemID(post) then
			have[ns.ItemID(post)] = true
		end
	end
	local n = 0
	for _, m in ipairs(missing) do
		if not have[m.item] then
			local link = "|Hitem:" .. m.item .. "|h[" .. m.name .. "]|h"
			local post = B.Publish("want", link, m.missing, "")
			if not post then
				break
			end
			n = n + 1
		end
	end
	ns.Print(L.FROM_TALLER_DONE:format(n))
	return n
end
