function sensors = read_xplane(~)
%READ_XPLANE Le o estado da aeronave no X-Plane via XPlaneConnect.
%
%   sensors = read_xplane(dummy)
%
%   Output (1x10):
%     sensors(1)  = VT    - velocidade aerodinamica (m/s)
%     sensors(2)  = theta - arfagem (rad)
%     sensors(3)  = q     - taxa de arfagem (rad/s)
%     sensors(4)  = h     - altitude MSL (m)
%     sensors(5)  = phi   - rolamento (rad)
%     sensors(6)  = p     - taxa de rolamento (rad/s)
%     sensors(7)  = psi   - proa (rad)
%     sensors(8)  = r     - taxa de guinada (rad/s)
%     sensors(9)  = xN    - posicao Norte relativa ao inicio (m)
%     sensors(10) = xE    - posicao Leste relativa ao inicio (m)
%
%   Usa variavel global GlobalSocket (compartilhada com send_xplane).
%   Posicao e relativa ao ponto onde a simulacao iniciou.

    global GlobalSocket;
    import XPlaneConnect.*;

    persistent xN0 xE0 initialized;

    sensors = zeros(1, 10);

    % --- Abrir conexao se necessario ---
    if isempty(GlobalSocket)
        try
            GlobalSocket = openUDP('127.0.0.1', 49009);
            disp('read_xplane: Conexao X-Plane aberta.');
        catch ME
            disp(['read_xplane: Falha ao conectar - ' ME.message]);
            return;
        end
    end

    % --- Verificar socket valido ---
    if ~isa(GlobalSocket, 'gov.nasa.xpc.XPlaneConnect')
        return;
    end

    % --- Ler DataRefs ---
    try
        drefs = {
            'sim/flightmodel/position/true_airspeed',  % 1: VT (m/s)
            'sim/flightmodel/position/theta',          % 2: pitch (deg)
            'sim/flightmodel/position/Q',              % 3: pitch rate (deg/s)
            'sim/flightmodel/position/elevation',      % 4: altitude MSL (m)
            'sim/flightmodel/position/phi',            % 5: roll (deg)
            'sim/flightmodel/position/P',              % 6: roll rate (deg/s)
            'sim/flightmodel/position/psi',            % 7: heading (deg)
            'sim/flightmodel/position/R',              % 8: yaw rate (deg/s)
            'sim/flightmodel/position/local_x',        % 9: posicao X OpenGL (East)
            'sim/flightmodel/position/local_z'         % 10: posicao Z OpenGL (South)
        };

        % getDREFs retorna single array (nao cell) — usar indexacao ()
        result = double(getDREFs(drefs, GlobalSocket));

        d2r = pi / 180;

        VT    = result(1);
        theta = result(2) * d2r;
        q     = result(3) * d2r;
        h     = result(4);
        phi   = result(5) * d2r;
        p     = result(6) * d2r;
        psi   = result(7) * d2r;
        psi   = atan2(sin(psi), cos(psi));  % wrap p/ [-pi,pi]
        r     = result(8) * d2r;

        % Posicao OpenGL -> NED (verificado empiricamente)
        % local_x = East, local_z = South (diminui voando Norte)
        xE_abs = result(9);
        xN_abs = -result(10);

        % Posicao relativa ao ponto inicial
        if isempty(initialized)
            xN0 = xN_abs;
            xE0 = xE_abs;
            initialized = true;
            disp(['read_xplane: Posicao inicial capturada (N=' ...
                num2str(xN0, '%.1f') ', E=' num2str(xE0, '%.1f') ')']);
        end

        xN = xN_abs - xN0;
        xE = xE_abs - xE0;

        sensors = [VT, theta, q, h, phi, p, psi, r, xN, xE];

    catch ME
        disp(['read_xplane: Erro na leitura - ' ME.message]);
    end
end
