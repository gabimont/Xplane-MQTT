% start.m  —  Click Run (▶) in MATLAB to put the X-Plane aircraft in the
%              air and begin publishing its position to MQTT.
%
%   The script blocks on a wait loop after starting the publisher, so
%   the MATLAB Stop button (red square ■, next to Run in the toolbar)
%   stays active. Click it (or press Ctrl+C in the command window) to
%   stop the publisher cleanly — `onCleanup` runs `stop_publisher`
%   automatically.
%
%   What to edit:
%     - Callsign / broker / rate           → block below in this file
%     - Initial position / altitude / etc. → block at the top of
%                                            `teleport_aircraft.m`

% ====================================================================
% EDIT PER AIRCRAFT  (different value on each PC)
% ====================================================================
% Unique identifier for THIS PC's aircraft. MUST be different on each
% PC so the tower can tell them apart. The MQTT topic published is
% derived from this:
%
%     radar/aircraft/<CALLSIGN>/state
%
% e.g. CALLSIGN='PIPER01'  → radar/aircraft/PIPER01/state
%      CALLSIGN='CESSNA02' → radar/aircraft/CESSNA02/state
%
% The tower's radar_gui subscribes to radar/aircraft/+/state by default,
% so every running publisher shows up automatically — no extra config
% needed on the tower when you add a new PC.
CALLSIGN = 'PIPER01';

% Optional: also tweak the EDIT block at the top of
% `teleport_aircraft.m` per PC (heading / altitude / N-E offset) so
% the aircraft don't all spawn on top of each other.

% ====================================================================
% SHARED  (keep matching across every PC and the tower)
% ====================================================================
BROKER   = 'tcp://broker.emqx.io';   % broker hostname (with tcp:// or ssl://)
PORT     = 1883;                      % MQTT port
RATE_HZ  = 5;                         % publish rate
% ====================================================================

publisher_loop(CALLSIGN, BROKER, PORT, RATE_HZ);


% ============================  local functions  ============================

function publisher_loop(cs, broker, port, rate_hz)
    % --- Path setup ---
    here = fileparts(mfilename('fullpath'));
    addpath(here);                              % aircraft/
    addpath(fullfile(here, '..', 'common'));    % common/

    % --- Stop any previous publisher cleanly ---
    prev = getappdata(0, 'xplane_mqtt_pub');
    if ~isempty(prev) && isstruct(prev)
        fprintf('start: previous publisher found — stopping it first...\n');
        try
            stop_publisher(prev);
        catch
        end
        setappdata(0, 'xplane_mqtt_pub', []);
    end

    % --- 1) Teleport the aircraft into the air ---
    teleport_aircraft;

    % --- 2) Start the MQTT publisher ---
    pub = start_publisher( ...
        Callsign = cs, ...
        Broker   = broker, ...
        Port     = port, ...
        RateHz   = rate_hz);
    setappdata(0, 'xplane_mqtt_pub', pub);

    % onCleanup fires when the function exits — by normal return,
    % unhandled error, or Stop / Ctrl+C interrupt.
    cleaner = onCleanup(@() try_stop(pub));

    fprintf(['\n>>> Publisher running.\n' ...
             '>>> Click STOP (red square ■) in the MATLAB toolbar ' ...
             'to stop.\n\n']);

    % Block here until interrupted. pause(1) yields to the event
    % queue so the publisher timer (5 Hz default) keeps firing.
    try
        while true
            pause(1);
        end
    catch
        % Caught Ctrl+C / Stop button — cleanup runs after this.
    end
end

function try_stop(pub)
    fprintf('\nstop: shutting down publisher...\n');
    try
        stop_publisher(pub);
    catch
    end
    setappdata(0, 'xplane_mqtt_pub', []);
    fprintf('stop: done.\n');
end
