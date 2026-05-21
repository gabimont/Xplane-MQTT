function teleport_aircraft()
%TELEPORT_AIRCRAFT Teleport the X-Plane aircraft to an ABSOLUTE lat/lon
%   with cruise velocity, so it's already flying when MQTT broadcasts
%   start. Run this BEFORE start_publisher (or let start.m do it).
%
%   Edit the values in the "EDIT THESE VALUES" block below and then
%   call:
%
%       >> teleport_aircraft
%
%   Why absolute (not relative)? With relative offsets, calling this
%   twice in a row stacks the displacement (aircraft drifts further and
%   further). Hardcoded lat/lon means it always ends up at the same
%   point on the map.

    % ====================================================================
    % EDIT THESE VALUES
    % ====================================================================
    XPCHost   = '127.0.0.1';     % X-Plane host (usually localhost)
    XPCPort   = 49009;           % XPC plugin port

    % --- WHERE to put the aircraft (offset in METERS from the tower) ---
    % The tower lat/lon lives in common/tower_position.m (single source
    % of truth, shared with the radar). Positive offsets: North / East.
    % Negative: South / West. Default is (0, 0) — same lat/lon as the
    % tower so the teleport lands on already-loaded scenery (the
    % aircraft is just lifted up and given cruise velocity).
    OffsetNorthM = 0;            % m  (+N / -S). 10000 = 10 km north of tower
    OffsetEastM  = 0;            % m  (+E / -W)
    Altitude     = 100;          % m MSL (absolute, NOT relative to tower)

    % --- HOW it should be flying ---
    Speed    = 15;               % m/s true airspeed (Piper cruise ~15)
    Heading  = 0;                % deg true: 0=N, 90=E, 180=S, 270=W
    Pitch    = -7;               % deg (nose down so it builds speed cleanly)
    Throttle = 0.49;             % normalized [0, 1]
    Gear     = 1;                % 1 = down (fixed-gear / taildragger),
                                 % 0 = up   (retractable-gear aircraft)
    % ====================================================================

    % --- Paths ---
    here = fileparts(mfilename('fullpath'));
    repo = fileparts(here);
    addpath(fullfile(repo, 'common'));       % so tower_position() is findable
    xpcMatlab = fullfile(repo, 'XPlaneConnect-master', 'MATLAB');
    if exist(xpcMatlab, 'dir')
        addpath(xpcMatlab);
    end

    if isempty(which('XPlaneConnect.openUDP'))
        error('teleport_aircraft:NoXPC', ...
              ['XPlaneConnect API not found on path. Expected ' ...
               '+XPlaneConnect/openUDP.m under %s'], xpcMatlab);
    end

    import XPlaneConnect.*

    % --- Resolve the absolute target from the tower + the m offsets ---
    % 1 degree latitude ≈ 111000 m everywhere
    % 1 degree longitude ≈ 111000 * cos(lat) m
    [TowerLat, TowerLon] = tower_position();
    TargetLat = TowerLat + OffsetNorthM / 111000;
    TargetLon = TowerLon + OffsetEastM  / (111000 * cosd(TowerLat));

    fprintf('teleport_aircraft: opening XPC at %s:%d ...\n', XPCHost, XPCPort);
    socket = openUDP(XPCHost, XPCPort);
    cleaner = onCleanup(@() closeUDP(socket));

    % Read current lat/lon just for the log line (so the user can see
    % what changed). The teleport target itself is computed from the
    % tower + offsets above.
    drefs_ll = {'sim/flightmodel/position/latitude', ...
                'sim/flightmodel/position/longitude'};
    ll   = double(getDREFs(drefs_ll, socket));
    lat0 = ll(1);
    lon0 = ll(2);

    pauseSim(1, socket);
    pause(0.2);

    % POSI: [lat, lon, alt_m, pitch_deg, roll_deg, heading_true_deg, gear]
    sendPOSI([TargetLat, TargetLon, Altitude, Pitch, 0, Heading, Gear], 0, socket);

    % Initial velocity along the heading vector, in OpenGL local frame.
    % local_vx = East+, local_vy = Up+, local_vz = South+ (so -vz = North).
    hdg_rad = Heading * pi/180;
    sendDREF('sim/flightmodel/position/local_vx',  Speed * sin(hdg_rad), socket);
    sendDREF('sim/flightmodel/position/local_vy',  0,                    socket);
    sendDREF('sim/flightmodel/position/local_vz', -Speed * cos(hdg_rad), socket);

    sendCTRL([0, 0, 0, Throttle, -998, -998], 0, socket);

    pause(0.3);
    pauseSim(0, socket);

    fprintf(['teleport_aircraft: from (%.4f, %.4f) → (%.4f, %.4f); ' ...
             '%+.0f m N / %+.0f m E from tower (%.4f, %.4f); ' ...
             'alt=%.0f m, %.0f m/s @ %.0f° hdg, pitch %.1f°, ' ...
             'throttle %.2f, gear %d\n'], ...
            lat0, lon0, TargetLat, TargetLon, ...
            OffsetNorthM, OffsetEastM, TowerLat, TowerLon, ...
            Altitude, Speed, Heading, Pitch, Throttle, Gear);
end
