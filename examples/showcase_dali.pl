%% DALI2 Example: Feature Showcase (DALI Original Syntax)
%% This file demonstrates DALI2 using the original DALI syntax conventions:
%%   - E suffix for external events, :> operator
%%   - I suffix for internal events, :> operator + internal_event/5
%%   - A suffix for actions
%%   - N suffix for present events
%%   - :< operator for condition-action rules
%%   - ~/ operator for export past
%%   - </ operator for export past NOT done
%%   - ?/ operator for export past done
%%   - :~ operator for constraints
%%   - messageA(Dest, send_message(Content, Me)) for sending
%%   - eventP(Args) for past event check
%%   - obt_goal/test_goal for goals
%%   - past_event/2, remember_event/2, remember_event_mod/3
%%
%% DALI2-only features use similar style:
%%   - every (periodic tasks)
%%   - when (condition monitors)
%%   - helper (utility predicates)
%%   - on_proposal (action proposals)
%%   - ontology, ontology_file, learn_from
%%   - ask_ai, bb_read/bb_write/bb_remove
%%
%% Run:  swipl -l src/server.pl -g main -- 8080 examples/showcase_dali.pl

%% ============================================================
%% THERMOSTAT — internal events, constraints, condition-action
%% ============================================================

:- agent(thermostat, [cycle(2)]).

%% Initial beliefs
thermostat:believes(target_temp(22)).
thermostat:believes(current_temp(20)).
thermostat:believes(mode(idle)).

%% Internal event with interval (fires every 5 seconds)
%% Handler: what to do when the internal event fires
thermostat:temp_checkI :>
    believes(current_temp(T)),
    log("INTERVAL INTERNAL: temperature check (every 5s), current=~w", [T]).

%% Configuration for the internal event (DALI internal_event/5 style)
thermostat:internal_event(temp_check, 5, forever, true, forever).

%% Internal event with times + change condition
thermostat:startup_diagnosticI :>
    log("CHANGE INTERNAL: startup diagnostic (resets on temp change)"),
    assert_belief(diagnostic_done).

thermostat:internal_event(startup_diagnostic, 0, change([current_temp(_)]), true, forever).

%% Internal event with trigger (fires only when mode is cooling)
thermostat:cooling_monitorI :>
    believes(current_temp(T)),
    log("TRIGGERED INTERNAL: Monitoring cooling, current temp: ~w", [T]).

thermostat:internal_event(cooling_monitor, 0, forever, believes(mode(cooling)), forever).

%% Constraint: temperature must stay below 50 (DALI :~ syntax)
thermostat :~ (believes(current_temp(T)), T < 50) :-
    log("CONSTRAINT VIOLATED: Temperature ~w exceeds safe limit!", [T]),
    send(coordinator, emergency(overheating, T)).

%% Condition-action rule (DALI :< syntax, edge-triggered)
thermostat:believes(mode(cooling)) :< (
    log("ON_CHANGE: Cooling mode just activated"),
    send(logger, log_event(mode_change, thermostat, cooling))
).

%% External event handlers (DALI :> syntax with E suffix)
thermostat:set_tempE(NewTarget) :>
    log("Target temperature set to ~w", [NewTarget]),
    retract_belief(target_temp(_)),
    assert_belief(target_temp(NewTarget)).

thermostat:update_tempE(T) :>
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
%% SENSOR — periodic, present events, learning, blackboard
%% ============================================================

:- agent(sensor, [cycle(2)]).

%% Initial beliefs
sensor:believes(calibrated(false)).

%% Past event lifetime (DALI syntax)
sensor:past_event(sensor_data(_), 30).
sensor:remember_event(sensor_data(_), 300).
sensor:remember_event_mod(sensor_data(_), number(10), last).

%% Periodic task (DALI2 feature, similar style)
sensor:every(15, log("Sensor heartbeat")).

%% Present event (DALI N suffix — monitor blackboard)
sensor:environmentN(temp, T) :-
    log("PRESENT: Environment temperature from blackboard: ~w", [T]),
    send(thermostat, update_temp(T)).

