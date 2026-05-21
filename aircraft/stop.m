% stop.m  —  Click Run (▶) in MATLAB to stop the publisher started by start.m.

here = fileparts(mfilename('fullpath'));
addpath(here);

pub = getappdata(0, 'xplane_mqtt_pub');
if isempty(pub) || ~isstruct(pub)
    disp('stop: no publisher running.');
else
    stop_publisher(pub);
    setappdata(0, 'xplane_mqtt_pub', []);
    disp('stop: publisher stopped.');
end
