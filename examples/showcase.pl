%% DALI2 Example: Feature Showcase
%% Demonstrates ALL DALI2 rule types and DSL predicates in a single file.
%%
%% Agents:
%%   - thermostat:   internal events (interval, change, trigger), constraints, on_change
%%   - sensor:       periodic tasks, present events, learning, blackboard, past lifetime/remember
%%   - coordinator:  reactive rules, tell/told (priority queue), FIPA messages, multi-events,
%%                   goals, residue goals, export past rules, action proposal sending
%%   - logger:       ontology (inline + external file), helpers, condition monitor
%%   - worker:       action proposals (on_proposal), FIPA responses, export past rules
%%
%% Features demonstrated (25 total):
%%   1.  Reactive rules (on)                    — all agents
%%   2.  Internal events (forever/times)        — thermostat
%%   3.  Internal event interval(N)             — thermostat (temp_check: every 5s)
%%   4.  Internal event change([Facts])         — thermostat (startup_diagnostic: resets on temp change)
%%   5.  Internal event trigger(Condition)      — thermostat (cooling_monitor: only when cooling)
%%   6.  Internal event between(time)           — thermostat (work hours check)
%%   7.  Periodic tasks (every)                 — sensor (heartbeat 15s)
%%   8.  Condition monitors (when)              — logger (high log volume warning)
%%   9.  Condition-action (on_change)           — thermostat (cooling mode edge-triggered)
%%  10.  Present/environment events (on_present)— sensor (blackboard monitoring)
%%  11.  Multi-events (on_all)                  — coordinator (sensor_data + alert)
%%  12.  Constraints (constraint)               — thermostat (temp < 50)
%%  13.  Goals (achieve/test)                   — sensor (calibration), coordinator (alert test)
%%  14.  Tell/told filtering                    — coordinator (priority-based message acceptance)
%%  15.  Priority queue for messages            — coordinator (told priorities: 200/100/50/...)
%%  16.  FIPA confirm/disconfirm                — coordinator sends, worker receives
%%  17.  FIPA query_ref                         — coordinator queries worker beliefs
%%  18.  FIPA propose/accept/reject             — coordinator proposes to worker
%%  19.  FIPA inform                            — worker sends analysis results
%%  20.  Action proposals (on_proposal)         — worker handles proposals
%%  21.  Past event lifetime + remember tier    — sensor (30s expire, 5min remember)
%%  22.  Export past rules (on_past)            — coordinator (alert + reading consumed)
%%  23.  Export past rules (on_past_not_done)   — coordinator (backup not done warning)
%%  24.  Residue goals                          — coordinator (deferred goal retry)
%%  25.  External ontology file loading         — logger (test_ontology.pl)
%%  26.  Inline ontology declarations           — logger (same_as, eq_property, symmetric)
%%  27.  Learning rules                         — sensor (overheating pattern)
%%  28.  Actions (do)                           — worker (analyze action)
%%  29.  Beliefs                                — all agents
%%  30.  Helpers                                — logger (count_logs)
%%  31.  Blackboard                             — sensor writes, sensor reads via on_present
%%  32.  AI Oracle (if configured)              — coordinator (emergency analysis)
%%
%% Run:   AGENT_FILE=examples/showcase.pl docker compose up --build
%% Or:    swipl -l src/server.pl -g main -- 8080 examples/showcase.pl
%%
%% See EXAMPLES.md for step-by-step test commands.

%% ============================================================
%% THERMOSTAT — internal events, constraints, on_change
%% ============================================================
%%
%% Demonstrates:
%%   - Internal event with interval(5) — fires every 5 seconds, not every cycle
%%   - Internal event with times(3) + change([current_temp(_)]) — resets counter on belief change
%%   - Internal event with trigger(believes(mode(cooling))) — fires only when condition holds
%%   - Internal event with between(time) — fires only during a time window
%%   - Constraint — temperature must stay below 50
%%   - On_change — edge-triggered: fires once when cooling mode activates
%%   - Reactive rules — set_temp, update_temp

:- agent(thermostat, [cycle(2)]).

%% Initial beliefs
thermostat:believes(target_temp(22)).
thermostat:believes(current_temp(20)).
thermostat:believes(mode(idle)).

%% F1: Internal event with interval — fires every 5 seconds (not every cycle)
thermostat:internal(temp_check, [forever, interval(5)]) :-
    believes(current_temp(T)),
    log("INTERVAL INTERNAL: temperature check (every 5s), current=~w", [T]).

