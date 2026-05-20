function close_xplane()
%CLOSE_XPLANE Fecha a conexao UDP com o X-Plane.
%   Chamado automaticamente como StopFcn do modelo Simulink,
%   ou manualmente pelo usuario.

    global GlobalSocket;
    import XPlaneConnect.*;

    if ~isempty(GlobalSocket)
        try
            closeUDP(GlobalSocket);
            disp('close_xplane: Conexao X-Plane fechada.');
        catch
        end
    end
    GlobalSocket = [];

    % Limpar persistent vars do read_xplane (posicao inicial)
    clear read_xplane;
end
