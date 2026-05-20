function topic = mqtt_topic(callsign)
%MQTT_TOPIC Build the MQTT topic name for a given aircraft callsign.
%   topic = mqtt_topic('PIPER01')  ->  'radar/aircraft/PIPER01/state'
    arguments
        callsign (1,:) char
    end
    topic = sprintf('radar/aircraft/%s/state', upper(strtrim(callsign)));
end
