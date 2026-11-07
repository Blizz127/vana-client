-- The Empyrean and other NMs' pops (the pop trackers' trees): each pop's id (key item or item), the monster that
-- drops it and how it appears (forced at a ??? or on a timer, map squares), the pops of that monster below it; the NM's
-- weapon item and how many count. Names come from the game's resources.

return {
  { name = "Alfard", zone = "Abyssea - Grauberg", collect = { 3291, 75 }, pops = {
    { ki = 1530, from = "Ningishzida", how = "Forced (I-7/I-8)", pops = {
      { item = 3262, from = "Jaculus", how = "Timed (I-8)" },
      { item = 3261, from = "Minaruja", how = "Forced (I-10)", pops = {
        { item = 3267, from = "Faunus Wyvern", how = "(I-9)" },
      } },
      { item = 3268, from = "Glade Wivre", how = "(I-8)" },
    } },
  } },
  { name = "Amphitrite", zone = "Abyssea - Grauberg", pops = {
    { ki = 1532, from = "Melo Melo", how = "Timed (F-11/G-11)" },
  } },
  { name = "Apademak", zone = "Abyssea - Uleguerand", collect = { 3289, 75 }, pops = {
    { ki = 1525, from = "Dhorme Khimaira", how = "Forced (F-7)", pops = {
      { item = 3246, from = "Upas-Kamuy", how = "Forced (G-5)", pops = {
        { item = 3252, from = "Snowflake", how = "(G-5)" },
      } },
      { item = 3247, from = "Sisyphus", how = "Timed (F-6/G-6)" },
      { item = 3253, from = "Olyphant", how = "(F-6)" },
    } },
  } },
  { name = "Arch Dynamis Lord", zone = "Dynamis - Xarcabard [D]", note = "not Abyssea", pops = {
    { item = 3429, from = "Dynamis Lord", how = "Forced (E-8)", pops = {
      { item = 3358, from = "Various Demon lottery NMs", how = "" },
    } },
    { item = 3430, from = "Duke Haures", how = "Forced (J-7)", pops = {
      { item = 3400, from = "Kindred DRK", how = "RDM & SAM" },
    } },
    { item = 3431, from = "Marquis Caim", how = "Forced (J-6)", pops = {
      { item = 3401, from = "Kindred BRD", how = "NIN, SMN & WAR" },
    } },
    { item = 3432, from = "Baron Avnas", how = "Forced (I-5)", pops = {
      { item = 3402, from = "Kindred DRG", how = "MNK, THF & WHM" },
    } },
    { item = 3433, from = "Count Haagenti", how = "Forced (F-7)", pops = {
      { item = 3403, from = "Kindred BLM", how = "BST, PLD & RNG" },
    } },
  } },
  { name = "Azdaja", zone = "Abyssea - Grauberg", collect = { 3292, 75 }, pops = {
    { ki = 1531, from = "Deelgeed", how = "Timed (F-9/F-10)" },
  } },
  { name = "Bennu", zone = "Abyssea - Altepa", pops = {
    { ki = 1522, from = "Ouzelum", how = "Timed (I-8/J-9)" },
  } },
  { name = "Briareus", zone = "Abyssea - La Theine", collect = { 2929, 50 }, pops = {
    { ki = 1482, from = "Adamastor", how = "Forced (C-4)", pops = {
      { item = 2894, from = "Bathyal Gigas", how = "(C-5/D-5)" },
    } },
    { ki = 1484, from = "Grandgousier", how = "Forced (F-10)", pops = {
      { item = 2896, from = "Demersal Gigas", how = "(E-9/F-9)" },
    } },
    { ki = 1483, from = "Pantagruel", how = "Forced (F-7)", pops = {
      { item = 2895, from = "Hadal Gigas", how = "(F-6/F-7)" },
    } },
  } },
  { name = "Brulo", zone = "Abyssea - Altepa", note = "Conflux #5", collect = { 3294, 75 }, pops = {
    { ki = 1652, from = "Koios", how = "(Conflux #5)", pops = {
      { ki = 1565, from = "Fire/Earth Elemental", how = "", pops = {
        { ki = 1564, from = "Any Cruor Prospector", how = "" },
      } },
    } },
  } },
  { name = "Bukhis", zone = "Abyssea - Vunkerl", collect = { 2966, 50 }, pops = {
    { ki = 1508, from = "Khalkotaur", how = "Forced (F-4)", pops = {
      { item = 3098, from = "Aestutaur", how = "(G-9/G-10)" },
    } },
    { ki = 1509, from = "Quasimodo", how = "Forced (F-4)", pops = {
      { item = 3099, from = "Gruesome Gargouille", how = "(F-10/G-10)" },
    } },
    { ki = 1510, from = "Lord Varney", how = "Timed (G-10/H-10)" },
  } },
  { name = "Carabosse", zone = "Abyssea - La Theine", collect = { 2930, 50 }, pops = {
    { ki = 1485, from = "La Theine Liege", how = "Forced (I-7)", pops = {
      { item = 2897, from = "Plateau Glider", how = "(H-7)" },
    } },
    { ki = 1486, from = "Baba Yaga", how = "Forced (H-7)", pops = {
      { item = 2898, from = "Farfadet", how = "(H-7)" },
    } },
  } },
  { name = "Chloris", zone = "Abyssea - Tahrongi", collect = { 2928, 50 }, pops = {
    { ki = 1470, from = "Hedetet", how = "Forced (F-7)", pops = {
      { item = 2921, from = "Canyon Scorpion", how = "(F-7)" },
      { item = 2948, from = "Gancanagh", how = "Forced (H-8)", pops = {
        { item = 2920, from = "Pachypodium", how = "(H-8)" },
      } },
    } },
    { ki = 1469, from = "Treble Noctules", how = "Forced (I-9)", pops = {
      { item = 2919, from = "Blood Bat", how = "(I-9)" },
      { item = 2947, from = "Cannered Noz", how = "Forced (F-6)", pops = {
        { item = 2918, from = "Caoineag", how = "(F-6)" },
      } },
    } },
    { ki = 1468, from = "Ophanim", how = "Forced (G-9)", pops = {
      { item = 2917, from = "Beholder", how = "(G-9)" },
      { item = 2946, from = "Vetehinen", how = "Forced (H-10)", pops = {
        { item = 2916, from = "Gulch Limule", how = "(H-10)" },
      } },
      { item = 2945, from = "Halimede", how = "Forced (G-12)", pops = {
        { item = 2915, from = "Gully Clionid", how = "(G-12)" },
      } },
    } },
    { ki = 1471, from = "Chukwa", how = "Timed (F-5)" },
  } },
  { name = "Cirein-croin", zone = "Abyssea - Misareaux", collect = { 2965, 50 }, pops = {
    { ki = 1504, from = "Cep-Kamuy", how = "Forced (F-4)", pops = {
      { item = 3089, from = "Ancient Orobon", how = "(F-5)" },
    } },
    { ki = 1505, from = "Heqet", how = "Timed (I-6)" },
  } },
  { name = "Dragua", zone = "Abyssea - Altepa", collect = { 3288, 75 }, pops = {
    { ki = 1521, from = "Hazhdiha", how = "Timed (H-10)" },
  } },
  { name = "Glavoid", zone = "Abyssea - Tahrongi", collect = { 2927, 50 }, pops = {
    { ki = 1473, from = "Minhocao", how = "Timed (I-6)" },
    { ki = 1475, from = "Adze", how = "Timed (G-5)" },
    { ki = 1472, from = "Alectryon", how = "(H-8)", pops = {
      { item = 2923, from = "Cluckatrice", how = "(H-8)" },
      { item = 2949, from = "Abas", how = "Forced (K-10)", pops = {
        { item = 2922, from = "Canyon Eft", how = "(J-10/J-11)" },
      } },
    } },
    { ki = 1474, from = "Muscaliet", how = "Forced (J-6)", pops = {
      { item = 2925, from = "Hieracosphinx", how = "(J-6)" },
      { item = 2950, from = "Tefenet", how = "Forced (G-6)", pops = {
        { item = 2924, from = "Jaguarundi", how = "(G-6)" },
      } },
    } },
  } },
  { name = "Ironclad Smiter", zone = "Abyssea - Altepa", collect = { 3293, 50 }, pops = {
    { item = 3230, from = "Tablilla", how = "Forced (C-11)", pops = {
      { item = 3235, from = "Sand Sweeper", how = "(D-10)" },
    } },
    { item = 3236, from = "Bonfire", how = "(D-11/E-11)" },
  } },
  { name = "Ironclad Sunderer", zone = "Abyssea - Grauberg", collect = { 3293, 50 }, pops = {
    { item = 3260, from = "Teekesselchen", how = "Forced (I-5)", pops = {
      { item = 3265, from = "Sinister Seidel", how = "(J-5)" },
    } },
    { item = 3266, from = "Stygian Djinn", how = "(K-7)" },
  } },
  { name = "Ironclad Triturator", zone = "Abyssea - Uleguerand", collect = { 3293, 50 }, pops = {
    { item = 3245, from = "Koghatu", how = "Forced (G-8)", pops = {
      { item = 3250, from = "Mechanical Menace", how = "(G-8/H-8)" },
    } },
    { item = 3251, from = "Sub-zero Gear", how = "(F-8/F-9)" },
  } },
  { name = "Isgebind", zone = "Abyssea - Uleguerand", collect = { 3290, 75 }, pops = {
    { ki = 1526, from = "Kur", how = "Timed (I-5/J-5)" },
  } },
  { name = "Itzpapalotl", zone = "Abyssea - Attohwa", collect = { 2962, 50 }, pops = {
    { ki = 1488, from = "Granite Borer", how = "Forced (K-10)", pops = {
      { item = 3072, from = "Gullycampa", how = "(K-10)" },
    } },
    { ki = 1490, from = "Tunga", how = "Timed (K-10)" },
    { ki = 1489, from = "Blazing Eruca", how = "Forced (J-10)", pops = {
      { item = 3073, from = "Ignis Eruca", how = "(J-10)" },
    } },
  } },
  { name = "Kukulkan", zone = "Abyssea - Konschtat", collect = { 2932, 50 }, pops = {
    { ki = 1466, from = "Arimaspi", how = "Forced (K-6)", pops = {
      { item = 2913, from = "Deep Eye", how = "(K-6/K-7)" },
    } },
    { ki = 1464, from = "Alkonost", how = "Forced (H-6)", pops = {
      { item = 2912, from = "Ypotryll", how = "(I-7)" },
    } },
    { ki = 1465, from = "Keratyrannos", how = "Forced (G-6)", pops = {
      { item = 2910, from = "Mesa Wivre", how = "(G-6)" },
    } },
  } },
  { name = "Maere", zone = "Abyssea - Grauberg", note = "Conflux #8", collect = { 3294, 75 }, pops = {
    { ki = 1654, from = "Gamayun", how = "(Conflux #8)", pops = {
      { ki = 1565, from = "Air/Dark Elemental", how = "", pops = {
        { ki = 1564, from = "Any Cruor Prospector", how = "" },
      } },
    } },
  } },
  { name = "Ogopogo", zone = "Abyssea - Uleguerand", note = "Conflux #7", collect = { 3294, 75 }, pops = {
    { ki = 1653, from = "Chione", how = "(Conflux #7)", pops = {
      { ki = 1565, from = "Ice/Water Elemental", how = "", pops = {
        { ki = 1564, from = "Any Cruor Prospector", how = "" },
      } },
    } },
  } },
  { name = "Orthrus", zone = "Abyssea - Altepa", collect = { 3287, 75 }, pops = {
    { ki = 1520, from = "Amarok", how = "Forced (E-6)", pops = {
      { item = 3231, from = "Sharabha", how = "Forced (G-5)", pops = {
        { item = 3237, from = "Dune Manticore", how = "(F-5/F-6)" },
      } },
      { item = 3232, from = "Ansherekh", how = "Timed (F-8/G-8)" },
      { item = 3238, from = "Camelopardalis", how = "(F-7/G-7)" },
    } },
  } },
  { name = "Resheph", zone = "Abyssea - Uleguerand", pops = {
    { ki = 1527, from = "Awahondo", how = "Timed (K-6/K-7)" },
  } },
  { name = "Sedna", zone = "Abyssea - Vunkerl", collect = { 2967, 50 }, pops = {
    { ki = 1512, from = "Hrosshvalur", how = "Timed (J-6)" },
    { ki = 1511, from = "Iku-Turso", how = "Forced (J-7)", pops = {
      { item = 3100, from = "Jasconius", how = "(I-7/J-7)" },
    } },
  } },
  { name = "Sobek", zone = "Abyssea - Misareaux", collect = { 2964, 50 }, pops = {
    { ki = 1500, from = "Gukumatz", how = "Timed (J-11)" },
    { ki = 1498, from = "Minax Bugard", how = "Forced (K-10)", pops = {
      { item = 3085, from = "Abyssobugard", how = "(J-10/K-11)" },
    } },
    { ki = 1499, from = "Sirrush", how = "Forced (I-11)", pops = {
      { item = 3086, from = "Dusk Lizard", how = "(J-11)" },
    } },
  } },
  { name = "Ulhuadshi", zone = "Abyssea - Attohwa", collect = { 2963, 50 }, pops = {
    { ki = 1492, from = "Amun", how = "Timed (H-8/I-9)" },
    { ki = 1491, from = "Pallid Percy", how = "Forced (J-7)", pops = {
      { item = 3074, from = "Entozoon", how = "(J-7)" },
    } },
  } },
  { name = "Warder of Courage", zone = "Escha - Ru'Aun", note = "not Abyssea", pops = {
    { ki = 2986, from = "Dremi", how = "(NPC)", pops = {
      { ki = 2976, from = "Warder of Temperance (Zdei", how = "portal #1)" },
      { ki = 2977, from = "Warder of Fortitude (Ghrah", how = "portal #3)" },
      { ki = 2978, from = "Warder of Faith (Euvhi", how = "portal #12)" },
      { ki = 2979, from = "Warder of Justice (Xzomit", how = "portal #6)" },
      { ki = 2980, from = "Warder of Hope (Phuabo", how = "portal #1)" },
      { ki = 2981, from = "Warder of Prudence (Hpemde", how = "portal #9)" },
      { ki = 2982, from = "Warder of Love", how = "(Yovra)" },
      { ki = 2983, from = "Warder of Dignity (Limule", how = "portal #4)" },
      { ki = 2984, from = "Warder of Loyalty (Clionid", how = "portal #13)" },
      { ki = 2985, from = "Warder of Mercy (Murex", how = "portal #7)" },
    } },
  } },
}
