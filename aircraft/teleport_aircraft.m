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

    % --- WHERE to put the aircraft (ABSOLUTE coordinates) ---
    % These should be near the tower position configured in
    % radar/radar_state.m so the aircraft shows up on the radar.
    % Default below is ~10 km North of the default tower.
    TargetLat = 46.7738;         % degrees  (+N / -S)
    TargetLon = -122.9831;       % degrees  (+E / -W)
    Altitude  = 100;             % m MSL

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

    fprintf('teleport_aircraft: opening XPC at %s:%d ...\n', XPCHost, XPCPort);
    socket = openUDP(XPCHost, XPCPort);
    cleaner = onCleanup(@() closeUDP(socket));

    % Read current lat/lon just for the log line (so the user can see
    % what changed). The teleport target itself is the hardcoded value.
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
             'alt=%.0f m, %.0f m/s @ %.0f° hdg, pitch %.1f°, ' ...
             'throttle %.2f, gear %d\n'], ...
            lat0, lon0, TargetLat, TargetLon, ...
            Altitude, Speed, Heading, Pitch, Throttle, Gear);
end
