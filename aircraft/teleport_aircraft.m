function teleport_aircraft(opts)
%TELEPORT_AIRCRAFT Standalone: put the X-Plane aircraft in the air with
%   an initial velocity, then disconnect. Run this BEFORE start_publisher
%   so the aircraft is already flying when MQTT broadcasts start.
%
%   teleport_aircraft()                                  % defaults
%   teleport_aircraft(OffsetNorthKm=10, Heading=270)     % custom
%   teleport_aircraft(Altitude=1500, Speed=70)           % higher / faster
%
%   Defaults: 5 km North of current position, 1000 m AMSL, 50 m/s, heading
%   90° (East), throttle 0.6. The throttle + velocity keep the aircraft
%   flying so it doesn't stall and fall right after the teleport.
%
%   Opens its own XPC connection and closes it on exit; no MQTT involved.

    arguments
        opts.XPCHost        (1,:) char    = '127.0.0.1'
        opts.XPCPort        (1,1) double  = 49009
        opts.OffsetNorthKm  (1,1) double  = 5
        opts.OffsetEastKm   (1,1) double  = 0
        opts.Altitude       (1,1) double  = 1000
        opts.Speed          (1,1) double  = 50
        opts.Heading        (1,1) double  = 90
        opts.Throttle       (1,1) double  = 0.6
    end

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

    fprintf('teleport_aircraft: opening XPC at %s:%d ...\n', opts.XPCHost, opts.XPCPort);
    socket = openUDP(opts.XPCHost, opts.XPCPort);

    cleaner = onCleanup(@() closeUDP(socket));

    position_aircraft(socket, ...
        OffsetNorthKm = opts.OffsetNorthKm, ...
        OffsetEastKm  = opts.OffsetEastKm,  ...
        Altitude      = opts.Altitude,      ...
        Speed         = opts.Speed,         ...
        Heading       = opts.Heading,       ...
        Throttle      = opts.Throttle);

    fprintf('teleport_aircraft: done. Now run start_publisher to broadcast MQTT.\n');
end
