function pub = start_publisher(opts)
%START_PUBLISHER Begin publishing X-Plane aircraft state to MQTT.
%
%   pub = start_publisher()
%   pub = start_publisher(Callsign='CESSNA02', RateHz=10)
%   pub = start_publisher(Broker='tcp://broker.hivemq.com', Port=1883, ...)
%
%   Returns a handle struct. Use stop_publisher(pub) to clean up.
%
%   Requires X-Plane running with the XPlaneConnect plugin loaded, the
%   XPlaneConnect MATLAB API on path (or under ../XPlaneConnect-master/
%   MATLAB), and the Industrial Communication Toolbox (mqttclient).

    arguments
        opts.Broker    (1,:) char    = 'tcp://broker.emqx.io'
        opts.Port      (1,1) double  = 1883
        opts.Callsign  (1,:) char    = 'PIPER01'
        opts.RateHz    (1,1) double  = 5
        opts.XPCHost   (1,:) char    = '127.0.0.1'
        opts.XPCPort   (1,1) double  = 49009
    end

    here = fileparts(mfilename('fullpath'));
    repo = fileparts(here);
    xpcMatlab = fullfile(repo, 'XPlaneConnect-master', 'MATLAB');
    if exist(xpcMatlab, 'dir')
        addpath(xpcMatlab);
    end
    addpath(fullfile(repo, 'common'));

    % `which` (not `exist`) — `exist` doesn't recognize package-scoped
    % names like '+XPlaneConnect.openUDP' so it always returned 0.
    if isempty(which('XPlaneConnect.openUDP')) && isempty(which('openUDP'))
        error('start_publisher:NoXPC', ...
              ['XPlaneConnect API not found on path. Expected ' ...
               '+XPlaneConnect/openUDP.m under %s.'], xpcMatlab);
    end

    import XPlaneConnect.*
    fprintf('start_publisher: connecting to X-Plane at %s:%d ...\n', opts.XPCHost, opts.XPCPort);
    socket = openUDP(opts.XPCHost, opts.XPCPort);

    fprintf('start_publisher: connecting to MQTT broker %s:%d ...\n', opts.Broker, opts.Port);
    mqtt = mqttclient(opts.Broker, Port=opts.Port);

    % Uppercased so the resulting MQTT topic is canonical regardless of
    % how the user typed the callsign.
    callsign = upper(strtrim(opts.Callsign));
    topic    = mqtt_topic(callsign);

    state = struct( ...
        'callsign', callsign, ...
        'topic',    topic, ...
        'socket',   socket, ...
        'mqtt',     mqtt);

    % BusyMode='drop' — if a tick takes longer than 1/RateHz (slow
    % broker or network hiccup), the next tick is skipped rather than
    % queued, so the timer can't fall into a runaway backlog.
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
