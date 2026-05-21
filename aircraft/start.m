% start.m  —  Click Run (▶) in MATLAB to put the X-Plane aircraft in the
%              air and begin publishing its position to MQTT.
%
%   When the small dialog window pops up, the publisher is running.
%   Close the dialog (X button) to stop the publisher cleanly.
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
setappdata(0, 'xplane_mqtt_pub', pub);

% --- Block here until the user closes the dialog ---
msg = sprintf([ ...
    'Publishing aircraft state to MQTT.\n\n' ...
    'Callsign : %s\n' ...
    'Topic    : %s\n' ...
    'Broker   : %s:%d\n' ...
    'Rate     : %g Hz\n\n' ...
    'Close this window (or click OK) to STOP the publisher.'], ...
    pub.callsign, pub.topic, BROKER, PORT, RATE_HZ);
uiwait(msgbox(msg, 'X-Plane MQTT Publisher', 'modal'));

% --- User closed the dialog: shut down ---
fprintf('\nstop: shutting down publisher...\n');
try
    stop_publisher(pub);
catch ME
    warning('start:StopFailed', '%s', ME.message);
end
setappdata(0, 'xplane_mqtt_pub', []);
fprintf('stop: done.\n');
