function state = radar_state()
%RADAR_STATE Build the initial state struct for the radar GUI.
%   Contains broker config, subscription list, aircraft cache,
%   history (for trails), and display settings.

    state = struct();

    % Broker
    state.broker        = 'tcp://broker.emqx.io';
    state.port          = 1883;
    state.connected     = false;
    state.client        = [];

    % Subscriptions (cell array of topic strings)
    state.subscriptions = {'radar/aircraft/+/state'};

    % Aircraft state: callsign -> last payload struct (with .last timestamp)
    state.aircraft      = containers.Map('KeyType','char','ValueType','any');

    % Trail history: callsign -> struct('lat',[],'lon',[],'alt',[])
    state.history       = containers.Map('KeyType','char','ValueType','any');

    % --- Tower position (HARDCODED) ---
    % The radar plots aircraft positions relative to this fixed point.
    % It does NOT change automatically when aircraft connect. Edit here
    % (or in the GUI's Tower lat/lon fields) to use a different
    % reference point. The "Snap" button still works for an explicit
    % one-shot recenter to an aircraft if you ever want that.
    state.tower_lat     = 46.6838;
    state.tower_lon     = -122.9831;

    % Display
    state.max_range_km  = 25;     % polar axes RLim
    state.trail_len     = 20;     % keep last N samples per aircraft

    % Stale / drop timing (seconds)
    state.stale_sec     = 10;     % grey out after this
    state.drop_sec      = 60;     % forget after this
end
