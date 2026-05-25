# X-Plane Radar via MQTT

Sistema distribuído de radar tipo ATC: cada **aeronave** roda em um PC
separado com X-Plane + MATLAB e publica sua posição/heading via MQTT.
Uma **torre** central (GUI MATLAB com PPI estilo radar real e Map
cartesiano) se inscreve no tópico e renderiza todas as aeronaves em
tempo real.

```
   PC aeronave A             ┌──────────────┐              PC torre
   (X-Plane + MATLAB)        │              │              (MATLAB)
                             │              │
   X-Plane ─XPC UDP→ MATLAB ─│─ MQTT pub ──▶│              MATLAB
   (Piper)            │      │              │              radar_gui
                      │      │   broker     │                  │
                      └──────│  broker.emqx │              ┌───┴──┐
                             │              │     ◀ sub ───│ PPI  │
   PC aeronave B             │              │              │ Map  │
   (X-Plane + MATLAB)        │              │              └──────┘
                             │              │
   X-Plane ─XPC UDP→ MATLAB ─│─ MQTT pub ──▶│
   (Cessna)                  │              │
                             └──────────────┘
```

Funciona com 1 aeronave ou N aeronaves simultâneas (cada uma com seu
callsign), através de qualquer broker público — não precisa servidor
próprio.

---

## Início rápido

### Pré-requisitos

| Onde | O que precisa | Notas |
|------|---------------|-------|
| PC torre | MATLAB R2022a+ com **Industrial Communication Toolbox** | só dá pra usar `mqttclient` com ela |
| PC aeronave | mesmas toolboxes + **X-Plane 11/12** + plugin **XPlaneConnect** | plugin vai em `<X-Plane>/Resources/plugins/XPlaneConnect/` |
| Rede | qualquer broker MQTT alcançável dos dois | default: `broker.emqx.io:1883` (público, sem credenciais) |

### Lado torre

```matlab
cd Xplane-MQTT
addpath('radar','common')
radar_gui
```

Na janela: clica **Connect** → indicador vira verde → a subscrição
wildcard `radar/aircraft/+/state` já está pronta. Qualquer aeronave
que publicar aparece automaticamente. Botão **Open Fullscreen** abre
o radar grande em janela própria (com toggle PPI/Map).

### Lado aeronave

Com o X-Plane aberto, aeronave numa pista:

```matlab
cd Xplane-MQTT
addpath('aircraft','common')
% abre aircraft/start.m, edita o CALLSIGN no bloco do topo se quiser,
% e clica em Run (▶) na barra do MATLAB
```

Pra parar: clica em **Stop (■)** na barra do MATLAB (ou Ctrl+C). O
`onCleanup` chama `stop_publisher` automaticamente.

Detalhes da configuração por PC: [aircraft/README_publisher.md](aircraft/README_publisher.md).

---

## Protocolo MQTT

### Tópico

```
radar/aircraft/<CALLSIGN>/state
```

- `<CALLSIGN>` é o identificador único da aeronave (`PIPER01`,
  `CESSNA02`, `GLIDER03`, ...). Sempre **MAIÚSCULAS** — o publisher
  faz `upper(strtrim(...))` antes.
- O template literal vive em **um único lugar**: [common/mqtt_topic.m](common/mqtt_topic.m).
  Mudar o prefixo (`radar/aircraft/`) ali se propaga pros dois lados.

A torre se inscreve com **wildcard MQTT** `+`:

```
radar/aircraft/+/state
```

O `+` casa com qualquer string num único nível, então a torre captura
todas as aeronaves de uma vez, sem precisar saber os callsigns
antecipadamente. Pra filtrar uma aeronave específica, digite o tópico
exato (sem `+`) no campo Topic da GUI.

### Payload (JSON UTF-8)

```json
{
  "callsign": "PIPER01",
  "lat": 46.8248,
  "lon": -123.0380,
  "alt": 152.3,
  "hdg": 0.785,
  "vt":  18.4,
  "ts":  1747780000.123
}
```

| Campo | Tipo | Unidade | Origem (DataRef do X-Plane) |
|-------|------|---------|------------------------------|
| `callsign` | string | — | configurado em `start.m` (`CALLSIGN`) |
| `lat` | double | grau | `sim/flightmodel/position/latitude` |
| `lon` | double | grau | `sim/flightmodel/position/longitude` |
| `alt` | double | m MSL | `sim/flightmodel/position/elevation` |
| `hdg` | double | **rad, wrap [-π, π]** | `sim/flightmodel/position/psi` (deg→rad) |
| `vt` | double | m/s | `sim/flightmodel/position/true_airspeed` |
| `ts` | double | Unix epoch s | `posixtime(datetime('now'))` no PC publisher |

O heading vai em **radianos** wrappeados em `[-π, π]` (não em graus
0–360) pra evitar a descontinuidade em 360°/0° que quebraria cálculos
em loop. A torre converte pra desenhar o triângulo apontado.

`vt` e `ts` são tecnicamente opcionais — uma ferramenta externa
(`mosquitto_pub`, script Python) pode publicar só os 4 campos
essenciais (`callsign`, `lat`, `lon`, `alt`, `hdg`) e a torre ainda
funciona.

