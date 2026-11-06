local ADDON, ns = ...
local L = ns.L
local B, S = ns.Board, ns.Sync

-- Login: register the prefix, drop what expired, ask the guild a few seconds in (late loaders answer too).
local ASK_DELAY = 8

local onSlash -- the /trueque handler, defined below; guarded once the saved variables are in
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == ADDON then
			ns.InitDB()
			frame:UnregisterEvent("ADDON_LOADED")
			-- from here on a Lua error in a handler is kept, not thrown (see /trueque errores)
			SlashCmdList.TRUEQUE = ns.guard.Install(frame, onSlash)
		end
	elseif event == "PLAYER_LOGIN" then
		S.Register()
		B.Expire()
		ns.UI.Minimap()
		S.TrialNotice()
		frame:RegisterEvent("CHAT_MSG_ADDON")
		C_Timer.After(ASK_DELAY, function()
			S.AskIfDue()
		end)
	elseif event == "CHAT_MSG_ADDON" then
		S.OnMessage(...)
	end
end)

SLASH_TRUEQUE1 = "/trueque"
onSlash = function(msg)
	msg = strtrim((msg or ""):lower())
	if msg == "mios" or msg == "míos" or msg == "mine" then
		ns.UI.Toggle("mine")
	elseif msg:match("^dias") or msg:match("^días") or msg:match("^days") then
		local n = tonumber(msg:match("(%d+)%s*$"))
		if n and n >= 1 and n <= 30 then
			ns.db.settings.days = n
			ns.Print(L.DAYS_SET:format(n))
		else
			ns.Print(L.DAYS_USAGE)
		end
	elseif msg:match("^minimapa%s+juntar") or msg:match("^minimap%s+merge") then
		local on = msg:match("%s+(%a+)$")
		if on == "on" or on == "off" then
			ns.UI.SetMinimapMerged(on == "on")
		else
			ns.UI.SetMinimapMerged(not ns.db.settings.minimapMerged)
		end
	elseif msg:match("^minimapa") or msg:match("^minimap") then
		local on = msg:match("%s+(%a+)$")
		if on == "on" or on == "si" or on == "sí" then
			ns.db.settings.minimap = true
		elseif on == "off" or on == "no" then
			ns.db.settings.minimap = false
		else
			ns.db.settings.minimap = not ns.db.settings.minimap
		end
		ns.UI.Minimap()
	elseif msg:match("^idioma") or msg:match("^language") or msg:match("^lang") then
		local code = msg:match("%s+(%a+)$")
		if code == "es" or code == "en" or code == "auto" then
			ns.db.settings.lang = code
			ns.ApplyLanguage(code)
			ns.Print(L.LANG_SET:format(L.LANG_NAMES[code]))
		else
			ns.Print(L.LANG_USAGE)
		end
	elseif msg == "errores" or msg == "errors" then
		ns.UI.Errors()
	elseif msg == "help" or msg == "ayuda" then
		ns.Print(L.HELP)
	else
		ns.UI.Toggle()
	end
end
SlashCmdList.TRUEQUE = onSlash

-- the addon compartment is not a frame, so its click is wrapped by hand (an error is kept, not thrown)
function Trueque_OnAddonCompartmentClick()
	if ns.guard then
		ns.guard.Wrap(ns.UI.Toggle, "compartment")()
	else
		ns.UI.Toggle()
	end
end
function Trueque_OnAddonCompartmentEnter(_, button)
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:SetText(L.TITLE)
	GameTooltip:AddLine(L.COMPARTMENT, 1, 1, 1)
	GameTooltip:Show()
end
function Trueque_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end

-- Key binding (Bindings.xml, loaded by the game on its own: it is not listed in the TOC) and its names.
_G["Trueque_Toggle"] = function()
	ns.UI.Toggle()
end
_G["BINDING_HEADER_TRUEQUE"] = "Trueque"
_G["BINDING_NAME_TRUEQUE_TOGGLE"] = L.BINDING_TOGGLE
