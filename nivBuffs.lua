--[[
	Originally created by Luzzifus
	Updated by Caleb

	Further credits as seen on http://www.wowinterface.com/downloads/info18440-nivBuffs.html
	Credits:
		A big "Thank You!" goes to sigg, as he posted this nice tutorial on SecureAuraHeaders in the forums.

	TODO:
		Rewrite how the AuraButtons are handled to have proper Constructor/Destructor functions
		Think about if we want to support Consolidation at all
]]--

-- GLOBALS: SlashCmdList SLASH_nivBuffs1 SLASH_nivBuffs2

-- upvalues
local CreateFrame = CreateFrame
local GameFontNormalSmall = GameFontNormalSmall
local unpack = unpack
local floor = floor
local ceil = ceil
local UnitAura = UnitAura
local _ = _
local GetTime = GetTime
local GetWeaponEnchantInfo = GetWeaponEnchantInfo
local DebuffTypeColor = DebuffTypeColor
local GetInventorySlotInfo = GetInventorySlotInfo
local GetInventoryItemTexture = GetInventoryItemTexture
local GetInventoryItemQuality = GetInventoryItemQuality
local GetItemQualityColor = GetItemQualityColor
local TemporaryEnchantFrame = TemporaryEnchantFrame
local ConsolidatedBuffs = ConsolidatedBuffs
local collectgarbage = collectgarbage
local BuffFrame = BuffFrame
local LibStub = LibStub
local InterfaceOptionsFrame_OpenToCategory = InterfaceOptionsFrame_OpenToCategory
local tonumber = tonumber
local tostring = tostring
local pairs = pairs
local print = print
local next = next
local UIParent = UIParent
local UnitInVehicle = UnitInVehicle

local BF = nil
local grey = nil
local blinkStep = nil
local buffTestFrames = {}
local buffTestFrameshown = false
local debuffTestFrames = {}
local debuffTestFrameshown = false

local defaults = {
	profile = {
	-- Anchors = { AnchorFrom, AnchorFrame, AnchorTo, x-offset (horizontal), y-offset (vertical) }
	--> Glue the <AnchorFrom> corner of the header to the <AnchorTo> corner of <AnchorFrame>
	--
	-- See addon description on wowinterface.com for more information and examples!

	buffAnchor = { "TOPLEFT", "UIParent", "BOTTOMLEFT", 1300, 855 },
	debuffAnchor = { "TOPLEFT", "UIParent", "BOTTOMLEFT", 800, 425 },

	-- horizontal distance between icons in a row
	-- (positive values -> to the right, negative values -> to the left)
	buffXoffset = -38,
	debuffXoffset = -35,

	-- vertical distance between icons in a row
	-- (positive values -> up, negative values -> down)
	buffYoffset = 0,
	debuffYoffset = 0,

	-- maximum number of icons in one row before a new row starts
	buffIconsPerRow = 15,
	debuffIconsPerRow = 10,

	-- maximum number of rows
	buffMaxWraps = 4,
	debuffMaxWraps = 3,

	-- horizontal offset when starting a new row
	-- (positive values -> to the right, negative values -> to the left)
	buffWrapXoffset = 0,
	debuffWrapXoffset = 0,

	-- vertical offset when starting a new row
	-- (positive values -> up, negative values -> down)
	buffWrapYoffset = -40,
	debuffWrapYoffset = -40,

	-- scale
	buffScale = 1.25,
	debuffScale = 2,

	sortMethod = "TIME",				-- how to sort the buffs/debuffs, possible values are "NAME", "INDEX" or "TIME"
	sortBuffReverse = "+",				-- reverse sort order for buffs
	sortDebuffReverse = "-",			-- reverse sort order for debuffs
	showWeaponEnch = true,				-- show or hide temporary weapon enchants
	showDurationSpiral = true,			-- show or hide the duration spiral
	showDurationBar = false,			-- show or hide the duration bar
	showDurationTimers = true,			-- show or hide the duration text timers
	remainingTimeFormat = "HH:MM:SS",	-- remaining time format possible values are : "HH:MM:SS", "Abbreviated"
	coloredBorder = true,				-- highlight debuffs and weapon enchants with a different border color
	borderBrightness = 0,				-- brightness of the default non-colored icon border ( 0 -> black, 1 -> white )
	blinkTime = 6,						-- a buff/debuff icon will blink when it expires in less than x seconds, set to 0 to disable
	blinkSpeed = 2,						-- blinking speed as number of blink cycles per second
	useButtonFacade = true,				-- toggle ButtonFacade support

	-- position of duration text
	-- possible values are "TOP", "BOTTOM", "LEFT" or "RIGHT"
	durationPos = "BOTTOM",
	durationXoffset = 0,
	durationYoffset = 3,

	-- position of stack counter
	stacksXoffset = -4,
	stacksYoffset = 2,

	-- font settings
	-- style can be "MONOCHROME", "OUTLINE", "THICKOUTLINE" or nil
	-- color table as { r, g, b, a }

	-- duration text
	durationFont = "Friz Quadrata TT",
	durationFontColor = { r = 1.0, g = 1.0, b = 1.0},
	durationFontStyle = nil,
	durationFontSize = 10,

	-- stack count text
	stackFont = "Friz Quadrata TT",
	stackFontColor = { r = 1.0, g = 1.0, b = 1.0 },
	stackFontStyle = nil,
	stackFontSize = 10,
	}
}

local nivBuffs = CreateFrame("FRAME", nil, UIParent)
nivBuffs:SetScript('OnEvent', function(self, event, ...) self[event](self, event, ...) end)
nivBuffs:RegisterEvent("ADDON_LOADED")

local addon = nivBuffs

local CallbackHandler = LibStub("CallbackHandler-1.0")
local LBF = LibStub('Masque', true)
local L = LibStub("AceLocale-3.0"):GetLocale("nivBuffs")
local LSM3 = LibStub("LibSharedMedia-3.0")
local bfButtons = {}

-- init secure aura headers
local buffHeader = CreateFrame("Frame", "nivBuffs_Buffs", UIParent, "SecureAuraHeaderTemplate")
local debuffHeader = CreateFrame("Frame", "nivBuffs_Debuffs", UIParent, "SecureAuraHeaderTemplate")
local nivBuffsSecStateHandler = CreateFrame("Frame", nil, nil, "SecureHandlerStateTemplate")
nivBuffsSecStateHandler:SetAttribute("_onstate-aurastate", [[
local buffs = self:GetFrameRef("nivBuffs_Buffs")
local debuffs = self:GetFrameRef("nivBuffs_Debuffs")
local state = newstate == "invehicle" and "vehicle" or "player"
buffs:SetAttribute("unit",state)
debuffs:SetAttribute("unit",state)
]])

nivBuffsSecStateHandler:SetFrameRef("nivBuffs_Buffs", buffHeader)
nivBuffsSecStateHandler:SetFrameRef("nivBuffs_Debuffs", debuffHeader)
RegisterStateDriver(nivBuffsSecStateHandler, "aurastate", "[vehicleui] invehicle; notinvehicle")

do
	local child

	local function btn_iterator(self, i)
		i = i + 1
		child = self:GetAttribute("child" .. i)
		if child and child:IsShown() then return i, child, child:GetAttribute("index") end
	end

	function buffHeader:ActiveButtons() return btn_iterator, self, 0 end
	function debuffHeader:ActiveButtons() return btn_iterator, self, 0 end
