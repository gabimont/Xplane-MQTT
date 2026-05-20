# Radar (tower side)

MATLAB GUI that subscribes to one or more MQTT topics carrying aircraft state
and displays them as blips on a PPI-style polar radar.

## Requirements

- MATLAB R2022a+ with **Industrial Communication Toolbox** (`mqttclient`).
- No Mapping Toolbox needed (range/bearing computed in `ll2rb.m`).
- Network access to the broker (default `test.mosquitto.org:1883`).

## Quick start

```matlab
addpath('radar');
radar_gui;
```

In the window:
1. Confirm or change broker / port → **Connect**. Indicator turns green.
2. The default subscription `radar/aircraft/+/state` (wildcard) is already
   in the list; new aircraft appear automatically as they publish.
3. Set tower lat/lon to your reference point so range/bearing are correct.
4. Adjust Range (km) and Trail length to taste.

## What you see

- **PPI**: green polar plot, North up, clockwise bearing. Concentric labels
  every `max_range/5` km. Each aircraft is a triangle blip with its callsign
  and altitude (m) as label; a fading line behind shows the last N positions.
- **Right table**: callsign, range (km), bearing (deg, 000-359), altitude,
  heading, and status (`OK` or `STALE`).
- **STALE** = no message for > 10 s. The blip turns grey. After 60 s the
  aircraft is forgotten and removed.

## Add/remove topics

The default wildcard catches anything under `radar/aircraft/+/state`. If you
want to subscribe to a specific aircraft or to an entirely different prefix:

1. Type the topic in the "Topic:" field (MQTT wildcards `+` and `#` allowed).
2. Click **Subscribe**.
3. To unsubscribe, click the topic in the list and **Unsubscribe**.

## Smoke test (without X-Plane)

If you have the mosquitto CLI:
```bash
mosquitto_pub -h test.mosquitto.org -t 'radar/aircraft/FAKE01/state' \
  -m '{"callsign":"FAKE01","lat":-23.5,"lon":-46.6,"alt":300,"hdg":1.57,"vt":50,"ts":0}'
```

A green triangle should appear ~14 km NE of the tower (with default tower
coords). Republish with new lat/lon to see it move.

## Files

- `radar_gui.m`   — main GUI app (single function, nested callbacks).
- `radar_state.m` — factory for the shared state struct.
- `ll2rb.m`       — Haversine + initial-bearing helper.

## Notes

- The MQTT message callback only updates state; the redraw runs on a separate
  10 Hz timer so the plot doesn't stutter when many aircraft publish at once.
- The PPI uses `polaraxes` with `ThetaZeroLocation='top'` and clockwise
  direction (so North = up, East = 90°, like a compass).
