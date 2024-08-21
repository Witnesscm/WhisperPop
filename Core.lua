------------------------------------------------------------
-- Core.lua
--
-- Abin
-- 2015/9/06
------------------------------------------------------------

local pairs = pairs
local ipairs = ipairs
local strfind = strfind
local type = type
local tinsert = tinsert
local strsub = strsub
local date = date
local time = time
local format = format
local select = select
local PlaySoundFile = PlaySoundFile
local wipe = wipe
local tremove = tremove
local GetPlayerInfoByGUID = GetPlayerInfoByGUID
local BNGetNumFriends = BNGetNumFriends
local GMChatFrame_IsGM = GMChatFrame_IsGM
local ChatFrame_GetMessageEventFilters = ChatFrame_GetMessageEventFilters
local ChatFrame_SendTell = ChatFrame_SendTell
local ChatFrame_SendBNetTell = ChatFrame_SendBNetTell
local SendWho = C_FriendList.SendWho
local InviteUnit = C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit
local FriendsFrame_ShowDropdown = FriendsFrame_ShowDropdown
local FriendsFrame_ShowBNDropdown = FriendsFrame_ShowBNDropdown
local DEFAULT_CHAT_FRAME = DEFAULT_CHAT_FRAME

local function getDeprecatedAccountInfo(accountInfo)
	if accountInfo then
		local clientProgram = accountInfo.gameAccountInfo.clientProgram ~= "" and accountInfo.gameAccountInfo.clientProgram or nil
		return
			accountInfo.bnetAccountID, accountInfo.accountName, accountInfo.battleTag, accountInfo.isBattleTagFriend,
			accountInfo.gameAccountInfo.characterName, accountInfo.gameAccountInfo.gameAccountID, clientProgram,
			accountInfo.gameAccountInfo.isOnline, accountInfo.lastOnlineTime, accountInfo.isAFK, accountInfo.isDND, accountInfo.customMessage, accountInfo.note, accountInfo.isFriend,
			accountInfo.customMessageTime, false, accountInfo.rafLinkType == Enum.RafLinkType.Recruit, accountInfo.gameAccountInfo.canSummon
	end
end

local BNGetFriendInfo = BNGetFriendInfo or function(friendIndex)
	local accountInfo = C_BattleNet.GetFriendAccountInfo(friendIndex)
	return getDeprecatedAccountInfo(accountInfo)
end

local BNGetFriendInfoByID  = BNGetFriendInfoByID or function(id)
	local accountInfo = C_BattleNet.GetAccountInfoByID(id)
	return getDeprecatedAccountInfo(accountInfo)
end

local addon = LibAddonManager:CreateAddon(...)
local L = addon.L

addon:RegisterDB("WhisperPopDB")
addon:RegisterSlashCmd("whisperpop", "wp") -- Type /whisperpop or /wp to toggle the frame

addon.ICON_FILE = "Interface\\Icons\\INV_Letter_05"
addon.SOUND_FILE = "Interface\\AddOns\\WhisperPop\\Sounds\\Notify.ogg"
addon.BACKGROUND = "Interface\\DialogFrame\\UI-DialogBox-Background"
addon.BORDER = "Interface\\Tooltips\\UI-Tooltip-Border"

addon.MAX_MESSAGES = 500 -- Maximum messages stored for each conversation

-- Message are saved in format of: [1/0][timestamp][contents]
-- The first char is 1 if this message is inform, 0 otherwise
addon.TimestampFormat = {
	[1] = "%m/%d %H:%M",
	[2] = "%m/%d %H:%M:%S",
	[3] = "%m/%d/%y %H:%M",
	[4] = "%m/%d/%y %H:%M:%S",
	[5] = "%y/%m/%d %H:%M",
	[6] = "%y/%m/%d %H:%M:%S",
	[7] = "%Y/%m/%d %H:%M",
	[8] = "%Y/%m/%d %H:%M:%S",
	[9] = "%m-%d %H:%M",
	[10] = "%m-%d %H:%M:%S",
	[11] = "%Y-%m-%d %H:%M",
	[12] = "%Y-%m-%d %H:%M:%S",
}

function addon:FormatTimestamp(timeFormat, timestamp)
	return format("[%s]", date(timeFormat, timestamp))
end

function addon:GetFormattedTime(timestamp)
	return addon:FormatTimestamp(addon.TimestampFormat[self.db.timeFormat], timestamp)
end

