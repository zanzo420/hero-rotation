-- Assumptions: build as tanky as possible. 
-- TODO: 4/30


--- ============================ HEADER ============================
--- ======= LOCALIZE =======
-- Addon
local addonName, addonTable = ...
-- HeroLib
local HL         = HeroLib
local Cache      = HeroCache
local Unit       = HL.Unit
local Player     = Unit.Player
local Target     = Unit.Target
local Pet        = Unit.Pet
local Spell      = HL.Spell
local MultiSpell = HL.MultiSpell
local Item       = HL.Item
-- HeroRotation
local HR         = HeroRotation

-- Azerite Essence Setup
local AE         = HL.Enum.AzeriteEssences
local AESpellIDs = HL.Enum.AzeriteEssenceSpellIDs

--- ============================ CONTENT ===========================
--- ======= APL LOCALS =======
-- luacheck: max_line_length 9999

-- Spells
if not Spell.Warrior then Spell.Warrior = {} end
Spell.Warrior.Protection = {
  ThunderClap                           = Spell(6343),
  DemoralizingShout                     = Spell(1160),
  BoomingVoice                          = Spell(202743),
  Bloodsport                            = Spell(279172),
  DragonRoar                            = Spell(118000),
  Revenge                               = Spell(6572),
  FreeRevenge                           = Spell(5302),
  Ravager                               = Spell(228920),
  ShieldBlock                           = Spell(2565),
  ShieldSlam                            = Spell(23922),
  ShieldBlockBuff                       = Spell(132404),
  UnstoppableForce                      = Spell(275336),
  AvatarBuff                            = Spell(107574),
  BraceForImpact                        = Spell(277636),
  DeafeningCrash                        = Spell(272824),
  Devastate                             = Spell(20243),
  Intercept                             = Spell(198304),
  BloodFury                             = Spell(20572),
  Berserking                            = Spell(26297),
  ArcaneTorrent                         = Spell(50613),
  LightsJudgment                        = Spell(255647),
  Fireblood                             = Spell(265221),
  AncestralCall                         = Spell(274738),
  BagofTricks                           = Spell(312411),
  IgnorePain                            = Spell(190456),
  Avatar                                = Spell(107574),
  LastStand                             = Spell(12975),
  LastStandBuff                         = Spell(12975),
  VictoryRush                           = Spell(34428),
  ImpendingVictory                      = Spell(202168),
  Pummel                                = Spell(6552),
  IntimidatingShout                     = Spell(5246),
  RazorCoralDebuff                      = Spell(303568),
  BloodoftheEnemy                       = Spell(297108),
  MemoryofLucidDreams                   = Spell(298357),
  PurifyingBlast                        = Spell(295337),
  RippleInSpace                         = Spell(302731),
  ConcentratedFlame                     = Spell(295373),
  TheUnboundForce                       = Spell(298452),
  WorldveinResonance                    = Spell(295186),
  FocusedAzeriteBeam                    = Spell(295258),
  GuardianofAzeroth                     = Spell(295840),
  AnimaofDeath                          = Spell(294926),
  ConcentratedFlameBurn                 = Spell(295368),
  RecklessForceBuff                     = Spell(302932),
  MemoryofLucidDreamsBuff               = Spell(298357)
};
local S = Spell.Warrior.Protection;

-- Items
if not Item.Warrior then Item.Warrior = {} end
Item.Warrior.Protection = {
  PotionofUnbridledFury            = Item(169299),
  GrongsPrimalRage                 = Item(165574, {13, 14}),
  AshvanesRazorCoral               = Item(169311, {13, 14}),
  AzsharasFontofPower              = Item(169314, {13, 14}),
  LingeringPsychicShell            = Item(174277, {13, 14}),
};
local I = Item.Warrior.Protection;

-- Create table to exclude above trinkets from On Use function
local OnUseExcludes = {
  I.GrongsPrimalRage:ID(),
  I.AshvanesRazorCoral:ID(),
  I.AzsharasFontofPower:ID(),
  I.LingeringPsychicShell:ID()
}

-- Rotation Var
local ShouldReturn; -- Used to get the return string
local gcdTime;

