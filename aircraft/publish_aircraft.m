function publish_aircraft(state)
%PUBLISH_AIRCRAFT Sample X-Plane and publish one JSON state message.
%   Called by the timer set up in start_publisher. The try/catch
%   swallows transient XPC or MQTT errors so the timer keeps firing
%   instead of dying on a single bad sample.
%
%   state fields:  callsign  topic  socket (XPC)  mqtt (mqttclient)

    import XPlaneConnect.*

    try
        drefs = {
            'sim/flightmodel/position/latitude'      % deg
            'sim/flightmodel/position/longitude'     % deg
            'sim/flightmodel/position/elevation'     % m MSL
            'sim/flightmodel/position/psi'           % deg true
            'sim/flightmodel/position/true_airspeed' % m/s
        };
        r = double(getDREFs(drefs, state.socket));

        psi = atan2(sind(r(4)), cosd(r(4)));

        payload = struct( ...
            'callsign', state.callsign, ...
            'lat',      r(1), ...
            'lon',      r(2), ...
            'alt',      r(3), ...
            'hdg',      psi, ...
            'vt',       r(5), ...
            'ts',       posixtime(datetime('now')));

        write(state.mqtt, state.topic, jsonencode(payload));
    catch ME
        warning('publish_aircraft:Error', '%s', ME.message);
    end
end
