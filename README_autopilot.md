# Autopiloto PIPER J-3 ↔ X-Plane (Simulink, legado)

Setup original do repositório, anterior ao radar MQTT. Mantido aqui
porque os arquivos `xplane_autopilot.slx`, `inicializar_xplane.m`,
`posicionar_xplane.m`, `read_xplane.m`, `send_xplane.m`, `close_xplane.m`
ainda funcionam e demonstram que a mesma malha de controle do
`modeloNL1.slx` pilota o Piper dentro do X-Plane via XPC.

> Para o radar MQTT (uso principal deste repo), veja o
> [README principal](readme.md).

## Como usar

### 1. Instalar o plugin no X-Plane (uma vez)

Copiar `XPlaneConnect-master/Resources/plugins/XPlaneConnect/` para
`X-Plane/Resources/plugins/`. Versão `64/` para X-Plane 11/12.

### 2. (Re)gerar o modelo (opcional, já vem pronto no repo)

```matlab
cd PIPER-1-6-GUI
inicializar
criar_xplane_autopilot
```

### 3. Rodar a simulação

Com o X-Plane aberto no Piper J-3 Cub em uma pista:

```matlab
open('xplane_autopilot.slx')
sim('xplane_autopilot')         % ou Run no Simulink
```

Os callbacks do modelo cuidam de tudo:

- `InitFcn` → `inicializar_xplane` (carrega workspace, abre UDP)
- `StartFcn` → `posicionar_xplane` (pausa sim, teleporta para 100 m / VT=15 / hdg=0, despausa)
- `StopFcn` → `close_xplane` (fecha UDP)

### 4. Alterar referências

Definidas em `inicializar_xplane.m` ou no workspace antes do `sim`:

```matlab
h_ref   = 150;    % altitude (m)
VT_ref  = 18;     % velocidade aerodinâmica (m/s)
psi_ref = pi/4;   % proa (rad)
```

O bloco `controle` lê `h_ref`/`VT_ref` direto do workspace via
`Constant1`/`Constant2` patcheados pelo `criar_xplane_autopilot.m`.

## Arquitetura do modelo

```
┌──────────────┐                                       ┌──────────────┐
│ X-Plane      │   10 sinais   ┌─────────┐ buses      │ controle     │ 4 cmds  ┌──────────┐  ┌──────────────┐
│ Sensors      │──────────────▶│  Demux  │──Goto/From▶│ (subsystem   │────────▶│ Cmd Mux  │─▶│ X-Plane      │
│ (MATLAB Fcn  │               │ + Goto  │ p,q,r,phi, │ copiado do   │ Thr,    │ ordem    │  │ Actuators    │
│  read_xplane)│               └─────────┘ theta,psi, │ modeloNL1)   │ Elev,   │ delta_e/ │  │ (MATLAB Fcn  │
└──────────────┘                           VT,h,xN,xE └──────────────┘ Ail,Rud │ a/r/T    │  │  send_xplane)│
                                                                                └──────────┘  └──────────────┘
```

- **Solver**: `ode4`, `FixedStep = 0.05` s (20 Hz), `EnablePacing='on', PacingRate=1`
  — real-time pacing essencial para casar com o X-Plane.
- **MATLAB Function blocks**: `coder.extrinsic` para `read_xplane`/`send_xplane`,
  com `ChartUpdate='DISCRETE', SampleTime='0.05'` forçado (sem isso o chart
  herda contínuo e é chamado nos sub-passos do RK4).

## Sinais

### Lidos do X-Plane (`read_xplane.m`)

| # | Sinal | DataRef | Conversão |
|---|-------|---------|-----------|
| 1 | VT (m/s) | `true_airspeed` | — |
| 2 | theta (rad) | `theta` | deg→rad |
| 3 | q (rad/s) | `Q` | deg/s→rad/s |
| 4 | h (m) | `elevation` | — |
| 5 | phi (rad) | `phi` | deg→rad |
| 6 | p (rad/s) | `P` | deg/s→rad/s |
| 7 | psi (rad) | `psi` | deg→rad, **wrap [-π,π]** via `atan2(sin,cos)` |
| 8 | r (rad/s) | `R` | deg/s→rad/s |
| 9 | xN (m) | `-local_z` | relativo ao início |
| 10 | xE (m) | `local_x` | relativo ao início |

O wrap em `psi` evita que o X-Plane reportando 360° (≈6.28 rad) gere
erro gigante na malha lateral nos primeiros segundos (saturava o aileron).

### Enviados ao X-Plane (`send_xplane.m`)

| # | Comando | Faixa | Conversão |
|---|---------|-------|-----------|
| 1 | delta_e | ±0.4363 rad | / 0.4363 → [−1,+1] |
| 2 | delta_a | ±0.4363 rad | / 0.4363 → [−1,+1] |
| 3 | delta_r | ±0.4363 rad | / 0.4363 → [−1,+1] |
| 4 | delta_T | [0,1] | — |

## Comunicação

- UDP `127.0.0.1:49009`
- `GlobalSocket` (variável global) compartilhada entre `read_xplane` /
  `send_xplane` / `posicionar_xplane`
- Valores não usados → `-998` (convenção XPC)

## Solução de problemas

- **Aeronave cai nos primeiros segundos**: confirmar que o `psi` está
  sendo wrapeado em `read_xplane.m` e que o `StartFcn` está como
  `posicionar_xplane;` (não `InitFcn`, senão a aeronave fica solta
  durante a compilação).
- **Modelo diverge / oscila**: confirmar `EnablePacing='on'`. Sem
  pacing o Simulink roda as-fast-as-possible e o laço com o X-Plane
  diverge.
- **Porta UDP travada**: `clear global GlobalSocket` e rodar de novo.
- **DataRef não encontrado**: trocar `true_airspeed` por
  `indicated_airspeed` em `read_xplane.m`.
