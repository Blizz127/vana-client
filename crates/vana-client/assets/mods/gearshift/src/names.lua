-- The words each add-on's files compare against, exactly as each one spells them.

local M = {}

M.JOBS_FULL = { "Warrior", "Monk", "White Mage", "Black Mage", "Red Mage", "Thief", "Paladin", "Dark Knight", "Beastmaster",
  "Bard", "Ranger", "Samurai", "Ninja", "Dragoon", "Summoner", "Blue Mage", "Corsair", "Puppetmaster", "Dancer",
  "Scholar", "Geomancer", "Rune Fencer" }

-- GearSwap (Windower's resources).
M.GS = {
  ELEMENTS = { [0] = "Fire", "Ice", "Wind", "Earth", "Lightning", "Water", "Light", "Dark", [15] = "None", [-1] = "Physical" },
  STATUS = { [0] = "Idle", "Engaged", "Dead", "Engaged dead", "Event", "Chocobo", [33] = "Resting", [38] = "Fishing",
    [47] = "Sitting", [48] = "Kneeling", [85] = "Mount" },
  SPELL_TYPES = { "WhiteMagic", "BlackMagic", "SummonerPact", "Ninjutsu", "BardSong", "BlueMagic", "Geomancy", "Trust" },
  -- Every key written out: Lua numbers unkeyed entries from 1 whatever key comes before them.
  SKILLS = { [1] = "Hand-to-Hand", [2] = "Dagger", [3] = "Sword", [4] = "Great Sword", [5] = "Axe", [6] = "Great Axe",
    [7] = "Scythe", [8] = "Polearm", [9] = "Katana", [10] = "Great Katana", [11] = "Club", [12] = "Staff",
    [22] = "Automaton Melee", [23] = "Automaton Archery", [24] = "Automaton Magic", [25] = "Archery",
    [26] = "Marksmanship", [27] = "Throwing", [28] = "Guard", [29] = "Evasion", [30] = "Shield", [31] = "Parrying",
    [32] = "Divine Magic", [33] = "Healing Magic", [34] = "Enhancing Magic", [35] = "Enfeebling Magic",
    [36] = "Elemental Magic", [37] = "Dark Magic", [38] = "Summoning Magic", [39] = "Ninjutsu", [40] = "Singing",
    [41] = "Stringed Instrument", [42] = "Wind Instrument", [43] = "Blue Magic", [44] = "Geomancy", [45] = "Handbell" },
  TARGETS = { [1] = "Self", [2] = "Player", [4] = "Party", [8] = "Ally", [16] = "NPC", [32] = "Enemy" },
  NATIONS = { [0] = "San d'Oria", "Bastok", "Windurst" },
}

-- LuAshitacast.
M.LAC = {
  SLOTS = { "Main", "Sub", "Range", "Ammo", "Head", "Body", "Hands", "Legs", "Feet", "Neck", "Waist", "Ear1", "Ear2",
    "Ring1", "Ring2", "Back" },
  ELEMENTS = { [0] = "Fire", "Ice", "Wind", "Earth", "Thunder", "Water", "Light", "Dark", [15] = "Non-Elemental" },
  SKILLS = { [32] = "Divine Magic", [33] = "Healing Magic", [34] = "Enhancing Magic", [35] = "Enfeebling Magic",
    [36] = "Elemental Magic", [37] = "Dark Magic", [38] = "Summoning", [39] = "Ninjutsu", [40] = "Singing",
    [43] = "Blue Magic", [44] = "Geomancy" },
  SPELL_TYPES = { "White Magic", "Black Magic", "Summoning", "Ninjutsu", "Bard Song", "Blue Magic" },
  ABILITY_TYPES = { [10] = "Rune Enchantment", [102] = "Ready", [173] = "Blood Pact: Rage", [174] = "Blood Pact: Ward",
    [193] = "Corsair Roll", [195] = "Quick Draw" },
  STATUS = { [0] = "Idle", "Engaged", "Dead", "Dead", "Zoning", [33] = "Resting" },
  DAYS = { [0] = "Firesday", "Earthsday", "Watersday", "Windsday", "Iceday", "Lightningday", "Lightsday", "Darksday" },
  DAY_ELEMENTS = { [0] = "Fire", "Earth", "Water", "Wind", "Ice", "Thunder", "Light", "Dark" },
  WEATHER = { [0] = "Clear", "Sunshine", "Clouds", "Fog", "Fire", "Fire x2", "Water", "Water x2", "Earth", "Earth x2",
    "Wind", "Wind x2", "Ice", "Ice x2", "Thunder", "Thunder x2", "Light", "Light x2", "Dark", "Dark x2" },
  WEATHER_ELEMENT = { [0] = "None", "None", "None", "None", "Fire", "Fire", "Water", "Water", "Earth", "Earth", "Wind",
    "Wind", "Ice", "Ice", "Thunder", "Thunder", "Light", "Light", "Dark", "Dark" },
  CONTAINERS = { Inventory = 0, Safe = 1, Storage = 2, Temporary = 3, Locker = 4, Satchel = 5, Sack = 6, Case = 7,
    Wardrobe = 8, Safe2 = 9, Wardrobe2 = 10, Wardrobe3 = 11, Wardrobe4 = 12 },
}

-- The SCH storm buffs as weather ids (178..185 storms I, 589..596 storms II), as both add-ons have them.
M.STORMS = { [178] = 4, [179] = 12, [180] = 10, [181] = 8, [182] = 14, [183] = 6, [184] = 16, [185] = 18,
  [589] = 5, [590] = 13, [591] = 11, [592] = 9, [593] = 15, [594] = 7, [595] = 17, [596] = 19 }

-- The weather's element (Windower's names) by weather id.
M.GS.WEATHER_ELEMENT = { [0] = "None", "None", "None", "None", "Fire", "Fire", "Water", "Water", "Earth", "Earth", "Wind",
  "Wind", "Ice", "Ice", "Lightning", "Lightning", "Light", "Light", "Dark", "Dark" }

return M
