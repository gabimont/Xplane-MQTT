function position_aircraft(socket, opts)
%POSITION_AIRCRAFT Teleport aircraft to spawn + offset with initial velocity.
%
%   position_aircraft(socket)
%   position_aircraft(socket, OffsetNorthKm=10, Heading=270)
%
%   Reads current lat/lon (treated as spawn), computes target lat/lon by
%   adding OffsetNorthKm / OffsetEastKm, then:
%     - pauseSim
%     - sendPOSI to the new position with given heading + altitude
%     - sendDREF on local_vx/vy/vz to give the aircraft initial velocity
%       along the heading vector (OpenGL frame: vx=E, vy=Up, vz=S)
%     - sendCTRL with cruise throttle
%     - unpauseSim
%
%   Designed to be called by start_publisher (Teleport=true), but works
%   standalone too — just hand it the XPC socket returned by openUDP.

    arguments
        socket
        opts.OffsetNorthKm  (1,1) double = 5      % km north of spawn
        opts.OffsetEastKm   (1,1) double = 0      % km east of spawn
        opts.Altitude       (1,1) double = 1000   % m MSL
        opts.Speed          (1,1) double = 50     % m/s true airspeed
        opts.Heading        (1,1) double = 90     % deg true (0=N, 90=E)
        opts.Throttle       (1,1) double = 0.6
    end

    import XPlaneConnect.*

    drefs_ll = {'sim/flightmodel/position/latitude', ...
                'sim/flightmodel/position/longitude'};
    ll = double(getDREFs(drefs_ll, socket));
    lat0 = ll(1); lon0 = ll(2);

    % 1 deg latitude ≈ 111 km; 1 deg longitude ≈ 111·cos(lat) km
    dLat = opts.OffsetNorthKm / 111.0;
    dLon = opts.OffsetEastKm  / (111.0 * cosd(lat0));
    lat1 = lat0 + dLat;
    lon1 = lon0 + dLon;

    pauseSim(1, socket);
    pause(0.2);

    % POSI: [lat, lon, alt_m, pitch_deg, roll_deg, heading_true_deg, gear]
    sendPOSI([lat1, lon1, opts.Altitude, 0, 0, opts.Heading, 0], 0, socket);

    % Initial velocity along the heading vector, in OpenGL local frame.
    hdg_rad = opts.Heading * pi/180;
    sendDREF('sim/flightmodel/position/local_vx',  opts.Speed * sin(hdg_rad), socket);
    sendDREF('sim/flightmodel/position/local_vy',  0, socket);
    sendDREF('sim/flightmodel/position/local_vz', -opts.Speed * cos(hdg_rad), socket);

    % Cruise throttle so the aircraft keeps flying.
    sendCTRL([0, 0, 0, opts.Throttle, -998, -998], 0, socket);

    pause(0.3);
    pauseSim(0, socket);

    fprintf(['position_aircraft: spawn (%.4f, %.4f) → target (%.4f, %.4f); ' ...
             'offset = %.1f km N, %.1f km E; alt=%.0f m, %.0f m/s @ %.0f°\n'], ...
            lat0, lon0, lat1, lon1, ...
            opts.OffsetNorthKm, opts.OffsetEastKm, ...
            opts.Altitude, opts.Speed, opts.Heading);
end