function addon:EncodeMessage(text, inform)
	local timestamp = time()
	local formattedTime = addon:GetFormattedTime(timestamp)
	return (inform and "1" or "0")..format("[T%d]", timestamp)..(text or ""), formattedTime
end

function addon:DecodeMessage(line)
	if type(line) ~= "string" then
		return
	end

	local inform
	if strsub(line, 1, 1) == "1" then
		inform = 1
	end

	local timestamp, text = strmatch(line, "^[01]%[T(%d-)%](.*)")
	local formattedTime = timestamp and addon:GetFormattedTime(timestamp)
	if not formattedTime then
		formattedTime, text = strmatch(line, "^[01](%[.-%])(.*)")
	end
	if not formattedTime then
		formattedTime = strsub(line, 2, 17)
		text = strsub(line, 18)
	end

	return text, inform, formattedTime
end

-- Splits name-realm
function addon:ParseNameRealm(text)
	if type(text) == "string" then
		local _, _, name, realm = strfind(text, "(.+)%-(.+)")
		return name or text, realm
	end
end

function addon:GetDisplayName(text, forceRealm)
	if self:IsBattleTag(text) then
		local _, name = self:GetBNInfoFromTag(text)
		return name or text
	end

	if forceRealm then
		return text
	end

	local name, realm = self:ParseNameRealm(text)
	if self.db.showRealm then
		if self.db.foreignOnly and realm == self.normalizedRealm then
			return name
		else
			return text
		end
	else
		return name
	end
end

function addon:GetBNInfoFromTag(tag)
	if type(tag) ~= "string" then
		return
	end

	for i = 1, BNGetNumFriends() do
		local id, name, battleTag, _, _, _, _, online = BNGetFriendInfo(i)
		if battleTag == tag then
			return id, name, online, i
		end
	end
end

function addon:IsBattleTag(name)
	if type(name) == "string" then
		local _, _, prefix, surfix = strfind(name, "(.+)#(%d+)$")
		return prefix, surfix
	end
end

function addon:GetNewMessage()
	for i = 1, #self.db.history do
		local data = self.db.history[i]
		if data.new then
			return addon:GetDisplayName(data.name), data.class, addon:DecodeMessage(data.messages[1])
		end
	end
end

function addon:GetNewNames()
	local newNames = {}
	for i = 1, #self.db.history do
		local data = self.db.history[i]
		if data.new then
			tinsert(newNames, addon:GetDisplayName(data.name))
		end
	end
	return newNames
end

function addon:AddTooltipText(tooltip)
	local newNames = self:GetNewNames()
	if newNames[1] then
		tooltip:AddLine(L["new messages from"], 1, 1, 1, true)
		for i = 1, #newNames do
			tooltip:AddLine(newNames[i], 0, 1, 0, true)
		end
	else
		tooltip:AddLine(L["no new messages"], 1, 1, 1, true)
	end
end

function addon:BattlenetInvite(bnId, bnIndex)
	if FriendsFrame_BattlenetInviteByIndex then
		FriendsFrame_BattlenetInviteByIndex(bnIndex)
	elseif FriendsFrame_BattlenetInvite then
		FriendsFrame_BattlenetInvite(nil, bnId)
	end
end

-- Temporary fix
hooksecurefunc("CopyToClipboard", function(text)
	if text and addon.currentName and strfind(addon.currentName, text) then
		ChatFrame_OpenChat(addon.currentName, SELECTED_DOCK_FRAME)
	end
end)

function addon:HandleAction(name, action)
	if type(name) ~= "string" then
		return
	end

	local bnId, bnName, bnOnline, bnIndex
	if addon:IsBattleTag(name) then
		bnId, bnName, bnOnline, bnIndex = self:GetBNInfoFromTag(name)
		if not bnId then
			return
		end
	end

	if action == "MENU" then
		if bnId then
			FriendsFrame_ShowBNDropdown(bnName, bnOnline, nil, nil, nil, 1, bnId)
		else
			FriendsFrame_ShowDropdown(name, 1)
			addon.currentName = name
		end

	elseif action == "WHO" then
		if not bnId then
			SendWho(WHO_TAG_EXACT..name)
		end

	elseif action == "INVITE" then
		if bnId and bnIndex then
			self:BattlenetInvite(bnId, bnIndex)
		else
			InviteUnit(name)
		end

	elseif action == "WHISPER" then
		if bnName then
			ChatFrame_SendBNetTell(bnName)
		else
			ChatFrame_SendTell(name, SELECTED_DOCK_FRAME)
		end
	end