end

function addon:showDurationBar(btn)
	local ic = btn.icon
	local br, bg
	if addon.db.profile.showDurationBar then
		br = CreateFrame("STATUSBAR", nil, ic)
		br:SetPoint("TOPLEFT", ic, "TOPLEFT", 3, -3)
		br:SetPoint("BOTTOMLEFT", ic, "BOTTOMLEFT", 3, 3)
		br:SetWidth(2)
		br:SetStatusBarTexture("Interface\\Addons\\nivBuffs\\Textures\\bar")
		br:SetOrientation("VERTICAL")
		btn.bar = br

		bg = br:CreateTexture(nil, "BACKGROUND")
		bg:SetPoint("TOPLEFT", ic, "TOPLEFT", 3, -3)
		bg:SetPoint("BOTTOMLEFT", ic, "BOTTOMLEFT", 3, 3)
		bg:SetWidth(3)
		bg:SetTexture("Interface\\Addons\\nivBuffs\\Textures\\bar")
		bg:SetTexCoord(0, 1, 0, 1)
		bg:SetVertexColor(0, 0, 0, 0.6)
		btn.bar.bg = bg
	else
		if btn.bar then btn.bar:Hide() btn.bar.bg:Hide() end
	end
end

function addon:durationPos(btn)
	local dX, dY = addon.db.profile.durationXoffset, addon.db.profile.durationYoffset
	btn.text:ClearAllPoints()
	if addon.db.profile.durationPos == "TOP" then btn.text:SetPoint("BOTTOM", btn.icon, "TOP", dX, 2 + dY)
	elseif addon.db.profile.durationPos == "LEFT" then btn.text:SetPoint("RIGHT", btn.icon, "LEFT", dX - 2, dY)
	elseif addon.db.profile.durationPos == "RIGHT" then btn.text:SetPoint("LEFT", btn.icon, "RIGHT", 2 + dX, dY)
	else btn.text:SetPoint("TOP", btn.icon, "BOTTOM", dX,  dY - 2) end
end

function addon:stackPos(btn)
	btn.stacks:ClearAllPoints()
	btn.stacks:SetPoint("BOTTOMRIGHT", btn.icon, "BOTTOMRIGHT", 4 + addon.db.profile.stacksXoffset, addon.db.profile.stacksYoffset - 2)
end

function addon:createAuraButton(btn, filter)
	local s, b = 1, 3 / 28
	local n = addon.db.profile

	local ic, tx, cd, br, bd, bg, vf, dr, st

	-- border texture
	local backdrop = {
		edgeFile = "Interface\\Addons\\nivBuffs\\Textures\\borderTex",
		edgeSize = 16,
		insets = { left = s, right = s, top = s, bottom = s }
	}
	-- subframe for icon and border
	ic = CreateFrame("Button", nil, btn)
	ic:SetAllPoints(btn)
	ic:SetFrameLevel(1)
	ic:EnableMouse(false)
	btn.icon = ic

	-- icon texture
	tx = ic:CreateTexture(nil, "ARTWORK")
	tx:SetPoint("TOPLEFT", s, -s)
	tx:SetPoint("BOTTOMRIGHT", -s, s)
	tx:SetTexCoord(b, 1-b, b, 1-b)
	btn.icon.tex = tx
	if not BF then ic:SetBackdrop(backdrop) end

	-- duration spiral
	if n.showDurationSpiral then
		cd = CreateFrame("Cooldown", nil, ic)
		cd:SetAllPoints(tx)
		cd:SetReverse(true)
		cd.noCooldownCount = true -- no OmniCC timers
		cd:SetFrameLevel(3)
		btn.cd = cd
	end

	addon:showDurationBar(btn)

	-- buttonfacade border
	bd = ic:CreateTexture(nil, "OVERLAY")
	bd:SetAllPoints(btn)
	btn.BFborder = bd

	-- subframe for value texts
	vf = CreateFrame("Frame", nil, btn)
	vf:SetAllPoints(btn)
	vf:SetFrameLevel(20)
	btn.vFrame = vf

	-- duration text
	dr = vf:CreateFontString(nil, "OVERLAY")
	dr:SetFontObject(GameFontNormalSmall)
	dr:SetTextColor(n.durationFontColor.r, n.durationFontColor.g, n.durationFontColor.b)
	dr:SetFont(LSM3:Fetch(LSM3.MediaType.FONT, n.durationFont), n.durationFontSize, n.durationFontStyle)
	btn.text = dr

	addon:durationPos(btn)

	-- stack count
	st = vf:CreateFontString(nil, "OVERLAY")
	st:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", 4 + n.stacksXoffset, n.stacksYoffset - 2)
	st:SetFontObject(GameFontNormalSmall)
	st:SetTextColor(n.stackFontColor.r, n.stackFontColor.g, n.stackFontColor.b)
	st:SetFont(LSM3:Fetch(LSM3.MediaType.FONT, n.stackFont), n.stackFontSize, n.stackFontStyle)
	btn.stacks = st

	-- buttonfacade
	if BF then
		bfButtons:AddButton(btn.icon, { Icon = btn.icon.tex, Cooldown = btn.cd, Border = btn.BFborder } )
	end

	btn.lastUpdate = 0
	btn.filter = filter
	btn.created = true
	btn.cAlpha = 1
end

local function round(x)
  return floor(x + 0.5);
end

local formatTimeRemaining
do
	formatTimeRemaining = function(timeLeft)
		if not addon.db.profile.showDurationTimers then return "" end
		if addon.db.profile.remainingTimeFormat == "Abbreviated" then
			if (timeLeft >= 86400) then
				return ("%dd"):format(round(timeLeft / 86400))
			end
			if (timeLeft >= 3600) then
				return ("%dh"):format(round(timeLeft / 3600))
			end
			if (timeLeft >= 60) then
				return ("%dm"):format(round(timeLeft / 60))
			end
			return ("%ds"):format(timeLeft)
		elseif addon.db.profile.remainingTimeFormat == "HH:MM:SS" then
			local days, hours, minutes, seconds = floor(timeLeft / 86400), floor((timeLeft % 86400) / 3600), floor((timeLeft % 3600) / 60), timeLeft % 60
			if days ~= 0 then
				return ("%d:%.2d:%.2d:%.2d"):format(days, hours, minutes, seconds)
			elseif hours ~= 0 then
				return ("%d:%.2d:%.2d"):format(hours, minutes, seconds)
			elseif minutes ~= 0 then
				return ("%d:%.2d"):format(minutes, seconds)
			else
				return ("%d"):format(seconds)
			end
		else -- invalid format
			return ""
		end
	end
end

local function updateBlink(btn)
	if btn.cAlpha >= 1 then btn.increasing = false elseif btn.cAlpha <= 0.1 then btn.increasing = true end
	btn.cAlpha = btn.cAlpha + (btn.increasing and blinkStep or -blinkStep)
	btn:SetAlpha(btn.cAlpha)
end

local updateBar
do
	local r, g

	updateBar = function(btn, duration)
		if not btn.bar then return end

		if btn.rTime > duration / 2 then r, g = (duration - btn.rTime) * 2 / duration, 1
		else r, g = 1, btn.rTime * 2 / duration end

		btn.bar:SetValue(btn.rTime)
		btn.bar:SetStatusBarColor(r, g, 0)
	end
