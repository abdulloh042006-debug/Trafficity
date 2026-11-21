[out:json][timeout:180];
// Park, gardens, lawns, trees, canals, drains, ponds and water bodies.
(
 nwr["leisure"~"^(park|garden|nature_reserve|recreation_ground|playground|pitch|sports_centre|golf_course)$"](41.18,69.10,41.46,69.45);
 nwr["landuse"~"^(forest|grass|meadow|orchard|allotments|village_green|recreation_ground)$"](41.18,69.10,41.46,69.45);
 nwr["natural"~"^(wood|water|wetland|grassland|tree|tree_row|shrubbery)$"](41.18,69.10,41.46,69.45);
 nwr["water"](41.18,69.10,41.46,69.45);
 nwr["waterway"~"^(river|canal|stream|ditch|drain|riverbank|wadi)$"](41.18,69.10,41.46,69.45);
 nwr["man_made"~"^(reservoir|water_tower|water_well|water_works|dam|weir|watermill)$"](41.18,69.10,41.46,69.45);
);
out body geom;