%% Learning rules (DALI2 feature, similar style)
sensor:learn_from(read_temp(T), overheating) :- T > 80.
sensor:learn_from(read_temp(T), normal) :- T =< 80.

%% External event handler (DALI :> syntax)
sensor:read_tempE(T) :>
    log("Sensor read: ~w", [T]),
    bb_write(environment(temp, T)),
    ( learned(read_temp(_), overheating) ->
        log("WARNING: Previously learned overheating pattern!"),
        send(coordinator, alert(repeated_overheating, T))
    ;
        true
    ),
    send(coordinator, sensor_data(T)).

%% Obtain goal (DALI obt_goal syntax)
sensor:obt_goal(believes(calibrated(true))) :-
    log("Attempting calibration..."),
    send(coordinator, calibration_request).

%% External event handler
sensor:calibration_doneE :>
    log("Calibration confirmed!"),
    retract_belief(calibrated(_)),
    assert_belief(calibrated(true)).

%% ============================================================
%% COORDINATOR — reactive, tell/told, FIPA, goals, export past
%% ============================================================

:- agent(coordinator, [cycle(2)]).

%% Initial beliefs
coordinator:believes(status(active)).
coordinator:believes(alerts_received(0)).

%% Told rules (DALI2 style, kept as-is since DALI told was in separate file)
coordinator:told(emergency(_, _), 200).
coordinator:told(alert(_, _), 100).
coordinator:told(confirm(_), 90).
coordinator:told(inform(_, _), 80).
coordinator:told(accept_proposal(_), 70).
coordinator:told(reject_proposal(_), 70).
coordinator:told(query_ref(_), 60).
coordinator:told(notify(_, _), 50).
coordinator:told(sensor_data(_), 30).
coordinator:told(calibration_request, 10).

%% Tell rules
coordinator:tell(calibration_done).
coordinator:tell(response(_)).
coordinator:tell(log_event(_, _, _)).
coordinator:tell(propose(_)).
coordinator:tell(confirm(_)).
coordinator:tell(query_ref(_)).
coordinator:tell(analyze(_)).

%% Multi-event (DALI conjunction of E-suffix events)
coordinator:sensor_dataE(_), coordinator:alertE(_, _) :>
    log("MULTI-EVENT: Both sensor data and alert received!"),
    send(logger, log_event(combined_alert, coordinator, multi_trigger)).

%% External event handlers (DALI :> syntax)
coordinator:sensor_dataE(T) :>
    log("Coordinator received sensor data: ~w", [T]),
    ( T > 40 ->
        send(logger, log_event(high_temp, coordinator, T))
    ; true ).

coordinator:alertE(Type, Value) :>
    log("Coordinator alert: ~w = ~w", [Type, Value]),
    believes(alerts_received(N)),
    N1 is N + 1,
    retract_belief(alerts_received(N)),
    assert_belief(alerts_received(N1)).

coordinator:emergencyE(Type, Value) :>
    log("EMERGENCY: ~w = ~w", [Type, Value]),
    send(logger, log_event(emergency, coordinator, [Type, Value])),
    ( ai_available ->
        ask_ai(analyze(emergency(Type, Value)), Advice),
        log("AI advice for emergency: ~w", [Advice])
    ; true ).

coordinator:calibration_requestE :>
    log("Processing calibration request"),
    send(sensor, calibration_done).

%% FIPA handlers
coordinator:confirmE(Fact) :>
    log("FIPA CONFIRM received: ~w", [Fact]).

coordinator:informE(Content, Meta) :>
    log("FIPA INFORM received: ~w meta=~w", [Content, Meta]).

coordinator:accept_proposalE(Action) :>
    log("FIPA PROPOSAL ACCEPTED: ~w", [Action]).

coordinator:reject_proposalE(Action) :>
    log("FIPA PROPOSAL REJECTED: ~w", [Action]).

