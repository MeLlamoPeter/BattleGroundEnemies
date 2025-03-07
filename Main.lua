local AddonName, Data = ...
local L = Data.L
local LSM = LibStub("LibSharedMedia-3.0")
local DRList = LibStub("DRList-1.0")

local LibRaces = LibStub("LibRaces-1.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local LibChangelog = LibStub("LibChangelog")

--upvalues
local _G = _G
local math_floor = math.floor
local gsub = gsub
local math_random = math.random
local math_max = math.max
local pairs = pairs
local print = print
local table_insert = table.insert
local table_remove = table.remove
local time = time
local type = type
local unpack = unpack

local AuraUtil = AuraUtil
local C_PvP = C_PvP
local CreateFrame = CreateFrame
local CTimerNewTicker = C_Timer.NewTicker
local GetArenaOpponentSpec = GetArenaOpponentSpec
local GetBattlefieldArenaFaction = GetBattlefieldArenaFaction
local GetBattlefieldScore = GetBattlefieldScore
local GetBattlefieldTeamInfo = GetBattlefieldTeamInfo
local GetBestMapForUnit = C_Map.GetBestMapForUnit
local GetNumBattlefieldScores = GetNumBattlefieldScores
local GetNumGroupMembers = GetNumGroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local GetSpecializationInfoByID = GetSpecializationInfoByID
local GetSpellInfo = GetSpellInfo
local GetTime = GetTime
local GetUnitName = GetUnitName
local InCombatLockdown = InCombatLockdown
local IsInBrawl = C_PvP.IsInBrawl
local IsInInstance = IsInInstance
local IsInRaid = IsInRaid
local UnitInRange = UnitInRange
local IsItemInRange = IsItemInRange
local IsSpellInRange = IsSpellInRange
local IsRatedBattleground = C_PvP.IsRatedBattleground
local RequestBattlefieldScoreData = RequestBattlefieldScoreData
local RequestCrowdControlSpell = C_PvP.RequestCrowdControlSpell
local SetBattlefieldScoreFaction = SetBattlefieldScoreFaction
local UnitExists = UnitExists
local UnitFactionGroup = UnitFactionGroup
local UnitGUID = UnitGUID
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsGhost = UnitIsGhost
local UnitName = UnitName
local UnitRace = UnitRace
local UnitRealmRelationship = UnitRealmRelationship

local IsRetail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
local IsClassic = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
local IsTBCC = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC
local IsWrath = WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC

local HasSpeccs = not not GetNumSpecializationsForClassID
local HasRBG = not not IsRatedBattleground

local MaxLevel = GetMaxPlayerLevel()

local LGIST
if HasSpeccs then
	LGIST=LibStub:GetLibrary("LibGroupInSpecT-1.1")
end


local LibRangeCheck = LibStub("LibRangeCheck-3.0")

local function InRange(unit)
  return LibRangeCheck:GetRange(unit, true);
end

if not GetUnitName then
	GetUnitName = function(unit, showServerName)
		local name, server = UnitName(unit);

		if ( server and server ~= "" ) then
			if ( showServerName ) then
				return name.."-"..server;
			else
				local relationship = UnitRealmRelationship(unit);
				if (relationship == LE_REALM_RELATION_VIRTUAL) then
					return name;
				else
					return name..FOREIGN_SERVER_LABEL;
				end
			end
		else
			return name;
		end
	end
end


LSM:Register("font", "PT Sans Narrow Bold", [[Interface\AddOns\BattleGroundEnemies\Fonts\PT Sans Narrow Bold.ttf]])
LSM:Register("statusbar", "UI-StatusBar", "Interface\\TargetingFrame\\UI-StatusBar")

local BattleGroundEnemies = CreateFrame("Frame", "BattleGroundEnemies", UIParent)
BattleGroundEnemies.Counter = {}

--todo: add castbars and combat indicator to testmode
--move unitID update for allies

-- for Clique Support
ClickCastFrames = ClickCastFrames or {}


--[[ 
Ally frames use Scoreboard, FakePlayers, GroupMembers, 
Enemy frames use Scoreboard, FakePlayers, ArenaPlayers, CombatLog
]]

local PlayerSources = {
	Scoreboard = "Scoreboard",
	GroupMembers = "GroupMembers",
	ArenaPlayers = "ArenaPlayers",
	FakePlayers = "FakePlayers",
	CombatLog = "CombatLog"
}

local PlayerTypes = {
	Allies = "Allies",
	Enemies = "Enemies"
}



local function getFilterFromAuraInfo(aura)
	return aura.isHarmful and "HARMFUL" or "HELPFUL"
end

--variables used in multiple functions, if a variable is only used by one function its declared above that function
--BattleGroundEnemies.BattlegroundBuff --contains the battleground specific enemy buff to watchout for of the current active battlefield
BattleGroundEnemies.BattleGroundDebuffs = {} --contains battleground specific debbuffs to watchout for of the current active battlefield
BattleGroundEnemies.Testmode = {
	BGSizeTestmode = 5,
	Active = false,
	FakePlayerAuras = {},--key = playerbutton, value = {}
	FakePlayerDRs = {}, --key = playerButtonTable, value = {categoryname = {state = 0, expirationTime}
	FakeRaidTargetIcons = {} --key = playerButtonTable, value = {categoryname = {state = 0, expirationTime}}
}

BattleGroundEnemies.IsRatedBG = false
BattleGroundEnemies.CurrentMapID = false --contains the map id of the current active battleground
BattleGroundEnemies.ButtonModules = {} --contains moduleFrames, key is the module name

local playerFaction = UnitFactionGroup("player")
local PlayerButton --the button of the Player himself
local IsInArena --wheter or not the player is in a arena map
local IsInBattleground
local specCache = {} -- key = GUID, value = specName (localized)

--[[  from wowpedia
1	IconSmall RaidStar.png 		Yellow 4-point Star
2	IconSmall RaidCircle.png 	Orange Circle
3	IconSmall RaidDiamond.png 	Purple Diamond
4	IconSmall RaidTriangle.png 	Green Triangle
5	IconSmall RaidMoon.png 		White Crescent Moon
6	IconSmall RaidSquare.png 	Blue Square
7	IconSmall RaidCross.png 	Red "X" Cross
8	IconSmall RaidSkull.png 	White Skull
 ]]


local function UpdateFakeRaidTargetIcons(playerButton)
	local testmode = BattleGroundEnemies.Testmode
	local fakeRaidTargetIcons = testmode.FakeRaidTargetIcons
	local somethingChanged = false

	if fakeRaidTargetIcons[playerButton] then
		fakeRaidTargetIcons[playerButton] = nil --player lost the raidtargeticon
		somethingChanged = true
	else
		local randomIndex = math_random(1, 8)
		local indexAlreadyUsed = false
		for playerBtn, targetIcon in pairs(testmode.FakeRaidTargetIcons) do
			if targetIcon == randomIndex then
				indexAlreadyUsed = true
				--can't asign this one, another player already has it
				break -- move on to the next index
			end
		end

		if not indexAlreadyUsed then
			fakeRaidTargetIcons[playerButton] = randomIndex
			somethingChanged = true
		end

		--see which icons arent used yet
	end
	if somethingChanged then
		playerButton:UpdateRaidTargetIcon(fakeRaidTargetIcons[playerButton])
	end
end



local auraFilters = {"HELPFUL", "HARMFUL"}

local function CreateFakeAura(filter)
	local foundA = Data.FoundAuras[filter]

	local auraTable
	local addDRAura
	if filter == "HARMFUL" then
		addDRAura = math_random(1,5) == 1 -- 20% probability to get diminishing Aura Applied
	end

	local unitCaster, canApplyAura, castByPlayer

	if addDRAura and #foundA.foundDRAuras > 0 then

		auraTable = foundA.foundDRAuras
	else
		local addPlayerAura = math_random(1,5) == 1 --20% probablility to add a player Aura if no DR was applied
		if addPlayerAura then
			unitCaster = "player"
			canApplyAura = true
			castByPlayer = true

			auraTable = foundA.foundPlayerAuras
		else
			auraTable = foundA.foundNonPlayerAuras
		end
	end
	if not auraTable or (#auraTable <1 ) then return end
	local whichAura = math_random(1, #auraTable)
	local auraToSend = auraTable[whichAura]


	if not GetSpellInfo(auraToSend.spellId) then return end --this spellID is probably not existing in this version of the game

	local newAura = {
		applications = auraToSend.applications,
		name = GetSpellInfo(auraToSend.spellId),
		auraInstanceID = nil,
		canApplyAura = canApplyAura or auraToSend.canApplyAura,
		charges	= nil,
		dispelName = auraToSend.dispelName,
		duration = auraToSend.duration,
		expirationTime = GetTime() + auraToSend.duration,
		icon = auraToSend.icon,
		isBossAura = auraToSend.isBossAura,
		isFromPlayerOrPlayerPet	= castByPlayer or auraToSend.isFromPlayerOrPlayerPet,
		isHarmful = filter == "HARMFUL",
		isHelpful = filter == "HELPFUL",
		isNameplateOnly	= nil,
		isRaid = nil,
		isStealable	= auraToSend.isStealable,
		maxCharges = nil,
		nameplateShowAll = auraToSend.nameplateShowAll,
		nameplateShowPersonal = auraToSend.nameplateShowPersonal,
		points = nil, --	array	Variable returns - Some auras return additional values that typically correspond to something shown in the tooltip, such as the remaining strength of an absorption effect.
		sourceUnit = unitCaster or auraToSend.sourceUnit,
		spellId	= auraToSend.spellId,
		timeMod	= auraToSend.timeMod
	}

	return newAura
end

local function UpdateFakeAuras(playerButton)
	local currentTime = GetTime()

	local testmode = BattleGroundEnemies.Testmode
	local fakePlayerAuras = testmode.FakePlayerAuras
	local fakePlayerDRs = testmode.FakePlayerDRs
	fakePlayerAuras[playerButton] = fakePlayerAuras[playerButton] or {}

	for i = 1, #auraFilters do
		local filter = auraFilters[i]
		fakePlayerAuras[playerButton][filter] = fakePlayerAuras[playerButton][filter] or {}
		fakePlayerDRs[playerButton] = fakePlayerDRs[playerButton] or {}

		local createNewAura = not playerButton.isDead
		if createNewAura then
			local newFakeAura = CreateFakeAura(filter)
			if newFakeAura then
				local categoryNewAura = DRList:GetCategoryBySpellID(IsClassic and newFakeAura.name or newFakeAura.spellId)

				local dontAddNewAura
				for j = 1, #fakePlayerAuras[playerButton][filter] do

					local fakeAura = fakePlayerAuras[playerButton][filter][j]

					local categoryCurrentAura = DRList:GetCategoryBySpellID(IsClassic and fakeAura.name or fakeAura.spellId)

					if categoryCurrentAura and categoryNewAura and categoryCurrentAura == categoryNewAura then
						dontAddNewAura = true
						break
						-- if playerButton.PlayerName == "Enemy2-Realm2" then
						-- 	print("1")
						-- end

						-- end
					elseif fakePlayerDRs[playerButton][categoryNewAura] and fakePlayerDRs[playerButton][categoryNewAura].status then


					elseif newFakeAura.spellId == fakeAura.spellId then
						dontAddNewAura = true --we tried to apply the same spell twice but its not a DR, dont add it, we dont wan't to clutter it
						break
					end

					-- we already are showing this spell, check if this spell is a DR
				end

				local status = fakePlayerDRs[playerButton][categoryNewAura] and fakePlayerDRs[playerButton][categoryNewAura].status
				--check if the aura even can be applied, the new aura can only be applied if the expirationTime of the new aura would be later than the current one
				-- this is only the case if the aura is already 50% expired
				if status then
					if status <= 2 then
						local duration = newFakeAura.duration / (2^status)
						newFakeAura.duration = duration
						newFakeAura.expirationTime = currentTime + duration
					else
						dontAddNewAura = true -- we are at full DR and we can't apply the aura for a fourth time
					end
				end

				if not dontAddNewAura then
					table_insert(fakePlayerAuras[playerButton][filter], newFakeAura)
				end
			end
		end

		-- remove all expired auras
		for j = #fakePlayerAuras[playerButton][filter], 1, -1 do
			local fakeAura = fakePlayerAuras[playerButton][filter][j]
			if fakeAura.expirationTime <= currentTime then
				-- if playerButton.PlayerName == "Enemy2-Realm2" then
				-- 	print("1")
				-- end

				local category = DRList:GetCategoryBySpellID(IsClassic and fakeAura.name or fakeAura.spellId)
				if category then
					-- if playerButton.PlayerName == "Enemy2-Realm2" then
					-- 	print("2")
					-- end

					fakePlayerDRs[playerButton][category] = fakePlayerDRs[playerButton][category] or {}

					local resetDuration = DRList:GetResetTime(category)
					fakePlayerDRs[playerButton][category].expirationTime = fakeAura.expirationTime + resetDuration
					fakePlayerDRs[playerButton][category].status = (fakePlayerDRs[playerButton][category].status or 0) + 1
					-- if playerButton.PlayerName == "Enemy2-Realm2" then
					-- 	print("3", FakePlayerDRs[playerButton][category].status)
					-- end
				end

				table_remove(fakePlayerAuras[playerButton][filter], j)
				playerButton:AuraRemoved(fakeAura.spellId, fakeAura.name)
			end
		end
	end



	--set all expired DRs to status 0
	for categoryname, drData in pairs(fakePlayerDRs[playerButton]) do
		if drData.expirationTime and drData.expirationTime <= currentTime then
			drData.status = 0
			drData.expirationTime = nil
		end
	end
	playerButton:UNIT_AURA()
end

local function FakeUnitAura(playerButton, index, filter)
	local fakePlayerAuras = BattleGroundEnemies.Testmode.FakePlayerAuras
	local aura = fakePlayerAuras[playerButton][filter][index]
	return aura
end

-- returns true if <frame> or one of the frames that <frame> is dependent on is anchored to <otherFrame> and nil otherwise
-- dont ancher to otherframe is
function BattleGroundEnemies:IsFrameDependentOnFrame(frame, otherFrame)
	if frame == nil then
		return false
	end

	if otherFrame == nil then
		return false
	end

	if frame == otherFrame then
		return true
	end

	local points = frame:GetNumPoints()
	for i = 1, points do
		local _, relFrame = frame:GetPoint(i)
		if relFrame and self:IsFrameDependentOnFrame(relFrame, otherFrame) then
			return true
		end
	end
end




local enemyButtonFunctions = {}
do

	--Remove from OnUpdate
	function enemyButtonFunctions:DeleteActiveUnitID() --Delete from OnUpdate
		--BattleGroundEnemies:Debug("DeleteActiveUnitID")
		self.unitID = false
		self.TargetUnitID = false
		self:UpdateRange(false)

		if self.Target then
			self:IsNoLongerTarging(self.Target)
		end

		self.UnitIDs.HasAllyUnitID = false
		self:UNIT_AURA()
		self:DispatchEvent("UnitIdUpdate")
	end

	function enemyButtonFunctions:UpdateEnemyUnitID(key, value)
		if self.PlayerDetails.isFakePlayer then return end
		local unitIDs = self.UnitIDs
		if key then
			unitIDs[key] = value
		end

		local unitID = unitIDs.Arena or unitIDs.Nameplate or unitIDs.Target or unitIDs.Focus
		if unitID then
			unitIDs.HasAllyUnitID = false
			self:NewUnitID(unitID)
		elseif unitIDs.Ally then
			unitIDs.HasAllyUnitID = true
			local playerButton = BattleGroundEnemies:GetPlayerbuttonByUnitID(unitIDs.Ally)
			if playerButton and playerButton == self then
				self:NewUnitID(unitIDs.Ally)
				unitIDs.HasAllyUnitID = true
			end
		else
			self:DeleteActiveUnitID()
		end
	end
end


local buttonFunctions = {}

do

	function buttonFunctions:GetOppositeMainFrame()
		return BattleGroundEnemies[self.PlayerType == PlayerTypes.Enemies  and PlayerTypes.Allies  or PlayerTypes.Enemies]
	end

	function buttonFunctions:OnDragStart()
		return BattleGroundEnemies.db.profile.Locked or self:GetParent():StartMoving()
	end


	function buttonFunctions:OnDragStop()
		local parent = self:GetParent()
		parent:StopMovingOrSizing()
		if not InCombatLockdown() then
			local scale = self:GetEffectiveScale()
			self.bgSizeConfig.Position_X = parent:GetLeft() * scale
			self.bgSizeConfig.Position_Y = parent:GetTop() * scale
		end
	end

	function buttonFunctions:UpdateAll(temporaryUnitID)
		local updateStuffWithEvents = false --only update health, power, etc for players that dont get events for that or that dont have a unitID assigned
		local unitID
		local updateAuras = false
		if temporaryUnitID then
			updateStuffWithEvents = true
			unitID = temporaryUnitID
			updateAuras = true
		else
			if self.unitID then
				unitID = self.unitID
				if self.UnitIDs.HasAllyUnitID then
					updateStuffWithEvents = true

					--throttle the aura updates in case we only have a ally unitID
					local lastAuraUpdate = self.lastAuraUpdate
					if lastAuraUpdate then
						if GetTime() - lastAuraUpdate > 0.5 then
							updateAuras = true
						end
					else
						updateAuras = true
					end
				end
			end
		end
		--BattleGroundEnemies:LogToSavedVariables("UpdateAll", unitID, updateStuffWithEvents)
		if not unitID then return end
		--BattleGroundEnemies:LogToSavedVariables("UpdateAll", 1)

		if not UnitExists(unitID) then return end

		--this further checks dont seem necessary since they dont seem to rule out any other unitiDs (all unit ids that exist also are a button and are also this frame)


		--[[ BattleGroundEnemies:LogToSavedVariables("UpdateAll", 2)

		local playerButton = BattleGroundEnemies:GetPlayerbuttonByUnitID(unitID)

		if not playerButton then return end
		BattleGroundEnemies:LogToSavedVariables("UpdateAll", 3)
		if playerButton ~= self then return	end
		BattleGroundEnemies:LogToSavedVariables("UpdateAll", 4) ]]


		if updateStuffWithEvents then
			self:UNIT_POWER_FREQUENT(unitID)
			self:UNIT_HEALTH(unitID)
			if updateAuras then
				self:UNIT_AURA(unitID) --throttle aura updates
			end
		end

		--self:UpdateRange(IsItemInRange(self.config.RangeIndicator_Range, unitID))
		--local inRange, checkedRange = UnitInRange(unitID)
		--self:UpdateRange(inRange)
		--self:UpdateRange(IsSpellInRange("Smite", unitID))
		self:UpdateRange(InRange(unitID))
		self:UpdateTarget()
	end

	function buttonFunctions:GetSpecData()
		if not self.PlayerDetails then return end
		if self.PlayerDetails.PlayerClass and self.PlayerDetails.PlayerSpecName then
			local t = Data.Classes[self.PlayerDetails.PlayerClass]
			if t then
				t = t[self.PlayerDetails.PlayerSpecName]
				return t
			end
		end
	end

	function buttonFunctions:PlayerDetailsChanged()
		self:SetBindings()
		self:DispatchEvent("PlayerDetailsChanged", self.PlayerDetails)
	end

	function buttonFunctions:UpdateRaidTargetIcon(forceIndex)
		local unit = self:GetUnitID()
		local newIndex = forceIndex --used for testmode, otherwise it will just be nil and overwritten when one actually exists
		if unit then
			newIndex = GetRaidTargetIndex(unit)
			if newIndex then
				if newIndex == 8 and (not self.RaidTargetIconIndex or self.RaidTargetIconIndex ~= 8) then
					if BattleGroundEnemies.IsRatedBG and BattleGroundEnemies.db.profile.RBG.TargetCalling_NotificationEnable then
						local path = LSM:Fetch("sound", BattleGroundEnemies.db.profile.RBG.TargetCalling_NotificationSound, true)
						if path then
							PlaySoundFile(path, "Master")
						end
					end
				end
			end
		end
		self.RaidTargetIconIndex = newIndex
		self:DispatchEvent("UpdateRaidTargetIcon", self.RaidTargetIconIndex)
	end

	function buttonFunctions:UpdateCrowdControl(unitID)
		local spellId, itemID, startTime, duration
		if IsClassic or IsTBCC or IsWrath then
			spellId, itemID, startTime, duration = C_PvP.GetArenaCrowdControlInfo(unitID)
		else
			spellId, startTime, duration = C_PvP.GetArenaCrowdControlInfo(unitID)
		end

		if spellId then
			self.Trinket:DisplayTrinket(spellId, itemID)
			self.Trinket:SetTrinketCooldown(startTime/1000.0, duration/1000.0)
		end
	end

	function buttonFunctions:NewUnitID(unitID, targetUnitID)
		if not UnitExists(unitID) then return end
		self.unitID = unitID
		if self.PlayerIsEnemy then
			self.TargetUnitID = unitID.."target"
			self:UpdateRaidTargetIcon()
		else
			--self.unitID already gets assigned for allies before, info from GROUP_ROSTER_UPDATE
			self.TargetUnitID = targetUnitID
			if self.unit ~= unitID then
				--ally has a new unitID now
				--self:Debug("player", groupMember.PlayerName, "has a new unit and targeted something")

				local targetButton = self.Target
				if targetButton then
					--reset the TargetedByEnemy
					targetButton:IsNoLongerTarging(targetButton)
					targetButton:IsNowTargeting(targetButton)
				end

				if InCombatLockdown() then --if we are in combat we go get to set the stuff below later since GROUP_ROSTER_UPDATE also has a combat check and will get called after combat
					return BattleGroundEnemies:QueueForUpdateAfterCombat(BattleGroundEnemies[self.PlayerType], "UpdateAllUnitIDs")
				else
					self.unit = unitID
					self:SetAttribute('unit', unitID)
					BattleGroundEnemies.Allies:SortPlayers()
				end
			end
		end
		self:UpdateAll(unitID)
		self:DispatchEvent("UnitIdUpdate", unitID)
	end

	function buttonFunctions:SetModuleConfig(moduleName)
		local moduleFrameOnButton = self[moduleName]
		local moduleConfigOnButton = self.bgSizeConfig.ButtonModules[moduleName]

		moduleFrameOnButton.config = moduleConfigOnButton
		if moduleConfigOnButton.Enabled and BattleGroundEnemies:IsModuleEnabledOnThisExpansion(moduleName) then
			moduleFrameOnButton.Enabled = true
		else
			moduleFrameOnButton.Enabled = false
		end
	end

	function buttonFunctions:SetAllModuleConfigs()
		for moduleName, moduleFrame in pairs(BattleGroundEnemies.ButtonModules) do
			self:SetModuleConfig(moduleName)
		end
	end

	function buttonFunctions:SetModulePositions()
		self:ApplyConfigs()
		if not self:GetRect() then return end --the position of the button is not set yet
		local i = 1
		repeat -- we basically run this roop to get out of the anchring hell (making sure all the frames that a module is depending on is set)
			local allModulesSet = true
			for moduleName, moduleFrame in pairs(BattleGroundEnemies.ButtonModules) do
				self:SetModuleConfig(moduleName)
				local moduleFrameOnButton = self[moduleName]

				local config = moduleFrameOnButton.config
				if not config then return end


				if config.Points then
					if i == 1 then moduleFrameOnButton:ClearAllPoints() end

					for j = 1, config.ActivePoints do
						local pointConfig = config.Points[j]
						if pointConfig then
							if pointConfig.RelativeFrame then
								local relativeFrame = self:GetAnchor(pointConfig.RelativeFrame)


								if relativeFrame then
									if relativeFrame:GetNumPoints() > 0 then

										moduleFrameOnButton:SetPoint(pointConfig.Point, relativeFrame, pointConfig.RelativePoint, pointConfig.OffsetX or 0, pointConfig.OffsetY or 0)
									else
										-- the module we are depending on hasn't been set yet
										allModulesSet = false
										--BattleGroundEnemies:LogToSavedVariables("moduleName", moduleName, "isnt set yet")
									end
								else
									if not relativeFrame then return print("error", relativeFrame, "for module", moduleName, "doesnt exist") end
								end

							else
								--do nothing, the point was probably deleted
							end
						end
					end
				end
				if config.Parent then
					moduleFrameOnButton:SetParent(self:GetAnchor(config.Parent))
				end

				if not moduleFrameOnButton.Enabled and moduleFrame.flags.SetZeroWidthWhenDisabled then
					moduleFrameOnButton:SetWidth(0.01)
				else
					if config.UseButtonHeightAsWidth then
						moduleFrameOnButton:SetWidth(self:GetHeight())
					else
						if config.Width and BattleGroundEnemies:ModuleFrameNeedsWidth(moduleFrame, config) then
							moduleFrameOnButton:SetWidth(config.Width)
						end
					end
				end


				if not moduleFrameOnButton.Enabled and moduleFrame.flags.SetZeroHeightWhenDisabled then
					moduleFrameOnButton:SetHeight(0.001)
				else
					if config.UseButtonHeightAsHeight then
						moduleFrameOnButton:SetHeight(self:GetHeight())
					else
						if config.Height and BattleGroundEnemies:ModuleFrameNeedsHeight(moduleFrame, config) then
							moduleFrameOnButton:SetHeight(config.Height)
						end
					end
				end
			end

			self.MyTarget:SetParent(self.healthBar)
			self.MyTarget:SetPoint("TOPLEFT", self.healthBar, "TOPLEFT")
			self.MyTarget:SetPoint("BOTTOMRIGHT", self.healthBar, "BOTTOMRIGHT")
			self.MyFocus:SetParent(self.healthBar)
			self.MyFocus:SetPoint("TOPLEFT", self.healthBar, "TOPLEFT")
			self.MyFocus:SetPoint("BOTTOMRIGHT", self.healthBar, "BOTTOMRIGHT")

			i = i + 1

			-- if i > 10 then
			-- 	BattleGroundEnemies:LogToSavedVariables("something went wrong in SetModulePositions")
			-- end
		until allModulesSet or i > 10 --maxium of 10 tries
	end

	function buttonFunctions:ApplyConfigs()
		self.config = BattleGroundEnemies.db.profile[self.PlayerType]
		self.bgSizeConfig = self.config[tostring(BattleGroundEnemies.BGSize)]
	end

	function buttonFunctions:ApplyButtonSettings()
		self:ApplyConfigs()
		local conf = self.bgSizeConfig

		self:SetWidth(conf.BarWidth)
		self:SetHeight(conf.BarHeight)

		self:ApplyRangeIndicatorSettings()

		-- auras on spec

		--MyTarget, indicating the current target of the player
		self.MyTarget:SetBackdrop({
			bgFile = "Interface/Buttons/WHITE8X8", --drawlayer "BACKGROUND"
			edgeFile = 'Interface/Buttons/WHITE8X8', --drawlayer "BORDER"
			edgeSize = BattleGroundEnemies.db.profile.MyTarget_BorderSize
		})
		self.MyTarget:SetBackdropColor(0, 0, 0, 0)
		self.MyTarget:SetBackdropBorderColor(unpack(BattleGroundEnemies.db.profile.MyTarget_Color))

		--MyFocus, indicating the current focus of the player
		self.MyFocus:SetBackdrop({
			bgFile = "Interface/Buttons/WHITE8X8", --drawlayer "BACKGROUND"
			edgeFile = 'Interface/Buttons/WHITE8X8', --drawlayer "BORDER"
			edgeSize = BattleGroundEnemies.db.profile.MyFocus_BorderSize
		})
		self.MyFocus:SetBackdropColor(0, 0, 0, 0)
		self.MyFocus:SetBackdropBorderColor(unpack(BattleGroundEnemies.db.profile.MyFocus_Color))




		wipe(self.ButtonEvents)
		self:SetAllModuleConfigs()
		self:SetModulePositions()

		for moduleName, moduleFrame in pairs(BattleGroundEnemies.ButtonModules) do
			local moduleFrameOnButton = self[moduleName]

			if moduleFrameOnButton.Enabled then
				if moduleFrame.events then
					for i = 1, #moduleFrame.events do
						local event = moduleFrame.events[i]
						self.ButtonEvents[event] = self.ButtonEvents[event] or {}

						table_insert(self.ButtonEvents[event], moduleFrameOnButton)
					end
				end
				moduleFrameOnButton.Enabled = true
				moduleFrameOnButton:Show()
				if moduleFrameOnButton.Enable then moduleFrameOnButton:Enable() end
				if moduleFrameOnButton.ApplyAllSettings then moduleFrameOnButton:ApplyAllSettings() end
			else
				moduleFrameOnButton.Enabled = false
				moduleFrameOnButton:Hide()
				if moduleFrameOnButton.Disable then moduleFrameOnButton:Disable() end
				if moduleFrameOnButton.Reset then moduleFrameOnButton:Reset() end
			end
		end
	end





	do
		local mouseButtons = {
			[1] = "LeftButton",
			[2] = "RightButton",
			[3] = "MiddleButton"
		}

		function buttonFunctions:SetBindings()
			local setupUsualAttributes = true
			--use a table to track changes and compare them to GetAttribute
			--set baseline
			local newState = {
				unit = false,
				type1 = false,
				type2 = false,
				type3 = false,
				macrotext1 = false,
				macrotext2 = false,
				macrotext3 = false
			}

			if ClickCastFrames[self] then
				ClickCastFrames[self] = nil
			end

			if self.PlayerIsEnemy then
				if self.PlayerDetails.PlayerArenaUnitID then --its a arena enemy
					newState.unit = self.PlayerDetails.PlayerArenaUnitID
					newState.type1 = "target"		-- type1 = LEFT-Click to target
					newState.type2 = "focus"		 -- type2 = Right-Click to focus
					setupUsualAttributes = false
				end
			else
				if BattleGroundEnemies.db.profile[self.PlayerType].UseClique then
					BattleGroundEnemies:Debug("Clique used")
					ClickCastFrames[self] = true
					setupUsualAttributes = false
				end
			end

			if setupUsualAttributes then
				newState.type1 = "macro"		-- type1 = LEFT-Click
				newState.type2 = "macro"		-- type2 = Right-Click
				newState.type3 = "macro"		-- type3 = Middle-Click

				for i = 1, 3 do
					local bindingType = self.config[mouseButtons[i].."Type"]

					if bindingType == "Target" then
						newState['macrotext'..i] = '/cleartarget\n'..
						'/targetexact '..
						self.PlayerDetails.PlayerName
					elseif bindingType == "Focus" then
						newState['macrotext'..i] = '/targetexact '..self.PlayerDetails.PlayerName..'\n'..
						'/focus\n'..
						'/targetlasttarget'
					else -- Custom
						local macrotext = (BattleGroundEnemies.db.profile[self.PlayerType][mouseButtons[i].."Value"]):gsub("%%n", self.PlayerDetails.PlayerName)
						newState['macrotext'..i] = macrotext
					end
				end
			end

			--check what have actually changed
			local updateNeeded = false
			for attribute, value in pairs(newState) do
				local currentValue = self:GetAttribute(attribute)
				if currentValue ~= value then
					updateNeeded = true
					break
				end
			end
			if updateNeeded then
				if InCombatLockdown() then
					return BattleGroundEnemies:QueueForUpdateAfterCombat(self, "SetBindings")
				end
				for attribute, value in pairs(newState) do
					self:SetAttribute(attribute, value)
				end
			end
		end
	end

	function buttonFunctions:PlayerDied()
		if self.PlayerDetails.isFakePlayer then
			if BattleGroundEnemies.Testmode.FakePlayerAuras[self] then wipe(BattleGroundEnemies.Testmode.FakePlayerAuras[self]) end
			if BattleGroundEnemies.Testmode.FakePlayerDRs[self] then wipe(BattleGroundEnemies.Testmode.FakePlayerDRs[self]) end
		end

		self:DispatchEvent("UnitDied")
		self.isDead = true
	end

	local maxHealths = {}  --key = playerbutton, value = {}
	local deadPlayers = {}

	function buttonFunctions:FakeUnitHealth()
		local now = GetTime()
		if deadPlayers[self] then
			--this player is dead, check if we can revive him
			if deadPlayers[self] + 26 < now then -- he died more than 26 seconds ago
				deadPlayers[self] = nil
			else
				return 0-- let the player be dead
			end
		end
		local maxHealth = self:FakeUnitHealthMax()

		local health = math_random(0, 100)
		if health == 0 then
			deadPlayers[self] = now
			self:PlayerDied()
			return 0
		else
			return math_floor((health/100) * maxHealth)
		end
	end

	function buttonFunctions:FakeUnitHealthMax()
		if not maxHealths[self] then
			local myMaxHealth = UnitHealthMax("player")
			local playerMaxHealthDifference = math_random(-15, 15) -- the player has the same health as me +/- 15%
			local playerMaxHealth = math.ceil(myMaxHealth * (1 + (playerMaxHealthDifference/100)))
			maxHealths[self] = playerMaxHealth
		end
		return maxHealths[self]
	end



	function buttonFunctions:UNIT_HEALTH(unitID) --gets health of nameplates, player, target, focus, raid1 to raid40, partymember
		if not self.isShown then return end
		local health
		local maxHealth
		if self.PlayerDetails.isFakePlayer then
			health = self:FakeUnitHealth()
			maxHealth = self:FakeUnitHealthMax()
		else
			health = UnitHealth(unitID)
			maxHealth = UnitHealthMax(unitID)
		end

		self:DispatchEvent("UpdateHealth", unitID, health, maxHealth)
		if unitID then
			if UnitIsDeadOrGhost(unitID) then
				self:PlayerDied()
			else
				self.isDead = false
			end
		else
			-- we are in testmode
			self.isDead = health == 0
		end
	end

	function buttonFunctions:ApplyRangeIndicatorSettings()

		--set everything to default
		for frameName, enableRange in pairs(self.config.RangeIndicator_Frames) do
			if self[frameName] then
				self[frameName]:SetAlpha(1)
			else
				--probably old saved variables version
				self.config.RangeIndicator_Frames[frameName] = nil
			end
		end
		self:SetAlpha(1)
		self:UpdateRange(not self.wasInRange)
	end

	function buttonFunctions:ArenaOpponentShown(unitID)
		if unitID then
			BattleGroundEnemies.ArenaIDToPlayerButton[unitID] = self
			if self.PlayerIsEnemy then
				self:UpdateEnemyUnitID("Arena", unitID)
			end
			RequestCrowdControlSpell(unitID)
		end
		self:DispatchEvent("ArenaOpponentShown")
	end

	-- Shows/Hides targeting indicators for a button
	function buttonFunctions:UpdateTargetIndicators()
		self:DispatchEvent("UpdateTargetIndicators")
		local isAlly = false
		local isPlayer = false

		if self == PlayerButton then
			isPlayer = true
		elseif not self.PlayerIsEnemy then
			isAlly = true
		end

		local i = 0
		for enemyButton in pairs(self.UnitIDs.TargetedByEnemy) do
			i = i + 1
		end

		local enemyTargets = i

		if BattleGroundEnemies.IsRatedBG then
			if isAlly then
				if BattleGroundEnemies.db.profile.RBG.EnemiesTargetingAllies_Enabled then
					if enemyTargets >= (BattleGroundEnemies.db.profile.RBG.EnemiesTargetingAllies_Amount or 1)  then
						local path = LSM:Fetch("sound", BattleGroundEnemies.db.profile.RBG.EnemiesTargetingAllies_Sound, true)
						if path then
							PlaySoundFile(path, "Master")
						end
					end
				end
			end
			if isPlayer then
				if BattleGroundEnemies.db.profile.RBG.EnemiesTargetingMe_Enabled then
					if enemyTargets >= BattleGroundEnemies.db.profile.RBG.EnemiesTargetingMe_Amount  then
						local path = LSM:Fetch("sound", BattleGroundEnemies.db.profile.RBG.EnemiesTargetingMe_Sound, true)
						if path then
							PlaySoundFile(path, "Master")
						end
					end
				end
			end
		end
	end

	function buttonFunctions:UpdateRange(inRange)
		--BattleGroundEnemies:Information("UpdateRange", inRange, self.PlayerName, self.config.RangeIndicator_Enabled, self.config.RangeIndicator_Alpha)

		if not self.config.RangeIndicator_Enabled then return end

		if inRange ~= self.wasInRange then
			local alpha = inRange and 1 or self.config.RangeIndicator_Alpha
			if self.config.RangeIndicator_Everything then
				self:SetAlpha(alpha)
			else
				for frameName, enableRange in pairs(self.config.RangeIndicator_Frames) do
					if enableRange then
						self[frameName]:SetAlpha(alpha)
					end
				end
			end
			self.wasInRange = inRange
		end
	end

	function buttonFunctions:GetUnitID()
		return self.unitID
	end

	function buttonFunctions:AuraRemoved(spellId, spellName)
		if not self.isShown then return end
		self:DispatchEvent("AuraRemoved", spellId, spellName)
		--BattleGroundEnemies:Debug(operation, spellId)
	end


	function buttonFunctions:ShouldSkipAuraUpdate(isFullUpdate, updatedAuraInfos, isRelevantFunc, unitID)
		if isFullUpdate then return false end
		-- Early out if the update cannot affect the frame

		local skipUpdate = false
		if updatedAuraInfos and isRelevantFunc then
			skipUpdate = true
			for i = 1, #updatedAuraInfos do
				local auraInfo = updatedAuraInfos[i]

				if isRelevantFunc(self, unitID, auraInfo) then
					skipUpdate = false
					break
				end
			end
		end
		return skipUpdate
	end

	function buttonFunctions:ShouldDisplayAura(unitID, filter, aura)
		if self:DispatchUntilTrue("CareAboutThisAura", unitID, filter, aura) then return true end
		return false --nobody cares about this aura
	end


	--[[


	updatedAuraInfos = {  Optional table of information about changed auras.


		Key						Type		Description
		canApplyAura			boolean		Whether or not the player can apply this aura.
		debuffType				string		Type of debuff this aura applies. May be an empty string.
		isBossAura				boolean		Whether or not this aura was applied by a boss.
		isFromPlayerOrPlayerPet	boolean		Whether or not this aura was applied by the player or their pet.
		isHarmful				boolean		Whether or not this aura is a debuff.
		isHelpful				boolean		Whether or not this aura is a buff.
		isNameplateOnly			boolean		Whether or not this aura should appear on nameplates.
		isRaid					boolean		Whether or not this aura meets the conditions of the RAID aura filter.
		name					string		The name of the aura.
		nameplateShowAll		boolean		Whether or not this aura should be shown on all nameplates, instead of just the personal one.
		sourceUnit				UnitId		Token of the unit that applied the aura.
		spellId					number		The spell ID of the aura.
	}

	]]

	local function addPriority(aura)
		aura.Priority = BattleGroundEnemies:GetSpellPriority(aura.spellId)
		return aura
	end

	--packaged the aura into the new UnitAura packaged format (structure UnitAuraInfo)
	local function UnitAuraToUnitAuraInfo(filter, name, icon, count, debuffType, duration, expirationTime, unitCaster, canStealOrPurge, nameplateShowPersonal, spellId, canApplyAura, isBossAura, castByPlayer, nameplateShowAll, timeMod, value1, value2, value3, value4)
		local aura
		if type(name) == "table" then  --seems alrady packaged
			aura = name
		else
			local isDebuff = filter == "HARMFUL" or "HELPFUL"
			--package that stuff up
			aura = {
				applications = count,
				auraInstanceID = nil,
				canApplyAura = canApplyAura,
				charges	= nil,
				dispelName = debuffType,
				duration = duration,
				expirationTime = expirationTime,
				icon = icon,
				isBossAura = isBossAura,
				isFromPlayerOrPlayerPet	= castByPlayer,
				isHarmful = isDebuff,
				isHelpful = not isDebuff,
				isNameplateOnly	= nil,
				isRaid = nil,
				isStealable	= canStealOrPurge,
				maxCharges = nil,
				name = name,
				nameplateShowAll = nameplateShowAll	,
				nameplateShowPersonal = nameplateShowPersonal,
				points = {value1, value2, value3, value4}, --	array	Variable returns - Some auras return additional values that typically correspond to something shown in the tooltip, such as the remaining strength of an absorption effect.
				sourceUnit = unitCaster,
				spellId	= spellId,
				timeMod	= timeMod,
			}
		end
		aura = addPriority(aura)
		return aura
	end

	function buttonFunctions:UNIT_AURA(unitID, second, third)
		if not self.isShown then return end
		local now = GetTime()
		if self.lastAuraUpdate and self.lastAuraUpdate == now then return end --this event will fire for the same player multiple times if lets say he is shown on nameplate and on target frame
		
		local updatedAuraInfos = {
			addedAuras = {},
			isFullUpdate = true
		}

		if unitID then
			if not second then
				updatedAuraInfos.isFullUpdate = true
			else
				if type(second) == "table" then --new 10.0 UNIT_AURA
					updatedAuraInfos = second
					if not updatedAuraInfos.isFullUpdate then
	
						local addedAuras = updatedAuraInfos.addedAuras
						if addedAuras ~= nil then
							for i = 1, #addedAuras do
								local addedAura = addedAuras[i]
								self.Auras[getFilterFromAuraInfo(addedAura)][addedAura.auraInstanceID] = addPriority(addedAura)
							end
						end
	
						local updatedAuraInstanceIDs = updatedAuraInfos.updatedAuraInstanceIDs
						if updatedAuraInstanceIDs ~= nil then
							for i = 1, #updatedAuraInstanceIDs do
								local auraInstanceID = updatedAuraInstanceIDs[i]
								if self.Auras.HELPFUL[auraInstanceID] then
									local newAura = C_UnitAuras.GetAuraDataByAuraInstanceID(unitID, auraInstanceID)
									if newAura then
										self.Auras.HELPFUL[auraInstanceID] = addPriority(newAura)
									end
								elseif self.Auras.HARMFUL[auraInstanceID] then
									local newAura = C_UnitAuras.GetAuraDataByAuraInstanceID(unitID, auraInstanceID)
									if newAura then
										self.Auras.HARMFUL[auraInstanceID] = addPriority(newAura)
									end
								end
							end
						end
	
						local removedAuraInstanceIDs = updatedAuraInfos.removedAuraInstanceIDs
						if removedAuraInstanceIDs ~= nil then
							for i = 1, #removedAuraInstanceIDs do
								local auraInstanceID = removedAuraInstanceIDs[i]
								if self.Auras.HELPFUL[auraInstanceID] ~= nil then
									self.Auras.HELPFUL[auraInstanceID] = nil
								end
								if self.Auras.HARMFUL[auraInstanceID] ~= nil then
									self.Auras.HARMFUL[auraInstanceID] = nil
								end
							end
						end
					end
				end
			end
		else
			wipe(self.Auras.HELPFUL)
			wipe(self.Auras.HARMFUL)
		end
		
	

		--[[

				third arg until patch 9.x (changed in 10.0)
				canApplyAura	boolean	Whether or not the player can apply this aura.
				debuffType	string	Type of debuff this aura applies. May be an empty string.
				isBossAura	boolean	Whether or not this aura was applied by a boss.
				isFromPlayerOrPlayerPet	boolean	Whether or not this aura was applied by the player or their pet.
				isHarmful	boolean	Whether or not this aura is a debuff.
				isHelpful	boolean	Whether or not this aura is a buff.
				isNameplateOnly	boolean	Whether or not this aura should appear on nameplates.
				isRaid	boolean	Whether or not this aura meets the conditions of the RAID aura filter.
				name	string	The name of the aura.
				nameplateShowAll	boolean	Whether or not this aura should be shown on all nameplates, instead of just the personal one.
				sourceUnit	UnitId	Token of the unit that applied the aura.
				spellId	number	The spell ID of the aura.



			10.0 second argument:

			addedAuras	UnitAuraInfo[]?	List of auras added to the unit during this update.
			updatedAuraInstanceIDs	number[]?	List of existing auras on the unit modified during this update.
			removedAuraInstanceIDs	number[]?	List of existing auras removed from the unit during this update.
			isFullUpdate	boolean	Wwhether or not a full update of the units' auras should be performed. If this is set, the other fields will likely be nil.


			structure UnitAuraInfo
			applications	number
			auraInstanceID	number
			canApplyAura	boolean
			charges	number
			dispelName	string?
			duration	number
			expirationTime	number
			icon	number
			isBossAura	boolean
			isFromPlayerOrPlayerPet	boolean
			isHarmful	boolean
			isHelpful	boolean
			isNameplateOnly	boolean
			isRaid	boolean
			isStealable	boolean
			maxCharges	number
			name	string
			nameplateShowAll	boolean
			nameplateShowPersonal	boolean
			points	array	Variable returns - Some auras return additional values that typically correspond to something shown in the tooltip, such as the remaining strength of an absorption effect.
			sourceUnit	string?
			spellId	number
			timeMod	number
		]]


		local batchCount = 40 -- TODO make this a option the player can choose, maximum amount of buffs / debuffs
		local shouldQueryAuras

		for i = 1, #auraFilters do
			local filter = auraFilters[i]
			shouldQueryAuras = unitID and self:DispatchUntilTrue("ShouldQueryAuras", unitID, filter) --ask all subscribers/modules if Aura Scanning is necessary for this filter
			if shouldQueryAuras then
				if updatedAuraInfos.isFullUpdate then
					wipe(self.Auras[filter])

					if AuraUtil.ForEachAura and not self.PlayerDetails.isFakePlayer then
						local usePackedAura = true --this will make the function return a aura info table instead of many returns, added in 10.0
						AuraUtil.ForEachAura(unitID, filter, batchCount, function(...)
							local aura = UnitAuraToUnitAuraInfo(filter, ...)
							if aura.auraInstanceID then
								self.Auras[filter][aura.auraInstanceID] = aura
							else
								table_insert(self.Auras[filter], aura)
							end
						end, usePackedAura)
					else
						local auraFunc = UnitAura
						if self.PlayerDetails.isFakePlayer then
							auraFunc = function(unitID, i, filter)
								return FakeUnitAura(self, i, filter)
							end
						end
						for j = 1, batchCount do
							local name, icon, count, debuffType, duration, expirationTime, unitCaster, canStealOrPurge, nameplateShowPersonal, spellId, canApplyAura, isBossAura, castByPlayer, nameplateShowAll, timeMod, value1, value2, value3, value4 = auraFunc(unitID, j, filter)

							if not name then break end

							local aura = UnitAuraToUnitAuraInfo(filter, name, icon, count, debuffType, duration, expirationTime, unitCaster, canStealOrPurge, nameplateShowPersonal, spellId, canApplyAura, isBossAura, castByPlayer, nameplateShowAll, timeMod, value1, value2, value3, value4)
							if aura.auraInstanceID then
								self.Auras[filter][aura.auraInstanceID] = aura
							else
								table_insert(self.Auras[filter], aura)
							end
						end
					end
				end
			end
			self:DispatchEvent("BeforeFullAuraUpdate", filter)
			for _, aura in pairs(self.Auras[filter]) do
				self:DispatchEvent("NewAura", unitID, filter, aura)
			end
			self:DispatchEvent("AfterFullAuraUpdate", filter)
		end
		self.lastAuraUpdate = now
	end


	buttonFunctions.UNIT_HEALTH_FREQUENT = buttonFunctions.UNIT_HEALTH --TBC compability, IsTBCC
	buttonFunctions.UNIT_MAXHEALTH = buttonFunctions.UNIT_HEALTH
	buttonFunctions.UNIT_HEAL_PREDICTION = buttonFunctions.UNIT_HEALTH
	buttonFunctions.UNIT_ABSORB_AMOUNT_CHANGED = buttonFunctions.UNIT_HEALTH
	buttonFunctions.UNIT_HEAL_ABSORB_AMOUNT_CHANGED = buttonFunctions.UNIT_HEALTH


	function buttonFunctions:UNIT_POWER_FREQUENT(unitID, powerToken) --gets power of nameplates, player, target, focus, raid1 to raid40, partymember
		if not self.isShown then return end
		self:DispatchEvent("UpdatePower", unitID, powerToken)
	end

	-- returns true if the other button is a enemy from the point of view of the button. True if button is ally and other button is enemy, and vice versa
	function buttonFunctions:IsEnemyToMe(playerButton)
		return self.PlayerIsEnemy ~= playerButton.PlayerIsEnemy
	end

	function buttonFunctions:UpdateTargetedByEnemy(playerButton, targeted)
		local unitIDs = self.UnitIDs
		unitIDs.TargetedByEnemy[playerButton] = targeted
		self:UpdateTargetIndicators()

		if self.PlayerIsEnemy then
			local allyUnitID = false

			for allyBtn in pairs(unitIDs.TargetedByEnemy) do
				if allyBtn ~= PlayerButton then
					allyUnitID = allyBtn.TargetUnitID
					break
				end
			end
			self:UpdateEnemyUnitID("Ally", allyUnitID)
		end
	end

	function buttonFunctions:IsNowTargeting(playerButton)
		--BattleGroundEnemies:LogToSavedVariables("IsNowTargeting", self.PlayerName, self.unitID, playerButton.PlayerName)
		self.Target = playerButton

		if not self:IsEnemyToMe(playerButton) then return end --we only care of the other player is of opposite faction

		playerButton:UpdateTargetedByEnemy(self, true)
	end

	function buttonFunctions:IsNoLongerTarging(playerButton)
		--BattleGroundEnemies:LogToSavedVariables("IsNoLongerTarging", self.PlayerName, self.unitID, playerButton.PlayerName)
		self.Target = nil

		if not self:IsEnemyToMe(playerButton) then return end --we only care of the other player is of opposite faction

		playerButton:UpdateTargetedByEnemy(self, nil)
	end

	function buttonFunctions:UpdateTarget()
		--BattleGroundEnemies:LogToSavedVariables("UpdateTarget", self.PlayerName, self.unitID)

		local oldTargetPlayerButton = self.Target
		local newTargetPlayerButton

		if self.TargetUnitID then
			newTargetPlayerButton = BattleGroundEnemies:GetPlayerbuttonByUnitID(self.TargetUnitID)
		end


		if oldTargetPlayerButton then
			--BattleGroundEnemies:LogToSavedVariables("UpdateTarget", "oldTargetPlayerButton", self.PlayerName, self.unitID, oldTargetPlayerButton.PlayerName, oldTargetPlayerButton.unitID)

			if newTargetPlayerButton and oldTargetPlayerButton == newTargetPlayerButton then return end
			self:IsNoLongerTarging(oldTargetPlayerButton)
		end

		--player didnt have a target before or the player targets a new player

		if newTargetPlayerButton then --player targets an existing player and not for example a pet or a NPC
			--BattleGroundEnemies:LogToSavedVariables("UpdateTarget", "newTargetPlayerButton", self.PlayerName, self.unitID, newTargetPlayerButton.PlayerName, newTargetPlayerButton.unitID)
			self:IsNowTargeting(newTargetPlayerButton)
		end
	end

	function buttonFunctions:DispatchEvent(event, ...)
		if not self.ButtonEvents then return end

		local moduleFrames = self.ButtonEvents[event]

		if not moduleFrames then return end
		for i = 1, #moduleFrames do
			local moduleFrameOnButton = moduleFrames[i]
			if moduleFrameOnButton[event] then
				moduleFrameOnButton[event](moduleFrameOnButton, ...)
			else
				BattleGroundEnemies:OnetimeInformation("Event:", event, "There is no key with the event name for this module",  moduleFrameOnButton.moduleName)
			end
		end
	end

	-- used for the AuraInfo (third return of UNIT_AURA) of UNIT_AURA, we dispatch until one of the consumers (modules) returns true, then we proceed with aura scanning
	function buttonFunctions:DispatchUntilTrue(event, ...)

		local moduleFrames = self.ButtonEvents[event]
		if not moduleFrames then return end

		for i = 1, #moduleFrames do
			local moduleFrameOnButton = moduleFrames[i]
			if moduleFrameOnButton[event] then
				if moduleFrameOnButton[event](moduleFrameOnButton, ...) then return true end
			else
				BattleGroundEnemies:OnetimeInformation("Event:", event, "There is no key with the event name for this module",  moduleFrameOnButton.moduleName)
			end
		end
	end

	function buttonFunctions:GetAnchor(relativeFrame)
		return relativeFrame == "Button" and self or self[relativeFrame]
	end
end

local function PopulateMainframe(playerType)
	local mainframe = BattleGroundEnemies[playerType]
	mainframe.Players = {} --index = name, value = button(table), contains enemyButtons
	mainframe.CurrentPlayerOrder = {} --index = number, value = playerButton(table)
	mainframe.InactivePlayerButtons = {} --index = number, value = button(table)
	mainframe.NewPlayersDetails = {} -- index = numeric, value = playerdetails, used for creation of new buttons, use (temporary) table to not create an unnecessary new button if another player left
	mainframe.PlayerType = playerType
	mainframe.PlayerSources = {}
	mainframe.NumShownPlayers = 0


	function mainframe:InitializeAllPlayerSources()
		for sourceName in pairs(PlayerSources) do
			mainframe.PlayerSources[sourceName] = {}
		end
	end

	mainframe:InitializeAllPlayerSources()
	mainframe.config = BattleGroundEnemies.db.profile[playerType]

	function mainframe:ApplyAllSettings()
		--BattleGroundEnemies:Debug(self.PlayerType)
		if BattleGroundEnemies.BGSize then mainframe:ApplyBGSizeSettings() end
	end

	function mainframe:RemoveAllPlayersFromAllSources()
		self:InitializeAllPlayerSources()
		self:AfterPlayerSourceUpdate()
	end


	function mainframe:RemoveAllPlayersFromSource(source)
		self:BeforePlayerSourceUpdate(source)
		self:AfterPlayerSourceUpdate()
	end

	function mainframe:BeforePlayerSourceUpdate(source)
		self.PlayerSources[source] = {}
	end

	function mainframe:AddPlayerToSource(source, playerT)
		table.insert(self.PlayerSources[source], playerT)
	end

	function mainframe:FindPlayerInSource(source, playerT)
		local playerSource = self.PlayerSources[source]
		for i = 1, #playerSource do
			local playerData = playerSource[i]
			if playerData.name == playerT.name then
				return playerData
			end
		end
	end

	local function matchBattleFieldScoreToArenaEnemyPlayer(scoreTables, arenaPlayerInfo)
		local foundPlayer = false
		local foundMatchIndex
		for i = 1, #scoreTables do
			local scoreInfo = scoreTables[i]
	
			-- local faction = scoreInfo.faction
			-- local name = scoreInfo.name
			-- local classToken = scoreInfo.classToken
			-- local specName = scoreInfo.talentSpec
			-- local raceName = scoreInfo.raceName
	
			if scoreInfo.classToken and arenaPlayerInfo.classTag then
				if scoreInfo.faction == BattleGroundEnemies.EnemyFaction and scoreInfo.classToken == arenaPlayerInfo.classTag and scoreInfo.talentSpec == arenaPlayerInfo.specName then --specname/talentSpec can be nil for old expansions
					if foundPlayer then
						return false -- we already had a match but found a second player that matches, unlucky
					end
					foundPlayer = true --we found a match, make sure its the only one
					foundMatchIndex = i
				end
			end
		end
		if foundPlayer then
			return scoreTables[foundMatchIndex]
		end
	end

	function mainframe:AfterPlayerSourceUpdate()
		local newPlayers = {} --contains combined data from PlayerSources
		if self.PlayerType == PlayerTypes.Enemies then
			if BattleGroundEnemies.Testmode.Active then
				newPlayers = self.PlayerSources[PlayerSources.FakePlayers]
			else
				local scoreboardEnemies = self.PlayerSources[PlayerSources.Scoreboard]
				local numScoreboardEnemies = #scoreboardEnemies
				local addScoreBoardPlayers = false
				if IsInArena then
					--use arenaPlayers is primary source
					local arenaEnemies = self.PlayerSources[PlayerSources.ArenaPlayers]
					local numArenaEnemies = #arenaEnemies
					if numArenaEnemies > 0 then
						for i = 1, numArenaEnemies do
							local playerName
							local arenaEnemy = arenaEnemies[i]
							if arenaEnemy.name then
								playerName = arenaEnemy.name
							else
								--useful in solo shuffle in first round, then we can show a playername via data from scoreboard
								local match = matchBattleFieldScoreToArenaEnemyPlayer(scoreboardEnemies, arenaEnemy)
								if match then
									--BattleGroundEnemies:LogToSavedVariables("found a match")
									playerName = match.name
								else
									--BattleGroundEnemies:LogToSavedVariables("didnt find a match", arenaEnemy.additionalData.PlayerArenaUnitID)
									-- use the unitID
									playerName = arenaEnemy.additionalData.PlayerArenaUnitID
								end
							end
							local t = Mixin({}, arenaEnemy)
							t.name = playerName
							table.insert(newPlayers, t)
						end
					else
						addScoreBoardPlayers = true
						--maybe we got some in scoreboard
					end
				else --in BattleGround 
					if numScoreboardEnemies == 0 then
						if self.IsRatedBG and IsRetail then
							BattleGroundEnemies:EnableFallbackToCombatlogScanning()
							newPlayers = self.PlayerSources[PlayerSources.CombatLog]
						end
					else
						BattleGroundEnemies:DisableFallbackToCombatlogScanning()
						addScoreBoardPlayers = true
					end
				end
				if addScoreBoardPlayers then
					for i = 1, numScoreboardEnemies do
						local scoreboardEnemy = scoreboardEnemies[i]
						table.insert(newPlayers, {
							name = scoreboardEnemy.name,
							raceName = scoreboardEnemy.raceName,
							classTag = scoreboardEnemy.classToken,
							specName = scoreboardEnemy.talentSpec
						})
					end
				end
			end
		else --"Allies"
			local groupMembers = self.PlayerSources[PlayerSources.GroupMembers]
			local numGroupMembers = #groupMembers
			local addWholeGroup = false
			if BattleGroundEnemies.Testmode.Active then
				if BattleGroundEnemies.db.profile.Testmode_UseTeammates then
					addWholeGroup = true
				else
					--just addMyself and fill up the rest with fakeplayers
					if PlayerButton.PlayerDetails then
						table.insert(newPlayers, groupMembers[numGroupMembers]) --i am always last in here
						local fakeAllies = self.PlayerSources[PlayerSources.FakePlayers]
						local numFakeAllies = #fakeAllies
						for i = 1, numFakeAllies do
							local fakeAlly = fakeAllies[i]
							table.insert(newPlayers, fakeAlly)
						end
					end
				end
			else
				addWholeGroup = true
			end
			if addWholeGroup then
				for i = 1, numGroupMembers do
					local groupMember = groupMembers[i]
					local specName = groupMember.specName
					if not specName or specName == "" then
						local name = groupMember.name
						--BattleGroundEnemies:LogToSavedVariables("player", name, "doesnt have a spec from group member")
						local match = self:FindPlayerInSource(PlayerSources.Scoreboard, groupMember)
						if match then
							--BattleGroundEnemies:LogToSavedVariables("player", name, "we found a spec from the scoreboard")
							groupMember.specName = match.talentSpec
						end
					end
					table.insert(newPlayers, groupMember)
				end
			end
		end
		self:BeforePlayerUpdate()
		for i = 1, #newPlayers do
			local newPlayer = newPlayers[i]
			local name = newPlayer.name
			local raceName = newPlayer.raceName
			local classTag = newPlayer.classTag
			local specName = newPlayer.specName
			local additionalData = newPlayer.additionalData
			self:CreateOrUpdatePlayer(name, raceName, classTag, specName, additionalData)
		end
		self:UpdatePlayers()
	end

	function mainframe:Enable()
		--BattleGroundEnemies:LogToSavedVariables(self.PlayerType, "enabled")

		if BattleGroundEnemies.Testmode.Active then
			self:SetScript("OnUpdate", nil)
		else
			if self.PlayerType == PlayerTypes.Enemies then
				--BattleGroundEnemies:LogToSavedVariables("Registered enemie events")
				self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
				self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
				self:RegisterEvent("UNIT_NAME_UPDATE")
				if HasSpeccs then
					self:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS")
				end
			end
			self:SetScript("OnUpdate", self.RealPlayersOnUpdate)

			if IsInArena or IsInBattleground then
				BattleGroundEnemies:CheckForArenaEnemies()
			end
		end
		self:Show()
	end

	function mainframe:Disable()
		--BattleGroundEnemies:LogToSavedVariables(self.PlayerType, "disabled")
		self:UnregisterAllEvents()
		self:Hide()
	end

	function mainframe:ApplyBGSizeSettings()
		--BattleGroundEnemies:LogToSavedVariables("ApplyBGSizeSettings", BattleGroundEnemies.BGSize, self.PlayerType)
		--if not BattleGroundEnemies.BGSize then return end
		self.config = BattleGroundEnemies.db.profile[self.PlayerType]

		self.bgSizeConfig = self.config[tostring(BattleGroundEnemies.BGSize)]
		if InCombatLockdown() then
			return BattleGroundEnemies:QueueForUpdateAfterCombat(self, "ApplyBGSizeSettings")
		end

		local conf = self.bgSizeConfig

		self:SetSize(conf.BarWidth, 30)
		self:SetScale(conf.Framescale)

		self:ClearAllPoints()
		if not conf.Position_X and not conf.Position_Y then
			self:SetPoint("CENTER", UIParent, "CENTER")
		else
			local scale = self:GetEffectiveScale()
			self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", conf.Position_X / scale, conf.Position_Y / scale)
		end
		self:SetPlayerCountJustifyV(conf.BarVerticalGrowdirection)

		self.PlayerCount:ApplyFontStringSettings(conf.PlayerCount.Text)

		self:SortPlayers(true) --force repositioning

		for name, playerButton in pairs(self.Players) do
			playerButton:ApplyButtonSettings()
			playerButton:SetBindings()
		end


		for number, playerButton in pairs(self.InactivePlayerButtons) do
			playerButton:ApplyButtonSettings()
		end

		self:UpdatePlayerCount()
		self:CheckEnableState()
	end

	function mainframe:CheckEnableState()
		if self.config.Enabled and BattleGroundEnemies.BGSize and self.bgSizeConfig.Enabled then
			self:Enable()
		else
			self:Disable()
		end
	end


	function mainframe:UpdatePlayerCount(currentCount)
		--BattleGroundEnemies:LogToSavedVariables("UpdatePlayerCount", currentCount)
		currentCount = currentCount or 0
		currentCount =  math.max(self.NumShownPlayers, currentCount)



		BattleGroundEnemies:UpdateBGSize()

		local isEnemy = self.PlayerType == PlayerTypes.Enemies
		BattleGroundEnemies.EnemyFaction = BattleGroundEnemies.EnemyFaction or (playerFaction == "Horde" and 1 or 0)

		if self.bgSizeConfig and self.bgSizeConfig.PlayerCount.Enabled then
			self.PlayerCount:Show()
			self.PlayerCount:SetText(format(isEnemy == (BattleGroundEnemies.EnemyFaction == 0) and PLAYER_COUNT_HORDE or PLAYER_COUNT_ALLIANCE, currentCount))
		else
			self.PlayerCount:Hide()
		end
	end

	function mainframe:GetPlayerbuttonByUnitID(unitID)
		local uName = GetUnitName(unitID, true)

		return self.Players[uName]
	end

	function mainframe:GetRandomPlayer()
		local t = {}
		for playerName, playerButton in pairs(self.Players) do
			table_insert(t, playerButton)
		end
		local numPlayers = #t
		if numPlayers > 0 then
			return t[math_random(1, numPlayers)]
		end
	end

	function mainframe:SetPlayerCountJustifyV(direction)
		if direction == "downwards" then
			self.PlayerCount:SetJustifyV("BOTTOM")
		else
			self.PlayerCount:SetJustifyV("TOP")
		end
	end

	function mainframe:SetupButtonForNewPlayer(playerDetails)
		local playerButton = self.InactivePlayerButtons[#self.InactivePlayerButtons]
		if playerButton then --recycle a previous used button

			table_remove(self.InactivePlayerButtons, #self.InactivePlayerButtons)
			--Cleanup previous shown stuff of another player
			playerButton.MyTarget:Hide()	--reset possible shown target indicator frame
			playerButton.MyFocus:Hide()	--reset possible shown target indicator frame

			for moduleName, moduleFrameOnButton in pairs(BattleGroundEnemies.ButtonModules) do
				if playerButton[moduleName] and playerButton[moduleName].Reset then
					playerButton[moduleName]:Reset()
				end
			end


			if playerButton.UnitIDs then
				wipe(playerButton.UnitIDs.TargetedByEnemy)
				playerButton:UpdateTargetIndicators()
				if playerButton.PlayerIsEnemy then
					playerButton:DeleteActiveUnitID()
				end
			end

			if playerButton.Auras then
				if playerButton.Auras.HELPFUL then
					wipe(playerButton.Auras.HELPFUL)
				end
				if playerButton.Auras.HARMFUL then
					wipe(playerButton.Auras.HARMFUL)
				end
			end

			playerButton.unitID = nil
			playerButton.unit = nil
		else --no recycleable buttons remaining => create a new one
			playerButton = CreateFrame('Button', nil, self, 'SecureUnitButtonTemplate')
			playerButton:RegisterForClicks('AnyUp')
			playerButton:Hide()
			-- setmetatable(playerButton, self)
			-- self.__index = self


			playerButton.ButtonEvents = playerButton.ButtonEvents or {}
			playerButton.UnitIDs = {TargetedByEnemy = {}}
			playerButton.Auras = {
				HELPFUL = {},
				HARMFUL = {}
			}


			playerButton.PlayerType = self.PlayerType
			playerButton.PlayerIsEnemy = playerButton.PlayerType == PlayerTypes.Enemies and true or false

			playerButton:SetScript("OnSizeChanged", function(self, width, height)
				--self.DRContainer:SetWidthOfAuraFrames(height)
				self:DispatchEvent("PlayerButtonSizeChanged", width, height)
			end)

			Mixin(playerButton, buttonFunctions)

			if playerButton.PlayerIsEnemy then
				Mixin(playerButton, enemyButtonFunctions)
			end

			playerButton.Counter = {}
			playerButton:SetScript("OnEvent", function(self, event, ...)
				--self.Counter[event] = (self.Counter[event] or 0) + 1

				self[event](self, ...) end)
			playerButton:SetScript("OnShow", function()
				playerButton.isShown = true
			end)
			playerButton:SetScript("OnHide", function()
				playerButton.isShown = false
			end)

			-- events/scripts
			playerButton:RegisterForDrag('LeftButton')
			playerButton:SetClampedToScreen(true)

			playerButton:SetScript('OnDragStart', playerButton.OnDragStart)
			playerButton:SetScript('OnDragStop', playerButton.OnDragStop)


			playerButton.RangeIndicator_Frame = CreateFrame("Frame", nil, playerButton)
			--playerButton.RangeIndicator_Frame:SetFrameLevel(playerButton:GetFrameLevel())
			-- playerButton.RangeIndicator = playerButton.RangeIndicator_Frame


			--MyTarget, indicating the current target of the player
			playerButton.MyTarget = CreateFrame('Frame', nil, playerButton.healthBar, BackdropTemplateMixin and "BackdropTemplate")

			playerButton.MyTarget:Hide()

			--MyFocus, indicating the current focus of the player
			playerButton.MyFocus = CreateFrame('Frame', nil, playerButton.healthBar, BackdropTemplateMixin and "BackdropTemplate")
			playerButton.MyFocus:SetBackdrop({
				bgFile = "Interface/Buttons/WHITE8X8", --drawlayer "BACKGROUND"
				edgeFile = 'Interface/Buttons/WHITE8X8', --drawlayer "BORDER"
				edgeSize = 1
			})
			playerButton.MyFocus:SetBackdropColor(0, 0, 0, 0)
			playerButton.MyFocus:Hide()

			playerButton.ButtonModules = {}
			for moduleName, moduleFrame in pairs(BattleGroundEnemies.ButtonModules) do
				if moduleFrame.AttachToPlayerButton then
					moduleFrame:AttachToPlayerButton(playerButton)

					if not playerButton[moduleName] then print("something went wrong here after AttachToPlayerButton", moduleName) end

					playerButton[moduleName].GetConfig = function(self)
						self.config = playerButton.bgSizeConfig.ButtonModules[moduleName]
						return self.config
					end
					playerButton[moduleName].moduleName = moduleName
				end
			end

			playerButton:ApplyButtonSettings()
		end

		playerButton.PlayerDetails = playerDetails
		-- BattleGroundEnemies:LogToSavedVariables("PlayerDetailsChanged")
		playerButton:PlayerDetailsChanged()

		self.Target = nil

		if playerButton.PlayerIsEnemy then
			playerButton:UpdateRange(false)
		else
			playerButton:UpdateRange(true)
		end

		playerButton:Show()

		self.Players[playerButton.PlayerDetails.PlayerName] = playerButton

		return playerButton
	end

	function mainframe:RemovePlayer(playerButton)
		if playerButton == PlayerButton then return end -- dont remove the Player itself

		local targetEnemyButton = playerButton.Target
		if targetEnemyButton then -- if that no longer exiting ally targeted something update the button of its target
			playerButton:IsNoLongerTarging(targetEnemyButton)
		end

		playerButton:Hide()

		table_insert(self.InactivePlayerButtons, playerButton)
		self.Players[playerButton.PlayerDetails.PlayerName] = nil
	end

	function mainframe:RemoveAllPlayers()
		for playerName, playerButton in pairs(self.Players) do
			self:RemovePlayer(playerButton)
		end
		self:SortPlayers()
	end

	function mainframe:ButtonPositioning()
		local orderedPlayers = self.CurrentPlayerOrder

		local config = self.bgSizeConfig
		local columns = config.BarColumns


		local barHeight = config.BarHeight
		local barWidth = config.BarWidth

		local verticalSpacing = config.BarVerticalSpacing
		local horizontalSpacing = config.BarHorizontalSpacing

		local growDownwards = (config.BarVerticalGrowdirection == "downwards")
		local growRightwards = (config.BarHorizontalGrowdirection == "rightwards")

		local playerCount = #orderedPlayers

		local rowsPerColumn = math.ceil(playerCount/columns)

		local pointX, offsetX, offsetY, pointY, relPointY, offsetDirectionX, offsetDirectionY

		if growRightwards then
			pointX = "LEFT"
			offsetDirectionX = 1
		else
			pointX = "RIGHT"
			offsetDirectionX = -1
		end

		if growDownwards then
			pointY = "TOP"
			relPointY = "BOTTOM"
			offsetDirectionY = -1
		else
			pointY = "BOTTOM"
			relPointY = "TOP"
			offsetDirectionY = 1
		end

		local point = pointY..pointX
		local relpoint = relPointY..pointX

		local column = 1
		local row = 1

		for i = 1, playerCount do
			local playerButton = orderedPlayers[i]
			if playerButton then --should never be nil
				playerButton.Position = i
				if column > 1 then
					offsetX = (column - 1) * (barWidth + horizontalSpacing) * offsetDirectionX
				else
					offsetX = 0
				end

				if row > 1 then
					offsetY = (row - 1) * (barHeight + verticalSpacing) * offsetDirectionY
				else
					offsetY = 0
				end


				playerButton:ClearAllPoints()
				playerButton:SetPoint(point, self, relpoint, offsetX, offsetY)

				playerButton:SetModulePositions()


				if row < rowsPerColumn then
					row = row + 1
				else
					column = column + 1
					row = 1
				end
			end
		end
	end

	function mainframe:BeforePlayerUpdate()
		wipe(self.NewPlayersDetails)
	end

	function mainframe:CreateOrUpdatePlayer(name, race, classTag, specName, additionalData)
		local spec = false
		if specName and specName ~="" then
			spec = specName
		end
		local specData
		if classTag and spec then
			local t = Data.Classes[classTag]
			if t then
				t = t[spec]
				specData = t
			end
		end

		local playerDetails = {
			PlayerName = name,
			PlayerClass = string.upper(classTag), --apparently it can happen that we get a lowercase "druid" from GetBattlefieldScore() in TBCC, IsTBCC
			PlayerClassColor = RAID_CLASS_COLORS[classTag],
			PlayerRace = race and LibRaces:GetRaceToken(race) or "Unknown", --delivers a locale independent token for relentless check
			PlayerSpecName = spec, --set to false since we use Mixin() and Mixin doesnt mixin nil values and therefore we dont overwrite values with nil
			PlayerRoleNumber = specData and specData.roleNumber,
			PlayerLevel = false,
			isFakePlayer = false, 		--to set a base value, might be overwritten by mixin
			PlayerArenaUnitID = nil 	--to set a base value, might be overwritten by mixin
		}
		if additionalData then
			Mixin(playerDetails, additionalData)
		end

		-- BattleGroundEnemies:LogToSavedVariables("CreateOrUpdatePlayer", name, race, classTag, specName, additionalData)
		local playerButton = self.Players[name]
		if playerButton then	--already existing
			local currentDetails = playerButton.PlayerDetails
			local detailsChanged = false

			for k, v in pairs(playerDetails) do
				if v ~= currentDetails[k] then
					detailsChanged = true
					-- BattleGroundEnemies:LogToSavedVariables("k changed1", k)
					break
				end
			end

			if not detailsChanged then
				for k, v in pairs(currentDetails) do
					if v ~= playerDetails[k] then
						detailsChanged = true
						-- BattleGroundEnemies:LogToSavedVariables("k changed2", k)
						break
					end
				end
			end
			playerButton.PlayerDetails = playerDetails

			if detailsChanged then
				playerButton:PlayerDetailsChanged()
			end

			playerButton.Status = 1 --1 means found, already existing
			playerDetails = playerButton.PlayerDetails
		else
			table.insert(self.NewPlayersDetails, playerDetails)
		end
	end

	function mainframe:UpdatePlayers()
		local inCombat = InCombatLockdown()
		for playerName, playerButton in pairs(self.Players) do
			if playerButton.Status == 2 then --no longer existing
				if inCombat then
					return BattleGroundEnemies:QueueForUpdateAfterCombat(self, "AfterPlayerSourceUpdate")
				else
					self:RemovePlayer(playerButton)
				end
			else -- == 1 -- set to 2 for the next comparison
				playerButton.Status = 2
			end
		end

		local newPlayerCount =  #self.NewPlayersDetails
		for i = 1, newPlayerCount do
			local playerDetails = self.NewPlayersDetails[i]
			if inCombat then
				return BattleGroundEnemies:QueueForUpdateAfterCombat(self, "AfterPlayerSourceUpdate")
			else
				local playerButton = self:SetupButtonForNewPlayer(playerDetails)
				playerButton.Status = 2
			end
		end
		self:SortPlayers(false)
	end

	do
		local BlizzardsSortOrder = {}
		for i = 1, #CLASS_SORT_ORDER do -- Constants.lua
			BlizzardsSortOrder[CLASS_SORT_ORDER[i]] = i --key = ENGLISH CLASS NAME, value = number
		end

		local function PlayerSortingByRoleClassName(playerA, playerB)-- a and b are playerButtons
			local detailsPlayerA = playerA.PlayerDetails
			local detailsPlayerB = playerB.PlayerDetails

			if detailsPlayerA.PlayerRoleNumber and detailsPlayerB.PlayerRoleNumber then
				if detailsPlayerA.PlayerRoleNumber == detailsPlayerB.PlayerRoleNumber then
					if BlizzardsSortOrder[ detailsPlayerA.PlayerClass ] == BlizzardsSortOrder[ detailsPlayerB.PlayerClass ] then
						if detailsPlayerA.PlayerName < detailsPlayerB.PlayerName then return true end
					elseif BlizzardsSortOrder[ detailsPlayerA.PlayerClass ] < BlizzardsSortOrder[ detailsPlayerB.PlayerClass ] then return true end
				elseif detailsPlayerA.PlayerRoleNumber < detailsPlayerB.PlayerRoleNumber then return true end
			else
				if BlizzardsSortOrder[ detailsPlayerA.PlayerClass ] == BlizzardsSortOrder[ detailsPlayerB.PlayerClass ] then
					if detailsPlayerA.PlayerName < detailsPlayerB.PlayerName then return true end
				elseif BlizzardsSortOrder[ detailsPlayerA.PlayerClass ] < BlizzardsSortOrder[ detailsPlayerB.PlayerClass ] then return true end
			end
		end

		local function PlayerSortingByArenaUnitID(playerA, playerB)-- a and b are playerButtons
			if not (playerA and playerB) then return end
			local detailsPlayerA = playerA.PlayerDetails
			local detailsPlayerB = playerB.PlayerDetails
			if not (detailsPlayerA.PlayerArenaUnitID and detailsPlayerB.PlayerArenaUnitID) then return end
			if detailsPlayerA.PlayerArenaUnitID <= detailsPlayerB.PlayerArenaUnitID then
				return true
			end
		end

		local function CRFSort_Group_(playerA, playerB) -- this is basically a adapted CRFSort_Group to make the sorting in arena
			if not (playerA and playerB) then return end
			local detailsPlayerA = playerA.PlayerDetails
			local detailsPlayerB = playerB.PlayerDetails
			if not (detailsPlayerA.unitID and detailsPlayerB.unitID) then return true end
			if ( detailsPlayerA.unitID == "player" ) then
				return true;
			elseif ( detailsPlayerB.unitID == "player" ) then
				return false;
			else
				return detailsPlayerA.unitID < detailsPlayerB.unitID;	--String compare is OK since we don't go above 1 digit for party.
			end
		end

		function mainframe:SortPlayers(forceRepositioning)
			--BattleGroundEnemies:LogToSavedVariables("SortPlayers", self.PlayerType)
			local newPlayerOrder = {}
			for playerName, playerButton in pairs(self.Players) do
				-- BattleGroundEnemies:LogToSavedVariables(playerName)
				table.insert(newPlayerOrder, playerButton)
			end
--[[ 
			BattleGroundEnemies:LogToSavedVariables("before sorting")
			for i = 1, #newPlayerOrder do
				BattleGroundEnemies:LogToSavedVariables(i, newPlayerOrder[i].PlayerDetails.PlayerName)
			end

 ]]

			if IsInArena then
				if (self.PlayerType == PlayerTypes.Enemies) then
					local usePlayerSortingByArenaUnitID = false
					usePlayerSortingByArenaUnitID = true
					for i = 1, #newPlayerOrder do
						if not newPlayerOrder[i].PlayerDetails.PlayerArenaUnitID then
							usePlayerSortingByArenaUnitID = false
							break
						end
					end
					if usePlayerSortingByArenaUnitID then
						-- BattleGroundEnemies:LogToSavedVariables("usePlayerSortingByArenaUnitID", self.PlayerType)
						table.sort(newPlayerOrder, PlayerSortingByArenaUnitID)
					else
						-- BattleGroundEnemies:LogToSavedVariables("dont usePlayerSortingByArenaUnitID", self.PlayerType)
						table.sort(newPlayerOrder, PlayerSortingByRoleClassName)
					end
				else
					table.sort(newPlayerOrder, CRFSort_Group_)
				end
			else
				table.sort(newPlayerOrder, PlayerSortingByRoleClassName)
			end

			local orderChanged = false
			for i = 1, math_max(#newPlayerOrder, #self.CurrentPlayerOrder) do --players can leave or join so #self.CurrentPlayerOrder can be unequal to #newPlayerOrder
				if newPlayerOrder[i] ~= self.CurrentPlayerOrder[i] then
					orderChanged = true
					break
				end
			end

--[[ 			BattleGroundEnemies:LogToSavedVariables("after sorting")
			for i = 1, #newPlayerOrder do
				BattleGroundEnemies:LogToSavedVariables(i, newPlayerOrder[i].PlayerDetails.PlayerName)
			end ]]

			self.NumShownPlayers = #newPlayerOrder
			self:UpdatePlayerCount()
			if orderChanged or forceRepositioning then
				local inCombat = InCombatLockdown()
				if inCombat then
					return BattleGroundEnemies:QueueForUpdateAfterCombat(self, "AfterPlayerSourceUpdate")
				end
				self.CurrentPlayerOrder = newPlayerOrder
				self:ButtonPositioning()
			end
		end
	end


	mainframe:SetClampedToScreen(true)
	mainframe:SetMovable(true)
	mainframe:SetUserPlaced(true)
	mainframe:SetResizable(true)
	mainframe:SetToplevel(true)

	mainframe.PlayerCount = BattleGroundEnemies.MyCreateFontString(mainframe)
	mainframe.PlayerCount:SetAllPoints()
	mainframe.PlayerCount:SetJustifyH("LEFT")
end


--BattleGroundEnemies.EnemyFaction
--BattleGroundEnemies.AllyFaction

--each module can heave one of the different types
--dynamicContainer == the container is only as big as the children its made of, the container sets only 1 point
--buttonHeightLengthVariable = a attachment that has the height of the button and a variable width (the module will set the width itself). when unused sets to 0.01 width
--buttonHeightSquare = a attachment that has the height of the button and the same width, when unused sets to 0.01 width
--HeightAndWidthVariable


function BattleGroundEnemies:IsModuleEnabledOnThisExpansion(moduleName)
	local moduleFrame = self.ButtonModules[moduleName]
	if moduleFrame then
		return moduleFrame.enabledInThisExpansion
	end
	return false
end

local function copySettingsWithoutOverwrite(src, dest)
	if not src or type(src) ~="table" then return end
    if type(dest) ~= "table" then dest = {} end

    for k, v in pairs(src) do
        if type(v) == "table" then
            dest[k] = copySettingsWithoutOverwrite(v, dest[k])
        elseif type(v) ~= type(dest[k]) then -- only overwrite if the type in dest is different
            dest[k] = v
        end
    end

    return dest
end

function BattleGroundEnemies:NewButtonModule(moduleSetupTable)
	if type(moduleSetupTable) ~= "table" then return error("Tried to register a Module but the parameter wasn't a table") end
	if not moduleSetupTable.moduleName then return error("NewButtonModule error: No moduleName specified") end
	local moduleName = moduleSetupTable.moduleName
	if not moduleSetupTable.localizedModuleName then return error("NewButtonModule error for module: " .. moduleName .. " No localizedModuleName specified") end
	if moduleSetupTable.enabledInThisExpansion == nil then return error("NewButtonModule error for module: " .. moduleName .. " enabledInThisExpansion is nil") end


	if self.ButtonModules[moduleName] then return error("module "..moduleName.." is already registered") end
	local moduleFrame = CreateFrame("Frame", nil, UIParent)

	moduleSetupTable.flags = moduleSetupTable.flags or {}
	Mixin(moduleFrame, moduleSetupTable)


	local BGSizes = {"5", "15", "40"}
	for k in pairs(PlayerTypes) do
		for j = 1, #BGSizes do
			local BGSize = BGSizes[j]
			Data.defaultSettings.profile[k][BGSize].ButtonModules = Data.defaultSettings.profile[k][BGSize].ButtonModules or {}
			Data.defaultSettings.profile[k][BGSize].ButtonModules[moduleName] = Data.defaultSettings.profile[k][BGSize].ButtonModules[moduleName] or {}
			copySettingsWithoutOverwrite(moduleSetupTable.defaultSettings, Data.defaultSettings.profile[k][BGSize].ButtonModules[moduleName])
		end
	end

	--not used
	--[[ moduleFrame:SetScript("OnEvent", function(self, event, ...)
		BattleGroundEnemies:Debug("BattleGroundEnemies module event", moduleName, event, ...)
		self[event](self, ...)
	end)

	moduleFrame.Debug = function(self, ...)
		BattleGroundEnemies:Debug("UnitInCombat module debug", moduleName, ...)
	end ]]

	self.ButtonModules[moduleName] = moduleFrame
	return moduleFrame
end

function BattleGroundEnemies:GetBigDebuffsPriority(spellId)
	if not BattleGroundEnemies.db.profile.UseBigDebuffsPriority then return end
	if not BigDebuffs then return end
	local priority = BigDebuffs.GetDebuffPriority and BigDebuffs:GetDebuffPriority(spellId)
	if not priority then return end
	if priority == 0 then return end
	return priority
end

function BattleGroundEnemies:GetSpellPriority(spellId)
	return self:GetBigDebuffsPriority(spellId) or Data.SpellPriorities[spellId]
end




BattleGroundEnemies:SetScript("OnEvent", function(self, event, ...)
	--self.Counter[event] = (self.Counter[event] or 0) + 1
	--BattleGroundEnemies:Debug("BattleGroundEnemies OnEvent", event, ...)
	self[event](self, ...)
end)
BattleGroundEnemies:Hide()

function BattleGroundEnemies:ShowTooltip(owner, func)
	if self.db.profile.ShowTooltips then
		GameTooltip:SetOwner(owner, "ANCHOR_RIGHT", 0, 0)
		func()
		GameTooltip:Show()
	end
end


function BattleGroundEnemies:GetColoredName(playerDetails)
	local name = playerDetails.PlayerName
	local classTag = playerDetails.PlayerClass
	local tbl = CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classTag] or RAID_CLASS_COLORS[classTag] or GRAY_FONT_COLOR
	return ("|cFF%02x%02x%02x%s|r"):format(tbl.r*255, tbl.g*255, tbl.b*255, name)
end

local function FindAuraBySpellID(unitID, spellId, filter)
	if not unitID or not spellId then return end

	for i = 1, 40 do
		local name, _, amount, debuffType, duration, expirationTime, unitCaster, _, _, id, _, _, _, _, _, value2, value3, value4 = UnitAura(unitID, i, filter)
		if not id then return end -- no more auras

		if spellId == id then
			return i, name, _, amount, debuffType, duration, expirationTime, unitCaster, _, _, id, _, _, _, _, _, value2, value3, value4
		end
	end
end

-- for classic, IsClassic
local function FindAuraBySpellName(unitID, spellName, filter)
	if not unitID or not spellName then return end

	for i = 1, 40 do
		local name, _, amount, debuffType, duration, expirationTime, unitCaster, _, _, id, _, _, _, _, _, value2, value3, value4 = UnitAura(unitID, i, filter)
		if not name then return end -- no more auras

		if spellName == name then
			return i, name, _, amount, debuffType, duration, expirationTime, unitCaster, _, _, id, _, _, _, _, _, value2, value3, value4
		end
	end
end




-- BattleGroundEnemies.Fake_ARENA_OPPONENT_UPDATE()
-- 	BattleGroundEnemies:ARENA_OPPONENT_UPDATE()
-- end

function BattleGroundEnemies:ShowAuraTooltip(playerButton, displayedAura)
	if not displayedAura then return end

	local spellId = displayedAura.spellId
	if not spellId then return end

	local unitID = playerButton:GetUnitID()
	local filter = getFilterFromAuraInfo(displayedAura)
	if unitID and filter then
		local index = FindAuraBySpellID(unitID, spellId, filter)
		if index then
			return GameTooltip:SetUnitAura(unitID, index, filter)
		else
			GameTooltip:SetSpellByID(spellId)
		end
	else
		GameTooltip:SetSpellByID(spellId)
	end
end




local randomTrinkets = {} -- key = number, value = spellId
local randomRacials = {} -- key = number, value = spellId
local FakePlayersOnUpdateFrame = CreateFrame("frame")
FakePlayersOnUpdateFrame:Hide()


local function SetupTrinketAndRacialData()
	do
		local count = 1
		for triggerSpellID, trinketData in pairs(Data.TrinketData) do
			if type(triggerSpellID) == "string" then   --support for classic, IsClassic
				randomTrinkets[count] = triggerSpellID
				count = count + 1
			else
				if GetSpellInfo(triggerSpellID) then
					randomTrinkets[count] = triggerSpellID
					count = count + 1
				end
			end
		end
	end

	do
		local count = 1
		for racialSpelliD, data in pairs(Data.RacialSpellIDtoCooldown) do
			if GetSpellInfo(racialSpelliD) then
				randomRacials[count] = racialSpelliD
				count = count + 1
			end
		end
	end
end

function BattleGroundEnemies.ToggleTestmodeOnUpdate()
	local enabled = not FakePlayersOnUpdateFrame:IsShown()
	FakePlayersOnUpdateFrame:SetShown(enabled)
	if enabled then
		BattleGroundEnemies:Information(L.FakeEventsEnabled)
	else
		BattleGroundEnemies:Information(L.FakeEventsDisabled)
	end
end

function BattleGroundEnemies.ToggleTestmode()
	if BattleGroundEnemies.Testmode.Active then --disable testmode
		BattleGroundEnemies:DisableTestMode()
	else --enable Testmode
		BattleGroundEnemies:EnableTestMode()
	end
end


function BattleGroundEnemies:DisableTestMode()
	self.Testmode.Active = false
	self.BattlegroundBuff = false
	self.Allies:RemoveAllPlayersFromSource(PlayerSources.FakePlayers)
	self.Enemies:RemoveAllPlayersFromSource(PlayerSources.FakePlayers)
	FakePlayersOnUpdateFrame:Hide()
	self:Disable()
	self:Information(L.TestmodeDisabled)
end

do
	local counter

	function BattleGroundEnemies:FillFakePlayerData(amount, mainFrame, role)
		for i = 1, amount do
			local name, classTag, specName

			if HasSpeccs then
				local randomSpec
				randomSpec = Data.RolesToSpec[role][math_random(1, #Data.RolesToSpec[role])]
				classTag = randomSpec.classTag
				specName = randomSpec.specName
			else
				classTag = Data.ClassList[math_random(1, #Data.ClassList)]
			end
			local nameprefix = mainFrame.PlayerType == PlayerTypes.Enemies and "Enemy" or "Ally"
			name = L[nameprefix]..counter.."-Realm"..counter

			mainFrame:AddPlayerToSource(PlayerSources.FakePlayers, {
				name = name,
				raceName = nil,
				classTag = classTag,
				specName = specName,
				additionalData = {
					isFakePlayer = true,
					PlayerLevel = i==1 and MaxLevel or math_random(MaxLevel - 10, MaxLevel -1)
				}
			})
			counter = counter + 1
		end
	end

	function BattleGroundEnemies:CreateFakePlayers()
		local count = self.Testmode.BGSizeTestmode or 5
		for number, mainFrame in pairs({self.Allies, self.Enemies}) do
			local continue = true
			mainFrame:BeforePlayerSourceUpdate(PlayerSources.FakePlayers)

			local healerAmount = math_random(2, 3)
			local tankAmount = math_random(1)
			local damagerAmount = count - healerAmount - tankAmount


			if mainFrame == self.Allies then
				local myRole
				if HasSpeccs then
					if not specCache[self.PlayerDetails.GUID] then
						myRole = "DAMAGER"
					else
						myRole = Data.Classes[self.PlayerDetails.PlayerClass][specCache[self.PlayerDetails.GUID]].roledID
					end
				else
					myRole = "DAMAGER"
				end
				if myRole == "HEALER" then
					healerAmount = healerAmount - 1
				elseif myRole == "TANK" then
					tankAmount = tankAmount - 1
				else
					damagerAmount = damagerAmount - 1
				end
			end

			counter = 1
			BattleGroundEnemies:FillFakePlayerData(healerAmount, mainFrame, "HEALER")
			BattleGroundEnemies:FillFakePlayerData(tankAmount, mainFrame, "TANK")
			BattleGroundEnemies:FillFakePlayerData(damagerAmount, mainFrame, "DAMAGER")
		
			mainFrame:AfterPlayerSourceUpdate()

			if continue then
				for name, playerButton in pairs(mainFrame.Players) do
					if IsRetail then
						playerButton.Covenant:UpdateCovenant(math_random(1, #Data.CovenantIcons))
					end
				end
			end
		end
	end

	Data.FoundAuras = {
		HELPFUL = {
			foundPlayerAuras = {},
			foundNonPlayerAuras = {},
		},
		HARMFUL = {
			foundPlayerAuras = {},
			foundNonPlayerAuras = {},
			foundDRAuras = {}
		}
	}

	local TestmodeRanOnce = false
	function BattleGroundEnemies:EnableTestMode()
		self.Testmode.Active = true

		if not TestmodeRanOnce then
			SetupTrinketAndRacialData()
			TestmodeRanOnce = true
		end

		wipe(self.Testmode.FakePlayerAuras)
		wipe(self.Testmode.FakePlayerDRs)
		wipe(self.Testmode.FakeRaidTargetIcons)

		local mapIDs = {}
		for mapID, data in pairs(Data.BattlegroundspezificBuffs) do
			mapIDs[#mapIDs + 1] = mapID
		end
		local mandomm = math_random(1, #mapIDs)
		local randomMapID = mapIDs[mandomm]

		self.BattlegroundBuff = Data.BattlegroundspezificBuffs[randomMapID]

		for i = 1, #auraFilters do
			local filter = auraFilters[i]

			local auras = Data.FakeAuras[filter]
			local foundA = Data.FoundAuras[filter]
			local playerSpells = {}
			local numTabs = GetNumSpellTabs()
			for i = 1, numTabs do
				local name, texture, offset, numSpells = GetSpellTabInfo(i)
				for j = 1, numSpells do
					local id = j + offset
					local spellName, _, spelliD = GetSpellBookItemName(id, 'spell')
					if spelliD and IsSpellKnown(spelliD) then
						playerSpells[spelliD] = true
					end
				end
			end

			for spellId, auraDetails in pairs(auras) do
				if GetSpellInfo(spellId) then
					if filter == "HARMFUL" and DRList:GetCategoryBySpellID(IsClassic and auraDetails.name or spellId) then
						foundA.foundDRAuras[#foundA.foundDRAuras + 1] = auraDetails
					elseif playerSpells[spellId] then
						foundA.foundPlayerAuras[#foundA.foundPlayerAuras + 1] = auraDetails
						-- this buff could be applied from the player
					else
						foundA.foundNonPlayerAuras[#foundA.foundNonPlayerAuras + 1] = auraDetails
					end
				end
			end
		end


		self:CreateFakePlayers()

		self:Enable()

		FakePlayersOnUpdateFrame:Show()
		self:Information(L.TestmodeEnabled)
	end
end


do
	local holdsflag
	local TimeSinceLastOnUpdate = 0
	local UpdatePeroid = 1 --update every second

	local function FakeOnUpdate(self, elapsed) --OnUpdate runs if the frame FakePlayersOnUpdateFrame is shown
		TimeSinceLastOnUpdate = TimeSinceLastOnUpdate + elapsed
		if TimeSinceLastOnUpdate > UpdatePeroid then

			for number, mainFrame in pairs({BattleGroundEnemies.Allies, BattleGroundEnemies.Enemies}) do
				local hasFlag = false
				for name, playerButton in pairs(mainFrame.Players) do
					if playerButton.PlayerDetails.isFakePlayer then
						local n = math_random(1,10)
						--self:Debug("number", number)

						--self:Debug(playerButton.ObjectiveAndRespawn.Cooldown:GetCooldownDuration())

						if not playerButton.isDead then
							if BattleGroundEnemies.BGSize == 15 and n == 1 and not hasFlag then --this guy has a objective now
								-- hide old flag carrier
								local oldFlagholder = holdsflag
								if oldFlagholder then
									oldFlagholder:DispatchEvent("ArenaOpponentHidden")
								end

								playerButton:ArenaOpponentShown()

								holdsflag = playerButton
								hasFlag = true

							elseif n == 2 and playerButton.Racial.Cooldown:GetCooldownDuration() == 0 then -- racial used
								BattleGroundEnemies.CombatLogevents.SPELL_CAST_SUCCESS(BattleGroundEnemies, playerButton.PlayerDetails.PlayerName, nil, randomRacials[math_random(1, #randomRacials)])
							elseif n == 3 and playerButton.Trinket.Cooldown:GetCooldownDuration() == 0 then -- trinket used
								BattleGroundEnemies.CombatLogevents.SPELL_CAST_SUCCESS(BattleGroundEnemies, playerButton.PlayerDetails.PlayerName, nil, randomTrinkets[math_random(1, #randomTrinkets)])
							elseif n == 4 then --power simulation
								playerButton:UNIT_POWER_FREQUENT()
							elseif n == 5 then

								--let the player changed target or target someone if he didnt have a target before
								if playerButton.Target then
									playerButton:IsNoLongerTarging(playerButton.Target)
								end

								local oppositeMainFrame = playerButton:GetOppositeMainFrame()
								if oppositeMainFrame then --this really should never be nil
									local randomPlayer = oppositeMainFrame:GetRandomPlayer()

									if randomPlayer then
										playerButton:IsNowTargeting(randomPlayer)
									end
								end
							elseif n == 6 then
								UpdateFakeRaidTargetIcons(playerButton)
							end
							UpdateFakeAuras(playerButton)
						end
						playerButton:UNIT_HEALTH()

						if n == 6 then --toggle range
							playerButton:UpdateRange(not playerButton.wasInRange)
						end
					end
				end
			end

			TimeSinceLastOnUpdate = 0
		end
	end
	FakePlayersOnUpdateFrame:SetScript("OnUpdate", FakeOnUpdate)
end


BattleGroundEnemies.Objects = {}


local RequestFrame = CreateFrame("Frame", nil, BattleGroundEnemies)
RequestFrame:Hide()
do
	local TimeSinceLastOnUpdate = 0
	local UpdatePeroid = 2 --update every second
	local function RequestTicker(self, elapsed) --OnUpdate runs if the frame RequestFrame is shown
		TimeSinceLastOnUpdate = TimeSinceLastOnUpdate + elapsed
		if TimeSinceLastOnUpdate > UpdatePeroid then
			RequestBattlefieldScoreData()
			TimeSinceLastOnUpdate = 0
		end
	end
	RequestFrame:SetScript("OnUpdate", RequestTicker)
end



local function CreatedebugFrame()
	local f = FCF_OpenTemporaryWindow("FILTERED")
	f:SetMaxLines(2500)
	FCF_UnDockFrame(f);
	f:ClearAllPoints();
	f:SetPoint("CENTER", "UIParent", "CENTER", 0, 0);
	FCF_SetTabPosition(f, 0);
	f:Show();
	f.Tab = _G[f:GetName().."Tab"]
	f.Tab.conversationIcon:Hide()
	FCF_SetWindowName(f, "BGE_DebugFrame")

	return f
end

BattleGroundEnemies.ArenaIDToPlayerButton = {} --key = arenaID: arenaX, value = playerButton of that unitID

BattleGroundEnemies.Enemies = CreateFrame("Frame", nil, BattleGroundEnemies)
BattleGroundEnemies.Enemies.Counter = {}


BattleGroundEnemies.Enemies:Hide()
BattleGroundEnemies.Enemies:SetScript("OnEvent", function(self, event, ...)
	--self.Counter[event] = (self.Counter[event] or 0) + 1
	--BattleGroundEnemies:Debug("Enemies OnEvent", event, ...)
	self[event](self, ...)
end)


BattleGroundEnemies.Allies = CreateFrame("Frame", nil, BattleGroundEnemies) --index = name, value = table
BattleGroundEnemies.Allies.Counter = {}
BattleGroundEnemies.Allies.GUIDToAllyname = {}


BattleGroundEnemies.Allies:Hide()
BattleGroundEnemies.Allies:SetScript("OnEvent", function(self, event, ...)
	--self.Counter[event] = (self.Counter[event] or 0) + 1

	--BattleGroundEnemies:Debug("Allies OnEvent", event, ...)
	self[event](self, ...)
end)








function BattleGroundEnemies.Allies:GroupInSpecT_Update(event, GUID, unitID, info)
	if not GUID or not info.class then return end

	specCache[GUID] = info.spec_name_localized

	BattleGroundEnemies:GROUP_ROSTER_UPDATE()
end




BattleGroundEnemies:RegisterEvent("PLAYER_LOGIN") --Fired on reload UI and on initial loading screen

BattleGroundEnemies.GeneralEvents = {
	"UPDATE_BATTLEFIELD_SCORE", --stopping the onupdate script should do it but other addons make "UPDATE_BATTLEFIELD_SCORE" trigger aswell
	"COMBAT_LOG_EVENT_UNFILTERED",
	"UPDATE_MOUSEOVER_UNIT",
	"PLAYER_TARGET_CHANGED",
	"PLAYER_FOCUS_CHANGED",
	"ARENA_OPPONENT_UPDATE", --fires when a arena enemy appears and a frame is ready to be shown
	"ARENA_CROWD_CONTROL_SPELL_UPDATE", --fires when data requested by C_PvP.RequestCrowdControlSpell(unitID) is available
	"ARENA_COOLDOWNS_UPDATE", --fires when a arenaX enemy used a trinket or racial to break cc, C_PvP.GetArenaCrowdControlInfo(unitID) shoudl be called afterwards to get used CCs
	"RAID_TARGET_UPDATE",
	"UNIT_TARGET",
	"PLAYER_ALIVE",
	"PLAYER_UNGHOST",
	"UNIT_AURA",
	"UNIT_HEALTH",
	"UNIT_MAXHEALTH",
	"UNIT_POWER_FREQUENT",
	"PLAYER_REGEN_ENABLED"
}

BattleGroundEnemies.RetailEvents = {
	"UNIT_HEAL_PREDICTION",
	"UNIT_ABSORB_AMOUNT_CHANGED",
	"UNIT_HEAL_ABSORB_AMOUNT_CHANGED"
}

BattleGroundEnemies.ClassicEvents = {
	"UNIT_HEALTH_FREQUENT",
}

BattleGroundEnemies.WrathEvents = {
	"UNIT_HEALTH_FREQUENT"
}


function BattleGroundEnemies:RegisterEvents()
	for i = 1, #self.GeneralEvents do
		self:RegisterEvent(self.GeneralEvents[i])
	end
	if IsClassic then
		for i = 1, #self.ClassicEvents do
			self:RegisterEvent(self.ClassicEvents[i])
		end
	end
	if IsWrath then
		for i = 1, #self.WrathEvents do
			self:RegisterEvent(self.WrathEvents[i])
		end
	end
	if IsRetail then
		for i = 1, #self.RetailEvents do
			self:RegisterEvent(self.RetailEvents[i])
		end
	end
end

function BattleGroundEnemies:UnregisterEvents()
	for i = 1, #self.GeneralEvents do
		self:UnregisterEvent(self.GeneralEvents[i])
	end
	if IsClassic then
		for i = 1, #self.ClassicEvents do
			self:UnregisterEvent(self.ClassicEvents[i])
		end
	end
	if IsWrath then
		for i = 1, #self.WrathEvents do
			self:UnregisterEvent(self.WrathEvents[i])
		end
	end
	if IsRetail then
		for i = 1, #self.RetailEvents do
			self:UnregisterEvent(self.RetailEvents[i])
		end
	end
end

do
	local TimeSinceLastOnUpdate = 0
	local UpdatePeroid = 0.1 --update every 0.1 seconds
	function BattleGroundEnemies.Enemies:RealPlayersOnUpdate(elapsed)
		TimeSinceLastOnUpdate = TimeSinceLastOnUpdate + elapsed
		if TimeSinceLastOnUpdate > UpdatePeroid then
			if BattleGroundEnemies.PlayerIsAlive then
				for playerName, enemyButton in pairs(self.Players) do
					enemyButton:UpdateAll()
				end
			end
			TimeSinceLastOnUpdate = 0
		end
	end
end

do
	local TimeSinceLastOnUpdate = 0
	local UpdatePeroid = 0.1 --update every 0.1 seconds
	local inRange, checkedRange = 0, 0
	function BattleGroundEnemies.Allies:RealPlayersOnUpdate(elapsed)
		--BattleGroundEnemies:Debug("läuft")
		TimeSinceLastOnUpdate = TimeSinceLastOnUpdate + elapsed
		if TimeSinceLastOnUpdate > UpdatePeroid then
			if BattleGroundEnemies.PlayerIsAlive then
				for name, allyButton in pairs(self.Players) do
					if allyButton ~= PlayerButton then
					--BattleGroundEnemies:Debug(IsItemInRange(self.config.RangeIndicator_Range, allyButton.unitID), self.config.RangeIndicator_Range, allyButton.unitID)
						--allyButton:UpdateRange(IsItemInRange(self.config.RangeIndicator_Range, allyButton.unitID))
						inRange, checkedRange = UnitInRange(allyButton.unitID)
						allyButton:UpdateRange(inRange)
					else
						allyButton:UpdateRange(true)
					end
				end
			end
			TimeSinceLastOnUpdate = 0
		end
	end
end




-- if lets say raid1 leaves all remaining players get shifted up, so raid2 is the new raid1, raid 3 gets raid2 etc.



local function EnableShadowColor(fontString, enableShadow, shadowColor)
	if shadowColor then fontString:SetShadowColor(unpack(shadowColor)) end
	if enableShadow then
		fontString:SetShadowOffset(1, -1)
	else
		fontString:SetShadowOffset(0, 0)
	end
end

function BattleGroundEnemies.CropImage(texture, width, height, hasTexcoords)
	local left, right, top, bottom = 0.075, 0.925, 0.075, 0.925
	local ratio = height / width
	if ratio > 1 then --crop the sides
		ratio = 1/ratio
		texture:SetTexCoord( (left) + ((1- ratio) / 2), right - ((1- ratio) / 2), top, bottom)
	elseif ratio == 1 then
		texture:SetTexCoord(left, right, top, bottom)
	else
		-- crop the height
		texture:SetTexCoord(left, right, top + ((1- ratio) / 2), bottom - ( (1- ratio) / 2))
	end
end

local function ApplyFontStringSettings(fs, settings)
	fs:SetFont(LSM:Fetch("font", BattleGroundEnemies.db.profile.Font), settings.FontSize, settings.FontOutline)


	--idk why, but without this the SetJustifyH and SetJustifyV dont seem to work sometimes even tho GetJustifyH returns the new, correct value
	fs:GetRect()
	fs:GetStringHeight()
	fs:GetStringWidth()

	if settings.JustifyH then
		fs:SetJustifyH(settings.JustifyH)
	end

	if settings.JustifyV then
		fs:SetJustifyV(settings.JustifyV)
	end

	if settings.WordWrap ~= nil then
		fs:SetWordWrap(settings.WordWrap)
	end

	if settings.FontColor then
		fs:SetTextColor(unpack(settings.FontColor))
	end

	fs:EnableShadowColor(settings.EnableShadow, settings.ShadowColor)
end

local function ApplyCooldownSettings(self, config, cdReverse, setDrawSwipe, swipeColor)
	self:SetReverse(cdReverse)
	self:SetDrawSwipe(setDrawSwipe)
	if swipeColor then self:SetSwipeColor(unpack(swipeColor)) end
	self:SetHideCountdownNumbers(not config.ShowNumber)
	if self.Text then
		self.Text:ApplyFontStringSettings(config)
	end
end



function BattleGroundEnemies.MyCreateFontString(parent)
	local fontString = parent:CreateFontString(nil, "OVERLAY")
	fontString.ApplyFontStringSettings = ApplyFontStringSettings
	fontString.EnableShadowColor = EnableShadowColor
	fontString:SetDrawLayer('OVERLAY', 2)
	return fontString
end

function BattleGroundEnemies.GrabFontString(frame)
	for _, region in pairs{frame:GetRegions()} do
		if region:GetObjectType() == "FontString" then
			return region
		end
	end
end

function BattleGroundEnemies.AttachCooldownSettings(cooldown)
	cooldown.ApplyCooldownSettings = ApplyCooldownSettings
	-- Find fontstring of the cooldown
	local fontstring = BattleGroundEnemies.GrabFontString(cooldown)
	if fontstring then
		cooldown.Text = fontstring
		cooldown.Text.ApplyFontStringSettings = ApplyFontStringSettings
		cooldown.Text.EnableShadowColor = EnableShadowColor
	end
end



function BattleGroundEnemies.MyCreateCooldown(parent)
	local cooldown = CreateFrame("Cooldown", nil, parent)
	cooldown:SetAllPoints()
	cooldown:SetSwipeTexture('Interface/Buttons/WHITE8X8')

	BattleGroundEnemies.AttachCooldownSettings(cooldown)

	return cooldown
end

function BattleGroundEnemies:Disable()
	self.enabled = false
	--BattleGroundEnemies:LogToSavedVariables("BattleGroundEnemies disabled")
	self:UnregisterEvents()
	self:Hide()
	RequestFrame:Hide()
	FakePlayersOnUpdateFrame:Hide()
	self.Allies:Disable()
	self.Enemies:Disable()
end

function BattleGroundEnemies:Enable()
	self.enabled = true
	--BattleGroundEnemies:LogToSavedVariables("BattleGroundEnemies enabled")

	self:RegisterEvents()
	if self.Testmode.Active then
		RequestFrame:Hide()
		FakePlayersOnUpdateFrame:Show()
	else
		RequestFrame:Show()
		FakePlayersOnUpdateFrame:Hide()
	end
	self:Show()
	self.Allies:CheckEnableState()
	self.Enemies:CheckEnableState()
end

function BattleGroundEnemies:BGSizeChanged(newBGSize)
	--BattleGroundEnemies:LogToSavedVariables("BGSizeChanged", newBGSize)
	self.BGSize = newBGSize
	--self:Debug(newBGSize)
	self.Allies:ApplyBGSizeSettings()
	self.Enemies:ApplyBGSizeSettings()
end

function BattleGroundEnemies:UpdateBGSize()
	local MaxNumPlayers = math_max(self.Allies.NumShownPlayers, self.Enemies.NumShownPlayers)
	--BattleGroundEnemies:LogToSavedVariables("UpdateBGSize", MaxNumPlayers)
	if MaxNumPlayers then
		if MaxNumPlayers > 15 then
			if not self.BGSize or self.BGSize ~= 40 then
				self:BGSizeChanged(40)
			end
		else
			if MaxNumPlayers <= 5 then
				if not self.BGSize or self.BGSize ~= 5 then --arena
					self:BGSizeChanged(5)
				end
			else
				if not self.BGSize or self.BGSize ~= 15 then
					self:BGSizeChanged(15)
				end
			end
		end
	end
end



do


	local function PVPMatchScoreboard_OnHide()
		if PVPMatchScoreboard.selectedTab ~= 1 then
			-- user was looking at another tab than all players
			SetBattlefieldScoreFaction() -- request a UPDATE_BATTLEFIELD_SCORE
		end
	end




	--Triggered immediately before PLAYER_ENTERING_WORLD on login and UI Reload, but NOT when entering/leaving instances.
	function BattleGroundEnemies:PLAYER_LOGIN()
		self.PlayerDetails = {
			PlayerName = UnitName("player"),
			PlayerClass = select(2, UnitClass("player")),
			isGroupLeader = UnitIsGroupLeader("player"),
			isGroupAssistant = UnitIsGroupAssistant("player"),
			unit = "player",
			GUID = UnitGUID("player")
		}


		self.db = LibStub("AceDB-3.0"):New("BattleGroundEnemiesDB", Data.defaultSettings, true)

		self.db.RegisterCallback(self, "OnProfileChanged", "ProfileChanged")
		self.db.RegisterCallback(self, "OnProfileCopied", "ProfileChanged")
		self.db.RegisterCallback(self, "OnProfileReset", "ProfileChanged")

		if self.db.profile then
			if not self.db.profile.Debug then
				self.db.profile.log = nil
			end
		end


		LibChangelog:Register(AddonName, Data.changelog, self.db.profile, "lastReadVersion", "onlyShowWhenNewVersion")

		LibChangelog:ShowChangelog(AddonName)


		PopulateMainframe(PlayerTypes.Allies)
		PopulateMainframe(PlayerTypes.Enemies)

		if LGIST then -- the libary doesnt work in TBCC, IsTBCC
			LGIST.RegisterCallback(BattleGroundEnemies.Allies, "GroupInSpecT_Update")
		end

		self:RegisterEvent("GROUP_ROSTER_UPDATE")
		self:RegisterEvent("PLAYER_ENTERING_WORLD") -- fired on reload UI and on every loading screen (for switching zones, intances etc)
		self:RegisterEvent("PARTY_LEADER_CHANGED")

		self:SetupOptions()

		AceConfigDialog:SetDefaultSize("BattleGroundEnemies", 709, 532)

		AceConfigDialog:AddToBlizOptions("BattleGroundEnemies", "BattleGroundEnemies")

		if PVPMatchScoreboard then -- for TBCC, IsTBCC
			PVPMatchScoreboard:HookScript("OnHide", PVPMatchScoreboard_OnHide)
		end

		--DBObjectLib:ResetProfile(noChildren, noCallbacks)


		self:GROUP_ROSTER_UPDATE()  --Scan again, the user could have reloaded the UI so GROUP_ROSTER_UPDATE didnt fire

		self:UnregisterEvent("PLAYER_LOGIN")
	end
end

function BattleGroundEnemies.Enemies:ChangeName(oldName, newName)  --only used in arena when players switch from "arenaX" to a real name
	local playerButton = self.Players[oldName]

	if playerButton then
		playerButton.PlayerDetails.PlayerName = newName
		-- BattleGroundEnemies:LogToSavedVariables("name changed", oldName, newName)
		playerButton:PlayerDetailsChanged()

		self.Players[newName] = playerButton
		self.Players[oldName] = nil
	end
end

function BattleGroundEnemies.Enemies:CreateArenaEnemies()
	-- BattleGroundEnemies:LogToSavedVariables("CreateArenaEnemies")
	if not IsInArena then return end

	self:BeforePlayerSourceUpdate(PlayerSources.ArenaPlayers)
	for i = 1, 15 do --we can have 15 enemies in the Arena Brawl Packed House
		local unitID = "arena"..i


		local _, classTag, specName
		if GetArenaOpponentSpec and GetSpecializationInfoByID then --HasSpeccs
			local specID, gender = GetArenaOpponentSpec(i)

			if (specID and specID > 0) then
				_, specName, _, _, _, classTag, _ = GetSpecializationInfoByID(specID, gender)
			end
		else
			classTag = select(2, UnitClass(unitID))
		end
		--BattleGroundEnemies:LogToSavedVariables("classTag", classTag)
		--BattleGroundEnemies:LogToSavedVariables("specName", specName)


		if classTag then
			local playerName
			local name = GetUnitName(unitID, true)
			if name and name ~= UNKNOWN then
				-- player has a real name, check if he is already shown as arenaX
				self:ChangeName(unitID, name)
				playerName = name
			end

			local raceName = UnitRace(unitID)
			self:AddPlayerToSource(PlayerSources.ArenaPlayers, {
				name = playerName,
				raceName = raceName,
				classTag = classTag,
				specName = specName,
				additionalData = {PlayerArenaUnitID = unitID}
			})
		end
	end

	self:AfterPlayerSourceUpdate()

	for playerName, playerButton in pairs(self.Players) do
		local playerDetails = playerButton.PlayerDetails
		if playerDetails.PlayerArenaUnitID then
			playerButton:UpdateAll(playerDetails.PlayerArenaUnitID)
		end
	end
end



--Notes about UnitIDs
--priority of unitIDs:
--1. Arena, detected by UNIT_HEALTH (health upate), ARENA_OPPONENT_UPDATE (this units exist, don't exist anymore), we need to check for UnitExists() since there is a small time frame after the objective isn't on that target anymore where UnitExists returns false for that unitID
--2. nameplates, detected by UNIT_HEALTH, NAME_PLATE_UNIT_ADDED, NAME_PLATE_UNIT_REMOVED
--3. player's target
--4. player's focus
--5. ally targets, UNIT_TARGET fires if the target changes, we need to check for UnitExists() since there is a small time frame after an ally lost that enemy where UnitExists returns false for that unitID



function BattleGroundEnemies:NotifyChange()
	AceConfigRegistry:NotifyChange("BattleGroundEnemies")
	self:ProfileChanged()
end

function BattleGroundEnemies:ProfileChanged()
	self:SetupOptions()
	self:ApplyAllSettings()
end


local timer = nil
function BattleGroundEnemies:ApplyAllSettings()
	if timer then timer:Cancel() end -- use a timer to apply changes after 0.2 second, this prevents the UI from getting laggy when the user uses a slider option
	timer = CTimerNewTicker(0.2, function()
		BattleGroundEnemies.Enemies:ApplyAllSettings()
		BattleGroundEnemies.Allies:ApplyAllSettings()
		timer = nil
	end, 1)
end

BattleGroundEnemies.DebugText = BattleGroundEnemies.DebugText or ""


local function stringifyMultitArgs(...)
	local args = {...}
	local text = ""

	for i = 1, #args do
		text = text.. " ".. tostring(args[i])
	end
	return text
end

local function getTimestamp()
	local timestampFormat = "[%I:%M:%S] " --timestamp format
	local stamp = BetterDate(timestampFormat, time())
	return stamp
end

function BattleGroundEnemies:Debug(...)
	if not self.db then return end
	if not self.db.profile then return end
	if not self.db.profile.Debug then return end

	if not self.debugFrame then
		self.debugFrame = CreatedebugFrame()
	end

	local text = stringifyMultitArgs(getTimestamp(), ...)

	self.debugFrame:AddMessage(text)
end

function BattleGroundEnemies:LogTablesToSavedVariables(...)
	local tables = {...}
	table.insert(self.db.profile.log, {timestamp = getTimestamp(), data = tables})
end

function BattleGroundEnemies:LogToSavedVariables(...)
	if not self.db then return end
	if not self.db.profile then return end
	if not self.db.profile.Debug then return end
	self.db.profile.log = self.db.profile.log or {}

	local text = stringifyMultitArgs(...)
	self:OnetimeInformation(text)
	text = stringifyMultitArgs(getTimestamp(), text)

	table_insert(self.db.profile.log, text)
end

local sentMessages = {}
function BattleGroundEnemies:OnetimeInformation(...)
	local message = table.concat({...}, ", ")
	if sentMessages[message] then return end
	print("|cff0099ffBattleGroundEnemies:|r", message)
	sentMessages[message] = true
end

function BattleGroundEnemies:Information(...)
	print("|cff0099ffBattleGroundEnemies:|r", ...)
end

BattleGroundEnemies.Enemies.ARENA_PREP_OPPONENT_SPECIALIZATIONS = BattleGroundEnemies.Enemies.CreateArenaEnemies -- for Prepframe, not available in TBC

function BattleGroundEnemies.Enemies:UNIT_NAME_UPDATE(unitID)
	--BattleGroundEnemies:LogToSavedVariables("UNIT_NAME_UPDATE", unitID)
	BattleGroundEnemies:ThrottleUpdateArenaPlayers()
end


function BattleGroundEnemies.Enemies:NAME_PLATE_UNIT_ADDED(unitID)
	local enemyButton = self:GetPlayerbuttonByUnitID(unitID)
	if enemyButton then
		enemyButton:UpdateEnemyUnitID("Nameplate", unitID)
	end
end

function BattleGroundEnemies.Enemies:NAME_PLATE_UNIT_REMOVED(unitID)
	--self:Debug(unitID)
	local enemyButton = self:GetPlayerbuttonByUnitID(unitID)
	if enemyButton then
		enemyButton:UpdateEnemyUnitID("Nameplate", false)
	end
end


--fires when a arena enemy appears and a frame is ready to be shown
function BattleGroundEnemies:ARENA_OPPONENT_UPDATE(unitID, unitEvent)
	--BattleGroundEnemies:LogToSavedVariables("ARENA_OPPONENT_UPDATE", unitID, unitEvent, UnitName(unitID))
	--unitEvent can be: "seen", "unseen", "destroyed", "cleared"
	--self:Debug("ARENA_OPPONENT_UPDATE", unitID, unitEvent, UnitName(unitID))

	if unitEvent == "cleared" then --"unseen", "cleared" or "destroyed"
		local playerButton = self.ArenaIDToPlayerButton[unitID]
		if playerButton then
			--BattleGroundEnemies:Debug("ARENA_OPPONENT_UPDATE", playerButton.DisplayedName, "ObjectiveLost")

			self.ArenaIDToPlayerButton[unitID] = nil
			playerButton.ObjectiveAndRespawn:Reset()

			if playerButton.PlayerIsEnemy then -- then this button is an enemy button
				playerButton:UpdateEnemyUnitID("Arena", false)
			end
			playerButton:DispatchEvent("ArenaOpponentHidden")
		end
	end
	self:ThrottleUpdateArenaPlayers()
end

function BattleGroundEnemies:GetPlayerbuttonByUnitID(unitID)
	local uName = GetUnitName(unitID, true)
	return self.Enemies.Players[uName] or self.Allies.Players[uName]
end

function BattleGroundEnemies:GetPlayerbuttonByName(name)
	return self.Enemies.Players[name] or self.Allies.Players[name]
end

local CombatLogevents = {}
BattleGroundEnemies.CombatLogevents = CombatLogevents

--[[ function CombatLogevents.SPELL_AURA_APPLIED(self, srcName, destName, spellId, spellName, auraType, amount)
	local playerButton = self:GetPlayerbuttonByName(destName)
	if playerButton and playerButton.isShown then
		playerButton:AuraApplied(spellId, spellName, srcName, auraType, amount)
	end
end ]]

-- fires when the stack of a aura increases
--[[ function CombatLogevents.SPELL_AURA_APPLIED_DOSE(self, srcName, destName, spellId, spellName, auraType, amount)
	local playerButton = self:GetPlayerbuttonByName(destName)
	if playerButton and playerButton.isShown then
		playerButton:AuraApplied(spellId, spellName, srcName, auraType, amount)
	end
end ]]
-- fires when the stack of a aura decreases
--[[ function CombatLogevents.SPELL_AURA_REMOVED_DOSE(self, srcName, destName, spellId, spellName, auraType, amount)
	local playerButton = self:GetPlayerbuttonByName(destName)
	if playerButton and playerButton.isShown then
		playerButton:AuraApplied(spellId, spellName, srcName, auraType, amount)
	end
end ]]


function CombatLogevents.SPELL_AURA_REFRESH(self, srcName, destName, spellId, spellName, auraType, amount)
	local playerButton = self:GetPlayerbuttonByName(destName)
	if playerButton then
		playerButton:AuraRemoved(spellId, spellName)
	end
end

function CombatLogevents.SPELL_AURA_REMOVED(self, srcName, destName, spellId, spellName, auraType)
	local playerButton = self:GetPlayerbuttonByName(destName)
	if playerButton then
		playerButton:AuraRemoved(spellId, spellName)
	end
end

--CombatLogevents.SPELL_DISPEL = CombatLogevents.SPELL_AURA_REMOVED

function CombatLogevents.SPELL_CAST_SUCCESS(self, srcName, destName, spellId)
	local playerButton = self:GetPlayerbuttonByName(srcName)
	if playerButton and playerButton.isShown then
		playerButton:DispatchEvent("SPELL_CAST_SUCCESS", srcName, destName, spellId)

		local defaultInterruptDuration = Data.Interruptdurations[spellId]
		if defaultInterruptDuration then -- check if enemy got interupted
			if playerButton.unitID then
				if UnitExists(playerButton.unitID) then
					local _,_,_,_,_,_,_, notInterruptible = UnitChannelInfo(playerButton.unitID)  --This guy was channeling something and we casted a interrupt on him
					if notInterruptible == false then --spell is interruptable
						playerButton:DispatchEvent("GotInterrupted", spellId, defaultInterruptDuration)
					end
				end
			end
		end
	end
end

function CombatLogevents.SPELL_INTERRUPT(self, _, destName, spellId, _, _)
	local playerButton = self:GetPlayerbuttonByName(destName)
	if playerButton and playerButton.isShown then
		local defaultInterruptDuration = Data.Interruptdurations[spellId]
		if defaultInterruptDuration then
			playerButton:DispatchEvent("GotInterrupted", spellId, defaultInterruptDuration)
		end
	end
end

CombatLogevents.Counter = {}
function CombatLogevents.UNIT_DIED(self, _, destName, _, _, _)
	--self:Debug("subevent", destName, "UNIT_DIED")
	local playerButton = self:GetPlayerbuttonByName(destName)
	if playerButton then
		playerButton:PlayerDied()
	end
end

function BattleGroundEnemies:UpdateEnemiesFromCombatlogScanning()
	self.Enemies.BeforePlayerSourceUpdate(PlayerSources.CombatLog)
	for guid, data in pairs(self.PlayerGUIDs) do
		if data.IsEnemy then
			--check if its still a enemy, a ally might have joined and we might have gotten a combat log event before that
			if self.Allies.Players[data.name] then
				data.IsEnemy = false
			else
				-- its still a enemy
				self.Enemies:AddPlayerToSource(PlayerSources.CombatLog, {
					name = data.name,
					raceName = data.race,
					classTag = data.classToken,
					specName =  data.spec,
				})
			end
		end
	end

	self.Enemies:AfterPlayerSourceUpdate()
end

local UpdateEnemmiesFoundByGUIDTicker = nil
function BattleGroundEnemies:COMBAT_LOG_EVENT_UNFILTERED()
	local timestamp,subevent,hide,srcGUID,srcName,srcF1,srcF2,destGUID,destName,destF1,destF2,spellId,spellName,spellSchool, auraType = CombatLogGetCurrentEventInfo()
	if self.combatlogScanningEnabled then
		if srcGUID and srcGUID ~= "" then
			if not self.SearchedGUIDs[srcGUID] then
				self.SearchedGUIDs[srcGUID] = true
				if not self.PlayerGUIDs[srcGUID] then
					-- see if its a player
					local localizedClass, englishClass, localizedRace, englishRace, sex, name, realm = GetPlayerInfoByGUID(srcGUID)

					if localizedClass then --we have a actual player
						if realm and realm ~= "" then
							name = name.."-"..realm
						end
						local ambiguatedName = Ambiguate(name, "none")
						local isEnemy = false

						local scoreInfo = C_PvP.GetScoreInfoByPlayerGuid(srcGUID)
						self.PlayerGUIDs[srcGUID] = {
							name = ambiguatedName,
							race = localizedRace,
							classToken = englishClass,
							scoreInfo = scoreInfo
						}

				--[[ 		if scoreInfo and type(scoreInfo) =="table" then
							if scoreInfo.faction ~= myBGFaction then
								isEnemy = true
								self.PlayerGUIDs[srcGUID].spec = scoreInfo.talentSpec
							end
						else
							if not self.Allies[ambiguatedName] then
								isEnemy = true
							end
						end ]]
						if not self.Allies.Players[ambiguatedName] then
							self.PlayerGUIDs[srcGUID].IsEnemy = true
							if UpdateEnemmiesFoundByGUIDTicker then UpdateEnemmiesFoundByGUIDTicker:Cancel() end -- use a timer to apply changes after 1 second, this prevents from too many updates after each player is found

							UpdateEnemmiesFoundByGUIDTicker = CTimerNewTicker(1, function()
								BattleGroundEnemies:UpdateEnemiesFromCombatlogScanning()
								UpdateEnemmiesFoundByGUIDTicker = nil
							end, 1)
						end
					end
				end
			end
		end
	end
	--self:Debug(timestamp,subevent,hide,srcGUID,srcName,srcF1,srcF2,destGUID,destName,destF1,destF2,spellId,spellName,spellSchool, auraType)
	local covenantID = Data.CovenantSpells[spellId]
	if covenantID then
		local playerButton = self:GetPlayerbuttonByName(srcName)
		if playerButton then
			-- this player used a covenant ability show an icon for that
			playerButton.Covenant:UpdateCovenant(covenantID)
		end
	end
	if CombatLogevents[subevent] then
		-- IsClassic: spellId is always 0, so we have to work with the spellname :( but at least UnitAura() shows spellIDs
		--CombatLogevents.Counter[subevent] = (CombatLogevents.Counter[subevent] or 0) + 1
		return CombatLogevents[subevent](self, srcName, destName, spellId, spellName, auraType)
	end
end

local function IamTargetcaller()
	return (BattleGroundEnemies.PlayerDetails.isGroupLeader and #BattleGroundEnemies.Allies.assistants == 0) or (not BattleGroundEnemies.PlayerDetails.isGroupLeader and BattleGroundEnemies.PlayerDetails.isGroupAssistant)
end

do
	local oldTarget
	function BattleGroundEnemies:PLAYER_TARGET_CHANGED()
		local playerButton = self:GetPlayerbuttonByUnitID("target")
		--BattleGroundEnemies:LogToSavedVariables("playerButton target", playerButton, GetUnitName("target", true))
		if oldTarget then
			if oldTarget.PlayerIsEnemy then
				oldTarget:UpdateEnemyUnitID("Target", false)
			end
			if PlayerButton then
				PlayerButton:IsNoLongerTarging(oldTarget)
			end
			oldTarget.MyTarget:Hide()
		end

		if playerButton then --i target an existing player
			if PlayerButton then
				if playerButton.PlayerIsEnemy then
					playerButton:UpdateEnemyUnitID("Target", "target")
				end
				PlayerButton:IsNowTargeting(playerButton)
			end
			playerButton.MyTarget:Show()
			oldTarget = playerButton


			if BattleGroundEnemies.IsRatedBG and self.db.profile.RBG.TargetCalling_SetMark and IamTargetcaller() then  -- i am the target caller
				SetRaidTarget("target", 8)
			end
		else
			oldTarget = false
		end
	end
end

do
	local oldFocus
	function BattleGroundEnemies:PLAYER_FOCUS_CHANGED()
		local playerButton = self:GetPlayerbuttonByUnitID("focus")
		--BattleGroundEnemies:LogToSavedVariables("playerButton focus", playerButton, GetUnitName("focus", true))
		if oldFocus then
			if oldFocus.PlayerIsEnemy then
				oldFocus:UpdateEnemyUnitID("Focus", false)
			end
			oldFocus.MyFocus:Hide()
		end
		if playerButton then
			if playerButton.PlayerIsEnemy then
				playerButton:UpdateEnemyUnitID("Focus", "focus")
			end
			playerButton.MyFocus:Show()
			oldFocus = playerButton
		else
			oldFocus = false
		end
	end
end


function BattleGroundEnemies:UPDATE_MOUSEOVER_UNIT()
	local enemyButton = self.Enemies:GetPlayerbuttonByUnitID("mouseover")
	if enemyButton then --unit is a shown enemy
		enemyButton:UpdateAll("mouseover")
	end
end




-- function BattleGroundEnemies:LOSS_OF_CONTROL_ADDED()
	-- local numEvents = C_LossOfControl.GetNumEvents()
	-- for i = 1, numEvents do
		-- local locType, spellId, text, iconTexture, startTime, timeRemaining, duration, lockoutSchool, priority, displayType = C_LossOfControl.GetEventInfo(i)
		-- --self:Debug(C_LossOfControl.GetEventInfo(i))
		-- if not self.LOSS_OF_CONTROL then self.LOSS_OF_CONTROL = {} end
		-- self.LOSS_OF_CONTROL[spellId] = locType
	-- end
-- end


--fires when data requested by C_PvP.RequestCrowdControlSpell(unitID) is available
function BattleGroundEnemies:ARENA_CROWD_CONTROL_SPELL_UPDATE(unitID, ...)
	local playerButton = self:GetPlayerbuttonByUnitID(unitID)
	if not playerButton then playerButton = self:GetPlayerbuttonByName(unitID) end -- the event fires before the name is set on the frame, so at this point the name is still the unitID
	if playerButton then
		local spellId, itemID = ... --itemID only exists in classic, tbc, wrath isClassic, isTBCC, IsWrath
		playerButton.Trinket:DisplayTrinket(spellId, itemID)
	end

	--if spellId ~= 72757 then --cogwheel (30 sec cooldown trigger by racial)
	--end
end



--fires when a arenaX enemy used a trinket or racial to break cc, C_PvP.GetArenaCrowdControlInfo(unitID) shoudl be called afterwards to get used CCs
--this event is kinda stupid, it doesn't say which unit used which cooldown, it justs says that somebody used some sort of trinket
function BattleGroundEnemies:ARENA_COOLDOWNS_UPDATE(unitID)
	if unitID then
		local playerButton = self:GetPlayerbuttonByUnitID(unitID)
		if playerButton then
			playerButton:UpdateCrowdControl(unitID)
		end
	else --for backwards compability, i am not sure if unitID was always given by ARENA_COOLDOWNS_UPDATE
		for i = 1, 5 do
			unitID = "arena"..i
			local playerButton = self:GetPlayerbuttonByUnitID(unitID)
			if playerButton then
				playerButton:UpdateCrowdControl(unitID)
			end
		end
	end
end

function BattleGroundEnemies:RAID_TARGET_UPDATE()
	for name, playerButton in pairs(self.Allies.Players) do
		playerButton:UpdateRaidTargetIcon()
	end
	for name, playerButton in pairs(self.Enemies.Players) do
		playerButton:UpdateRaidTargetIcon()
	end
end


function BattleGroundEnemies:UNIT_AURA(unitID, isFullUpdate, updatedAuraInfos)
	local playerButton = self:GetPlayerbuttonByUnitID(unitID)
	if playerButton then
		playerButton:UNIT_AURA(unitID, isFullUpdate, updatedAuraInfos)
	end
end

function BattleGroundEnemies:UNIT_HEALTH(unitID) --gets health of nameplates, player, target, focus, raid1 to raid40, partymember
	local playerButton = self:GetPlayerbuttonByUnitID(unitID)
	if playerButton then --unit is a shown player
		playerButton:UNIT_HEALTH(unitID)
	end
end

BattleGroundEnemies.UNIT_HEALTH_FREQUENT = BattleGroundEnemies.UNIT_HEALTH --used to be used only in tbc, now its only used in classic and wrath
BattleGroundEnemies.UNIT_MAXHEALTH = BattleGroundEnemies.UNIT_HEALTH
BattleGroundEnemies.UNIT_HEAL_PREDICTION = BattleGroundEnemies.UNIT_HEALTH
BattleGroundEnemies.UNIT_ABSORB_AMOUNT_CHANGED = BattleGroundEnemies.UNIT_HEALTH
BattleGroundEnemies.UNIT_HEAL_ABSORB_AMOUNT_CHANGED = BattleGroundEnemies.UNIT_HEALTH


function BattleGroundEnemies:UNIT_POWER_FREQUENT(unitID, powerToken) --gets power of nameplates, player, target, focus, raid1 to raid40, partymember
	local playerButton = self:GetPlayerbuttonByUnitID(unitID)
	if playerButton then --unit is a shown enemy
		playerButton:UNIT_POWER_FREQUENT(unitID, powerToken)
	end
end





BattleGroundEnemies.PendingUpdates = {}
function BattleGroundEnemies:QueueForUpdateAfterCombat(tbl, funcName)

	--dont add the same function twice
	for i = 1, #BattleGroundEnemies.PendingUpdates do
		local pendingUpdate = BattleGroundEnemies.PendingUpdates[i]
		if pendingUpdate.tbl == tbl and pendingUpdate.funcName == funcName then return end
	end

	table.insert(self.PendingUpdates, {tbl = tbl, funcName = funcName})
end

function BattleGroundEnemies:PLAYER_REGEN_ENABLED()

	--Check if there are any outstanding updates that have been hold back due to being in combat
	for i = 1, #self.PendingUpdates do
		local tbl = self.PendingUpdates[i].tbl
		local funcName = self.PendingUpdates[i].funcName
		tbl[funcName](tbl)
	end
	wipe(self.PendingUpdates)
end

function BattleGroundEnemies:PlayerAlive()
	--recheck the targets of groupmembers
	for allyName, allyButton in pairs(self.Allies.Players) do
		allyButton:UpdateTarget()
	end
	self.PlayerIsAlive = true
end

function BattleGroundEnemies:PLAYER_ALIVE()
	if UnitIsGhost("player") then --Releases his ghost to a graveyard.
		self.PlayerIsAlive = false
	else --alive (revived while not being a ghost)
		self:PlayerAlive()
	end
end

function BattleGroundEnemies:UNIT_TARGET(unitID)

	local playerButton = self:GetPlayerbuttonByUnitID(unitID)


	if playerButton and playerButton ~= PlayerButton then --we use Player_target_changed for the player
		--self:LogToSavedVariables("UNIT_TARGET", unitID, playerButton.PlayerDetails.PlayerName)
		playerButton:UpdateTarget()
	end
end

local function disableArenaFrames()
	if ArenaEnemyFrames then
		if ArenaEnemyFrames_Disable then
			ArenaEnemyFrames_Disable(ArenaEnemyFrames)
		end
	elseif ArenaEnemyMatchFramesContainer then
		if ArenaEnemyMatchFramesContainer.Disable then ArenaEnemyMatchFramesContainer:Disable() end
	end
end

local function checkEffectiveEnableStateForArenaFrames()
	if ArenaEnemyFrames then
		if ArenaEnemyFrames_CheckEffectiveEnableState then
			ArenaEnemyFrames_CheckEffectiveEnableState(ArenaEnemyFrames)
		end
	elseif ArenaEnemyMatchFramesContainer then
		if ArenaEnemyMatchFramesContainer.CheckEffectiveEnableState then ArenaEnemyMatchFramesContainer:CheckEffectiveEnableState() end
	end
end

function BattleGroundEnemies:ResetCombatLogScanninningTables()
	self.SearchedGUIDs = {}
	self.PlayerGUIDs = {}
end

function BattleGroundEnemies:EnableFallbackToCombatlogScanning()
	if not self.combatlogScanningEnabled then
		self:Information(L.CombatLogScanningForEnemiesEnabled)
		self:ResetCombatLogScanninningTables()
	end
	self.combatlogScanningEnabled = true
end

function BattleGroundEnemies:DisableFallbackToCombatlogScanning()
	if self.combatlogScanningEnabled then
		self:Information(L.CombatLogScanningForEnemiesDisabled)
		self:ResetCombatLogScanninningTables()
	end
	self.combatlogScanningEnabled = false
end

function BattleGroundEnemies:ToggleArenaFrames()
	if InCombatLockdown() then
		return self:QueueForUpdateAfterCombat(self, "ToggleArenaFrames")
	end

	if IsInArena and self.db.profile.DisableArenaFramesInArena then
		return disableArenaFrames()
	elseif IsInBattleground and self.db.profile.DisableArenaFramesInBattleground then
		return disableArenaFrames()
	end
	checkEffectiveEnableStateForArenaFrames()
end

local UpdateArenaPlayersTicker


--too avoid calling UpdateArenaPlayers too many times within a second
function BattleGroundEnemies:ThrottleUpdateArenaPlayers()
	if UpdateArenaPlayersTicker then UpdateArenaPlayersTicker:Cancel() end -- use a timer to apply changes after 1 second, this prevents from too many updates after each player is found

	UpdateArenaPlayersTicker = CTimerNewTicker(0.5, function()
		BattleGroundEnemies:UpdateArenaPlayers()
		UpdateArenaPlayersTicker = nil
	end, 1)
end

function BattleGroundEnemies:UpdateArenaPlayers()
	-- BattleGroundEnemies:LogToSavedVariables("UpdateArenaPlayers")
	self.Enemies:CreateArenaEnemies()

	if #BattleGroundEnemies.Enemies.CurrentPlayerOrder > 1 or #BattleGroundEnemies.Allies.CurrentPlayerOrder > 1 then --this ensures that we checked for enemies and the flag carrier will be shown (if its an enemy)
		for i = 1,  GetNumArenaOpponents() do
			local unitID = "arena"..i
			--BattleGroundEnemies:Debug(UnitName(unitID))
			local playerButton = BattleGroundEnemies:GetPlayerbuttonByUnitID(unitID)
			if playerButton then
				--BattleGroundEnemies:Debug("Button exists")
				playerButton:ArenaOpponentShown(unitID)
			end
		end
	else
		C_Timer.After(2, function() self:UpdateArenaPlayers() end)
	end
end

function BattleGroundEnemies:CheckForArenaEnemies()
	--BattleGroundEnemies:LogToSavedVariables("CheckForArenaEnemies")

	-- returns valid data on PLAYER_ENTERING_WORLD
	--self:Debug(numArenaOpponents)
	if GetNumArenaOpponents() == 0 then
		C_Timer.After(2, function() self:ThrottleUpdateArenaPlayers() end)
	else
		self:ThrottleUpdateArenaPlayers()
	end
end


BattleGroundEnemies.PLAYER_UNGHOST = BattleGroundEnemies.PlayerAlive --player is alive again


function BattleGroundEnemies:UpdateMapID()
	--	SetMapToCurrentZone() apparently removed in 8.0
	local mapID = GetBestMapForUnit('player')
	if mapID and mapID ~= -1 and mapID ~= 0 then-- when this values occur the map ID is not real
		self.BattlegroundBuff = Data.BattlegroundspezificBuffs[mapID]
		self.BattleGroundDebuffs = Data.BattlegroundspezificDebuffs[mapID]
		self.CurrentMapID = mapID
	else
		self.BattleGroundDebuffs = false
		self.BattlegroundBuff = false
		self.CurrentMapID = false
		C_Timer.After(2, function() --Delay this check, since its happening sometimes that this data is not ready yet
			self:UpdateMapID()
		end)
	end
end

local function parseBattlefieldScore(index)
	local result
	if C_PvP and C_PvP.GetScoreInfo then
		local scoreInfo = C_PvP.GetScoreInfo(index)

		--[[
		info
			PVPScoreInfo?
			Key	Type	Description
			name	string
			guid	string
			killingBlows	number
			honorableKills	number
			deaths	number
			honorGained	number
			faction	number
			raceName	string
			className	string
			classToken	string
			damageDone	number
			healingDone	number
			rating	number
			ratingChange	number
			prematchMMR	number
			mmrChange	number
			talentSpec	string
			honorLevel	number
			roleAssigned	number
			stats	PVPStatInfo[]


			PVPStatInfo
			Key	Type	Description
			pvpStatID	number
			pvpStatValue	number
			orderIndex	number
			name	string
			tooltip	string
			iconName	string

 		]]
		if not scoreInfo then return end
		if not type(scoreInfo) == "table" then return end
		result = scoreInfo
	else
		local _, name, faction, race, classTag, specName
		if HasSpeccs then
			--name, killingBlows, honorableKills, deaths, honorGained, faction, rank, race, class, classToken, damageDone, healingDone = GetBattlefieldScore(index)
			name, _, _, _, _, faction, race, _, classTag, _, _, _, _, _, _, specName = GetBattlefieldScore(index)
		else
			name, _, _, _, _, faction, _, race, _, classTag = GetBattlefieldScore(index)
		end
		result = {
			name = name,
			faction = faction,
			raceName = race,
			classToken = classTag,
			talentSpec = specName
		}
	end
	return result
end

function BattleGroundEnemies:UPDATE_BATTLEFIELD_SCORE()

	--BattleGroundEnemies:LogToSavedVariables("UPDATE_BATTLEFIELD_SCORE")
	-- self:Debug(GetCurrentMapAreaID())
	-- self:Debug("UPDATE_BATTLEFIELD_SCORE")
	-- self:Debug("GetBattlefieldArenaFaction", GetBattlefieldArenaFaction())
	-- self:Debug("C_PvP.IsInBrawl", C_PvP.IsInBrawl())
	-- self:Debug("GetCurrentMapAreaID", GetCurrentMapAreaID())
	-- self:Debug("horde players:", GetBattlefieldTeamInfo(0))
	-- self:Debug("alliance players:", GetBattlefieldTeamInfo(1))

	--self:Debug("IsRatedBG", IsRatedBG)

	local _, _, _, _, numEnemies = GetBattlefieldTeamInfo(self.EnemyFaction)
	local _, _, _, _, numAllies = GetBattlefieldTeamInfo(self.AllyFaction)

	self:Debug("numEnemies:", numEnemies)
	self:Debug("numAllies:", numAllies)

	if numEnemies then
		self.Enemies:UpdatePlayerCount(numEnemies)
	end

	if numAllies then
		self.Allies:UpdatePlayerCount(numAllies)
	end

	local battlefieldScores = {}
	local numScores = GetNumBattlefieldScores()
	for i = 1, numScores do
		local score = parseBattlefieldScore(i)
		if score then
			table.insert(battlefieldScores, score)
		end
	end

	--see if our faciton in BG changed
	for i = 1, #battlefieldScores do
		local score = battlefieldScores[i]
		local name = score.name
		local faction = score.faction

		if name == self.PlayerDetails.PlayerName and faction == self.EnemyFaction then
			self.EnemyFaction = self.AllyFaction
			self.AllyFaction = faction
		end
	end

	BattleGroundEnemies.Enemies:BeforePlayerSourceUpdate(PlayerSources.Scoreboard)
	BattleGroundEnemies.Allies:BeforePlayerSourceUpdate(PlayerSources.Scoreboard)

	for i = 1, #battlefieldScores do
		local score = battlefieldScores[i]

		local faction = score.faction
		local name = score.name
		local classToken = score.classToken

		local t
		if faction and name and classToken then
			if faction == self.EnemyFaction then
				t = BattleGroundEnemies.Enemies
			else
				t = BattleGroundEnemies.Allies
			end
			t:AddPlayerToSource(PlayerSources.Scoreboard, score)
		end
	end
	BattleGroundEnemies.Enemies:AfterPlayerSourceUpdate()
	BattleGroundEnemies.Allies:AfterPlayerSourceUpdate()
end


function BattleGroundEnemies.Allies:AddGroupMember(name, isLeader, isAssistant, classTag, unitID)
	local raceName, raceFile, raceID = UnitRace(unitID)
	local GUID = UnitGUID(unitID)

	if name and raceName and classTag then
		local specName = specCache[GUID]

		self:AddPlayerToSource(PlayerSources.GroupMembers, {
			name = name,
			raceName = raceName,
			classTag = classTag,
			specName = specName,
			additionalData = {
				isGroupLeader = isLeader,
				isGroupAssistant = isAssistant,
				GUID = GUID,
				unitID = unitID
			}
		})
	end

	self.GUIDToAllyname[GUID] = name

	if isLeader then
		self.groupLeader = name
	end
	if isAssistant then
		table_insert(self.assistants, name)
	end
end

function BattleGroundEnemies.Allies:UpdateAllUnitIDs()
		--it happens that numGroupMembers is higher than the value of the maximal players for that battleground, for example 15 in a 10 man bg, thats why we wipe AllyUnitIDToAllyDetails
	for allyName, allyButton in pairs(self.Players) do
		if allyButton then
			if allyButton.PlayerDetails.PlayerName ~= BattleGroundEnemies.PlayerDetails.PlayerName then
				local unitID = allyButton.PlayerDetails.unitID
				if not unitID then return end

				local targetUnitID = unitID.."target"
				allyButton:NewUnitID(unitID, targetUnitID)
			else
				allyButton:NewUnitID("player", "target")
				PlayerButton = allyButton
			end
		end
	end
end

function BattleGroundEnemies:GROUP_ROSTER_UPDATE()
	self.Allies:BeforePlayerSourceUpdate(PlayerSources.GroupMembers)
	self.Allies.groupLeader = nil
	self.Allies.assistants = {}

	--IsInGroup returns true when user is in a Raid and In a 5 man group

	self:RequestEverythingFromGroupmembers()

	-- GetRaidRosterInfo also works when in a party (not raid) but i am not 100% sure how the party unitID maps to the index in GetRaidRosterInfo()

	local numGroupMembers = GetNumGroupMembers()
	self.Allies:UpdatePlayerCount(numGroupMembers)

	if IsInRaid() then
		for i = 1, numGroupMembers do -- the player itself only shows up here when he is in a raid
			local name, rank, subgroup, level, localizedClass, classTag, zone, online, isDead, role, isML, combatRole = GetRaidRosterInfo(i)

			if name and name ~= self.PlayerDetails.PlayerName and rank and classTag then
				self.Allies:AddGroupMember(name, rank == 2, rank == 1, classTag, "raid"..i)
			end
		end
	else
		-- we are in a party, 5 man group
		for i = 1, numGroupMembers do
			local unitID = "party"..i
			local name = GetUnitName(unitID, true)

			local classTag = select(2, UnitClass(unitID))

			if name and classTag then
				self.Allies:AddGroupMember(name, UnitIsGroupLeader(unitID), UnitIsGroupAssistant(unitID), classTag, unitID)
			end
		end
	end

	self.PlayerDetails.isGroupLeader = UnitIsGroupLeader("player")
	self.PlayerDetails.isGroupAssistant = UnitIsGroupAssistant("player")
	self.Allies:AddGroupMember(self.PlayerDetails.PlayerName, self.PlayerDetails.isGroupLeader, self.PlayerDetails.isGroupAssistant, self.PlayerDetails.PlayerClass, "player")
	self.Allies:AfterPlayerSourceUpdate()
	self.Allies:UpdateAllUnitIDs()
end

BattleGroundEnemies.PARTY_LEADER_CHANGED = BattleGroundEnemies.GROUP_ROSTER_UPDATE




--Fires when the player logs in, /reloads the UI or zones between map instances. Basically whenever the loading screen appears.
function BattleGroundEnemies:PLAYER_ENTERING_WORLD()
	self:DisableFallbackToCombatlogScanning()
	if self.Testmode.Active then --disable testmode
		self:DisableTestMode()
	end

	self.Enemies:RemoveAllPlayersFromAllSources()
	self.Allies:RemoveAllPlayersFromSource(PlayerSources.Scoreboard)
	local _, zone = IsInInstance()
	if zone == "pvp" or zone == "arena" then
		if GetBattlefieldArenaFaction then
			local MyBgFaction = GetBattlefieldArenaFaction()  -- returns the playered faction 0 for horde, 1 for alliance, doesnt exist in TBC
			self:Debug("MyBgFaction:", MyBgFaction)
			if MyBgFaction == 0 then -- i am Horde
				self.EnemyFaction = 1 --Enemy is Alliance
				self.AllyFaction = 0
			else
				self.EnemyFaction = 0 --Enemy is Horde
				self.AllyFaction = 1
			end
		else
			self.EnemyFaction = 0 -- set a dummy value, we get data later from GetBattlefieldScore()
			self.AllyFaction = 1 -- set a dummy value, we get data later from GetBattlefieldScore()
		end

		if zone == "arena" then
			IsInArena = true
		else
			IsInBattleground = true
			if HasRBG then
				C_Timer.After(5, function() --Delay this check, since its happening sometimes that this data is not ready yet
					self.IsRatedBG = IsRatedBattleground()
					self:UPDATE_BATTLEFIELD_SCORE() --trigger the function again because since 10.0.0 UPDATE_BATTLEFIELD_SCORE doesnt fire reguralry anymore and RequestBattlefieldScore doesnt trigger the event
				end)
			end
		end

		self:Enable()

		-- self:Debug("PLAYER_ENTERING_WORLD")
		-- self:Debug("GetBattlefieldArenaFaction", GetBattlefieldArenaFaction())
		-- self:Debug("C_PvP.IsInBrawl", C_PvP.IsInBrawl())
		-- self:Debug("GetCurrentMapAreaID", GetCurrentMapAreaID())

		self.PlayerIsAlive = true
	else
		IsInArena = false
		IsInBattleground = false
		self:Disable()
	end

	self:UpdateMapID()
	self:ToggleArenaFrames()
end
