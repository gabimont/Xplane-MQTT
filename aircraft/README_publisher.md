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

## Quick start — just press Run (▶), then Stop (■)

With X-Plane open and the aircraft on a runway:

1. Open [`aircraft/start.m`](start.m) in the MATLAB editor
2. (Optional) edit `CALLSIGN` at the top if you want a different name
3. Press **Run (▶)** in the MATLAB toolbar (or F5)
4. When you want to stop, press **Stop (red square ■)** in the same
   toolbar (or Ctrl+C in the command window)

`start.m` does the path setup, teleports the aircraft up (via
`teleport_aircraft`), starts the MQTT publisher, then blocks on a
`pause(1)` loop so MATLAB's Stop button stays active. Clicking Stop
interrupts the loop and triggers `onCleanup`, which calls
`stop_publisher` automatically.

## Running multiple aircraft (one PC each)

For each additional aircraft / PC:

1. `git clone` (or `git pull`) the repo on that PC
2. Open [`aircraft/start.m`](start.m) and **change `CALLSIGN`** to
   something unique — e.g. `'CESSNA02'`, `'GLIDER03'`. The topic
   becomes `radar/aircraft/<CALLSIGN>/state` automatically.
3. **Edit [`teleport_aircraft.m`](teleport_aircraft.m)** on that PC
   so `TargetLat / TargetLon` are different from the other PCs —
   otherwise the aircraft all spawn on the same point and their blips
   overlap.
4. Press **Run (▶)**.

The tower (`radar_gui` on the Mac) doesn't need any changes — its
default subscription `radar/aircraft/+/state` picks up every callsign
that publishes under the prefix. New aircraft just appear on the PPI
as soon as they publish.

## Quick start (manual, two commands)

If you prefer the command window:

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
inside the **"EDIT THESE VALUES"** block at the top. Note that the
target is **absolute lat/lon** — every call teleports to the same
exact point, no compounding offsets:

```matlab
% --- WHERE to put the aircraft (ABSOLUTE coordinates) ---
TargetLat = 46.7738;     % degrees (+N / -S)
TargetLon = -122.9831;   % degrees (+E / -W)
Altitude  = 100;         % m MSL

% --- HOW it should be flying ---
Speed    = 15;        % m/s true airspeed
Heading  = 0;         % deg true: 0=N, 90=E, 180=S, 270=W
Pitch    = -7;        % deg (nose down so it builds speed cleanly)
Throttle = 0.49;      % normalized [0, 1]
Gear     = 1;         % 1=down (use for taildraggers/fixed gear),
                      % 0=up   (only for retractable-gear aircraft)
```

Pick `TargetLat / TargetLon` near the tower's hardcoded position
(see [`radar/radar_state.m`](../radar/radar_state.m)) so the aircraft
shows up on the radar from the start. The default values place the
aircraft about 10 km North of the default tower point.

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
