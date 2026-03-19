# DALI2

> Multi-Agent System Framework built on SWI-Prolog — DALI-compatible syntax, process-based agents

DALI2 is the evolution of the [DALI](https://github.com/AAAI-DISIM-UnivAQ/DALI) multi-agent system framework, now running on SWI-Prolog with DALI-compatible syntax and a process-per-agent architecture.

## Key Features

- **Identical DALI syntax** — no prefix needed, same operators (`:>`, `:<`, `~/`, `</`, `?/`) and suffixes (`E`, `I`, `A`, `N`, `P`) as the original DALI
- **Single-file multi-agent** — define all agents in one `.pl` file; `:- agent(name).` sets the context for subsequent rules
- **Full DALI feature set** — reactive rules, internal events, goals, constraints, learning, ontologies, tell/told filtering, and more
- **Process-per-agent architecture** — each agent runs as a separate OS process
- **Redis star topology** — agents communicate via Redis pub/sub (`LINDA` channel for messages, `LOGS` channel for monitoring)
- **Integrated web UI** — dashboard, log viewer, message sender, agent inspector
- **Docker-ready** — runs in a container with Redis, no local installation needed
- **LAN-ready** — remote machines on the same network just point to the same Redis instance
- **New features** — AI Oracle (ChatGPT), periodic tasks, condition monitors, helpers, blackboard, federation

**Documentation:** [RULES.md](RULES.md) (language reference) · [EXAMPLES.md](EXAMPLES.md) (examples guide)

## Quick Start

### With Docker (recommended)

```sh
# Default (agriculture example, no AI)
docker compose up --build

# Choose agent file (Linux/macOS)
AGENT_FILE=examples/emergency.pl docker compose up --build

# PowerShell
$env:AGENT_FILE="examples/emergency.pl"; docker compose up --build

# With OpenAI API key (Linux/macOS)
OPENAI_API_KEY=sk-your-key docker compose up --build

# PowerShell
$env:OPENAI_API_KEY="sk-your-key"; docker compose up --build
```

Open [http://localhost:8080](http://localhost:8080) in your browser.

### Distributed Mode — Running Agents Across Multiple Devices

DALI2 supports splitting agents from the **same** agent file across multiple nodes.
Each node loads the full file but starts only selected agents via `--agents`.
Nodes discover each other's agents and route messages transparently over HTTP.

Below is a complete walkthrough using the **agriculture** example, splitting 6 agents across 2 nodes.

#### Agent split

| Node | Name | Agents | Role |
|------|------|--------|------|
| Node A | `sensors` | `soil_sensor`, `weather_monitor`, `logger` | Field sensors + logging |
| Node B | `advisors` | `crop_advisor`, `irrigation_controller`, `farmer_agent` | Decision-making |

When `soil_sensor` sends a message to `crop_advisor`, DALI2 automatically forwards it over HTTP to Node B.
When `irrigation_controller` sends to `logger`, it goes back to Node A. No code changes needed.

#### Option 1: Two Docker containers on the same machine

Open **two terminals** and run one container each:

```sh
# Terminal 1 — sensors node (port 8081)
docker run --rm --init -p 8081:8080 \
  -v ./examples:/dali2/examples \
  --name agri-sensors \
  dali2 8080 examples/agriculture.pl --name sensors \
  --agents soil_sensor,weather_monitor,logger

# Terminal 2 — advisors node (port 8082)
docker run --rm --init -p 8082:8080 \
  -v ./examples:/dali2/examples \
  --name agri-advisors \
  dali2 8080 examples/agriculture.pl --name advisors \
  --agents crop_advisor,irrigation_controller,farmer_agent
```

Then connect the peers. Since Docker containers are isolated, create a shared network:

```sh
docker network create dali2-net
docker network connect dali2-net agri-sensors
docker network connect dali2-net agri-advisors
```

Register each node as a peer of the other (use container names as hostnames):

```sh
# Tell sensors node about advisors
curl -X POST http://localhost:8081/api/peers/register \
  -H "Content-Type: application/json" \
  -d '{"name":"advisors","url":"http://agri-advisors:8080"}'

# Tell advisors node about sensors
curl -X POST http://localhost:8082/api/peers/register \
  -H "Content-Type: application/json" \
  -d '{"name":"sensors","url":"http://agri-sensors:8080"}'
```

> **PowerShell equivalent:**
> ```powershell
> Invoke-RestMethod -Uri "http://localhost:8081/api/peers/register" -Method Post `
>   -ContentType "application/json" `
>   -Body '{"name":"advisors","url":"http://agri-advisors:8080"}'
>
> Invoke-RestMethod -Uri "http://localhost:8082/api/peers/register" -Method Post `
>   -ContentType "application/json" `
>   -Body '{"name":"sensors","url":"http://agri-sensors:8080"}'
> ```

#### Option 2: Two separate machines

On **Machine A** (e.g. `192.168.1.10`):

```sh
docker run --rm --init -p 8080:8080 \
  -v ./examples:/dali2/examples \
  dali2 8080 examples/agriculture.pl --name sensors \
  --agents soil_sensor,weather_monitor,logger
```

On **Machine B** (e.g. `192.168.1.20`):

```sh
docker run --rm --init -p 8080:8080 \
  -v ./examples:/dali2/examples \
  dali2 8080 examples/agriculture.pl --name advisors \
  --agents crop_advisor,irrigation_controller,farmer_agent
```

Connect them using real IP addresses:

```sh
# From Machine A (or any machine)
curl -X POST http://192.168.1.10:8080/api/peers/register \
  -H "Content-Type: application/json" \
  -d '{"name":"advisors","url":"http://192.168.1.20:8080"}'

curl -X POST http://192.168.1.20:8080/api/peers/register \
  -H "Content-Type: application/json" \
  -d '{"name":"sensors","url":"http://192.168.1.10:8080"}'
```

> You can also connect peers from the **Web UI**: open the Federation panel in the left sidebar,
> enter the peer name and URL, and click **Connect**.

#### Option 3: Without Docker (two shells, SWI-Prolog)

Requires [SWI-Prolog](https://www.swi-prolog.org/) installed locally.

```sh
# Shell 1 — sensors on port 8081
swipl -l src/server.pl -g main -t halt -- 8081 examples/agriculture.pl \
  --name sensors --agents soil_sensor,weather_monitor,logger

# Shell 2 — advisors on port 8082
swipl -l src/server.pl -g main -t halt -- 8082 examples/agriculture.pl \
  --name advisors --agents crop_advisor,irrigation_controller,farmer_agent
```

Connect them (both are on localhost, different ports):

```sh
curl -X POST http://localhost:8081/api/peers/register \
  -H "Content-Type: application/json" \
  -d '{"name":"advisors","url":"http://localhost:8082"}'

curl -X POST http://localhost:8082/api/peers/register \
  -H "Content-Type: application/json" \
  -d '{"name":"sensors","url":"http://localhost:8081"}'
```

#### Testing the distributed setup

Send a soil reading to the sensor on Node A:

```sh
curl -X POST http://localhost:8081/api/send \
  -H "Content-Type: application/json" \
  -d '{"to":"soil_sensor","content":"read_soil(25, 6.5, north_field)"}'
```

Expected chain of events across both nodes:

1. **soil_sensor** (Node A) receives `read_soil`, sends `soil_data` → **crop_advisor** (Node B) via federation
2. **crop_advisor** (Node B) detects low moisture (25 < 30), sends `irrigate` → **irrigation_controller** (Node B, local)
3. **crop_advisor** sends `notify(low_moisture)` → **farmer_agent** (Node B, local)
4. **irrigation_controller** (Node B) activates irrigation, sends `log_event` → **logger** (Node A) via federation
5. **farmer_agent** (Node B) logs the notification
6. **logger** (Node A) receives and logs events from both local and remote agents

Check the logs of each node to verify:

```sh
# Node A logs
docker logs agri-sensors

# Node B logs
docker logs agri-advisors
```

#### Pre-configured distributed example (emergency)

A ready-made two-node example is also included:

```sh
docker compose -f docker-compose.distributed.yml up --build
```

This starts `sensors` on port 8081 and `responders` on port 8082, auto-connected via `DALI2_PEERS` env var.

#### Cleanup

When using **Option 1** (two containers on the same machine), stop and clean up with:

```sh
# Stop both containers (or press CTRL+C in each terminal)
docker stop agri-sensors agri-advisors

# Remove the shared network
docker network rm dali2-net
```

For `docker compose` setups, simply use:

```sh
# Single instance
docker compose down

# Distributed
docker compose -f docker-compose.distributed.yml down
```

> **Tip:** The `--init` flag (used above) and `init: true` in docker-compose files ensure that
> CTRL+C stops containers cleanly. Without it, `swipl` as PID 1 may not handle signals correctly.

### Windows

Run `run.bat` — choose single or distributed mode interactively:

```sh
run.bat
```

## Agent Language

Agents are defined in a single `.pl` file using **identical DALI syntax** — no prefix needed. Each `:- agent(name).` directive sets the context for subsequent rules.

See **[RULES.md](RULES.md)** for the complete reference and **[EXAMPLES.md](EXAMPLES.md)** for walkthroughs.

```prolog
:- agent(my_agent, [cycle(1)]).

%% External event (E suffix + :> operator) — identical to DALI
alarmE(Type, Location) :>
    log("Alarm: ~w at ~w", [Type, Location]),
    assert_belief(active(Type, Location)),
    messageA(responder, send_message(dispatch(Type, Location), my_agent)).

%% Internal event (I suffix + :> operator + internal_event/5)
check_statusI :>
    believes(active(Type, Location)),
    log("Still active: ~w at ~w", [Type, Location]).
internal_event(check_status, 5, forever, true, forever).

%% Condition-action rule (:< operator)
believes(active(_, _)) :<
    log("Alert condition activated!"),
    send(logger, log_event(alert_active, my_agent)).

%% Export past (~/ operator)
send(logger, report(Type, Loc)) ~/
    alarm(Type, Loc), response(Loc).

%% Told rules (DALI communication.con style)
told(_, alarm(_,_), 100) :- true.
told(_, status(_), 50) :- true.

%% Past event lifetime
past_event(alarm(_,_), 60).
remember_event(alarm(_,_), 3600).

%% Obtain goal
obt_goal(believes(all_clear)) :-
    send(coordinator, check_status_request).

%% Action definition (A suffix)
dispatchA(Type, Location) :-
    log("Dispatching for ~w at ~w", [Type, Location]).

%% Initial beliefs
believes(status(idle)).
```

**New DALI2 features** (similar style, no prefix): `every` (periodic), `when` (condition monitor), `helper` (utility predicates), `on_proposal` (action proposals), `learn_from` (learning), `ontology`/`ontology_file`, `ask_ai` (AI Oracle), `bb_read`/`bb_write`/`bb_remove` (blackboard).

## Architecture: Redis Star Topology

Each agent runs as a **separate OS process**. All agents communicate through **Redis** in a star topology:

```
                    ┌─────────────┐
                    │    Redis    │
                    │  ┌───────┐  │
                    │  │ LINDA │  │  ← pub/sub channel for messages
                    │  │ LOGS  │  │  ← pub/sub channel for monitoring
                    │  │  BB   │  │  ← SET for shared blackboard
                    │  └───────┘  │
                    └──────┬──────┘
              ┌────────────┼────────────┐
              ↕            ↕            ↕
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │ Agent 1  │ │ Agent 2  │ │ Agent N  │
        │ (swipl)  │ │ (swipl)  │ │ (swipl)  │
        └──────────┘ └──────────┘ └──────────┘

        ┌──────────────────────────────────────┐
        │         Master Server (:8080)        │
        │  Web UI · REST API · Federation      │
        └──────────────────────────────────────┘
```

**LINDA channel** — all agents subscribe. Messages published as `TO:CONTENT:FROM` where `TO` is the destination agent (`*` for broadcast), `CONTENT` is the serialized Prolog term, `FROM` is the sender.

**LOGS channel** — agents publish log entries for external monitoring. No subscription needed.

**BB (Redis SET)** — shared blackboard replacing DALI's Linda tuple space. Agents read/write tuples via `bb_read`/`bb_write`/`bb_remove`.

**LAN support** — remote machines on the same network just point to the same Redis instance via `REDIS_HOST` environment variable.

## AI Oracle (ChatGPT Integration)

DALI2 can connect to OpenAI's ChatGPT API. Agents send context and receive a Prolog fact back.

### Configuration

- **Environment variable**: Set `OPENAI_API_KEY` when starting the Docker container
- **Web UI**: Enter the key in the "AI Oracle" panel at runtime
- **API**: `POST /api/ai/key` with `{"key": "sk-..."}`

The API key is **optional** — if not set, `ai_available` fails and `ask_ai` returns `suggestion(no_ai_available)`.

### Usage in agents

```prolog
:- agent(my_agent, [cycle(2)]).

analyzeE(Data) :>
    ( ai_available ->
        ask_ai(analyze_situation(Data), Advice),
        log("AI says: ~w", [Advice]),
        send(coordinator, ai_recommendation(Advice))
    ;
        log("AI not available, using default logic")
    ).
```

### Supported models

`gpt-4o-mini` (default), `gpt-4o`, `gpt-4-turbo`, `gpt-3.5-turbo`. Change via web UI or `POST /api/ai/model`.

## Web UI

The web interface at `http://localhost:8080` provides:

- **Agent list** — shows local and remote agents with running/stopped status
- **Event log** — real-time log with filtering by agent
- **Send events** — inject events into any agent from the browser
- **Agent details** — beliefs, past events, start/stop controls
- **Blackboard viewer** — current shared blackboard state
- **Source editor** — edit and hot-reload agent definitions (double-click the DALI2 logo)
- **Federation panel** — connect peers, view remote agents across nodes
- **AI Oracle panel** — configure API key, model, and test AI queries

## REST API

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/status` | System status |
| GET | `/api/agents` | List agents with status |
| GET | `/api/logs?agent=X&since=T` | Get log entries |
| POST | `/api/send` | Send event `{"to":"agent","content":"event(args)"}` |
| POST | `/api/inject` | Inject event `{"agent":"name","event":"event(args)"}` |
| POST | `/api/start` | Start agent `{"agent":"name"}` |
| POST | `/api/stop` | Stop agent `{"agent":"name"}` |
| POST | `/api/reload` | Reload agent file `{"file":"path"}` |
| GET | `/api/beliefs?agent=X` | Get agent beliefs |
| GET | `/api/past?agent=X` | Get past events |
| GET | `/api/learned?agent=X` | Get learned patterns |
| GET | `/api/goals?agent=X` | Get goal statuses |
| GET | `/api/blackboard` | View blackboard tuples |
| GET | `/api/source` | Get agent file source |
| POST | `/api/save` | Save agent file `{"content":"..."}` |
| GET | `/api/ai/status` | AI oracle status (enabled, model) |
| POST | `/api/ai/key` | Set OpenAI API key `{"key":"sk-..."}` |
| POST | `/api/ai/model` | Set AI model `{"model":"gpt-4o"}` |
| POST | `/api/ai/ask` | Query AI `{"context":"..."}` |
| GET | `/api/peers` | List federation peers |
| POST | `/api/peers/register` | Connect a peer `{"name":"n","url":"http://..."}` |
| POST | `/api/peers/unregister` | Disconnect a peer `{"name":"n"}` |
| POST | `/api/peers/sync` | Sync agent lists with all peers |
| GET | `/api/remote/agents` | List local agents (for peer queries) |
| POST | `/api/remote/receive` | Receive message from remote peer |

## Comparison with DALI

| Aspect | DALI (SICStus) | DALI2 (SWI-Prolog) |
|--------|----------------|---------------------|
| Source files | ~20 | 8 |
| Agent definition | Multiple files (instances + type files) | Single `.pl` file (multi-agent) |
| Process model | Separate process per agent + Linda server | **Separate OS process per agent** + Redis pub/sub |
| Communication | TCP sockets (Linda) | Redis star topology + HTTP federation |
| Tokenizer | Complex (tokefun + togli_var + metti_var) | None (direct parsing with DALI operators) |
| UI | Separate Python project (dalia) | Integrated web UI |
| AI integration | External Python TCP service | Built-in (direct OpenAI API calls) **[NEW]** |
| Docker setup | Complex (SICStus install) | Simple (swipl base image) |
| Event syntax | `eventE(X) :> body.` | `eventE(X) :> body.` (identical!) |
| Message sending | `messageA(dest, send_message(ev(X), Me))` | Same, or `send(dest, ev(X))` |
| Internal events | `eventI :> body.` + `internal_event/5` | `eventI :> body.` + `internal_event/5` (identical!) |
| Tell/told | `told(_, pattern, pri) :- true.` | `told(_, pattern, pri) :- true.` (identical!) |
| FIPA messages | `confirm`/`disconfirm`/`propose`/`query_ref` | `send(to, confirm(fact))` — full FIPA-ACL |
| Action definition | `actionA(X) :- body.` | `actionA(X) :- body.` (identical!) |
| Action proposal | `propose(A,C,Ag)` + `call_propose` | `on_proposal(action) :- body.` **[NEW]** |
| Past lifetime | `past_event(ev, 60).` | `past_event(ev, 60).` (identical!) |
| Remember | `remember_event_mod(ev, number(5), last).` | `remember_event_mod(ev, number(5), last).` (identical!) |
| Export past (~/) | `head ~/ past1, past2.` | `head ~/ past1, past2.` (identical!) |
| Export past (</) | `head </ past1, past2.` | `head </ past1, past2.` (identical!) |
| Export past (?/) | `head ?/ past1, past2.` | `head ?/ past1, past2.` (identical!) |
| Residue goals | `tenta_residuo(goal)` | `tenta_residuo(goal)` or `achieve(goal)` |
| Condition-action | `cond :< action.` | `cond :< action.` (identical!) |
| Present events | `condN :- body.` | `condN :- body.` (identical!) |
| Multi-events | `ev1E, ev2E :> body.` | `ev1E, ev2E :> body.` (identical!) |
| Constraints | `:~ constraint.` | `:~ constraint.` (identical!) |
| Ontologies | `meta/3` + OWL files | `ontology(same_as(a,b)).` + `ontology_file` |
| Learning | `learning.pl` + constraints | `learn_from(event, outcome) :- body.` **[NEW]** |
| Goals | `obt_goal(goal) :- plan.` | `obt_goal(goal) :- plan.` (identical!) |
| Periodic tasks | — | `every(seconds, goal).` **[NEW]** |
| Condition monitors | — | `when(condition) :- body.` **[NEW]** |
| Helpers | — | `helper(head) :- body.` **[NEW]** |
| AI Oracle | — | `ask_ai(context, result)` **[NEW]** |
| Blackboard | Linda (TCP) | `bb_read`/`bb_write`/`bb_remove` (Redis) **[NEW]** |

## License

Apache License 2.0