end

local UpdateAuraButtonCD
do
	local name, duration, eTime, msecs

	UpdateAuraButtonCD = function(btn, elapsed)
		if btn.lastUpdate < btn.freq then btn.lastUpdate = btn.lastUpdate + elapsed; return end
		btn.lastUpdate = 0

		name, _, _, _, _, duration, eTime = UnitAura(UnitInVehicle("player") and "vehicle" or "player", btn:GetID(), btn.filter)
		if name and duration > 0 then
			msecs = eTime - GetTime()
			btn.text:SetText(formatTimeRemaining(msecs))

			btn.rTime = msecs
			if btn.rTime < btn.bTime then btn.freq = .05 end
			if btn.rTime <= addon.db.profile.blinkTime then updateBlink(btn) end

			updateBar(btn, duration)
		end
	end
end

local UpdateWeaponEnchantButtonCD
do
	local r1, r2, rTime

	UpdateWeaponEnchantButtonCD = function(btn, elapsed)
		if btn.lastUpdate < btn.freq then
			btn.lastUpdate = btn.lastUpdate + elapsed
			return
		end
		btn.lastUpdate = 0

		_, r1, _, _, _, r2, _ = GetWeaponEnchantInfo()
		rTime = (btn.slotID == 16) and r1 or r2

		btn.rTime = rTime / 1000
		btn.text:SetText(formatTimeRemaining(btn.rTime))

		if btn.rTime < btn.bTime then
			btn.freq = .05
		end
		if btn.rTime <= addon.db.profile.blinkTime then
			updateBlink(btn)
		end

		updateBar(btn, 1800)
	end
end

local updateAuraButtonStyle
do
	local name, icon, count, dType, duration, eTime, cond
	local c = {}

	updateAuraButtonStyle = function(btn, filter)
		if not btn.created then addon:createAuraButton(btn, filter) end
		name, _, icon, count, dType, duration, eTime = UnitAura(UnitInVehicle("player") and "vehicle" or "player", btn:GetID(), filter)
		if name then
			btn.icon.tex:SetTexture(icon)

			cond = (filter == "HARMFUL") and addon.db.profile.coloredBorder
			c.r, c.g, c.b = cond and 0.6 or grey, cond and 0 or grey, cond and 0 or grey
			if dType and cond then c.r, c.g, c.b = DebuffTypeColor[dType].r, DebuffTypeColor[dType].g, DebuffTypeColor[dType].b end

			if BF then btn.BFborder:SetVertexColor(c.r, c.g, c.b, 1)
			else btn.icon:SetBackdropBorderColor(c.r, c.g, c.b, 1) end

			if duration > 0 then
				if btn.cd then
					btn.cd:SetCooldown(eTime - duration, duration)
					btn.cd:SetAlpha(1)
				end
				if btn.bar then
					btn.bar:SetMinMaxValues(0, duration)
					btn.bar:SetAlpha(1)
				end
				btn:SetAlpha(1)

				btn.rTime = eTime - GetTime()
				btn.bTime = addon.db.profile.blinkTime + 1.1
				btn.freq = 1

				btn:SetScript("OnUpdate", UpdateAuraButtonCD)
				UpdateAuraButtonCD(btn, 5)
			else
				btn.text:SetText("")
				btn:SetAlpha(1)
				if btn.cd then
					btn.cd:SetCooldown(0, -1)
					btn.cd:SetAlpha(0)
				end
				if btn.bar then btn.bar:SetAlpha(0) end
				btn:SetScript("OnUpdate", nil)
			end
			btn.stacks:SetText((count > 1) and count or "")
		else
			btn.text:SetText("")
			btn.stacks:SetText("")
			if btn.cd then
				btn.cd:SetCooldown(0, -1)
				btn.cd:SetAlpha(0)
			end
			if btn.bar then btn.bar:SetAlpha(0) end
			btn:SetScript("OnUpdate", nil)
		end
	end
end

local updateWeaponEnchantButtonStyle
do
	local icon, r, g, b, c

	updateWeaponEnchantButtonStyle = function(btn, slot, hasEnchant, rTime)
		if not btn.created then addon:createAuraButton(btn) end

		if hasEnchant then
			btn.slotID = GetInventorySlotInfo(slot)
			icon = GetInventoryItemTexture("player", btn.slotID)
			btn.icon.tex:SetTexture(icon)

			r, g, b = grey, grey, grey
			c = GetInventoryItemQuality("player", btn.slotID)
			if addon.db.profile.coloredBorder then
				r, g, b = GetItemQualityColor(c or 1)
			end

			if BF then
				btn.BFborder:SetVertexColor(r, g, b, 1)
			else
				btn.icon:SetBackdropBorderColor(r, g, b, 1)
			end

			btn.rTime = rTime / 1000
			btn.bTime = addon.db.profile.blinkTime + 1.1
			btn.freq = 1

			btn.duration = 1800
			if btn.cd then
				btn.cd:SetCooldown(GetTime() + btn.rTime - 1800, 1800)
				btn.cd:SetAlpha(1)
			end
			if btn.bar then
				btn.bar:SetMinMaxValues(0, 1800)
				btn.bar:SetAlpha(1)
			end
			btn:SetAlpha(1)

			btn:SetScript("OnUpdate", UpdateWeaponEnchantButtonCD)
			UpdateWeaponEnchantButtonCD(btn, 5)
		else
			btn.text:SetText("")
			if btn.cd then
				btn.cd:SetCooldown(0, -1)
				btn.cd:SetAlpha(0)
			end
			if btn.bar then btn.bar:SetAlpha(0) end
			btn:SetScript("OnUpdate", nil)
		end
	end
end

local updateStyle
do
	local hasMHe, MHrTime, hasOHe, OHrTime, wEnch1, wEnch2

	updateStyle = function(header, event, unit)
		if event == "PET_BATTLE_CLOSE" then
			header:Show()
		elseif event == "PET_BATTLE_OPENING_DONE" then
			header:Hide()
		end
		if event == "UNIT_AURA" and unit ~= "player" and unit ~= "vehicle" then return end
		for _,btn in header:ActiveButtons() do updateAuraButtonStyle(btn, header.filter) end
		if header.filter == "HELPFUL" then
			hasMHe, MHrTime, _, _, hasOHe, OHrTime, _ = GetWeaponEnchantInfo()
			wEnch1 = buffHeader:GetAttribute("tempEnchant1")
			--wEnch2 = buffHeader:GetAttribute("tempEnchant2")

			if wEnch1 then updateWeaponEnchantButtonStyle(wEnch1, "MainHandSlot", hasMHe, MHrTime) end
			--if wEnch2 then updateWeaponEnchantButtonStyle(wEnch2, "SecondaryHandSlot", hasOHe, OHrTime) end
		end
	end
end