%% F3: Internal event with change condition — fires 3 times, resets when current_temp changes
thermostat:internal(startup_diagnostic, [times(3), change([current_temp(_)])]) :-
    log("CHANGE INTERNAL: startup diagnostic (resets on temp change)"),
    assert_belief(diagnostic_done).

%% Trigger: fires only when the thermostat believes mode is cooling
thermostat:internal(cooling_monitor, [forever, trigger(believes(mode(cooling)))]) :-
    believes(current_temp(T)),
    log("TRIGGERED INTERNAL: Monitoring cooling, current temp: ~w", [T]).

%% Between: fires only during work hours (always active in this demo for testability)
thermostat:internal(work_hours_check, [forever, interval(10), between(time(0,0), time(23,59))]) :-
    log("BETWEEN INTERNAL: work hours system check").

%% Constraint: temperature must stay below 50
thermostat:constraint(believes(current_temp(T)), T < 50) :-
    log("CONSTRAINT VIOLATED: Temperature ~w exceeds safe limit!", [T]),
    send(coordinator, emergency(overheating, T)).

%% Condition-action (edge-triggered): fires once when cooling activates
thermostat:on_change(believes(mode(cooling))) :-
    log("ON_CHANGE: Cooling mode just activated"),
    send(logger, log_event(mode_change, thermostat, cooling)).

%% React to external temperature updates
thermostat:on(set_temp(NewTarget)) :-
    log("Target temperature set to ~w", [NewTarget]),
    retract_belief(target_temp(_)),
    assert_belief(target_temp(NewTarget)).

thermostat:on(update_temp(T)) :-
    log("Temperature updated to ~w", [T]),
    retract_belief(current_temp(_)),
    assert_belief(current_temp(T)),
    ( T > 30 ->
        retract_belief(mode(_)),
        assert_belief(mode(cooling)),
        send(coordinator, notify(cooling_active, T))
    ;
        retract_belief(mode(_)),
        assert_belief(mode(idle))
    ).

%% ============================================================
%% SENSOR — periodic, present events, learning, blackboard, past lifetime
%% ============================================================
%%
%% Demonstrates:
%%   - Periodic tasks (every 15s heartbeat)
%%   - Present events (monitor blackboard)
%%   - Learning rules (overheating pattern)
%%   - Blackboard usage (write + read)
%%   - Past event lifetime + remember tier
%%   - Goal (achieve calibration)

:- agent(sensor, [cycle(2)]).

%% Initial beliefs
sensor:believes(calibrated(false)).

%% F2: Past lifetime — sensor readings expire after 30s, then remembered for 5 minutes
sensor:past_lifetime(sensor_data(_), 30).
sensor:remember_lifetime(sensor_data(_), 300).
sensor:remember_limit(sensor_data(_), 10, last).

%% Periodic task: heartbeat every 15 seconds
sensor:every(15, log("Sensor heartbeat")).

%% Present event: monitor blackboard for external data
sensor:on_present(bb_read(environment(temp, T))) :-
    log("PRESENT: Environment temperature from blackboard: ~w", [T]),
    send(thermostat, update_temp(T)).

%% Learning rule: learn when readings indicate overheating
sensor:learn_from(read_temp(T), overheating) :- T > 80.
sensor:learn_from(read_temp(T), normal) :- T =< 80.

%% React to temperature readings
sensor:on(read_temp(T)) :-
    log("Sensor read: ~w", [T]),
    %% Write to blackboard so present events can detect it
    bb_write(environment(temp, T)),
    %% Check if we previously learned about overheating
    ( learned(read_temp(_), overheating) ->
        log("WARNING: Previously learned overheating pattern!"),
        send(coordinator, alert(repeated_overheating, T))
    ;
        true
    ),
    send(coordinator, sensor_data(T)).

%% Goal: achieve calibration (keeps trying until calibrated)
sensor:goal(achieve, believes(calibrated(true))) :-
    log("Attempting calibration..."),
    send(coordinator, calibration_request).

%% React to calibration confirmation
sensor:on(calibration_done) :-
    log("Calibration confirmed!"),
    retract_belief(calibrated(_)),
    assert_belief(calibrated(true)).