-- GUI Settings
local Everyone = HR.Commons.Everyone;
local Settings = {
  General = HR.GUISettings.General,
  Commons = HR.GUISettings.APL.Warrior.Commons,
  Protection = HR.GUISettings.APL.Warrior.Protection
};

-- Stuns
local StunInterrupts = {
  {S.IntimidatingShout, "Cast Intimidating Shout (Interrupt)", function () return true; end},
};

-- Small local utility functions or helpers.
local EnemyRanges = {8}
local function UpdateRanges()
  for _, i in ipairs(EnemyRanges) do
    HL.GetEnemies(i);
  end
end

local function num(val)
  if val then return 1 else return 0 end
end

local function bool(val)
  return val ~= 0
end

local function IsCurrentlyTanking()
  return Player:IsTankingAoE(16) or Player:IsTanking(Target);
end

local function IgnorePainWillNotCap()
  if Player:Buff(S.IgnorePain) then 
    local absorb = tonumber((GetSpellDescription(190456):match("%d+%S+%d"):gsub("%D","")))
    return Player:Buff(S.IgnorePain, 16, true) < (0.5 * math.floor(absorb * 1.3))
  else
    return true
  end
end

-- The amount of rage above which we dump revenges, below which we conserve for ignore pain.
local function RevengeThreshold()
  return 60
end


-- A bit of logic to dump rage immediately if the next spell suggested would take you past the rage threshold
local function shouldDumpRageIntoIP(rageGenerated)
  -- pick a threshold where rage-from-damage-taken doesn't cap you
  rageMax = 90
  -- make sure we have enough rage to cast IP
  if Player:Rage() >= 40 then
    if Player:BuffRemainsP(S.MemoryofLucidDreamsBuff) > Player:GCD() then
      -- rage gen is doubled. should dump rage into IP if rage + 2*rageGenerated >= rageMax
      return Player:Rage() + 2 * rageGenerated >= rageMax
    else
      return Player:Rage() + rageGenerated >= rageMax
    end
  else
    return false
  end
end

local function suggestRageDump(baseRageGen)
  if shouldDumpRageIntoIP(baseRageGen) then
    if HR.CastRightSuggested(S.IgnorePain) then return "rage capped"; end
  end
end

local function Precombat()
  -- flask
  -- food
  -- augmentation
  -- snapshot_stats
  if Everyone.TargetIsValid() then
    -- use_item,name=azsharas_font_of_power
    if I.AzsharasFontofPower:IsEquipReady() and Settings.Commons.UseTrinkets then
      if HR.Cast(I.AzsharasFontofPower, nil, Settings.Commons.TrinketDisplayStyle) then return "azsharas_font_of_power precombat"; end
    end
    -- potion
    if I.PotionofUnbridledFury:IsReady() and Settings.Commons.UsePotions then
      if HR.CastSuggested(I.PotionofUnbridledFury) then return "potion_of_unbridled_fury precombat"; end
    end
  end
end

local function Defensive()
  if S.ShieldBlock:IsReadyP() and ((Player:BuffDownP(S.ShieldBlockBuff) or Player:BuffRemainsP(S.ShieldBlockBuff) <= 1.5*gcdTime) and Player:BuffDownP(S.LastStandBuff) and Player:Rage() >= 30) then
    if HR.CastSuggested(S.ShieldBlock) then return "shield_block defensive" end
  end
  if S.LastStand:IsCastableP() and (Player:BuffDownP(S.ShieldBlockBuff) and S.ShieldBlock:RechargeP() > 1.5*gcdTime) then
    if HR.CastSuggested(S.LastStand) then return "last_stand defensive" end
  end
  if Player:HealthPercentage() <= 70 and I.LingeringPsychicShell:IsEquipReady() then
    if HR.CastRightSuggested(I.LingeringPsychicShell) then return "absorb trinket defensive" end
  end
end