local function setHeaderAttributes(header, template, isBuff)
	local s = function(...) header:SetAttribute(...) end
	local n = addon.db.profile

	s("unit", UnitInVehicle("player") and "vehicle" or "player")
	s("filter", isBuff and "HELPFUL" or "HARMFUL")
	s("template", template)
	s("separateOwn", 0)
	s("minWidth", 100)
	s("minHeight", 100)

	s("point", isBuff and n.buffAnchor[1] or n.debuffAnchor[1])
	s("xOffset", isBuff and n.buffXoffset or n.debuffXoffset)
	s("yOffset", isBuff and n.buffYoffset or n.debuffYoffset)
	s("wrapAfter", isBuff and n.buffIconsPerRow or n.debuffIconsPerRow)
	s("wrapXOffset", isBuff and n.buffWrapXoffset or n.debuffWrapXoffset)
	s("wrapYOffset", isBuff and n.buffWrapYoffset or n.debuffWrapYoffset)
	s("maxWraps", isBuff and n.buffMaxWraps or n.debuffMaxWraps)

	s("sortMethod", n.sortMethod)
	s("sortDirection", isBuff and n.sortBuffReverse or n.sortDebuffReverse)

	if isBuff and n.showWeaponEnch then
		s("includeWeapons", 1)
		s("weaponTemplate", "nivBuffButtonTemplate")
	end

	header:SetScale(isBuff and n.buffScale or n.debuffScale)
	header.filter = isBuff and "HELPFUL" or "HARMFUL"

	header:RegisterEvent("PLAYER_ENTERING_WORLD")
	header:RegisterEvent("GROUP_ROSTER_UPDATE")
	header:RegisterEvent("GROUP_JOINED")
	header:RegisterEvent("PET_BATTLE_CLOSE")
	header:RegisterEvent("PET_BATTLE_OPENING_DONE")
	header:HookScript("OnEvent", updateStyle)
end

-----------------------------------------------------------------------
-- GUI options
--

-- Buff test frames
local function onBuffDragStart(self) self:StartMoving() end
local function onBuffDragStop(self)
	self:StopMovingOrSizing()
	addon.db.profile.buffAnchor[4] = self:GetLeft()
	addon.db.profile.buffAnchor[5] = self:GetTop()
	buffHeader:SetPoint(unpack(addon.db.profile.buffAnchor))
end

local function hideBuffTestAnchor()
	if buffTestFrames[1] then for _, v in pairs(buffTestFrames) do v:Hide() end end
	buffTestFrameshown = false
end

local function createBuffTestAnchor()
	hideBuffTestAnchor()
	buffTestFrameshown = true
	local db = addon.db.profile
	buffTestFrames[1] = CreateFrame("Frame", nil, UIParent)
	buffTestFrames[1]["bg"] = buffTestFrames[1]:CreateTexture("Background", "BACKGROUND")
	buffTestFrames[1]["bg"]:SetTexture(0, 1, 0, 0.5)
	buffTestFrames[1]["bg"]:SetAllPoints()
	buffTestFrames[1]["text"] = buffTestFrames[1]:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	buffTestFrames[1]["text"]:SetPoint("CENTER")
	buffTestFrames[1]["text"]:SetText(L["Buffs"])
	buffTestFrames[1]:SetWidth(28)
	buffTestFrames[1]:SetHeight(28)
	buffTestFrames[1]:SetScale(db.buffScale)
	buffTestFrames[1]:SetPoint("TOPLEFT", "UIParent", "BOTTOMLEFT", db.buffAnchor[4], db.buffAnchor[5])
	buffTestFrames[1]:SetFrameStrata("HIGH")
	buffTestFrames[1]:EnableMouse(true)
	buffTestFrames[1]:SetClampedToScreen(true)
	buffTestFrames[1]:SetMovable(true)
	buffTestFrames[1]:SetResizable(true)
	buffTestFrames[1]:RegisterForDrag("LeftButton")
	buffTestFrames[1]:SetScript("OnDragStart", onBuffDragStart)
	buffTestFrames[1]:SetScript("OnDragStop", onBuffDragStop)

	local rowCounter = 1
	local Xoffset, Yoffset = 0, 0
	local rowXoffset, rowYoffset = 0, 0
	for i=2, db.buffIconsPerRow*db.buffMaxWraps do
		Xoffset = Xoffset + db.buffXoffset
		Yoffset = Yoffset + db.buffYoffset
		if i%db.buffIconsPerRow == 1 then
			Xoffset, Yoffset = 0, 0
			rowCounter = rowCounter + 1
			rowXoffset = rowXoffset + db.buffWrapXoffset
			rowYoffset = rowYoffset + db.buffWrapYoffset
		elseif db.buffIconsPerRow == 1 then
			Xoffset, Yoffset = 0, 0
			rowCounter = rowCounter + 1
			rowXoffset = rowXoffset + db.buffWrapXoffset
			rowYoffset = rowYoffset + db.buffWrapYoffset
		end
		buffTestFrames[i] = CreateFrame("Frame", nil, UIParent)
		buffTestFrames[i]["bg"] = buffTestFrames[i]:CreateTexture("Background", "BACKGROUND")
		buffTestFrames[i]["bg"]:SetTexture(0, 0.75, 0, 0.3)
		buffTestFrames[i]["bg"]:SetAllPoints()
		buffTestFrames[i]["text"] = buffTestFrames[i]:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		buffTestFrames[i]["text"]:SetPoint("CENTER")
		buffTestFrames[i]["text"]:SetText(i)
		buffTestFrames[i]:SetWidth(28)
		buffTestFrames[i]:SetHeight(28)
		buffTestFrames[i]:SetScale(db.buffScale)
		buffTestFrames[i]:SetPoint("CENTER", buffTestFrames[1], "CENTER", Xoffset+rowXoffset, Yoffset+rowYoffset)
		buffTestFrames[i]:SetFrameStrata("HIGH")
	end
end

--debuff
local function onDebuffDragStart(self) self:StartMoving() end
local function onDebuffDragStop(self)
	self:StopMovingOrSizing()
	addon.db.profile.debuffAnchor[4] = self:GetLeft()
	addon.db.profile.debuffAnchor[5] = self:GetTop()
	debuffHeader:SetPoint(unpack(addon.db.profile.debuffAnchor))
end

local function hideDebuffTestAnchor()
	if debuffTestFrames[1] then for _, v in pairs(debuffTestFrames) do v:Hide() end end
	debuffTestFrameshown = false
end