end

function addon:PlaySound()
	PlaySoundFile(self.SOUND_FILE, "Master") -- Sound alert
end

addon.DB_DEFAULTS = {
	time = 1,
	sound = 1,
	save = 1,
	notifyButton = 1,
	ignoreTags = 1,
	applyFilters = 1,
	receiveOnly = 0,
	showRealm = 1,
	foreignOnly = 1,
	timeFormat = 2,
	buttonScale = { min = 50, max = 200, step = 5, default = 100 },
	listScale = { min = 50, max = 200, step = 5, default = 100 },
	listWidth = { min = 100, max = 400, step = 5, default = 200 },
	listHeight = { min = 100, max = 640, step = 20, default = 320 }
}

function addon:OnInitialize(db, firstTime)
	if firstTime or not addon:VerifyDBVersion(4.12, db) then
		db.version = 4.12
		for k, v in pairs(self.DB_DEFAULTS) do
			if v == 1 then
				db[k] = 1
			elseif type(v) == "table" then
				-- print(k, db[k])
				if type(db[k]) ~= "number"  or db[k] < v.min or db[k] > v.max then
					db[k] = v.default
				end
			end
		end
	end

	if not db.timeFormat then
		db.timeFormat = addon.DB_DEFAULTS.timeFormat
	end

	if not db.positions then
		db.positions = {}
	end

	self:SetMovable(addon.frame)
	self:SetMovable(addon.notifyButton)

	if type(db.history) ~= "table" then
		db.history = {}
	end

	self:BroadcastEvent("OnInitialize", db)

	for k in pairs(self.DB_DEFAULTS) do
		self:BroadcastOptionEvent(k, db[k])
	end

	self:RegisterEvent("PLAYER_LOGOUT")
	self:RegisterEvent("CHAT_MSG_WHISPER")
	self:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
	self:RegisterEvent("CHAT_MSG_BN_WHISPER")
	self:RegisterEvent("CHAT_MSG_BN_WHISPER_INFORM")

	self:BroadcastEvent("OnListUpdate")
end

function addon:PLAYER_LOGOUT()
	if not self.db.save then
		wipe(self.db.history)
	end
end

function addon:Clear()
	local history = self.db.history
	for i = #history, 1, -1 do
		if not history[i].protected then
			tremove(history, i)
		end
	end

	self:BroadcastEvent("OnListUpdate")
	self:BroadcastEvent("OnClearMessages")
end

function addon:FindPlayerData(name)
	for index, data in ipairs(self.db.history) do
		if data.name == name then
			return index, data
		end
	end
end

function addon:Delete(name)
	local index, data = self:FindPlayerData(name)
	if index and not data.protected then
		tremove(self.db.history, index)
		self:BroadcastEvent("OnListUpdate")
	end
end

function addon:ProcessChatMsg(name, class, text, inform, bnid)
	if type(text) ~= "string" or type(name) ~= "string" then
		return
	end

	if self.db.ignoreTags then
		local tag = strsub(text, 1, 1)
		if tag == "<" or tag == "[" then
			return
		end
	end

	if self:IsIgnoredMessage(text) then
		return -- Ignored message
	end

	-- Names must be in the "name-realm" format except for BN friends
	if class == "BN" then
		name = select(3, BNGetFriendInfoByID(bnid or 0)) -- Seemingly better than my original solution, credits to Warbaby
		if not name then
			return
		end
	elseif class ~= "GM" then
		local _, realm = self:ParseNameRealm(name)
		if not realm then
			name = name.."-"..self.normalizedRealm
		end
	end

	-- Add data into message history
	local index, data = self:FindPlayerData(name)
	if index then
		if index > 1 then
			tremove(self.db.history, index)
			tinsert(self.db.history, 1, data)
		end
	else
		data = { name = name, class = class }
		tinsert(self.db.history, 1, data)
	end

	if type(data.messages) ~= "table" then
		data.messages = {}
	end

	if inform then
		data.new = nil
	else
		data.new = 1
		data.received = 1
	end

	local msg, timestamp = self:EncodeMessage(text, inform)
	tinsert(data.messages, msg)

	while #data.messages > self.MAX_MESSAGES do
		tremove(data.messages, 1)
	end

	self:BroadcastEvent("OnListUpdate")

	-- It's a new message
	if not inform and self.db.sound then
		self:PlaySound()
	end

	self:BroadcastEvent("OnNewMessage", name, class, text, inform, timestamp)
