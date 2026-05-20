function stop_publisher(pub)
%STOP_PUBLISHER Stop the publisher timer and close XPC connection.
%
%   stop_publisher(pub)
%
%   `pub` is the struct returned by start_publisher.

    arguments
        pub (1,1) struct
    end

    if isfield(pub, 'timer') && isa(pub.timer, 'timer') && isvalid(pub.timer)
        stop(pub.timer);
        delete(pub.timer);
    end

    if isfield(pub, 'socket') && ~isempty(pub.socket)
        try
            import XPlaneConnect.*
            closeUDP(pub.socket);
        catch ME
            warning('stop_publisher:CloseUDP', '%s', ME.message);
        end
    end

    fprintf('stop_publisher: %s stopped.\n', pub.callsign);
end