local function createDebuffTestAnchor()
	hideDebuffTestAnchor()
	debuffTestFrameshown = true
	local db = addon.db.profile
	debuffTestFrames[1] = CreateFrame("Frame", nil, UIParent)
	debuffTestFrames[1]["bg"] = debuffTestFrames[1]:CreateTexture("Background", "BACKGROUND")
	debuffTestFrames[1]["bg"]:SetTexture(1, 0, 0, 0.5)
	debuffTestFrames[1]["bg"]:SetAllPoints()
	debuffTestFrames[1]["text"] = debuffTestFrames[1]:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	debuffTestFrames[1]["text"]:SetPoint("CENTER")
	debuffTestFrames[1]["text"]:SetText(L["Debuffs"])
	debuffTestFrames[1]:SetWidth(28)
	debuffTestFrames[1]:SetHeight(28)
	debuffTestFrames[1]:SetScale(db.debuffScale)
	debuffTestFrames[1]:SetPoint("TOPLEFT", "UIParent", "BOTTOMLEFT", db.debuffAnchor[4], db.debuffAnchor[5])
	debuffTestFrames[1]:SetFrameStrata("HIGH")
	debuffTestFrames[1]:EnableMouse(true)
	debuffTestFrames[1]:SetClampedToScreen(true)
	debuffTestFrames[1]:SetMovable(true)
	debuffTestFrames[1]:SetResizable(true)
	debuffTestFrames[1]:RegisterForDrag("LeftButton")
	debuffTestFrames[1]:SetScript("OnDragStart", onDebuffDragStart)
	debuffTestFrames[1]:SetScript("OnDragStop", onDebuffDragStop)

	local rowCounter = 1
	local Xoffset, Yoffset = 0, 0
	local rowXoffset, rowYoffset = 0, 0
	for i=2, db.debuffIconsPerRow*db.debuffMaxWraps do
		Xoffset = Xoffset + db.debuffXoffset
		Yoffset = Yoffset + db.debuffYoffset
		if i%db.debuffIconsPerRow == 1 then
			Xoffset, Yoffset = 0, 0
			rowCounter = rowCounter + 1
			rowXoffset = rowXoffset + db.debuffWrapXoffset
			rowYoffset = rowYoffset + db.debuffWrapYoffset
		elseif db.debuffIconsPerRow == 1 then
			Xoffset, Yoffset = 0, 0
			rowCounter = rowCounter + 1
			rowXoffset = rowXoffset + db.debuffWrapXoffset
			rowYoffset = rowYoffset + db.debuffWrapYoffset
		end
		debuffTestFrames[i] = CreateFrame("Frame", nil, UIParent)
		debuffTestFrames[i]["bg"] = debuffTestFrames[i]:CreateTexture("Background", "BACKGROUND")
		debuffTestFrames[i]["bg"]:SetTexture(0.75, 0, 0, 0.3)
		debuffTestFrames[i]["bg"]:SetAllPoints()
		debuffTestFrames[i]["text"] = debuffTestFrames[i]:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		debuffTestFrames[i]["text"]:SetPoint("CENTER")
		debuffTestFrames[i]["text"]:SetText(i)
		debuffTestFrames[i]:SetWidth(28)
		debuffTestFrames[i]:SetHeight(28)
		debuffTestFrames[i]:SetScale(db.debuffScale)
		debuffTestFrames[i]:SetPoint("CENTER", debuffTestFrames[1], "CENTER", Xoffset+rowXoffset, Yoffset+rowYoffset)
		debuffTestFrames[i]:SetFrameStrata("HIGH")
	end
end

local LIST_VALUES = {
	["sortMethod"] = {
		NAME = L["Name"],
		INDEX = L["Index"],
		TIME = L["Time"],
	},
	["sortReverse"] = {
		["+"] = L["Ascending"],
		["-"] = L["Descending"],
	},
	["durationPos"] = {
		TOP    = L["Top"],
		BOTTOM = L["Bottom"],
		LEFT   = L["Left"],
		RIGHT  = L["Right"],
	},
	["outline"] = {
		NONE         = L["None"],
		MONOCHROMEOUTLINE   = L["Monochrome"],
		OUTLINE      = L["Outline"],
		THICKOUTLINE = L["Thick outline"],
	},
	["remainingTimeFormat"] = {
		["HH:MM:SS"] = L["HH:MM:SS"],
		["Abbreviated"] = L["Abbreviated"],
	},
}

