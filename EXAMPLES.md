# DALI2 Examples Guide

This guide explains all included examples, how to run them, and the commands to test each feature.

## Table of Contents

- [Running Examples](#running-examples)
- [1. Smart Agriculture (`agriculture.pl`)](#1-smart-agriculture)
- [2. Emergency Response (`emergency.pl`)](#2-emergency-response)
- [3. Feature Showcase (`showcase.pl`)](#3-feature-showcase)
- [4. Distributed Emergency (`emergency_sensors.pl` + `emergency_responders.pl`)](#4-distributed-emergency)
- [API Quick Reference](#api-quick-reference)

---

## Running Examples

### With Docker

```bash
# Single instance
AGENT_FILE=examples/agriculture.pl docker compose up --build

# Distributed (two nodes)
docker compose -f docker-compose.distributed.yml up --build
```

### With SWI-Prolog (local)

```bash
swipl -l src/server.pl -g main -- 8080 examples/agriculture.pl
```

### With run.bat (Windows)

```
run.bat
```

After starting, open **http://localhost:8080** for the web UI.

### Sending Events

All examples use the REST API to inject events. Use `curl` (Linux/Mac) or `Invoke-RestMethod` (PowerShell):

```bash
# curl (Linux/Mac)
curl -X POST http://localhost:8080/api/send \
  -H "Content-Type: application/json" \
  -d '{"to":"agent_name","content":"event(args)"}'

# PowerShell (Windows)
Invoke-RestMethod -Uri "http://localhost:8080/api/send" `
  -Method Post -ContentType "application/json" `
  -Body '{"to":"agent_name","content":"event(args)"}'
```

---

## 1. Smart Agriculture

**File:** `examples/agriculture.pl`

A precision agriculture system with 6 agents that monitor soil, weather, and automate irrigation decisions.

### Agents

| Agent | Role |
|-------|------|
| `soil_sensor` | Receives soil readings, forwards to crop_advisor |
| `weather_monitor` | Receives weather data, forwards to crop_advisor |
| `crop_advisor` | Analyzes data, decides irrigation and alerts |
| `irrigation_controller` | Activates irrigation on command |
| `farmer_agent` | Receives notifications and stores them |
| `logger` | Logs all events centrally |

### Features Demonstrated

- **Reactive rules** (`on`) — all agents react to incoming events
- **Belief management** — farmer stores notifications, irrigation tracks active fields
- **Multi-agent communication** — message chains across 4+ agents
- **AI Oracle** — crop_advisor uses AI for critical conditions (if API key configured)
- **Conditional logic** — crop_advisor branches on moisture/pH thresholds

### Test Commands

```bash
# 1. Soil reading with low moisture → triggers irrigation
curl -X POST http://localhost:8080/api/send \
  -H "Content-Type: application/json" \
  -d '{"to":"soil_sensor","content":"read_soil(25, 6.5, field_north)"}'
```

**Expected flow:**
```
soil_sensor → crop_advisor: soil_data(25, 6.5, field_north)
crop_advisor detects low moisture (25 < 30)
crop_advisor → irrigation_controller: irrigate(field_north, 25)
crop_advisor → farmer_agent: notify(low_moisture, field_north, 25)
irrigation_controller → farmer_agent: notify(irrigation_started, field_north, 25)
```

```bash
# 2. Abnormal pH reading
curl -X POST http://localhost:8080/api/send \
  -H "Content-Type: application/json" \
  -d '{"to":"soil_sensor","content":"read_soil(50, 8.2, field_south)"}'
```

**Expected:** pH alert sent to farmer_agent (8.2 > 7.5).

```bash
# 3. Drought conditions (high temp + low humidity)
curl -X POST http://localhost:8080/api/send \
  -H "Content-Type: application/json" \
  -d '{"to":"weather_monitor","content":"weather_update(38, 20, sunny)"}'
```

**Expected:** Drought risk detected → emergency irrigation for all fields.

```bash
# 4. Frost warning
curl -X POST http://localhost:8080/api/send \
  -H "Content-Type: application/json" \
  -d '{"to":"weather_monitor","content":"weather_update(1, 80, cloudy)"}'
```

**Expected:** Frost warning sent to farmer_agent (temp < 2).

```bash
# 5. Check agent beliefs
curl http://localhost:8080/api/beliefs?agent=farmer_agent
curl http://localhost:8080/api/beliefs?agent=irrigation_controller
```

---

## 2. Emergency Response

**File:** `examples/emergency.pl`

A multi-agent emergency response system with detection, coordination, evacuation, and communication.

### Agents

| Agent | Role |
|-------|------|
| `sensor` | Detects emergencies, reports to coordinator |
| `coordinator` | Dispatches responders, tracks reports |
| `evacuator` | Handles evacuation procedures |
| `responder` | First response on-site |
| `communicator` | Notifies civilians |
| `logger` | Logs all events |

### Features Demonstrated

- **Reactive rules** — full chain from detection to response
- **Belief management** — coordinator tracks active emergencies and reports
- **Broadcast coordination** — coordinator dispatches to multiple agents simultaneously

### Test Commands

```bash
# 1. Fire emergency
curl -X POST http://localhost:8080/api/send \
  -H "Content-Type: application/json" \
  -d '{"to":"sensor","content":"sense(fire, building_a)"}'
```

**Expected flow:**
```
sensor → coordinator: alarm(fire, building_a)
coordinator → evacuator: evacuate(building_a, fire)
coordinator → communicator: notify_civilians(building_a, fire)
coordinator → responder: respond(building_a, fire)
evacuator → coordinator: report(evacuator, evacuation_complete, building_a)
responder → coordinator: report(responder, response_active, building_a)
```

```bash
# 2. Earthquake emergency
curl -X POST http://localhost:8080/api/send \
  -H "Content-Type: application/json" \
  -d '{"to":"sensor","content":"sense(earthquake, downtown)"}'

# 3. Chemical spill
curl -X POST http://localhost:8080/api/send \
  -H "Content-Type: application/json" \
  -d '{"to":"sensor","content":"sense(chemical_spill, factory_zone)"}'

# 4. Check coordinator beliefs (active emergencies + reports)
curl http://localhost:8080/api/beliefs?agent=coordinator

# 5. Check past events
curl http://localhost:8080/api/past?agent=coordinator
```

---

## 3. Feature Showcase

**File:** `examples/showcase.pl`

Demonstrates **all 32 DALI2 features** in a single file. This is the comprehensive reference example that covers every rule type, DSL predicate, and advanced feature ported from DALI.

### Agents

| Agent | Role | Features Demonstrated |
|-------|------|----------------------|
| `thermostat` | Temperature control | Internal events (interval, change, trigger, between), constraints, on_change |
| `sensor` | Sensor readings | Periodic tasks, present events, learning, blackboard, past lifetime/remember |
| `coordinator` | Central coordination | Tell/told (priority queue), FIPA messages, multi-events, goals, residue goals, export past rules, proposal sending, AI oracle |
| `logger` | Semantic logging | Ontology (inline + external file), helpers, condition monitor |
| `worker` | Task execution | Action proposals (on_proposal), FIPA responses, export past rules, told rules |

### Features Tested

| # | Feature | Agent | How to Trigger |
|---|---------|-------|----------------|
| 1 | **Reactive rules** (`on`) | all | Send events to agents |
| 2 | **Internal event interval** | thermostat | Automatic — `temp_check` fires every 5s (not every cycle) |
| 3 | **Internal event change** | thermostat | Send `update_temp` — `startup_diagnostic` counter resets |
| 4 | **Internal event trigger** | thermostat | `cooling_monitor` fires only when `mode(cooling)` |
| 5 | **Internal event between** | thermostat | `work_hours_check` fires in time window |
| 6 | **Periodic tasks** | sensor | Automatic — heartbeat every 15 seconds |
| 7 | **Condition monitors** (`when`) | logger | Warns when log volume > 10 |
| 8 | **Condition-action** (`on_change`) | thermostat | Edge-triggered when cooling mode activates |
| 9 | **Present events** | sensor | Blackboard data triggers environment observation |
| 10 | **Multi-events** (`on_all`) | coordinator | Both `sensor_data` + `alert` → fires |
| 11 | **Constraints** | thermostat | Temperature > 50 triggers violation |
| 12 | **Goals (achieve)** | sensor | Calibration goal keeps trying until achieved |
| 13 | **Goals (test)** | coordinator | Tests if alerts received |
| 14 | **Tell/told filtering** | coordinator | Only accepts specific patterns; rejects others |
| 15 | **Priority queue** | coordinator | Messages sorted by told priority (200→10) |
| 16 | **FIPA confirm** | coordinator→worker | Inject `send_confirm(system_ok)` into coordinator |
| 17 | **FIPA query_ref** | coordinator→worker | Inject `query_worker(status(_))` — auto-response |
| 18 | **FIPA propose/accept** | coordinator→worker | Inject `request_analysis(data)` |
| 19 | **FIPA propose/reject** | coordinator→worker | Inject `test_reject` |
| 20 | **FIPA inform** | worker→coordinator | Worker sends analysis results |
| 21 | **Action proposals** (`on_proposal`) | worker | Accepts/rejects proposals from coordinator |
| 22 | **Past lifetime + remember** | sensor | `sensor_data` expires after 30s, remembered 5min |
| 23 | **Export past** (`on_past`) | coordinator | Alert + sensor_data consumed together |
| 24 | **Export past** (`on_past_not_done`) | coordinator | Fires if backup NOT done |
| 25 | **Residue goals** | coordinator | Inject `start_residue_test` then `residue_resolved` |
| 26 | **External ontology file** | logger | Loads `test_ontology.pl` on startup |
| 27 | **Inline ontology** | logger | `log_event` matches `log_entry` via `same_as` |
| 28 | **Learning** | sensor | `read_temp(85)` → learns overheating pattern |
| 29 | **Actions** (`do`) | worker | `analyze(Data)` action definition |
| 30 | **Helpers** | logger | `count_logs` helper |
| 31 | **Blackboard** | sensor | Writes environment data |
| 32 | **AI Oracle** | coordinator | Emergency analysis (if API key configured) |

### Test Commands — Step by Step

```bash
# Start the showcase
swipl -l src/server.pl -g main -- 8080 examples/showcase.pl
```

**Automatic behavior on startup:**
- thermostat: `temp_check` fires every 5s (interval), `startup_diagnostic` fires 3 times (change resets on temp change), `work_hours_check` fires (between), `cooling_monitor` does NOT fire (mode=idle)
- sensor: periodic heartbeat, achieve goal sends calibration requests
- coordinator: calibrates sensor, test goal checks for alerts
- logger: loads `test_ontology.pl` (external ontology)
- After ~4 seconds: sensor calibration achieved

```bash
# STEP 1: Send first temperature reading
# Triggers: learning, blackboard, present event, on_change, triggered internal,
#           constraint, export past (on_past), change condition reset, priority queue
curl -X POST http://localhost:8080/api/send \
  -H "Content-Type: application/json" \
  -d '{"to":"sensor","content":"read_temp(85)"}'
```

**Expected:**
- Sensor reads 85, writes to blackboard, sends `sensor_data(85)` to coordinator
- **Learning**: learns overheating pattern
- **Present event**: blackboard → thermostat gets `update_temp(85)`
- **On_change**: "Cooling mode just activated" (edge-triggered, fires once)
- **Triggered internal**: `cooling_monitor` starts firing (mode=cooling)
- **Constraint violated**: 85 > 50 → emergency sent to coordinator
- **Change condition**: thermostat's `startup_diagnostic` counter resets (current_temp changed)
- **Priority queue**: coordinator processes `emergency(200)` before `sensor_data(30)`
- Logger receives log_event → **ontology** matching works

```bash
# STEP 2: Send second reading (triggers learned pattern + multi-event + export past)
curl -X POST http://localhost:8080/api/send \
  -H "Content-Type: application/json" \
  -d '{"to":"sensor","content":"read_temp(90)"}'
```

**Expected:**
- **Learned knowledge**: "WARNING: Previously learned overheating pattern!"
- **Multi-event**: `sensor_data` + `alert` both in past → fires
- **Export past (on_past)**: `alert` + `sensor_data` consumed from past memory

```bash
# STEP 3: Test FIPA confirm — coordinator sends confirm to worker
curl -X POST http://localhost:8080/api/inject \
  -H "Content-Type: application/json" \
  -d '{"agent":"coordinator","event":"send_confirm(system_ok)"}'
```

**Expected:** Worker receives `confirm(system_ok)` → "Fact confirmed: system_ok" + "FIPA CONFIRM received"

```bash
# STEP 4: Test FIPA query_ref — coordinator queries worker's beliefs
curl -X POST http://localhost:8080/api/inject \
  -H "Content-Type: application/json" \
  -d '{"agent":"coordinator","event":"query_worker(status(_))"}'
```

**Expected:** Worker auto-responds with `inform(query_ref(status(_)), values([status(ready)]))` → coordinator logs "FIPA QUERY_REF response"

```bash
# STEP 5: Test FIPA proposals — coordinator proposes to worker
curl -X POST http://localhost:8080/api/inject \
  -H "Content-Type: application/json" \
  -d '{"agent":"coordinator","event":"request_analysis(sample_data)}"'
```

**Expected:** Worker accepts → executes `analyze(sample_data)` → sends `inform(analysis_result, complete)` back → coordinator logs "FIPA PROPOSAL ACCEPTED"

```bash
# STEP 6: Test rejected proposal
curl -X POST http://localhost:8080/api/inject \
  -H "Content-Type: application/json" \
  -d '{"agent":"coordinator","event":"test_reject"}'
```

**Expected:** Worker rejects `impossible_task` → coordinator logs "FIPA PROPOSAL REJECTED"

```bash
# STEP 7: Test export past not_done
curl -X POST http://localhost:8080/api/inject \
  -H "Content-Type: application/json" \
  -d '{"agent":"coordinator","event":"critical_data(important_backup)"}'
```

**Expected:** "EXPORT PAST NOT_DONE: backup NOT done! critical_data(important_backup) needs attention!"

```bash
# STEP 8: Test residue goals
curl -X POST http://localhost:8080/api/inject \
  -H "Content-Type: application/json" \
  -d '{"agent":"coordinator","event":"start_residue_test"}'
# Wait 2 seconds, then inject the resolution:
curl -X POST http://localhost:8080/api/inject \
  -H "Content-Type: application/json" \
  -d '{"agent":"coordinator","event":"residue_resolved"}'
```

**Expected:** "Goal queued as residue: has_past(residue_resolved)" → then "Residue goal achieved" after injection

```bash
# STEP 9: Test tell/told filtering — send an unaccepted message
curl -X POST http://localhost:8080/api/send \
  -H "Content-Type: application/json" \
  -d '{"to":"coordinator","content":"unknown_message(test)"}'
```

**Expected:** Message rejected by told rule (coordinator only accepts defined patterns)

```bash
# STEP 10: Lower temperature — constraint resolves, change condition resets diagnostic
curl -X POST http://localhost:8080/api/send \
  -H "Content-Type: application/json" \
  -d '{"to":"thermostat","content":"update_temp(20)"}'
```

**Expected:** Temperature drops to 20, constraint no longer violated, mode goes to idle, `startup_diagnostic` counter resets (change detected)

```bash
# STEP 11: Check all state via APIs
curl http://localhost:8080/api/agents
curl http://localhost:8080/api/beliefs?agent=thermostat
curl http://localhost:8080/api/beliefs?agent=coordinator
curl http://localhost:8080/api/beliefs?agent=worker
curl http://localhost:8080/api/past?agent=coordinator
curl http://localhost:8080/api/learned?agent=sensor
curl http://localhost:8080/api/goals?agent=sensor
curl http://localhost:8080/api/blackboard
```

---

## 4. Distributed Emergency

**Files:** `examples/emergency_sensors.pl` + `examples/emergency_responders.pl`

Two separate DALI2 nodes communicating via HTTP federation.

### Node 1: Sensors (`emergency_sensors.pl`)

| Agent | Role |
|-------|------|
| `sensor` | Detects emergencies |
| `logger` | Logs events |

### Node 2: Responders (`emergency_responders.pl`)

| Agent | Role |
|-------|------|
| `coordinator` | Dispatches responders |
| `evacuator` | Handles evacuation |
| `responder` | First response |
| `communicator` | Public notification |

### Running Distributed

**With Docker Compose:**
```bash
docker compose -f docker-compose.distributed.yml up --build
```

**Manually (two terminals):**
```bash
# Terminal 1 — Sensor node on port 8080
swipl -l src/server.pl -g main -- 8080 examples/emergency_sensors.pl

# Terminal 2 — Responder node on port 8081
swipl -l src/server.pl -g main -- 8081 examples/emergency_responders.pl
```

**Register peers:**
```bash
# Tell node 1 about node 2
curl -X POST http://localhost:8080/api/peers/register \
  -H "Content-Type: application/json" \
  -d '{"name":"responders","url":"http://localhost:8081"}'

# Tell node 2 about node 1
curl -X POST http://localhost:8081/api/peers/register \
  -H "Content-Type: application/json" \
  -d '{"name":"sensors","url":"http://localhost:8080"}'

# Sync agent lists
curl -X POST http://localhost:8080/api/peers/sync
curl -X POST http://localhost:8081/api/peers/sync
```

**Test:**
```bash
# Send emergency to sensor on node 1
curl -X POST http://localhost:8080/api/send \
  -H "Content-Type: application/json" \
  -d '{"to":"sensor","content":"detect(fire, building_a)"}'
```

**Expected:** sensor on node 1 sends alarm to coordinator on node 2 via federation. Coordinator dispatches to evacuator, responder, communicator (all on node 2). Logger messages go back to node 1.

---

## API Quick Reference

### Sending Events

```bash
# Send to a specific agent
curl -X POST http://localhost:8080/api/send \
  -H "Content-Type: application/json" \
  -d '{"to":"AGENT","content":"EVENT(ARGS)"}'

# Inject directly into an agent's event queue
curl -X POST http://localhost:8080/api/inject \
  -H "Content-Type: application/json" \
  -d '{"agent":"AGENT","event":"EVENT(ARGS)"}'
```

### Querying State

```bash
# List all agents
curl http://localhost:8080/api/agents

# Agent beliefs
curl http://localhost:8080/api/beliefs?agent=AGENT

# Past events
curl http://localhost:8080/api/past?agent=AGENT

# Learned patterns
curl http://localhost:8080/api/learned?agent=AGENT

# Goal statuses
curl http://localhost:8080/api/goals?agent=AGENT

# Blackboard contents
curl http://localhost:8080/api/blackboard

# System logs
curl http://localhost:8080/api/logs?agent=AGENT
```

### Agent Control

```bash
# Start/stop individual agents
curl -X POST http://localhost:8080/api/start -H "Content-Type: application/json" -d '{"agent":"AGENT"}'
curl -X POST http://localhost:8080/api/stop -H "Content-Type: application/json" -d '{"agent":"AGENT"}'

# Reload agent file
curl -X POST http://localhost:8080/api/reload -H "Content-Type: application/json" -d '{"file":"examples/showcase.pl"}'
```