### Como simular uma aeronave sem X-Plane

Útil pra testar o radar isoladamente:

```matlab
addpath('common')
c = mqttclient('tcp://broker.emqx.io', Port=1883);
[lat0, lon0] = tower_position();
for k = 1:60
    ang = 2*pi*k/30;
    p = struct('callsign','FAKE01', ...
               'lat', lat0 + 0.05*cos(ang), ...
               'lon', lon0 + 0.05*sin(ang)/cosd(lat0), ...
               'alt', 500, 'hdg', ang+pi/2, 'vt', 50, ...
               'ts', posixtime(datetime('now')));
    write(c, 'radar/aircraft/FAKE01/state', jsonencode(p));
    pause(0.5);
end
clear c
```

Faz uma aeronave fake voar em círculo de 5 km de raio em volta da
torre, 30 s/volta.

---

## Estrutura do repositório

```
Xplane-MQTT/
├── readme.md                       ← este arquivo
│
├── aircraft/        ◀ LADO PUBLISHER (PC com X-Plane)
│   ├── start.m              entry point — 1-click Play, edita CALLSIGN aqui
│   ├── start_publisher.m    abre XPC + MQTT, monta timer
│   ├── publish_aircraft.m   1 tick: lê 5 DataRefs → publica JSON
│   ├── teleport_aircraft.m  põe a aeronave no ar antes do publish começar
│   ├── stop_publisher.m     fecha timer + XPC
│   └── README_publisher.md
│
├── radar/           ◀ LADO TOWER
│   ├── radar_gui.m          GUI principal: PPI + tabela + fullscreen (Map toggle)
│   ├── radar_state.m        factory do struct de estado (defaults)
│   ├── ll2rb.m              Haversine: (lat,lon) ↔ (range_m, bearing_rad)
│   └── README_radar.md
│
├── common/          ◀ COMPARTILHADO entre publisher e torre
│   ├── mqtt_topic.m         "radar/aircraft/%s/state" — único lugar
│   └── tower_position.m     lat/lon hardcoded da torre — único lugar
│
└── XPlaneConnect-master/    biblioteca da NASA (incluída no repo)
```

---

## Configuração — onde mexer em cada coisa

| Quero mudar | Edito |
|-------------|-------|
| **CALLSIGN** da aeronave (1 valor por PC) | `aircraft/start.m`, bloco `EDIT PER AIRCRAFT` |
| **Broker / Port / RateHz** | `aircraft/start.m`, bloco `SHARED` |
| **Onde a aeronave teleporta** (offset em metros da torre) | `aircraft/teleport_aircraft.m`, bloco `EDIT THESE VALUES` |
| **Posição da torre** (lat/lon) | **`common/tower_position.m`** — fonte única, lida por publisher E torre |
| **Prefixo do tópico** (`radar/aircraft/...`) | `common/mqtt_topic.m`, single source of truth |
| **Cor / fonte do PPI, raio default, trail length, stale/drop times** | `radar/radar_state.m` (defaults) e `radar/radar_gui.m` (estilo) |

A "single source of truth" em `common/` garante que aeronave e torre
nunca divergem: editar uma vez, tudo se ajusta.

---

## Resolução de problemas

| Sintoma | Causa provável | Fix |
|---------|---------------|-----|
| `mqttclient` undefined | Industrial Communication Toolbox não instalada | instale via Add-On Explorer; mesma toolbox precisa estar em todos os PCs |
| Status fica `error: Failed to establish a connection` | broker inalcançável ou nome errado | confira broker (deve ter prefixo `tcp://`); teste com `nc -zv broker.emqx.io 1883` |
| Publisher conecta mas radar não mostra nada | tópico ou broker diferentes entre os lados | os dois precisam usar o mesmo prefixo (`radar/aircraft/...`) e o mesmo broker |
| Aeronave aparece longe demais / fora do PPI | torre hardcoded em outro lat/lon que não casa com o X-Plane | edite `common/tower_position.m` pra coords reais do aeroporto onde seu X-Plane carrega |
| Triangle apontando errado | heading sendo enviado em graus em vez de radianos | publisher precisa converter (`atan2(sind, cosd)`) — ferramentas externas devem publicar em radianos `[-π, π]` |
| `XPlaneConnect API not found` no PC aeronave | pasta `+XPlaneConnect/` ausente | clone está incluído em `XPlaneConnect-master/MATLAB/+XPlaneConnect/` — addpath é automático em `start.m` |
| Aeronave cai/crash após teleport | `TargetLat/TargetLon` em cenário não carregado do X-Plane | use `OffsetNorthM=0, OffsetEastM=0` pra teleportar em cima do aeroporto |

---

## Apêndice — links úteis

- **Documentação MQTT MATLAB**: [`mqttclient`](https://www.mathworks.com/help/icomm/ref/mqttclient.html)
- **Brokers públicos** alternativos:
  - `broker.emqx.io` (default neste projeto)
  - `broker.hivemq.com`
  - `test.mosquitto.org` (instável, sai do ar com frequência)
- **XPlaneConnect**: https://github.com/nasa/XPlaneConnect (já vendoreado em `XPlaneConnect-master/`)
- **Repositório**: https://github.com/gabimont/Xplane-MQTT