local options = {
	type = "group",
	handler = addon,
	get = function(info) return addon.db.profile[info[1]] end,
	set = function(info, v) addon.db.profile[info[1]] = v end,
	args = {
		warning = {
			type = "description",
			fontSize = "large",
			name = ("|cffff0000%s|r"):format(L["Changing some of the values might require reloading the UI to take effect. Watch out for the red text in the options tooltip description!"]),
			order = 1,
		},
		general_header = {
			type = "header",
			name = L["General"],
			order = 5,
		},
		sortMethod = {
			order = 10,
			type = "select",
			name = L["Sort method"],
			desc = L["How to sort the buffs/debuffs"],
			values = LIST_VALUES["sortMethod"],
			set = function (info, v)
				addon.db.profile[info[1]] = v
				setHeaderAttributes(buffHeader, "nivBuffButtonTemplate", true)
				setHeaderAttributes(debuffHeader, "nivBuffButtonTemplate", true)
				for _,btn in buffHeader:ActiveButtons() do btn:Hide() updateAuraButtonStyle(btn, buffHeader.filter) btn:Show() end
				for _,btn in debuffHeader:ActiveButtons() do btn:Hide() updateAuraButtonStyle(btn, debuffHeader.filter) btn:Show() end
			end,
		},
		showWeaponEnch = {
			order = 15,
			type = "toggle",
			name = L["Show weapon enchantments"],
			desc = ("|cffff0000%s|r"):format(L["This change requires reloading UI to take effect"]),
		},
		useButtonFacade = {
			order = 20,
			type = "toggle",
			name = L["Use Masque"],
			desc = ("|cffff0000%s|r"):format(L["This change requires reloading UI to take effect"]),
		},

		coloredBorder = {
			order = 25,
			type = "toggle",
			name = L["Colored border"],
			desc = L["Highlight debuffs and weapon enchants with a different border color"],--("|cffff0000%s|r"):format(L["This change requires reloading UI to take effect"]),
			set = function (info, v)
				addon.db.profile[info[1]] = v
				for _,btn in buffHeader:ActiveButtons() do btn:Hide() updateAuraButtonStyle(btn, buffHeader.filter) btn:Show() end
				for _,btn in debuffHeader:ActiveButtons() do btn:Hide() updateAuraButtonStyle(btn, debuffHeader.filter) btn:Show() end
			end,
		},
		borderBrightness = {
			order = 30,
			type = "range",
			name = L["Border brightness"],
			desc = L["Brightness of the default non-colored icon border ( 0 -> black, 1 -> white )"],
			min = 0, max = 1,
			set = function (info, v)
				addon.db.profile[info[1]] = v
				grey = v
				for _,btn in buffHeader:ActiveButtons() do btn:Hide() updateAuraButtonStyle(btn, buffHeader.filter) btn:Show() end
				for _,btn in debuffHeader:ActiveButtons() do btn:Hide() updateAuraButtonStyle(btn, debuffHeader.filter) btn:Show() end
			end,
		},
		blinkTime = {
			order = 35,
			type = "range",
			name = L["Blink start time"],
			desc = L["A buff/debuff icon will blink when it expires in less than X seconds, set to 0 to disable"],
			min = 0, max = 30,
		},
		blinkSpeed = {
			order = 40,
			type = "range",
			name = L["Blink speed"],
			desc = L["Blinking speed as number of blink cycles per second"],
			min = 1, max = 10, step = 1,
			set = function (info, v)
				addon.db.profile[info[1]] = v
				blinkStep = v/10
			end,
		},
		duration_header = {
			type = "header",
			name = L["Duration"],
			order = 42,
		},
		showDurationSpiral = {
			order = 45,
			type = "toggle",
			name = L["Show duration spiral"],
			desc = ("|cffff0000%s|r"):format(L["This change requires reloading UI to take effect"]),
		},
		showDurationBar = {
			order = 50,
			type = "toggle",
			name = L["Show duration bar"],
			set = function (info, v)
				addon.db.profile[info[1]] = v
				for _,btn in buffHeader:ActiveButtons() do addon:showDurationBar(btn) end
				for _,btn in debuffHeader:ActiveButtons() do addon:showDurationBar(btn) end
			end,
		},
		showDurationTimers = {
			order = 55,
			type = "toggle",
			name = L["Show duration text"],
		},
		remainingTimeFormat = {
			order = 58,
			type = "select",
			name = L["Duration time format"],
			values = LIST_VALUES["remainingTimeFormat"],
		},
		durationPos = {
			order = 60,
			type = "select",
			name = L["Duration position"],
			values = LIST_VALUES["durationPos"],
			set = function (info, v)
				addon.db.profile[info[1]] = v
				for _,btn in buffHeader:ActiveButtons() do addon:durationPos(btn) end
				for _,btn in debuffHeader:ActiveButtons() do addon:durationPos(btn) end
			end,
		},
		durationXoffset = {
			order = 63,
			type = "range",
			name = L["Duration horizontal offset"],
			desc = L["Positive values adjust to the right, negative values adjust to the left"],
			min = -100, max = 100, step = 1,
			set = function (info, v)
				addon.db.profile[info[1]] = v
				for _,btn in buffHeader:ActiveButtons() do addon:durationPos(btn) end
				for _,btn in debuffHeader:ActiveButtons() do addon:durationPos(btn) end
			end,
		},
		durationYoffset = {
			order = 64,
			type = "range",
			name = L["Duration vertical offset"],
			desc = L["Positive values adjust upwards, negative values adjust downwards"],
			min = -100, max = 100, step = 1,
			set = function (info, v)
				addon.db.profile[info[1]] = v
				for _,btn in buffHeader:ActiveButtons() do addon:durationPos(btn) end
				for _,btn in debuffHeader:ActiveButtons() do addon:durationPos(btn) end
			end,
		},
		durationFont = {
			type = "select",
			name = L["Duration font"],
			--desc = ("|cffff0000%s|r"):format(L["This change requires reloading UI to take effect"]),
			order = 67,
			--dialogControl = 'LSM30_Font',
			values = LSM3:List("font"),
			get = function(info)
				for i, v in next, LSM3:List("font") do
					if v == addon.db.profile[info[1]] then return i end
				end
			end,
			set = function(info, v)
				local list = LSM3:List("font")
				addon.db.profile[info[1]] = list[v]
				for _,btn in buffHeader:ActiveButtons() do btn.text:SetFont(LSM3:Fetch(LSM3.MediaType.FONT, addon.db.profile.durationFont), addon.db.profile.durationFontSize, addon.db.profile.durationFontStyle) end
				for _,btn in debuffHeader:ActiveButtons() do btn.text:SetFont(LSM3:Fetch(LSM3.MediaType.FONT, addon.db.profile.durationFont), addon.db.profile.durationFontSize, addon.db.profile.durationFontStyle) end
			end,
		},
		durationFontStyle = {
			order = 68,
			type = "select",
			name = L["Duration font outline"],
			values = LIST_VALUES["outline"],
			--desc = ("|cffff0000%s|r"):format(L["This change requires reloading UI to take effect"]),
			get = function (info)
				if not addon.db.profile[info[1]] then return "NONE" else return addon.db.profile[info[1]] end
			end,
			set = function (info, v)
				if v == "NONE" then v = nil end
				addon.db.profile[info[1]] = v
				for _,btn in buffHeader:ActiveButtons() do btn.text:SetFont(LSM3:Fetch(LSM3.MediaType.FONT, addon.db.profile.durationFont), addon.db.profile.durationFontSize, addon.db.profile.durationFontStyle) end
				for _,btn in debuffHeader:ActiveButtons() do btn.text:SetFont(LSM3:Fetch(LSM3.MediaType.FONT, addon.db.profile.durationFont), addon.db.profile.durationFontSize, addon.db.profile.durationFontStyle) end
			end,
		},
		durationFontSize = {
			order = 69,
			type = "range",
			name = L["Duration font size"],
			--desc = ("|cffff0000%s|r"):format(L["This change requires reloading UI to take effect"]),
			min = 1, max = 20, step = 1,
			set = function (info, v)
				addon.db.profile[info[1]] = v
				for _,btn in buffHeader:ActiveButtons() do btn.text:SetFont(LSM3:Fetch(LSM3.MediaType.FONT, addon.db.profile.durationFont), addon.db.profile.durationFontSize, addon.db.profile.durationFontStyle) end
				for _,btn in debuffHeader:ActiveButtons() do btn.text:SetFont(LSM3:Fetch(LSM3.MediaType.FONT, addon.db.profile.durationFont), addon.db.profile.durationFontSize, addon.db.profile.durationFontStyle) end
			end,
		},
		durationFontColor = {
			order = 70,
			type = "color",
			name = L["Duration font color"],
			--desc = ("|cffff0000%s|r"):format(L["This change requires reloading UI to take effect"]),
			get = function(info)
				return addon.db.profile[info[1]].r, addon.db.profile[info[1]].g, addon.db.profile[info[1]].b
			end,
			set = function(info, r, g, b)
				addon.db.profile[info[1]].r, addon.db.profile[info[1]].g, addon.db.profile[info[1]].b = r, g, b
				for _,btn in buffHeader:ActiveButtons() do btn.text:SetTextColor(r, g, b) end
				for _,btn in debuffHeader:ActiveButtons() do btn.text:SetTextColor(r, g, b) end
			end,
		},
		stacks_header = {
			type = "header",
			name = L["Stacks"],
			order = 79,
		},
		stacksXoffset = {
			order = 80,
			type = "range",
			name = L["Stack horizontal offset"],
			desc = L["Positive values adjust to the right, negative values adjust to the left"],
			min = -100, max = 100, step = 1,
			set = function (info, v)
				addon.db.profile[info[1]] = v
				for _,btn in buffHeader:ActiveButtons() do addon:stackPos(btn) end
				for _,btn in debuffHeader:ActiveButtons() do addon:stackPos(btn) end
			end,
		},
		stacksYoffset = {
			order = 81,
			type = "range",
			name = L["Stack vertical offset"],
			desc = L["Positive values adjust upwards, negative values adjust downwards"],
			min = -100, max = 100, step = 1,
			set = function (info, v)
				addon.db.profile[info[1]] = v
				for _,btn in buffHeader:ActiveButtons() do addon:stackPos(btn) end
				for _,btn in debuffHeader:ActiveButtons() do addon:stackPos(btn) end
			end,
		},
		stackFont = {
			type = "select",
			name = L["Stack font"],
			--desc = ("|cffff0000%s|r"):format(L["This change requires reloading UI to take effect"]),
			order = 87,
			--dialogControl = 'LSM30_Font',
			values = LSM3:List("font"),
			get = function(info)
				for i, v in next, LSM3:List("font") do
					if v == addon.db.profile[info[1]] then return i end
				end
			end,
			set = function(info, v)
				local list = LSM3:List("font")
				addon.db.profile[info[1]] = list[v]
				for _,btn in buffHeader:ActiveButtons() do btn.stacks:SetFont(LSM3:Fetch(LSM3.MediaType.FONT, addon.db.profile.stackFont), addon.db.profile.stackFontSize, addon.db.profile.stackFontStyle) end
				for _,btn in debuffHeader:ActiveButtons() do btn.stacks:SetFont(LSM3:Fetch(LSM3.MediaType.FONT, addon.db.profile.stackFont), addon.db.profile.stackFontSize, addon.db.profile.stackFontStyle) end
			end,
		},
		stackFontStyle = {
			order = 88,
			type = "select",
			name = L["Stack outline"],
			values = LIST_VALUES["outline"],
			--desc = ("|cffff0000%s|r"):format(L["This change requires reloading UI to take effect"]),
			get = function (info)
				if not addon.db.profile[info[1]] then return "NONE" else return addon.db.profile[info[1]] end
			end,
			set = function (info, v)
				if v == "NONE" then v = nil end
				addon.db.profile[info[1]] = v
				for _,btn in buffHeader:ActiveButtons() do btn.stacks:SetFont(LSM3:Fetch(LSM3.MediaType.FONT, addon.db.profile.stackFont), addon.db.profile.stackFontSize, addon.db.profile.stackFontStyle) end
				for _,btn in debuffHeader:ActiveButtons() do btn.stacks:SetFont(LSM3:Fetch(LSM3.MediaType.FONT, addon.db.profile.stackFont), addon.db.profile.stackFontSize, addon.db.profile.stackFontStyle) end
			end,
		},
		stackFontSize = {
			order = 89,
			type = "range",
			name = L["Stack size"],
			--desc = ("|cffff0000%s|r"):format(L["This change requires reloading UI to take effect"]),
			min = 1, max = 20, step = 1,
			set = function (info, v)
				addon.db.profile[info[1]] = v
				for _,btn in buffHeader:ActiveButtons() do btn.stacks:SetFont(LSM3:Fetch(LSM3.MediaType.FONT, addon.db.profile.stackFont), addon.db.profile.stackFontSize, addon.db.profile.stackFontStyle) end
				for _,btn in debuffHeader:ActiveButtons() do btn.stacks:SetFont(LSM3:Fetch(LSM3.MediaType.FONT, addon.db.profile.stackFont), addon.db.profile.stackFontSize, addon.db.profile.stackFontStyle) end
			end,
		},
		stackFontColor = {
			order = 90,
			type = "color",
			name = L["Stack font color"],
			--desc = ("|cffff0000%s|r"):format(L["This change requires reloading UI to take effect"]),
			get = function(info)
				return addon.db.profile[info[1]].r, addon.db.profile[info[1]].g, addon.db.profile[info[1]].b
			end,
			set = function(info, r, g, b)
				addon.db.profile[info[1]].r, addon.db.profile[info[1]].g, addon.db.profile[info[1]].b = r, g, b
				for _,btn in buffHeader:ActiveButtons() do btn.stacks:SetTextColor(r, g, b) end
				for _,btn in debuffHeader:ActiveButtons() do btn.stacks:SetTextColor(r, g, b) end
			end,
		},
		-- BUFFS
		buffs_header = {
			type = "header",
			name = L["Buffs"],
			order = 100,
		},
		test_anchor = {
			order = 200,
			type = "execute",
			name = L["Show/Hide Anchor"],
			desc = L["Show/Hide test anchor frame"],
			func = function()
				if buffTestFrameshown then hideBuffTestAnchor() else createBuffTestAnchor() end
			end
		},
		newline1 = {
			type = "description",
			name = "\n",
			order = 300,
		},
		buffIconsPerRow = {
			order = 400,
			type = "range",
			name = L["Icons/Row"],
			min = 1, max = 120, step = 1,
			set = function (info, v)
				addon.db.profile[info[1]] = v
				if buffTestFrameshown then createBuffTestAnchor() end
				setHeaderAttributes(buffHeader, "nivBuffButtonTemplate", true)
			end,
		},
		buffMaxWraps = {
			order = 500,
			type = "range",
			name = L["Number of Rows"],
			min = 1, max = 120, step = 1,
			set = function (info, v)
				addon.db.profile[info[1]] = v
				if buffTestFrameshown then createBuffTestAnchor() end
				setHeaderAttributes(buffHeader, "nivBuffButtonTemplate", true)
			end,
		},
		buffScale = {
			order = 600,
			type = "range",
			name = L["Scale"],
			softMin = 0.5, softMax = 3,
			set = function (info, v)
				addon.db.profile[info[1]] = v
				if buffTestFrameshown then createBuffTestAnchor() end
				setHeaderAttributes(buffHeader, "nivBuffButtonTemplate", true)
			end,
		},
		newline2 = {
			type = "description",
			name = "\n",
			order = 700,
		},
		buffXoffset = {
			order = 800,
			type = "range",
			name = L["Horizontal offset"],
			desc = L["Positive values adjust to the right, negative values adjust to the left"],
			softMin = -100, softMax = 100,
			set = function (info, v)
				addon.db.profile[info[1]] = v
				if buffTestFrameshown then createBuffTestAnchor() end
				setHeaderAttributes(buffHeader, "nivBuffButtonTemplate", true)
			end,
		},
		buffYoffset = {
			order = 900,
			type = "range",
			name = L["Vertical offset"],
			desc = L["Positive values adjust upwards, negative values adjust downwards"],
			softMin = -100, softMax = 100,
			set = function (info, v)
				addon.db.profile[info[1]] = v
				if buffTestFrameshown then createBuffTestAnchor() end
				setHeaderAttributes(buffHeader, "nivBuffButtonTemplate", true)
			end,
		},
		newline2 = {
			type = "description",
			name = "\n",
			order = 1000,
		},
		buffWrapXoffset = {
			order = 1100,
			type = "range",
			name = L["Horizontal row offset"],
			desc = L["Positive values adjust to the right, negative values adjust to the left"],
			softMin = -100, softMax = 100,
			set = function (info, v)
				addon.db.profile[info[1]] = v
				if buffTestFrameshown then createBuffTestAnchor() end
				setHeaderAttributes(buffHeader, "nivBuffButtonTemplate", true)
			end,
		},
		buffWrapYoffset = {
			order = 1200,
			type = "range",
			name = L["Vertical row offset"],
			desc = L["Positive values adjust upwards, negative values adjust downwards"],
			softMin = -100, softMax = 100,
			set = function (info, v)
				addon.db.profile[info[1]] = v
				if buffTestFrameshown then createBuffTestAnchor() end
				setHeaderAttributes(buffHeader, "nivBuffButtonTemplate", true)
			end,
		},
		newline3= {
			type = "description",
			name = "\n",
			order = 1250,
		},
		sortBuffReverse = {
			order = 1300,
			type = "select",
			name = L["Sort type"],
			values = LIST_VALUES["sortReverse"],
			set = function (info, v)
				addon.db.profile[info[1]] = v
				if buffTestFrameshown then createBuffTestAnchor() end
				setHeaderAttributes(buffHeader, "nivBuffButtonTemplate", true)
				for _,btn in buffHeader:ActiveButtons() do btn:Hide() updateAuraButtonStyle(btn, buffHeader.filter) btn:Show() end
			end,
		},
		-- DEBUFFS
		debuffs_header = {
			type = "header",
			name = L["Debuffs"],
			order = 2100,
		},
		debuff_test_anchor = {
			order = 2200,
			type = "execute",
			name = L["Show/Hide Anchor"],
			desc = L["Show/Hide test anchor frame"],
			func = function()
				if debuffTestFrameshown then hideDebuffTestAnchor() else createDebuffTestAnchor() end
			end
		},
		newline10 = {
			type = "description",
			name = "\n",
			order = 2300,
		},
		debuffIconsPerRow = {
			order = 2400,
			type = "range",
			name = L["Icons/Row"],
			min = 1, max = 120, step = 1,
			set = function (info, v)
				addon.db.profile[info[1]] = v
				if debuffTestFrameshown then createDebuffTestAnchor() end
				setHeaderAttributes(debuffHeader, "nivDebuffButtonTemplate", false)
			end,
		},
		debuffMaxWraps = {
			order = 2500,
			type = "range",
			name = L["Number of Rows"],
			min = 1, max = 120, step = 1,
			set = function (info, v)
				addon.db.profile[info[1]] = v
				if debuffTestFrameshown then createDebuffTestAnchor() end
				setHeaderAttributes(debuffHeader, "nivDebuffButtonTemplate", false)
			end,
		},
		debuffScale = {
			order = 2600,
			type = "range",
			name = L["Scale"],
			softMin = 0.5, softMax = 3,
			set = function (info, v)
				addon.db.profile[info[1]] = v
				if debuffTestFrameshown then createDebuffTestAnchor() end
				setHeaderAttributes(debuffHeader, "nivDebuffButtonTemplate", false)
			end,
		},
		newline20 = {
			type = "description",
			name = "\n",
			order = 2700,
		},
		debuffXoffset = {
			order = 2800,
			type = "range",
			name = L["Horizontal offset"],
			desc = L["Positive values adjust to the right, negative values adjust to the left"],
			softMin = -100, softMax = 100,
			set = function (info, v)
				addon.db.profile[info[1]] = v
				if debuffTestFrameshown then createDebuffTestAnchor() end
				setHeaderAttributes(debuffHeader, "nivDebuffButtonTemplate", false)
			end,
		},
		debuffYoffset = {
			order = 2900,
			type = "range",
			name = L["Vertical offset"],
			desc = L["Positive values adjust upwards, negative values adjust downwards"],
			softMin = -100, softMax = 100,
			set = function (info, v)
				addon.db.profile[info[1]] = v
				if debuffTestFrameshown then createDebuffTestAnchor() end
				setHeaderAttributes(debuffHeader, "nivDebuffButtonTemplate", false)
			end,
		},
		newline30 = {
			type = "description",
			name = "\n",
			order = 3000,
		},
		debuffWrapXoffset = {
			order = 3100,
			type = "range",
			name = L["Horizontal row offset"],
			desc = L["Positive values adjust to the right, negative values adjust to the left"],
			softMin = -100, softMax = 100,
			set = function (info, v)
				addon.db.profile[info[1]] = v
				if debuffTestFrameshown then createDebuffTestAnchor() end
				setHeaderAttributes(debuffHeader, "nivDebuffButtonTemplate", false)
			end,
		},
		debuffWrapYoffset = {
			order = 3200,
			type = "range",
			name = L["Vertical row offset"],
			desc = L["Positive values adjust upwards, negative values adjust downwards"],
			softMin = -100, softMax = 100,
			set = function (info, v)
				addon.db.profile[info[1]] = v
				if debuffTestFrameshown then createDebuffTestAnchor() end
				setHeaderAttributes(debuffHeader, "nivDebuffButtonTemplate", false)
			end,
		},
		newline40= {
			type = "description",
			name = "\n",
			order = 3250,
		},
		sortDebuffReverse = {
			order = 3300,
			type = "select",
			name = L["Sort type"],
			values = LIST_VALUES["sortReverse"],
			set = function (info, v)
				addon.db.profile[info[1]] = v
				if debuffTestFrameshown then createDebuffTestAnchor() end
				setHeaderAttributes(debuffHeader, "nivDebuffButtonTemplate", false)
				for _,btn in debuffHeader:ActiveButtons() do btn:Hide() updateAuraButtonStyle(btn, debuffHeader.filter) btn:Show() end
			end,
		},

	}

}

