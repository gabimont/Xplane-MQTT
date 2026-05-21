# Aircraft publisher (Windows side)

Reads aircraft position/heading from a running X-Plane via XPlaneConnect (XPC)
and publishes a JSON payload to MQTT at a fixed rate. Each running instance
represents one aircraft.

## Requirements

- Windows (or any OS) with MATLAB R2022a+ and **Industrial Communication
  Toolbox** (for `mqttclient`).
- X-Plane 11/12 running, with the XPlaneConnect plugin installed
  (`X-Plane/Resources/plugins/XPlaneConnect/`).
- The XPlaneConnect MATLAB API on the path:
  `Xplane-MQTT/XPlaneConnect-master/MATLAB/+XPlaneConnect/`. If you cloned
  this repo and the `+XPlaneConnect` folder is empty, grab it from
  [nasa/XPlaneConnect](https://github.com/nasa/XPlaneConnect) and drop it in.

## Quick start (two steps)

With X-Plane open and the aircraft on a runway:

```matlab
addpath('aircraft');

% 1) Put the aircraft in the air with initial velocity (no MQTT yet)
teleport_aircraft;

% 2) Start broadcasting position to MQTT
pub = start_publisher(Callsign='PIPER01');

% ... fly in X-Plane (or let it cruise) ...

stop_publisher(pub);
```

Default teleport (tuned for the Piper J-3 Cub, like the existing
`posicionar_xplane.m`): lifts the aircraft to **100 m** at its current
lat/lon, **15 m/s** heading **North**, nose **-7°**, gear **down**,
throttle **0.49**. Enough velocity + throttle so the Piper doesn't
stall.

Skip the teleport entirely if you want to fly manually from the runway
— just run `start_publisher` directly.

### Customizing the teleport

Open [`teleport_aircraft.m`](teleport_aircraft.m) and edit the values
inside the **"EDIT THESE VALUES"** block at the top:

```matlab
Altitude = 100;       % m MSL
Speed    = 15;        % m/s true airspeed
Heading  = 0;         % deg true: 0=N, 90=E, 180=S, 270=W
Pitch    = -7;        % deg (nose down so it builds speed cleanly)
Throttle = 0.49;      % normalized [0, 1]
Gear     = 1;         % 1=down (use for taildraggers/fixed gear),
                      % 0=up   (only for retractable-gear aircraft)
```

For higher/faster aircraft (jets, etc.), bump Altitude and Speed and
set Gear=0. For the Piper or any fixed-gear plane keep Gear=1.

Save and run `teleport_aircraft` again. The aircraft will be put in
the air, and **`start_publisher` afterwards** publishes MQTT.

### Custom broker / callsign / rate

```matlab
pub = start_publisher( ...
    Callsign='CESSNA02', ...
    RateHz=10, ...
    Broker='tcp://broker.hivemq.com', Port=1883);
```

## Published payload

Topic: `radar/aircraft/<CALLSIGN>/state` (callsign uppercased).

```json
{
  "callsign": "PIPER01",
  "lat": -23.5283,
  "lon": -46.6478,
  "alt": 152.3,
  "hdg": 0.78,
  "vt":  18.4,
  "ts":  1747780000.123
}
```

| Field    | Unit              | Source dataref                           |
|----------|-------------------|------------------------------------------|
| lat      | deg               | `sim/flightmodel/position/latitude`      |
| lon      | deg               | `sim/flightmodel/position/longitude`     |
| alt      | m MSL             | `sim/flightmodel/position/elevation`     |
| hdg      | rad, wrap [-π,π]  | `sim/flightmodel/position/psi` (deg→rad) |
| vt       | m/s               | `sim/flightmodel/position/true_airspeed` |
| ts       | Unix epoch sec    | host clock                               |

## Verify with `mosquitto_sub`

If you have the mosquitto CLI:
```bash
mosquitto_sub -h broker.emqx.io -t 'radar/aircraft/+/state' -v
```

Each publish should print:
```
radar/aircraft/PIPER01/state {"callsign":"PIPER01","lat":-23.52,...}
```

## Running multiple aircraft from one MATLAB session

Each `start_publisher` returns its own handle, with its own timer. You can
have several at once:
```matlab
pub1 = start_publisher(Callsign='PIPER01');
pub2 = start_publisher(Callsign='CESSNA02', XPCPort=49010);
```
(Each instance reads from its own XPC socket. To publish more than one
aircraft from the same X-Plane install you'd need multiple aircraft slots
in X-Plane — usually you run one publisher per machine.)

## Troubleshooting

- **`XPlaneConnect API not found on path`** — add the `+XPlaneConnect`
  folder to the MATLAB path. See Requirements above.
- **`mqttclient` undefined** — install Industrial Communication Toolbox or
  Instrument Control Toolbox (R2022a+ supports `mqttclient`).
- **Publisher runs but radar shows nothing** — confirm the broker host and
  that the topic prefix on both sides matches (default `radar/aircraft/`).
- **`getDREFs` returns NaN / errors** — the XPC plugin isn't loaded in
  X-Plane. Check the X-Plane Developer menu → Plugin Admin.
