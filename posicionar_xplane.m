function posicionar_xplane()
%POSICIONAR_XPLANE Teleporta a aeronave para a condicao inicial de voo
%   (100 m, VT=15 m/s, heading=Norte, pitch=-7 deg).
%   Reproduz o trecho de inicializacao do teste_autopiloto.m.

    global GlobalSocket;
    import XPlaneConnect.*;

    if isempty(GlobalSocket)
        try
            GlobalSocket = openUDP('127.0.0.1', 49009);
        catch ME
            disp(['posicionar_xplane: falha ao conectar - ' ME.message]);
            return;
        end
    end

    try
        drefs_ll = {'sim/flightmodel/position/latitude', ...
                    'sim/flightmodel/position/longitude'};
        ll = double(getDREFs(drefs_ll, GlobalSocket));

        pauseSim(1, GlobalSocket);
        pause(0.2);

        hdg = 0;  % Norte
        sendPOSI([ll(1), ll(2), 100, -7, 0, hdg, 1], 0, GlobalSocket);

        VT0 = 15; hdg_rad = hdg * pi/180;
        sendDREF('sim/flightmodel/position/local_vx',  VT0*sin(hdg_rad), GlobalSocket);
        sendDREF('sim/flightmodel/position/local_vy',  0,                GlobalSocket);
        sendDREF('sim/flightmodel/position/local_vz', -VT0*cos(hdg_rad), GlobalSocket);
        sendCTRL([0, 0, 0, 0.49, -998, -998], 0, GlobalSocket);

        pause(0.2);
        pauseSim(0, GlobalSocket);

        % Limpar persistent vars (xN0/xE0) para reiniciar refs de posicao
        clear read_xplane;

        disp('posicionar_xplane: aeronave em 100m, VT=15m/s, hdg=0.');
    catch ME
        disp(['posicionar_xplane: erro - ' ME.message]);
    end
end
