[out:json][timeout:180];
// Transport, bridges, tunnels, public facilities, shops and landmarks.
(
 nwr["highway"](41.18,69.10,41.46,69.45);
 nwr["railway"](41.18,69.10,41.46,69.45);
 nwr["public_transport"](41.18,69.10,41.46,69.45);
 nwr["bridge"](41.18,69.10,41.46,69.45);
 nwr["tunnel"](41.18,69.10,41.46,69.45);
 nwr["barrier"~"^(wall|fence|gate|bollard|retaining_wall)$"](41.18,69.10,41.46,69.45);
 nwr["shop"](41.18,69.10,41.46,69.45);
 nwr["amenity"](41.18,69.10,41.46,69.45);
 nwr["office"](41.18,69.10,41.46,69.45);
 nwr["tourism"](41.18,69.10,41.46,69.45);
 nwr["historic"](41.18,69.10,41.46,69.45);
 nwr["healthcare"](41.18,69.10,41.46,69.45);
);
out body geom;
