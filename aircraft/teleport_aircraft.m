function teleport_aircraft()
%TELEPORT_AIRCRAFT Lift the X-Plane aircraft to altitude with cruise
%   velocity so it's already flying when MQTT broadcasts start. Run
%   this BEFORE start_publisher.
%
%   Modeled after posicionar_xplane.m (which is known to work with the
%   Piper J-3 Cub): teleports to the current lat/lon, but at altitude,
%   with nose down a bit, gear down, and forward velocity along the
%   heading vector. Throttle is set to a cruise value.
%
%   Edit the values inside the "EDIT THESE VALUES" block below, then
%   just run:
%
%       >> teleport_aircraft

    % ====================================================================
    % EDIT THESE VALUES
    % ====================================================================
    XPCHost  = '127.0.0.1';     % X-Plane host (usually localhost)
    XPCPort  = 49009;           % XPC plugin port

    Altitude = 100;             % m MSL (the original uses 100 for the Piper)
    Speed    = 15;              % m/s true airspeed (Piper cruise ~ 15)
    Heading  = 0;               % deg true: 0=N, 90=E, 180=S, 270=W
    Pitch    = -7;              % deg (nose down so it builds speed cleanly)
    Throttle = 0.49;            % normalized [0, 1]
    Gear     = 1;               % 1 = down (use for fixed-gear/taildraggers),
                                % 0 = up   (only for retractable-gear aircraft)
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

    % Read current lat/lon (we lift the aircraft up at the same horizontal
    % position — no offset, just altitude + velocity).
    drefs_ll = {'sim/flightmodel/position/latitude', ...
                'sim/flightmodel/position/longitude'};
    ll = double(getDREFs(drefs_ll, socket));

    pauseSim(1, socket);
    pause(0.2);

    % POSI: [lat, lon, alt_m, pitch_deg, roll_deg, heading_true_deg, gear]
    sendPOSI([ll(1), ll(2), Altitude, Pitch, 0, Heading, Gear], 0, socket);

    % Initial velocity along the heading vector, in OpenGL local frame.
    % local_vx = East+, local_vy = Up+, local_vz = South+ (so -vz = North).
    hdg_rad = Heading * pi/180;
    sendDREF('sim/flightmodel/position/local_vx',  Speed * sin(hdg_rad), socket);
    sendDREF('sim/flightmodel/position/local_vy',  0,                    socket);
    sendDREF('sim/flightmodel/position/local_vz', -Speed * cos(hdg_rad), socket);

    sendCTRL([0, 0, 0, Throttle, -998, -998], 0, socket);

    pause(0.3);
    pauseSim(0, socket);

    fprintf(['teleport_aircraft: alt=%.0f m, %.0f m/s @ %.0f° hdg, ' ...
             'pitch %.1f°, throttle %.2f, gear %d\n'], ...
            Altitude, Speed, Heading, Pitch, Throttle, Gear);
end
