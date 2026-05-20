# X-Plane Integration

Integracao do autopiloto PIPER-1-6 com o X-Plane via plugin XPlaneConnect (XPC).
O autopiloto roda dentro de um modelo Simulink (`xplane_autopilot.slx`) que reusa
o mesmo subsystem `controle` ja validado no `controle/Não Linear/modeloNL1.slx`,
demonstrando que a mesma malha funciona em diferentes plantas (linear, NL, X-Plane).

## Estrutura

```
Xplane/
├── xplane_autopilot.slx        # Modelo Simulink: controle + bridge UDP
├── criar_xplane_autopilot.m    # Script que (re)gera o .slx do zero
├── inicializar_xplane.m        # InitFcn: ganhos, refs, paths XPC, abre UDP
├── posicionar_xplane.m         # StartFcn: teleporta a aeronave (100 m, 15 m/s, hdg=0)
├── close_xplane.m              # StopFcn: fecha conexao UDP
├── read_xplane.m               # Le 10 sensores via getDREFs (chamado pelo bloco MATLAB Fcn)
├── send_xplane.m               # Envia [delta_e, delta_a, delta_r, delta_T] via sendCTRL
└── XPlaneConnect-master/       # Biblioteca XPC (API MATLAB + plugins)
    ├── MATLAB/+XPlaneConnect/
    └── Resources/plugins/      # win.xpl / lin.xpl / mac.xpl
```

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
