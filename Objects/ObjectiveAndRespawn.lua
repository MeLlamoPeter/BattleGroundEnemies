local BattleGroundEnemies = BattleGroundEnemies
local AddonName, Data = ...
local GetTime = GetTime
local GetSpellTexture = GetSpellTexture

local L = Data.L

local defaultSettings = {
	Enabled = true,
	Parent = "Button",
	Width = 36,
	Points = {
		{
			Point = "TOPRIGHT",
			RelativeFrame = "TargetIndicatorNumeric",
			RelativePoint = "TOPLEFT",
			OffsetX = -2
		},
		{
			Point = "BOTTOMRIGHT",
			RelativeFrame = "TargetIndicatorNumeric",
			RelativePoint = "BOTTOMLEFT",
			OffsetX = -2
		}
	},
	Cooldown = {
		ShowNumber = true,
		FontSize = 12,
		FontOutline = "OUTLINE",
		EnableShadow = false,
		ShadowColor = {0, 0, 0, 1},
	},
	Text = {
		FontSize = 17,
		FontOutline = "THICKOUTLINE",
		FontColor = {1, 1, 1, 1},
		EnableShadow = false,
		ShadowColor = {0, 0, 0, 1}
	}
}

local options = function(location)
	return {
		TextSettings = {
			type = "group",
			name = L.TextSettings,
			--desc = L.TrinketSettings_Desc,
			inline = true,
			order = 4,
			get = function(option)
				return Data.GetOption(location.Text, option)
			end,
			set = function(option, ...)
				return Data.SetOption(location.Text, option, ...)
			end,
			args = Data.AddNormalTextSettings(location.Text)
		},
		CooldownTextSettings = {
			type = "group",
			name = L.Countdowntext,
			inline = true,
			get = function(option)
				return Data.GetOption(location.Cooldown, option)
			end,
			set = function(option, ...)
				return Data.SetOption(location.Cooldown, option, ...)
			end,
			order = 2,
			args = Data.AddCooldownSettings(location.Cooldown)
		}
	}
end

local flags = {
	Height = "Fixed",
	Width = "Variable"
}

local objectiveAndRespawn = BattleGroundEnemies:NewButtonModule({
	moduleName = "ObjectiveAndRespawn",
	localizedModuleName = L.ObjectiveAndRespawn,
	flags = flags,
	defaultSettings = defaultSettings,
	options = options,
	events = {"ShouldQueryAuras", "CareAboutThisAura", "BeforeUnitAura", "UnitAura", "UnitDied", "ArenaOpponentShown", "ArenaOpponentHidden"},
	expansions = "All"
})

