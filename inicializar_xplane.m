%% inicializar_xplane.m - Inicializacao para integracao com X-Plane
% Carrega todos os ganhos PID e parametros via inicializar.m,
% depois configura paths e variaveis especificas do X-Plane.
%
% Uso:
%   1) >> inicializar_xplane
%   2) >> criar_modelo_xplane   (apenas na primeira vez, gera o .slx)
%   3) >> open('Xplane/xplane_autopilot.slx')
%   4) Iniciar X-Plane com Piper J-3 Cub
%   5) Simular (Ctrl+T)

%% ========== Carregar base (ganhos, Xe, Ue, matrizes, etc.) ==========
% Salvar dir atual via setenv (sobrevive ao 'clear' do inicializar.m)
setenv('XPLANE_INIT_OLDDIR', pwd);
rootDir_ = fileparts(fileparts(mfilename('fullpath')));
cd(rootDir_);
inicializar;   % Faz clear/clc - apaga todo o workspace
% Recuperar apos o clear
cd(getenv('XPLANE_INIT_OLDDIR'));
setenv('XPLANE_INIT_OLDDIR', '');
rootDir = fileparts(fileparts(which('inicializar_xplane')));

%% ========== Paths do XPlaneConnect ==========
addpath(fullfile(rootDir, 'Xplane', 'XPlaneConnect-master', 'MATLAB'));
addpath(fullfile(rootDir, 'Xplane'));

%% ========== Limpar conexao anterior ==========
global GlobalSocket;
if ~isempty(GlobalSocket)
    try
        import XPlaneConnect.*;
        closeUDP(GlobalSocket);
        disp('inicializar_xplane: Conexao anterior fechada.');
    catch
    end
end
GlobalSocket = [];

%% ========== Parametros do X-Plane ==========
Ts_xplane = 0.05;  % Sample time: 20 Hz (ajustar se necessario)

%% ========== Referencias manuais (modo sem guiagem) ==========
h_ref   = -Xe(12);   % altitude de equilibrio (100 m)
VT_ref  = Xe(1);     % velocidade de equilibrio (15 m/s)
psi_ref = 0;         % proa inicial (rad)

%% ========== Pronto ==========
disp(' ');
disp('=== Workspace carregado para X-Plane ===');
disp(['  Sample time: ' num2str(Ts_xplane) ' s (' num2str(1/Ts_xplane) ' Hz)']);
disp(['  h_ref:  ' num2str(h_ref) ' m']);
disp(['  VT_ref: ' num2str(VT_ref) ' m/s']);
disp(['  psi_ref: ' num2str(rad2deg(psi_ref)) ' deg']);
disp(' ');
disp('  Proximo passo: abrir xplane_autopilot.slx e simular');
disp('  (Se primeira vez, rode: criar_modelo_xplane)');
