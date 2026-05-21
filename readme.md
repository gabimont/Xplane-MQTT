# X-Plane Integration + Radar MQTT

Dois subsistemas convivem neste repositório:

1. **Autopiloto PIPER-1-6 ↔ X-Plane via XPC** (Simulink, `xplane_autopilot.slx`).
   A mesma malha de controle do `modeloNL1.slx`, agora pilotando a aeronave
   dentro do X-Plane.
2. **Radar MQTT distribuído**. Uma torre (GUI MATLAB) monitora N aeronaves;
   cada uma roda X-Plane + MATLAB em outra máquina e publica sua posição
   via MQTT. Veja [radar/README_radar.md](radar/README_radar.md) e
   [aircraft/README_publisher.md](aircraft/README_publisher.md).

## Estrutura

```
Xplane-MQTT/
├── xplane_autopilot.slx        # Autopiloto: controle + bridge UDP (Simulink)
├── inicializar_xplane.m        # InitFcn: ganhos, refs, paths XPC, abre UDP
├── posicionar_xplane.m         # StartFcn: teleporta a aeronave
├── close_xplane.m              # StopFcn: fecha conexao UDP
├── read_xplane.m               # Le 10 sensores via getDREFs
├── send_xplane.m               # Envia [delta_e, delta_a, delta_r, delta_T]
├── XPlaneConnect-master/       # Biblioteca XPC (API MATLAB + plugins)
│
├── radar/                      # Lado torre (Mac): GUI PPI subscrita em MQTT
│   ├── radar_gui.m
│   ├── radar_state.m
│   ├── ll2rb.m
│   └── README_radar.md
├── aircraft/                   # Lado aeronave (Windows): publisher X-Plane→MQTT
│   ├── start_publisher.m
│   ├── publish_aircraft.m
│   ├── stop_publisher.m
│   └── README_publisher.md
└── common/
    └── mqtt_topic.m            # Convenção de nome de tópico
```

## Radar MQTT em uma linha

- **Mac (torre)**: `addpath('radar'); radar_gui`
- **Windows (aeronave, com X-Plane aberto)**: `addpath('aircraft'); pub = start_publisher(Callsign='PIPER01');`
- Broker default: `tcp://broker.emqx.io:1883` (público, sem credenciais; test.mosquitto.org saía do ar com frequência).
- Tópico: `radar/aircraft/<CALLSIGN>/state`, payload JSON `{lat, lon, alt, hdg, vt, ts, callsign}`.

Para o autopiloto Simulink → segue inalterado, instruções abaixo.

## Como usar

### 1. Instalar o plugin no X-Plane (uma vez)
Copiar `XPlaneConnect-master/Resources/plugins/XPlaneConnect/` para
`X-Plane/Resources/plugins/`. Versao `64/` para X-Plane 11/12.

### 2. (Re)gerar o modelo (opcional, ja vem pronto no repo)
```matlab
cd PIPER-1-6-GUI
inicializar          % carrega ganhos, Ue, Xe, refs
criar_xplane_autopilot
```

### 3. Rodar a simulacao
Com o X-Plane aberto no Piper J-3 Cub em uma pista:
```matlab
open('Xplane/xplane_autopilot.slx')
sim('xplane_autopilot')         % ou Run no Simulink
```

Os callbacks do modelo cuidam de tudo:
- `InitFcn` → `inicializar_xplane` (carrega workspace, abre UDP)
- `StartFcn` → `posicionar_xplane` (pausa sim, teleporta para 100 m / VT=15 / hdg=0, despausa)
- `StopFcn` → `close_xplane` (fecha UDP)

### 4. Alterar referencias
Definidas em `inicializar_xplane.m` ou no workspace antes do `sim`:
```matlab
h_ref   = 150;    % altitude (m)
VT_ref  = 18;     % velocidade aerodinamica (m/s)
psi_ref = pi/4;   % proa (rad)
```
O bloco `controle` le `h_ref`/`VT_ref` direto do workspace via `Constant1`/`Constant2`
patcheados pelo `criar_xplane_autopilot.m`.

## Arquitetura do modelo

