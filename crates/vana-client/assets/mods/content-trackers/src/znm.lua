-- The Zeni NMs by path (the ZNM helpers): each one's tier, pop item, the seals buying it takes, its trophy and the
-- seal the trophy gives, and its ??? (x, y, z, zone); each path's salt for its islet. Names come from the game's
-- resources.

local function znm(name, tier, pop, seals, trophy, seal, at)
  return { name = name, tier = tier, pop = pop, seals = seals, trophy = trophy, seal = seal, at = at }
end

return {
  { path = "Tinnin", salt = 1016, znms = {
    znm("Vulpangue", 1, 2580, {  }, 2616, 998, { -697, -7, -123, 51 }),
    znm("Chamrosh", 1, 2581, {  }, 2617, 998, { 206, 14, -285, 65 }),
    znm("Cheese Hoarder Gigiroon", 1, 2582, {  }, 2618, 998, { -184, -8, 24, 72 }),
    znm("Iriz Ima", 2, 2577, { 998 }, 2613, 999, { 253, -23, 116, 51 }),
    znm("Lividroot Amooshah", 2, 2578, { 998 }, 2614, 999, { 334, -10, 184, 52 }),
    znm("Iriri Samariri", 2, 2579, { 998 }, 2615, 999, { -118, 7, -80, 65 }),
    znm("Armed Gear", 3, 2574, { 999 }, 2610, 1000, { -42, -4, -169, 72 }),
    znm("Gotoh Zha the Redolent", 3, 2575, { 999 }, 2611, 1001, { -337, -31, 676, 51 }),
    znm("Dea", 3, 2576, { 999 }, 2612, 1002, { -34, -32, 481, 52 }),
    znm("Tinnin", 4, 2573, { 1000, 1001, 1002 }, 2609, 1003, { 278, 0, -703, 51 }),
  } },
  { path = "Sarameya", salt = 1017, znms = {
    znm("Brass Borer", 1, 2590, {  }, 2626, 1004, { 399, -27, 120, 61 }),
    znm("Claret", 1, 2591, {  }, 2627, 1004, { 497, -9, 52, 61 }),
    znm("Ob", 1, 2592, {  }, 2628, 1004, { 542, 0, -129, 72 }),
    znm("Anantaboga", 2, 2587, { 1004 }, 2623, 1005, { -368, -13, 366, 61 }),
    znm("Reacton", 2, 2588, { 1004 }, 2624, 1005, { 18, -9, 213, 62 }),
    znm("Dextrose", 2, 2589, { 1004 }, 2625, 1005, { -144, 11, 464, 62 }),
    znm("Nosferatu", 3, 2584, { 1005 }, 2620, 1006, { -199, 8, -62, 68 }),
    znm("Khromasoul Bhurborlor", 3, 2585, { 1005 }, 2621, 1007, { 88, -22, 70, 61 }),
    znm("Achamoth", 3, 2586, { 1005 }, 2622, 1008, { -34, 10, 336, 62 }),
    znm("Sarameya", 4, 2583, { 1008, 1007, 1006 }, 2619, 1009, { 322, -14, -581, 61 }),
  } },
  { path = "Tyger", salt = 1018, znms = {
    znm("Velionis", 1, 2600, {  }, 2636, 1010, { 311, -3, 27, 54 }),
    znm("Lil' Apkallu", 1, 2601, {  }, 2637, 1010, { 488, -1, 166, 54 }),
    znm("Chigre", 1, 2602, {  }, 2638, 1010, { -217, 35, 12, 68 }),
    znm("Wulgaru", 2, 2597, { 1010 }, 2633, 1011, { -22, -4, 204, 72 }),
    znm("Zareehkl the Jubilant", 2, 2598, { 1010 }, 2634, 1011, { 176, -4, 182, 54 }),
    znm("Verdelet", 2, 2599, { 1010 }, 2635, 1011, { 417, -19, -69, 79 }),
    znm("Mahjlaef the Paintorn", 3, 2594, { 1011 }, 2630, 1012, { 695, -7, 527, 79 }),
    znm("Experimental Lamia", 3, 2595, { 1011 }, 2631, 1013, { -773, -11, 322, 79 }),
    znm("Nuhn", 3, 2596, { 1011 }, 2632, 1014, { -451, -7, 389, 54 }),
    znm("Tyger", 4, 2593, { 1013, 1012, 1014 }, 2629, 1015, { -766, -12, 632, 79 }),
  } },
  { path = "Pandemonium Warden", znms = {
    znm("Pandemonium Warden", 5, 2572, { 1003, 1015, 1009 }, nil, nil, { 200, 33, -140, 68 }),
  } },
}
