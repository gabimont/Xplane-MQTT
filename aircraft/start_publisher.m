function pub = start_publisher(opts)
%START_PUBLISHER Begin publishing X-Plane aircraft state to MQTT.
%
%   pub = start_publisher()
%   pub = start_publisher(Callsign='CESSNA02', RateHz=10)
%   pub = start_publisher(Broker='tcp://broker.hivemq.com', Port=1883, ...)
%
%   Returns a handle struct. Use stop_publisher(pub) to clean up.
%
%   Requires:
%     - X-Plane running with XPlaneConnect plugin installed
%     - XPlaneConnect MATLAB API on the path (or in ../XPlaneConnect-master/MATLAB)
%     - Industrial Communication Toolbox (mqttclient)

    arguments
        opts.Broker         (1,:) char    = 'tcp://broker.emqx.io'
        opts.Port           (1,1) double  = 1883
        opts.Callsign       (1,:) char    = 'PIPER01'
        opts.RateHz         (1,1) double  = 5
        opts.XPCHost        (1,:) char    = '127.0.0.1'
        opts.XPCPort        (1,1) double  = 49009

        % --- Optional initial teleport + velocity (default ON) ---
        % After publishing one snap message at the spawn position (so the
        % tower can auto-snap there), teleport the aircraft to spawn +
        % offset and give it initial velocity along the heading vector.
        % Set Teleport=false to disable and start flying manually instead.
        opts.Teleport       (1,1) logical = true
        opts.OffsetNorthKm  (1,1) double  = 5
        opts.OffsetEastKm   (1,1) double  = 0
        opts.InitialAlt     (1,1) double  = 1000   % m MSL
        opts.InitialSpeed   (1,1) double  = 50     % m/s
        opts.InitialHeading (1,1) double  = 90     % deg true (0=N, 90=E)
        opts.InitialThrottle (1,1) double = 0.6
    end

    % --- Paths ---
    here = fileparts(mfilename('fullpath'));
    repo = fileparts(here);
    xpcMatlab = fullfile(repo, 'XPlaneConnect-master', 'MATLAB');
    if exist(xpcMatlab, 'dir')
        addpath(xpcMatlab);
    end
    addpath(fullfile(repo, 'common'));

    if isempty(which('XPlaneConnect.openUDP')) && isempty(which('openUDP'))
        error('start_publisher:NoXPC', ...
              ['XPlaneConnect API not found on path. Expected ' ...
               '+XPlaneConnect/openUDP.m under %s or anywhere on the MATLAB ' ...
               'path. Tried adding: %s'], ...
              xpcMatlab, xpcMatlab);
    end

    % --- X-Plane (XPC) ---
    import XPlaneConnect.*
    fprintf('start_publisher: connecting to X-Plane at %s:%d ...\n', opts.XPCHost, opts.XPCPort);
    socket = openUDP(opts.XPCHost, opts.XPCPort);

    % --- MQTT ---
    fprintf('start_publisher: connecting to MQTT broker %s:%d ...\n', opts.Broker, opts.Port);
    mqtt = mqttclient(opts.Broker, Port=opts.Port);

    callsign = upper(strtrim(opts.Callsign));
    topic    = mqtt_topic(callsign);

    state = struct( ...
        'callsign', callsign, ...
        'topic',    topic, ...
        'socket',   socket, ...
        'mqtt',     mqtt);

    % --- Snap message at spawn position so the tower can auto-snap there ---
    % Send one publish BEFORE teleporting; gives the tower (if already
    % connected) ~0.5s to receive and snap to the runway position.
    publish_aircraft(state);
    pause(0.5);

    % --- Optional teleport + initial velocity ---
    if opts.Teleport
        position_aircraft(socket, ...
            OffsetNorthKm = opts.OffsetNorthKm, ...
            OffsetEastKm  = opts.OffsetEastKm, ...
            Altitude      = opts.InitialAlt, ...
            Speed         = opts.InitialSpeed, ...
            Heading       = opts.InitialHeading, ...
            Throttle      = opts.InitialThrottle);
    end

    % --- Timer ---
    T = timer( ...
        'Name',          sprintf('xplane_mqtt_pub_%s', callsign), ...
        'Period',        1/opts.RateHz, ...
        'ExecutionMode', 'fixedRate', ...
        'BusyMode',      'drop', ...
        'TimerFcn',      @(~,~) publish_aircraft(state));

    pub = struct( ...
        'timer',    T, ...
        'socket',   socket, ...
        'mqtt',     mqtt, ...
        'topic',    topic, ...
        'callsign', callsign);

    start(T);
    fprintf('start_publisher: publishing %s -> %s at %g Hz\n', ...
            callsign, topic, opts.RateHz);
    fprintf('  Use stop_publisher(pub) to stop.\n');
end