end

function addon:CHAT_MSG_WHISPER(...)
	local text, name, _, _, _, flag, _, _, _, _, _, guid, _, _, _, hide = ...
	if hide then
		return
	end

	if flag == "GM" or flag == "DEV" then
		flag = "GM"
	else
		-- Spam filters only applied on incoming non-GM whispers, other cases make no sense
		if self.db.applyFilters then
			local filtersList = ChatFrame_GetMessageEventFilters("CHAT_MSG_WHISPER")
			if filtersList then
				local _, func
				for _, func in ipairs(filtersList) do
					if type(func) == "function" and func(DEFAULT_CHAT_FRAME, "CHAT_MSG_WHISPER", ...) then
						return
					end
				end
			end
		end

		flag = select(2, GetPlayerInfoByGUID(guid or ""))
	end

	self:ProcessChatMsg(name, flag, text)
end

function addon:CHAT_MSG_WHISPER_INFORM(...)
	local text, name, _, _, _, flag, _, _, _, _, _, guid = ...
	if flag == "GM" or flag == "DEV" or (GMChatFrame_IsGM and GMChatFrame_IsGM(name)) then
		flag = "GM"
	else
		flag = select(2, GetPlayerInfoByGUID(guid or ""))
	end

	self:ProcessChatMsg(name, flag, text, 1)
end

function addon:CHAT_MSG_BN_WHISPER(...)
	local text, name, _, _, _, _, _, _, _, _, _, _, bnid = ...
	self:ProcessChatMsg(name, "BN", text, nil, bnid)
end

function addon:CHAT_MSG_BN_WHISPER_INFORM(...)
	local text, name, _, _, _, _, _, _, _, _, _, _, bnid = ...
	self:ProcessChatMsg(name, "BN", text, 1, bnid)
end

------------------------------------------------------
-- Position functions
------------------------------------------------------

function addon:Round(number, idp)
	idp = idp or 0
	local mult = 10 ^ idp
	return floor(number * mult + .5) / mult
end

function addon:SavePosition(f)
	local orig, _, tar, x, y = f:GetPoint()
	x = self:Round(x)
	y = self:Round(y)

	local db = self.db
	local key = f.key or f:GetName()
	db.positions[key] = {orig, "UIParent", tar, x, y}
	f:ClearAllPoints()
	f:SetPoint(orig, "UIParent", tar, x, y)
end

function addon:LoadPosition(f)
	local db = self.db
	local key = f.key or f:GetName()
	db.positions[key] = db.positions[key] or {}
	local p, r, rp, x, y = unpack(db.positions[key])

	f:ClearAllPoints()
	if not p then
		if f.defaultPos then
			f:SetPoint(unpack(f.defaultPos))
		else
			f:SetPoint("CENTER")
		end
		self:SavePosition(f)
	else
		f:SetPoint(p, r, rp, x, y)
	end
end

local function Move_OnDragStart(self)
	self:StartMoving()
end

local function Move_OnDragStop(self)
	self:StopMovingOrSizing()
	addon:SavePosition(self)

	if self:GetScript("OnMouseUp") then
		self:GetScript("OnMouseUp")(self)
	end
end

function addon:SetMovable(f)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", Move_OnDragStart)
	f:SetScript("OnDragStop", Move_OnDragStop)
	self:LoadPosition(f)
end

------------------------------------------------------
-- Depreciated functions
------------------------------------------------------
-- It is not recommended to use WhisperPop's IGNORED_MESSAGES array to filter messages anymore,
-- I've added codes in v4 to support third-party filters so it's better let other professional addons do
-- the message-filtering job and we simply take their filter results.
------------------------------------------------------

addon.IGNORED_MESSAGES = {} -- Do not use anymore

-- Add additional ignoring patterns into addon.IGNORED_MESSAGES to filter messages in particular, not recommended since v4.0
function addon:AddIgnore(pattern)
	if type(pattern) ~= "string" then
		return
	end

	for index, str in ipairs(self.IGNORED_MESSAGES) do
		if str == pattern then
			return
		end
	end

	tinsert(self.IGNORED_MESSAGES, pattern)
end

function addon:IsIgnoredMessage(text)
	if type(text) ~= "string" then
		return
	end

	for _, pattern in ipairs(self.IGNORED_MESSAGES) do
		if strfind(text, pattern) then
			return pattern
		end
	end
end