%% ============================================================
%% COORDINATOR — reactive, tell/told, priority queue, FIPA, multi-events,
%%               goals, residue goals, export past rules, proposal sending
%% ============================================================
%%
%% Demonstrates:
%%   - Tell/told communication filtering with priority queue
%%   - FIPA message types: confirm, inform, query_ref, propose, accept/reject_proposal
%%   - Multi-events (on_all)
%%   - Goals (test)
%%   - Residue goals (deferred achieve)
%%   - Export past rules (on_past, on_past_not_done)
%%   - AI Oracle integration (filtered by tell/told)

:- agent(coordinator, [cycle(2)]).

%% Initial beliefs
coordinator:believes(status(active)).
coordinator:believes(alerts_received(0)).

%% F7: Tell/told with priority queue — messages processed highest priority first
coordinator:told(emergency(_, _), 200).      %% highest priority
coordinator:told(alert(_, _), 100).
coordinator:told(confirm(_), 90).
coordinator:told(inform(_, _), 80).
coordinator:told(accept_proposal(_), 70).
coordinator:told(reject_proposal(_), 70).
coordinator:told(query_ref(_), 60).
coordinator:told(notify(_, _), 50).
coordinator:told(sensor_data(_), 30).
coordinator:told(calibration_request, 10).   %% lowest priority

%% Tell: coordinator can only send these patterns
coordinator:tell(calibration_done).
coordinator:tell(response(_)).
coordinator:tell(log_event(_, _, _)).
coordinator:tell(propose(_)).
coordinator:tell(confirm(_)).
coordinator:tell(query_ref(_)).
%% Tell/told also apply to AI oracle queries and responses
coordinator:tell(analyze(_)).

%% Multi-event: fire when both sensor data AND an alert have been received
coordinator:on_all([sensor_data(_), alert(_, _)]) :-
    log("MULTI-EVENT: Both sensor data and alert received!"),
    send(logger, log_event(combined_alert, coordinator, multi_trigger)).

%% React to sensor data
coordinator:on(sensor_data(T)) :-
    log("Coordinator received sensor data: ~w", [T]),
    ( T > 40 ->
        send(logger, log_event(high_temp, coordinator, T))
    ; true ).

%% React to alerts
coordinator:on(alert(Type, Value)) :-
    log("Coordinator alert: ~w = ~w", [Type, Value]),
    believes(alerts_received(N)),
    N1 is N + 1,
    retract_belief(alerts_received(N)),
    assert_belief(alerts_received(N1)).

%% React to emergency (with optional AI oracle analysis, filtered by tell/told)
coordinator:on(emergency(Type, Value)) :-
    log("EMERGENCY: ~w = ~w", [Type, Value]),
    send(logger, log_event(emergency, coordinator, [Type, Value])),
    ( ai_available ->
        ask_ai(analyze(emergency(Type, Value)), Advice),
        log("AI advice for emergency: ~w", [Advice])
    ; true ).

%% React to calibration requests
coordinator:on(calibration_request) :-
    log("Processing calibration request"),
    send(sensor, calibration_done).

%% F4: FIPA confirm handler
coordinator:on(confirm(Fact)) :-
    log("FIPA CONFIRM received: ~w", [Fact]).

%% F4: FIPA inform handler
coordinator:on(inform(Content, Meta)) :-
    log("FIPA INFORM received: ~w meta=~w", [Content, Meta]).

%% F4: FIPA query_ref response handler
coordinator:on(inform(query_ref(Q), values(V))) :-
    log("FIPA QUERY_REF response: ~w = ~w", [Q, V]).

%% F4: FIPA accept/reject proposal handlers
coordinator:on(accept_proposal(Action)) :-
    log("FIPA PROPOSAL ACCEPTED: ~w", [Action]).

coordinator:on(reject_proposal(Action)) :-
    log("FIPA PROPOSAL REJECTED: ~w", [Action]).

%% F8: Send a proposal to worker for data analysis
coordinator:on(request_analysis(Data)) :-
    log("Requesting analysis, proposing to worker..."),
    send(worker, propose(analyze(Data))).

%% F8: Send a proposal that will be rejected
coordinator:on(test_reject) :-
    log("Testing proposal rejection..."),
    send(worker, propose(impossible_task)).

%% F4: Send a FIPA confirm to worker
coordinator:on(send_confirm(Fact)) :-
    log("Sending FIPA confirm(~w) to worker", [Fact]),
    send(worker, confirm(Fact)).

%% F4: Send a FIPA query_ref to worker
coordinator:on(query_worker(Q)) :-
    log("Sending FIPA query_ref(~w) to worker", [Q]),
    send(worker, query_ref(Q)).