local function Aoe()
  -- thunder_clap
  if (S.ThunderClap:IsCastableP(8) or S.ThunderClap:CooldownRemainsP() < 0.150) then
    suggestRageDump(5)
    if HR.Cast(S.ThunderClap) then return "thunder_clap 6"; end
  end
  -- memory_of_lucid_dreams,if=buff.avatar.down
  if S.MemoryofLucidDreams:IsCastableP() and (Player:BuffDownP(S.AvatarBuff)) then
    if HR.Cast(S.MemoryofLucidDreams, nil, Settings.Commons.EssenceDisplayStyle) then return "memory_of_lucid_dreams 7"; end
  end
  -- demoralizing_shout,if=talent.booming_voice.enabled
  if S.DemoralizingShout:IsCastableP(10) and (S.BoomingVoice:IsAvailable() and Player:RageDeficit() >= 40) then
    suggestRageDump(40)
    if HR.Cast(S.DemoralizingShout, Settings.Protection.GCDasOffGCD.DemoralizingShout) then return "demoralizing_shout 8"; end
  end
  -- anima_of_death,if=buff.last_stand.up
  if S.AnimaofDeath:IsCastableP() then
    if HR.Cast(S.AnimaofDeath, nil, Settings.Commons.EssenceDisplayStyle, 8) then return "anima_of_death 9"; end
  end
  -- dragon_roar
  if S.DragonRoar:IsCastableP(12) and HR.CDsON() then
    if HR.Cast(S.DragonRoar, Settings.Protection.GCDasOffGCD.DragonRoar) then return "dragon_roar 12"; end
  end
  -- revenge
  if S.Revenge:IsReadyP("Melee") and (Player:Buff(S.FreeRevenge) or Player:Rage() > RevengeThreshold()) then
    if HR.Cast(S.Revenge) then return "revenge 14"; end
  end
  -- ravager
  if S.Ravager:IsCastableP(40) then
    if HR.Cast(S.Ravager) then return "ravager 16"; end
  end
  -- shield_slam
  if S.ShieldSlam:IsCastableP("Melee") then
    suggestRageDump(15)
    if HR.Cast(S.ShieldSlam) then return "shield_slam 24"; end
  end
  -- devastate
  if S.Devastate:IsCastableP("Melee") then
    if HR.Cast(S.Devastate) then return "devastate 80"; end
  end
end

local function St()
  -- thunder_clap,if=spell_targets.thunder_clap=2&talent.unstoppable_force.enabled&buff.avatar.up
  if (S.ThunderClap:IsCastableP(8) or S.ThunderClap:CooldownRemainsP() < 0.150) and (Cache.EnemiesCount[8] == 2 and S.UnstoppableForce:IsAvailable() and Player:BuffP(S.AvatarBuff)) then
    suggestRageDump(5)
    if HR.Cast(S.ThunderClap) then return "thunder_clap 26"; end
  end
  -- shield_slam,if=buff.shield_block.up
  if S.ShieldSlam:IsCastableP("Melee") and (Player:BuffP(S.ShieldBlockBuff)) then
    suggestRageDump(15)
    if HR.Cast(S.ShieldSlam) then return "shield_slam 44"; end
  end
  -- thunder_clap,if=(talent.unstoppable_force.enabled&buff.avatar.up)
  if (S.ThunderClap:IsCastableP(8) or S.ThunderClap:CooldownRemainsP() < 0.150) and ((S.UnstoppableForce:IsAvailable() and Player:BuffP(S.AvatarBuff))) then
    suggestRageDump(5)
    if HR.Cast(S.ThunderClap) then return "thunder_clap 54"; end
  end
  -- demoralizing_shout,if=talent.booming_voice.enabled
  if S.DemoralizingShout:IsCastableP(10) and (S.BoomingVoice:IsAvailable() and Player:RageDeficit() >= 40) then
    suggestRageDump(40)
    if HR.Cast(S.DemoralizingShout, Settings.Protection.GCDasOffGCD.DemoralizingShout) then return "demoralizing_shout 60"; end
  end
  -- anima_of_death,if=buff.last_stand.up
  if S.AnimaofDeath:IsCastableP() then
    if HR.Cast(S.AnimaofDeath, nil, Settings.Commons.EssenceDisplayStyle, 8) then return "anima_of_death 61"; end
  end
  -- shield_slam
  if S.ShieldSlam:IsCastableP("Melee") then
    suggestRageDump(15)
    if HR.Cast(S.ShieldSlam) then return "shield_slam 70"; end
  end
  -- dragon_roar
  if S.DragonRoar:IsCastableP(12) and HR.CDsON() then
    if HR.Cast(S.DragonRoar, Settings.Protection.GCDasOffGCD.DragonRoar) then return "dragon_roar 73"; end
  end
  -- thunder_clap
  if S.ThunderClap:IsCastableP(8) then
    suggestRageDump(5)
    if HR.Cast(S.ThunderClap) then return "thunder_clap 74"; end
  end
  -- revenge
  if S.Revenge:IsReadyP("Melee") and (Player:Buff(S.FreeRevenge) or Player:Rage() >= RevengeThreshold() or ((not IsCurrentlyTanking()) and Player:Rage() >= 50)) then
    if HR.Cast(S.Revenge) then return "revenge 76"; end
  end
  -- ravager
  if S.Ravager:IsCastableP(40) then
    if HR.Cast(S.Ravager) then return "ravager 78"; end
  end
  -- devastate
  if S.Devastate:IsCastableP("Melee") then
    if HR.Cast(S.Devastate) then return "devastate 80"; end
  end