-----------------------------------------------------------------------
-- Slash command
--

local function slashCommand(input)
	InterfaceOptionsFrame_OpenToCategory("nivBuffs")
	InterfaceOptionsFrame_OpenToCategory("nivBuffs")
end

-----------------------------------------------------------------------
-- Event handler
--

function nivBuffs:ADDON_LOADED(event, addon)
	if (addon ~= 'nivBuffs') then return end
		self:UnregisterEvent(event)

		self.db = LibStub("AceDB-3.0"):New("nivBuffDB", defaults, true)

		self.callbacks = CallbackHandler:New(self)

		local function profileUpdate()
			self.callbacks:Fire("OnProfileUpdate")
			setHeaderAttributes(buffHeader, "nivBuffButtonTemplate", true)
			setHeaderAttributes(debuffHeader, "nivBuffButtonTemplate", true)
		end

		self.db.RegisterCallback(self, "OnProfileChanged", profileUpdate)
		self.db.RegisterCallback(self, "OnProfileCopied", profileUpdate)
		self.db.RegisterCallback(self, "OnProfileReset", profileUpdate)

		LibStub("AceConfig-3.0"):RegisterOptionsTable("nivBuffs", options)
		LibStub("AceConfigDialog-3.0"):AddToBlizOptions("nivBuffs", "nivBuffs")
		LibStub("AceConfig-3.0"):RegisterOptionsTable("nivBuffs Profile", LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db))
		LibStub("AceConfigDialog-3.0"):AddToBlizOptions("nivBuffs Profile", L["Profile"], "nivBuffs")

		SlashCmdList.nivBuffs = slashCommand
		SLASH_nivBuffs1 = "/nivbuffs"
		SLASH_nivBuffs2 = "/niv"
		BF = LBF and self.db.profile.useButtonFacade
		grey = self.db.profile.borderBrightness
		blinkStep = self.db.profile.blinkSpeed / 10

		-- hide Blizzard Aura Frames
		BuffFrame:Hide()
		TemporaryEnchantFrame:Hide()
		BuffFrame:UnregisterAllEvents()

		-- buttonfacade
		if not self.db.profile.nivBuffs_BF then self.db.profile.nivBuffs_BF = {} end

		if BF then
			LBF:Register("nivBuffs", self.BFSkinCallBack, self)

			bfButtons = LBF:Group("nivBuffs")
			bfButtons:AddButton(self.db.profile.nivBuffs_BF.skinID, self.db.profile.nivBuffs_BF.gloss, self.db.profile.nivBuffs_BF.backdrop, self.db.profile.nivBuffs_BF.colors)
		end

		-- init headers
		setHeaderAttributes(buffHeader, "nivBuffButtonTemplate", true)
		buffHeader:SetPoint(unpack(self.db.profile.buffAnchor))
		buffHeader:Show()

		setHeaderAttributes(debuffHeader, "nivDebuffButtonTemplate", false)
		debuffHeader:SetPoint(unpack(self.db.profile.debuffAnchor))
		debuffHeader:Show()
end

function nivBuffs:BFSkinCallBack(skinID, gloss, backdrop, group, button, colors)
	if group then return end
	self.db.profile.nivBuffs_BF.skinID = skinID
	self.db.profile.nivBuffs_BF.gloss = gloss
	self.db.profile.nivBuffs_BF.backdrop = backdrop
	self.db.profile.nivBuffs_BF.colors = colors
end