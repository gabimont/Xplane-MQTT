function publish_aircraft(state)
%PUBLISH_AIRCRAFT Read X-Plane state via XPC and publish to MQTT.
%   Called periodically by the timer started in start_publisher.
%
%   state is a struct with fields:
%     callsign (char), topic (char), socket (XPC handle), mqtt (mqttclient)

    import XPlaneConnect.*

    try
        drefs = {
            'sim/flightmodel/position/latitude'      % deg
            'sim/flightmodel/position/longitude'     % deg
            'sim/flightmodel/position/elevation'     % m MSL
            'sim/flightmodel/position/psi'           % deg
            'sim/flightmodel/position/true_airspeed' % m/s
        };
        r = double(getDREFs(drefs, state.socket));

        d2r = pi/180;
        psi = r(4) * d2r;
        psi = atan2(sin(psi), cos(psi));   % wrap [-pi, pi]

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
