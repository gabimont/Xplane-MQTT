function status = send_xplane(u)
%SEND_XPLANE Envia comandos de controle do autopiloto para o X-Plane.
%
%   status = send_xplane(u)
%
%   Input u (4x1):
%     u(1) = delta_e  - elevator (rad, [-0.4363, +0.4363])
%     u(2) = delta_a  - aileron  (rad, [-0.4363, +0.4363])
%     u(3) = delta_r  - rudder   (rad, [-0.4363, +0.4363])
%     u(4) = delta_T  - throttle ([0, 1])
%
%   Converte de radianos para normalizado [-1, 1] antes de enviar.
%   Usa variavel global GlobalSocket (compartilhada com read_xplane).

    global GlobalSocket;
    import XPlaneConnect.*;

    status = 0;

    % --- Abrir conexao se necessario ---
    if isempty(GlobalSocket)
        try
            GlobalSocket = openUDP('127.0.0.1', 49009);
            disp('send_xplane: Conexao X-Plane aberta.');
        catch
            return;
        end
    end

    % --- Verificar socket valido ---
    if ~isa(GlobalSocket, 'gov.nasa.xpc.XPlaneConnect')
        return;
    end

    % --- Converter e enviar ---
    try
        max_deflection = 0.4363;  % 25 deg em rad

        elevator = u(1) / max_deflection;
        aileron  = u(2) / max_deflection;
        rudder   = u(3) / max_deflection;
        throttle = u(4);

        % Clamp para faixa valida
        elevator = max(-1, min(1, elevator));
        aileron  = max(-1, min(1, aileron));
        rudder   = max(-1, min(1, rudder));
        throttle = max(0, min(1, throttle));

        % XPC: [elevator, aileron, rudder, throttle, gear, flaps]
        % -998 = "nao alterar"
        ctrl_data = [elevator, aileron, rudder, throttle, -998, -998];

        sendCTRL(ctrl_data, 0, GlobalSocket);
        status = 1;
    catch ME
        disp(['send_xplane: Erro no envio - ' ME.message]);
    end
end
