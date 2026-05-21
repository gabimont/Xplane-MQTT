% start.m  —  Click Run (▶) in MATLAB to put the X-Plane aircraft in the
%              air and begin publishing its position to MQTT.
%
%   Workflow:
%     1. Open X-Plane with an aircraft on a runway.
%     2. Open this file in the MATLAB editor.
%     3. Press Run (▶) in the toolbar (or F5).
%     4. When you're done, open `stop.m` and press Run.
%
%   What to edit:
%     - Callsign / broker / rate           → block below in this file
%     - Initial position / altitude / etc. → block at the top of
%                                            `teleport_aircraft.m`

% ====================================================================
% EDIT IF NEEDED
% ====================================================================
CALLSIGN = 'PIPER01';
BROKER   = 'tcp://broker.emqx.io';
PORT     = 1883;
RATE_HZ  = 5;
% ====================================================================

% --- Path setup ---
here = fileparts(mfilename('fullpath'));
addpath(here);                                 % aircraft/
addpath(fullfile(here, '..', 'common'));       % common/

% --- If a previous publisher is still alive, stop it cleanly first ---
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
    Callsign = CALLSIGN, ...
    Broker   = BROKER, ...
    Port     = PORT, ...
    RateHz   = RATE_HZ);

% Remember the handle so stop.m can find it
setappdata(0, 'xplane_mqtt_pub', pub);

fprintf('\n>>> Click Run on `stop.m` when you want to stop.\n\n');
