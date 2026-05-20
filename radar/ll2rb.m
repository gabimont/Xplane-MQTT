function [range_m, bearing_rad] = ll2rb(lat0, lon0, lat, lon)
%LL2RB Convert lat/lon to range (m) and initial bearing (rad, 0=North).
%
%   [r, brg] = ll2rb(lat0, lon0, lat, lon)
%
%   lat0, lon0  = observer (tower) location, degrees, scalar.
%   lat,  lon   = target location, degrees. May be vectors of equal size.
%   range_m     = great-circle distance in meters (Haversine).
%   bearing_rad = initial bearing in radians, [-pi, pi], 0 = North, +pi/2 = East.
%
%   No Mapping Toolbox required.

    R   = 6371000;          % Earth mean radius (m)
    d2r = pi / 180;
    phi0 = lat0 * d2r;
    phi  = lat  * d2r;
    dphi = (lat - lat0) * d2r;
    dlam = (lon - lon0) * d2r;

    a = sin(dphi/2).^2 + cos(phi0) .* cos(phi) .* sin(dlam/2).^2;
    range_m = 2 * R * atan2(sqrt(a), sqrt(1 - a));

    y = sin(dlam) .* cos(phi);
    x = cos(phi0) .* sin(phi) - sin(phi0) .* cos(phi) .* cos(dlam);
    bearing_rad = atan2(y, x);
end
