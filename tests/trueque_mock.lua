-- What Trueque needs on top of wow_mock.lua: the guild, addon messages (recorded, so tests carry them from
-- one client to another), whispers, the trial flag and item quality colours.

MOCK.guild = { name = "Los Del Fondo", realm = "Forever" } -- nil: not in a guild
MOCK.trial = false
MOCK.lockdown = false
MOCK.sent = {} -- { prefix, text, chatType }
MOCK.whispers = {} -- { text, target }
MOCK.prefixes = {}
MOCK.sendResult = 0

function GetNormalizedRealmName()
	return MOCK.player.realm
end
function IsInGuild()
	return MOCK.guild ~= nil
end
function GetGuildInfo(unit)
	if unit == "player" and MOCK.guild then
		return MOCK.guild.name, "Miembro", 3, MOCK.guild.realm
	end
end
function GetServerTime()
	return MOCK.now
end
function IsTrialAccount()
	return MOCK.trial
end
function Ambiguate(name, context)
	assert(context == "none" or context == "short" or context == "guild" or context == "all", "Ambiguate context")
	local short, realm = name:match("^(.-)%-(.+)$")
	if short and realm == MOCK.player.realm then
		return short
	end
	return name
end
function GameTooltip_Hide()
	GameTooltip:Hide()
end
Enum.SendAddonMessageResult = { Success = 0, NotInGuild = 10, AddOnMessageLockdown = 11 }
C_ChatInfo = {
	RegisterAddonMessagePrefix = function(prefix)
		assert(type(prefix) == "string" and #prefix > 0 and #prefix <= 16, "prefix is 1 to 16 characters")
		MOCK.prefixes[prefix] = true
		return 0
	end,
	SendAddonMessage = function(prefix, text, chatType, target)
		assert(MOCK.prefixes[prefix], "send with a registered prefix")
		assert(type(text) == "string" and #text <= 255, "addon messages are at most 255 bytes")
		if MOCK.sendResult == 0 then
			table.insert(MOCK.sent, { prefix = prefix, text = text, chatType = chatType or "PARTY", target = target })
		end
		return MOCK.sendResult
	end,
	InChatMessagingLockdown = function()
		return MOCK.lockdown
	end,
	SendChatMessage = function(text, chatType, _, target)
		table.insert(MOCK.whispers, { text = text, chatType = chatType, target = target })
	end,
}
ITEM_QUALITY_COLORS = {
	[0] = { hex = "|cff9d9d9d" },
	[1] = { hex = "|cffffffff" },
	[2] = { hex = "|cff1eff00" },
	[3] = { hex = "|cff0070dd" },
	[4] = { hex = "|cffa335ee" },
}
-- the only items this client knows a quality for
MOCK.items[2996] = 1
MOCK.items[2589] = 1
MOCK.items[818] = 2
