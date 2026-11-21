[out:json][timeout:180];
// Shops, services, public facilities, landmarks and visitor destinations.
// Approximate Tashkent bbox only; clip to the official city polygon.
(
 nwr["shop"](41.18,69.10,41.46,69.45);
 nwr["amenity"](41.18,69.10,41.46,69.45);
 nwr["office"](41.18,69.10,41.46,69.45);
 nwr["tourism"](41.18,69.10,41.46,69.45);
 nwr["historic"](41.18,69.10,41.46,69.45);
 nwr["healthcare"](41.18,69.10,41.46,69.45);
 nwr["craft"](41.18,69.10,41.46,69.45);
);
out body geom;