end

--- ======= ACTION LISTS =======
local function APL()
  gcdTime = Player:GCD()
  UpdateRanges()
  Everyone.AoEToggleEnemiesUpdate()

  -- call precombat
  if not Player:AffectingCombat() then
    local ShouldReturn = Precombat(); if ShouldReturn then return ShouldReturn; end
  end

  if Everyone.TargetIsValid() then
    -- Check defensives if tanking
    if IsCurrentlyTanking() then
      local ShouldReturn = Defensive(); if ShouldReturn then return ShouldReturn; end
    end
    -- Interrupt
    Everyone.Interrupt(5, S.Pummel, Settings.Commons.OffGCDasOffGCD.Pummel, StunInterrupts);
    -- auto_attack
    -- intercept,if=time=0
    if S.Intercept:IsCastableP(25) and (HL.CombatTime() == 0 and not Target:IsInRange(8)) then
      if HR.Cast(S.Intercept) then return "intercept 84"; end
    end
    -- use_items,if=cooldown.avatar.remains>20
    if (S.Avatar:CooldownRemainsP() > 20) then
      local TrinketToUse = HL.UseTrinkets(OnUseExcludes)
      if TrinketToUse then
        if HR.Cast(TrinketToUse, nil, Settings.Commons.TrinketDisplayStyle) then return "Generic use_items for " .. TrinketToUse:Name(); end
      end
    end

    if (HR.CDsON()) then
      -- blood_fury
      if S.BloodFury:IsCastableP() then
        if HR.Cast(S.BloodFury, Settings.Commons.OffGCDasOffGCD.Racials) then return "blood_fury 91"; end
      end
      -- berserking
      if S.Berserking:IsCastableP() then
        if HR.Cast(S.Berserking, Settings.Commons.OffGCDasOffGCD.Racials) then return "berserking 93"; end
      end
      -- arcane_torrent
      if S.ArcaneTorrent:IsCastableP() then
        if HR.Cast(S.ArcaneTorrent, Settings.Commons.OffGCDasOffGCD.Racials, nil, 8) then return "arcane_torrent 95"; end
      end
      -- lights_judgment
      if S.LightsJudgment:IsCastableP() then
        if HR.Cast(S.LightsJudgment, Settings.Commons.OffGCDasOffGCD.Racials, nil, 40) then return "lights_judgment 97"; end
      end
      -- fireblood
      if S.Fireblood:IsCastableP() then
        if HR.Cast(S.Fireblood, Settings.Commons.OffGCDasOffGCD.Racials) then return "fireblood 99"; end
      end
      -- ancestral_call
      if S.AncestralCall:IsCastableP() then
        if HR.Cast(S.AncestralCall, Settings.Commons.OffGCDasOffGCD.Racials) then return "ancestral_call 101"; end
      end
      -- bag_of_tricks
      if S.BagofTricks:IsCastableP() then
        if HR.Cast(S.BagofTricks, Settings.Commons.OffGCDasOffGCD.Racials, nil, 40) then return "bag_of_tricks 102"; end
      end
    end

    -- potion,if=buff.avatar.up|target.time_to_die<25
    if I.PotionofUnbridledFury:IsReady() and Settings.Commons.UsePotions and (Player:BuffP(S.AvatarBuff) or Target:TimeToDie() < 25) then
      if HR.CastSuggested(I.PotionofUnbridledFury) then return "potion_of_unbridled_fury 103"; end
    end
    if Player:HealthPercentage() < 80 and S.VictoryRush:IsReady("Melee") then
      if HR.Cast(S.VictoryRush) then return "victory_rush defensive" end
    end
    if Player:HealthPercentage() < 80 and S.ImpendingVictory:IsReadyP("Melee") then
      if HR.Cast(S.ImpendingVictory) then return "impending_victory defensive" end
    end
    -- ignore_pain,if=rage.deficit<25+20*talent.booming_voice.enabled*cooldown.demoralizing_shout.ready
    if S.IgnorePain:IsReadyP() and (Player:RageDeficit() < 25 + 20 * num(S.BoomingVoice:IsAvailable()) * num(S.DemoralizingShout:CooldownUpP()) and IgnorePainWillNotCap() and IsCurrentlyTanking()) then
      if HR.CastRightSuggested(S.IgnorePain) then return "ignore_pain 107"; end
    end
    -- worldvein_resonance,if=cooldown.avatar.remains<=2
    if S.WorldveinResonance:IsCastableP() and (S.Avatar:CooldownRemainsP() <= 2) then
      if HR.Cast(S.WorldveinResonance, nil, Settings.Commons.EssenceDisplayStyle) then return "worldvein_resonance 108"; end
    end
    -- ripple_in_space
    if S.RippleInSpace:IsCastableP() then
      if HR.Cast(S.RippleInSpace, nil, Settings.Commons.EssenceDisplayStyle) then return "ripple_in_space 109"; end
    end
    -- concentrated_flame,if=buff.avatar.down&!dot.concentrated_flame_burn.remains>0|essence.the_crucible_of_flame.rank<3
    if S.ConcentratedFlame:IsCastableP() and (Player:BuffDownP(S.AvatarBuff) and Target:DebuffDownP(S.ConcentratedFlameBurn) or Spell:EssenceRank(AE.TheCrucibleofFlame) < 3) then
      if HR.Cast(S.ConcentratedFlame, nil, Settings.Commons.EssenceDisplayStyle, 40) then return "concentrated_flame 111"; end
    end
    -- avatar
    if S.Avatar:IsCastableP() and HR.CDsON() and (Player:BuffDownP(S.AvatarBuff)) then
    suggestRageDump(20)
      if HR.Cast(S.Avatar, Settings.Protection.GCDasOffGCD.Avatar) then return "avatar 113"; end
    end
    -- memory_of_lucid_dreams
    if S.MemoryofLucidDreams:IsCastableP() and S.Avatar:CooldownRemainsP() > 0 then
      if HR.Cast(S.MemoryofLucidDreams, nil, Settings.Commons.EssenceDisplayStyle) then return "memory_of_lucid_dreams 110"; end
    end
    -- run_action_list,name=aoe,if=spell_targets.thunder_clap>=3
    if (Cache.EnemiesCount[8] >= 3) then
      return Aoe();
    end
    -- call_action_list,name=st
    if (true) then
      local ShouldReturn = St(); if ShouldReturn then return ShouldReturn; end
    end
  end
end

local function Init()
  HL.RegisterNucleusAbility(6343, 8, 6)               -- Thunder Clap
  HL.RegisterNucleusAbility(118000, 12, 6)            -- Dragon Roar
  HL.RegisterNucleusAbility(6572, 8, 6)               -- Revenge
  HL.RegisterNucleusAbility(228920, 8, 6)             -- Ravager
end

HR.SetAPL(73, APL, Init)