```
              ┌──────────────┐                                      ┌──────────────┐
              │ X-Plane      │   10 sinais   ┌─────────┐ buses     │ controle     │ 4 cmds  ┌──────────┐  ┌──────────────┐
              │ Sensors      │──────────────▶│  Demux  │──Goto/From▶│ (subsystem   │────────▶│ Cmd Mux  │─▶│ X-Plane      │
              │ (MATLAB Fcn  │               │ + Goto  │ p,q,r,phi, │ copiado do   │ Thr,    │ ordem    │  │ Actuators    │
              │  read_xplane)│               └─────────┘ theta,psi, │ modeloNL1)   │ Elev,   │ delta_e/ │  │ (MATLAB Fcn  │
              └──────────────┘                           VT,h,xN,xE └──────────────┘ Ail,Rud │ a/r/T    │  │  send_xplane)│
                                                                                              └──────────┘  └──────────────┘
```

- **Solver**: `ode4`, `FixedStep = 0.05` s (20 Hz), `EnablePacing='on', PacingRate=1`
  (real-time pacing essencial para casar com o X-Plane).
- **MATLAB Function blocks**: `coder.extrinsic` para `read_xplane`/`send_xplane`,
  com `ChartUpdate='DISCRETE', SampleTime='0.05'` forcado (lição do HIL: caso contrario
  o chart herda contínuo e e chamado nos sub-passos do RK4).
- **Goto/From**: sensores em laranja, comandos em ciano, para layout limpo.
- **Reuso do `controle`**: copiado uma vez do `modeloNL1.slx` pelo build script.
  As unicas modificacoes: `Constant1`→`h_ref`, `Constant2`→`VT_ref`, e zeramento
  de `Elevator_eq`/`Aileron_eq`/`Rudder_eq` (mantem `Throttle_eq=Ue(1)`).

## Sinais

### Lidos do X-Plane (`read_xplane.m`)
| # | Sinal | DataRef | Conversao |
|---|-------|---------|-----------|
| 1 | VT (m/s) | `true_airspeed` | — |
| 2 | theta (rad) | `theta` | deg→rad |
| 3 | q (rad/s) | `Q` | deg/s→rad/s |
| 4 | h (m) | `elevation` | — |
| 5 | phi (rad) | `phi` | deg→rad |
| 6 | p (rad/s) | `P` | deg/s→rad/s |
| 7 | psi (rad) | `psi` | deg→rad, **wrap [-π,π]** via `atan2(sin,cos)` |
| 8 | r (rad/s) | `R` | deg/s→rad/s |
| 9 | xN (m) | `-local_z` | relativo ao inicio |
| 10 | xE (m) | `local_x` | relativo ao inicio |

O wrap em `psi` evita que o X-Plane reportando 360° (≈6.28 rad) gere erro
gigante na malha lateral nos primeiros segundos (saturava o aileron).

### Enviados ao X-Plane (`send_xplane.m`)
| # | Comando | Faixa | Conversao |
|---|---------|-------|-----------|
| 1 | delta_e | ±0.4363 rad | / 0.4363 → [−1,+1] |
| 2 | delta_a | ±0.4363 rad | / 0.4363 → [−1,+1] |
| 3 | delta_r | ±0.4363 rad | / 0.4363 → [−1,+1] |
| 4 | delta_T | [0,1] | — |

## Comunicacao

- UDP `127.0.0.1:49009`
- `GlobalSocket` (variavel global) compartilhada entre `read_xplane`/`send_xplane`/`posicionar_xplane`
- Valores nao usados → `-998` (convencao XPC)

## Solucao de problemas

- **Aeronave cai nos primeiros segundos**: confirmar que o `psi` esta sendo wrapeado em `read_xplane.m` e que o `StartFcn` esta como `posicionar_xplane;` (nao `InitFcn`, senao a aeronave fica solta durante a compilacao).
- **Modelo diverge / oscila**: confirmar `EnablePacing='on'`. Sem pacing o Simulink roda as-fast-as-possible e o laco com o X-Plane diverge.
- **Porta UDP travada**: `clear global GlobalSocket` e rodar de novo.
- **DataRef nao encontrado**: trocar `true_airspeed` por `indicated_airspeed` em `read_xplane.m`.

## Dependencias
- MATLAB R2025a + Simulink
- X-Plane 11 ou 12
- Plugin XPlaneConnect (incluso)
