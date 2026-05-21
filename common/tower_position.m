function [lat, lon] = tower_position()
%TOWER_POSITION Single source of truth for the radar tower's lat/lon.
%
%   Both the radar GUI (radar_state.m) and the aircraft teleport
%   (teleport_aircraft.m) read this, so they always agree. Edit the
%   values here to move the tower; no other file needs touching.
%
%   Returns:
%     lat : degrees, +N / -S
%     lon : degrees, +E / -W

    lat = 46.6838;
    lon = -122.9831;
end