function objectiveAndRespawn:AttachToPlayerButton(playerButton)
	local frame = CreateFrame("frame", nil, playerButton)
	frame:SetFrameLevel(playerButton:GetFrameLevel()+5)

	frame.Icon = frame:CreateTexture(nil, "BORDER")
	frame.Icon:SetAllPoints()

	frame:SetScript("OnSizeChanged", function(self, width, height)
		BattleGroundEnemies.CropImage(self.Icon, width, height)
	end)
	frame:Hide()

	frame.AuraText = BattleGroundEnemies.MyCreateFontString(frame)
	frame.AuraText:SetAllPoints()
	frame.AuraText:SetJustifyH("CENTER")

	frame.Cooldown = BattleGroundEnemies.MyCreateCooldown(frame)
	frame.Cooldown:Hide()


	frame.Cooldown:SetScript("OnCooldownDone", function()
		frame:Reset()
	end)
	-- ObjectiveAndRespawn.Cooldown:SetScript("OnCooldownDone", function()
	-- 	ObjectiveAndRespawn:Reset()
	-- end)

	function frame:Reset()
		self:Hide()
		self.Icon:SetTexture()
		if self.AuraText:GetFont() then self.AuraText:SetText("") end
		self.ActiveRespawnTimer = false
	end


	function frame:ApplyAllSettings()
		if BattleGroundEnemies.BGSize == 15 then
			local conf = self.config
			self.AuraText:ApplyFontStringSettings(conf.Text)

			self.Cooldown:ApplyCooldownSettings(conf.Cooldown, true, true, {0, 0, 0, 0.75})
		end
	end
	function frame:SearchForDebuffs(name, icon, count, debuffType, duration, expirationTime, unitCaster, canStealOrPurge, nameplateShowPersonal, spellID, canApplyAura, isBossAura, castByPlayer, nameplateShowAll, timeMod, value1, value2, value3, value4)
		--BattleGroundEnemies:Debug("Läüft")
		local battleGroundDebuffs = BattleGroundEnemies.BattleGroundDebuffs
		local value
		for i = 1, #battleGroundDebuffs do
			if spellID == battleGroundDebuffs[i] then
				if BattleGroundEnemies.CurrentMapID == 417 then -- 417 is Kotmogu, we scan for orb debuffs

					--kotmogu
					if value2 then
						if not self.Value then
							--BattleGroundEnemies:Debug("hier")
							--player just got the debuff
							self.Icon:SetTexture(GetSpellTexture(spellID))
							self:Show()
							--BattleGroundEnemies:Debug("Texture set")
						end
						value = value2

								--values for orb debuff:
								--BattleGroundEnemies:Debug(value1, value2, value3, value4)
								-- value1 = Reduces healing received by value1
								-- value2 = Increases damage taken by value2
								-- value3 = Increases damage done by value3
					end
					--end of kotmogu

				else
					-- not kotmogu
					value = count
				end
				if value ~= self.Value then
					self.AuraText:SetText(value)
					self.Value = value
				end
				self.continue = false
				return
			end
		end
	end

	function frame:ShouldQueryAuras(unitID, filter)
		if BattleGroundEnemies.ArenaIDToPlayerButton[unitID] then
			return filter == "HARMFUL"
		else
			return false
		end
	end


	function frame:CareAboutThisAura(unitID, auraInfo, filter, spellID, unitCaster, canStealOrPurge, canApplyAura, debuffType)
		if BattleGroundEnemies.ArenaIDToPlayerButton[unitID] then -- this player is shown on the arena frame and is carrying a flag, orb, etc..
			local bgDebuffs = BattleGroundEnemies.BattleGroundDebuffs
			if bgDebuffs then
				if auraInfo then spellID = auraInfo.spellId end

				for i = 1, #bgDebuffs do
					if spellID == bgDebuffs[i] then
						return true
					end
				end
			end
		end
	end

	function frame:BeforeUnitAura(unitID, filter)
		if filter == "HARMFUL" then
			self.continue = true
		end
	end

	function frame:UnitAura(unitID, filter, ...)
		if filter ~= "HARMFUL" then return end
		if not self.continue then return end

		if BattleGroundEnemies.ArenaIDToPlayerButton[unitID] then -- This player is shown on arena enemy frames because he holds a objective
			if BattleGroundEnemies.BattleGroundDebuffs then
				self:SearchForDebuffs(...)
			end
		end
	end

	function frame:UnitDied()
		if (BattleGroundEnemies.IsRatedBG or (BattleGroundEnemies.TestmodeActive and BattleGroundEnemies.BGSize == 15)) then
		--BattleGroundEnemies:Debug("UnitIsDead SetCooldown")
			if not self.ActiveRespawnTimer then
				self:Show()
				self.Icon:SetTexture(GetSpellTexture(8326))
				self.AuraText:SetText("")
				self.ActiveRespawnTimer = true
			end
			self.Cooldown:SetCooldown(GetTime(), 26) --overwrite an already active timer
		end
	end

	function frame:ArenaOpponentShown()
		if BattleGroundEnemies.BattlegroundBuff then
			--BattleGroundEnemies:Debug(self:Getframe().PlayerName, "has buff")
			self.Icon:SetTexture(GetSpellTexture(BattleGroundEnemies.BattlegroundBuff[playerButton.PlayerIsEnemy and BattleGroundEnemies.EnemyFaction or BattleGroundEnemies.AllyFaction]))
			self:Show()
		end

		self.AuraText:SetText("")
		self.Value = false
	end

	function frame:ArenaOpponentHidden()
		self:Reset()
	end
	playerButton.ObjectiveAndRespawn = frame
end