coordinator:request_analysisE(Data) :>
    log("Requesting analysis, proposing to worker..."),
    send(worker, propose(analyze(Data))).

coordinator:test_rejectE :>
    log("Testing proposal rejection..."),
    send(worker, propose(impossible_task)).

coordinator:send_confirmE(Fact) :>
    log("Sending FIPA confirm(~w) to worker", [Fact]),
    send(worker, confirm(Fact)).

coordinator:query_workerE(Q) :>
    log("Sending FIPA query_ref(~w) to worker", [Q]),
    send(worker, query_ref(Q)).

%% Export past rules (DALI ~/ syntax)
%% When both alert and sensor_data in past, consume and react
coordinator:send(logger, log_event(past_consumed, coordinator, [Type, Value])) ~/
    alert(Type, _), sensor_data(Value).

%% Export past NOT done (DALI </ syntax)
%% Warn if backup was NOT done but critical data exists
coordinator:log("EXPORT PAST NOT_DONE: backup NOT done! critical_data needs attention!") </
    critical_data(_).

%% Residue goal test
coordinator:start_residue_testE :>
    log("Starting residue goal test..."),
    achieve(has_past(residue_resolved)).

%% Test goal (DALI test_goal syntax)
coordinator:test_goal(believes(alerts_received(N)), N > 0) :-
    log("Testing if any alerts received...").

%% ============================================================
%% LOGGER — ontology, helpers, condition monitor
%% ============================================================

:- agent(logger, [cycle(2)]).

%% Ontology (DALI2 feature, similar style)
logger:ontology(same_as(log_event, log_entry)).
logger:ontology(eq_property(log_event, record)).
logger:ontology(symmetric(related_to)).

%% Ontology file (DALI2 feature)
logger:ontology_file('examples/test_ontology.pl').

%% External event handler
logger:log_eventE(Type, Source, Data) :>
    log("LOG [~w] from ~w: ~w", [Type, Source, Data]),
    assert_belief(logged(Type, Source)),
    helper(count_logs).

%% Helper (DALI2 feature)
logger:helper(count_logs) :-
    findall(_, believes(logged(_, _)), Logs),
    length(Logs, N),
    log("Total log entries: ~w", [N]).

%% Condition monitor (DALI2 feature, similar style)
logger:when(believes(logged(_, _))) :-
    findall(_, believes(logged(_, _)), Logs),
    length(Logs, N),
    ( N > 10 ->
        log("WARNING: High log volume (~w entries)", [N])
    ; true ).

%% ============================================================
%% WORKER — action proposals, FIPA responses, actions
%% ============================================================

:- agent(worker, [cycle(2)]).

%% Initial beliefs
worker:believes(available(true)).
worker:believes(skill(data_analysis)).
worker:believes(status(ready)).

%% Told rules
worker:told(propose(_), 100).
worker:told(confirm(_), 90).
worker:told(query_ref(_), 80).
worker:told(inform(_, _), 70).

%% Proposal handler (DALI2 feature, similar style)
worker:on_proposal(analyze(Data)) :-
    believes(skill(data_analysis)),
    from(Sender),
    log("PROPOSAL: Accepting analyze(~w) from ~w", [Data, Sender]),
    accept_proposal(Sender, analyze(Data)),
    do(analyze(Data)).

worker:on_proposal(impossible_task) :-
    from(Sender),
    log("PROPOSAL: Rejecting impossible_task from ~w", [Sender]),
    reject_proposal(Sender, impossible_task).

%% Action definition (DALI A suffix style)
worker:analyzeA(Data) :-
    log("Executing analysis: ~w", [Data]),
    assert_belief(analysis_complete(Data)),
    send(coordinator, inform(analysis_result(Data), complete)).

%% External event handler
worker:confirmE(Fact) :>
    log("FIPA CONFIRM received: ~w", [Fact]).

%% Export past rule (DALI ~/ syntax)
worker:send(coordinator, inform(task_report(Task), complete)) ~/
    task_done(Task), report_needed(Task).