%% F5: Export past rule — when both alert and sensor_data in past, consume and react
coordinator:on_past([alert(Type, _), sensor_data(Value)]) :-
    log("EXPORT PAST: alert(~w) + sensor_data(~w) consumed!", [Type, Value]),
    send(logger, log_event(past_consumed, coordinator, [Type, Value])).

%% F5: Export past not_done — warn if backup not done but critical data exists
coordinator:on_past_not_done(backup(_), [critical_data(X)]) :-
    log("EXPORT PAST NOT_DONE: backup NOT done! critical_data(~w) needs attention!", [X]).

%% F6: Residue goal test — start a deferred goal
coordinator:on(start_residue_test) :-
    log("Starting residue goal test..."),
    achieve(has_past(residue_resolved)).

%% Goal: test that we have received at least one alert
coordinator:goal(test, believes(alerts_received(N)), N > 0) :-
    log("Testing if any alerts received...").

%% ============================================================
%% LOGGER — ontology (inline + file), helpers, condition monitor
%% ============================================================
%%
%% Demonstrates:
%%   - Inline ontology declarations (same_as, eq_property, symmetric)
%%   - External ontology file loading (test_ontology.pl)
%%   - Helper predicates
%%   - Condition monitors (when)

:- agent(logger, [cycle(2)]).

%% Inline ontology: treat different terms as equivalent
logger:ontology(same_as(log_event, log_entry)).
logger:ontology(eq_property(log_event, record)).
logger:ontology(symmetric(related_to)).

%% F10: External ontology file — loads same_as(temperature, temp), eq_class(sensor, detector), etc.
logger:ontology_file('examples/test_ontology.pl').

%% React to log events (also matches log_entry via ontology same_as)
logger:on(log_event(Type, Source, Data)) :-
    log("LOG [~w] from ~w: ~w", [Type, Source, Data]),
    assert_belief(logged(Type, Source)),
    helper(count_logs).

%% Helper: count total logs
logger:helper(count_logs) :-
    findall(_, believes(logged(_, _)), Logs),
    length(Logs, N),
    log("Total log entries: ~w", [N]).

%% Condition monitor: warn if too many logs
logger:when(believes(logged(_, _))) :-
    findall(_, believes(logged(_, _)), Logs),
    length(Logs, N),
    ( N > 10 ->
        log("WARNING: High log volume (~w entries)", [N])
    ; true ).

%% ============================================================
%% WORKER — action proposals, FIPA responses, export past rules
%% ============================================================
%%
%% Demonstrates:
%%   - Action proposals (on_proposal) with accept/reject
%%   - FIPA message handling (confirm, inform)
%%   - Named actions (do)
%%   - from(Sender) DSL predicate
%%   - accept_proposal/reject_proposal DSL predicates
%%   - Export past rules (on_past)
%%   - Told rules for FIPA message acceptance

:- agent(worker, [cycle(2)]).

%% Initial beliefs
worker:believes(available(true)).
worker:believes(skill(data_analysis)).
worker:believes(status(ready)).

%% Told rules: worker accepts these FIPA message types
worker:told(propose(_), 100).
worker:told(confirm(_), 90).
worker:told(query_ref(_), 80).
worker:told(inform(_, _), 70).

%% F8: Action proposal handler — accept analysis tasks
worker:on_proposal(analyze(Data)) :-
    believes(skill(data_analysis)),
    from(Sender),
    log("PROPOSAL: Accepting analyze(~w) from ~w", [Data, Sender]),
    accept_proposal(Sender, analyze(Data)),
    do(analyze(Data)).

%% F8: Action proposal handler — reject impossible tasks
worker:on_proposal(impossible_task) :-
    from(Sender),
    log("PROPOSAL: Rejecting impossible_task from ~w", [Sender]),
    reject_proposal(Sender, impossible_task).

%% Action definition
worker:do(analyze(Data)) :-
    log("Executing analysis: ~w", [Data]),
    assert_belief(analysis_complete(Data)),
    send(coordinator, inform(analysis_result(Data), complete)).

%% F4: React to FIPA confirm messages
worker:on(confirm(Fact)) :-
    log("FIPA CONFIRM received: ~w", [Fact]).

%% F5: Export past rule — when both task_done and report_needed exist, consume and act
worker:on_past([task_done(Task), report_needed(Task)]) :-
    log("EXPORT PAST: Task ~w done + report needed — both consumed!", [Task]),
    send(coordinator, inform(task_report(Task), complete)).
