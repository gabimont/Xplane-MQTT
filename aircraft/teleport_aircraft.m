function teleport_aircraft()
%TELEPORT_AIRCRAFT Standalone: put the X-Plane aircraft in the air with
%   an initial velocity, then disconnect. Run this BEFORE start_publisher
%   so the aircraft is already flying when MQTT broadcasts start.
%
%   Edit the values inside the "EDIT THESE VALUES" block below to
%   change the teleport, then just call:
%
%       >> teleport_aircraft
%
%   The throttle + velocity together keep the aircraft cruising so it
%   does not stall and fall right after the teleport.

    % ====================================================================
    % EDIT THESE VALUES
    % ====================================================================
    XPCHost       = '127.0.0.1';     % X-Plane host (usually localhost)
    XPCPort       = 49009;           % XPC plugin port

    OffsetNorthKm = 5;               % km north of spawn (use negative for south)
    OffsetEastKm  = 0;               % km east  of spawn (use negative for west)
    Altitude      = 1000;            % m MSL
    Speed         = 50;              % m/s true airspeed
    Heading       = 90;              % deg true: 0=N, 90=E, 180=S, 270=W
    Throttle      = 0.6;             % normalized [0, 1]
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

    position_aircraft(socket, ...
        OffsetNorthKm = OffsetNorthKm, ...
        OffsetEastKm  = OffsetEastKm,  ...
        Altitude      = Altitude,      ...
        Speed         = Speed,         ...
        Heading       = Heading,       ...
        Throttle      = Throttle);

    fprintf('teleport_aircraft: done. Now run start_publisher to broadcast MQTT.\n');
end
