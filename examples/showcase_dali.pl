%% DALI2 Example: Feature Showcase (DALI Original Syntax)
%% This file demonstrates DALI2 using the original DALI syntax conventions:
%%   - E suffix for external events, :> operator
%%   - I suffix for internal events, :> operator + internal_event/5
%%   - A suffix for actions
%%   - :< operator for condition-action rules
%%   - ~/ operator for export past
%%   - </ operator for export past NOT done
%%   - ?/ operator for export past done
%%   - :~ operator for constraints
%%   - obt_goal/test_goal for goals
%%   - past_event/2, remember_event/2, remember_event_mod/3
%%   - told/3, tell/3 (DALI communication.con style)
%%
%% DALI2-only features (no DALI equivalent, marked [NEW]):
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
believes(target_temp(22)).
believes(current_temp(20)).
believes(mode(idle)).

%% Internal event with interval (fires every 5 seconds)
temp_checkI :>
    believes(current_temp(T)),
    log("INTERVAL INTERNAL: temperature check (every 5s), current=~w", [T]).
internal_event(temp_check, 5, forever, true, forever).

%% Internal event with change condition
startup_diagnosticI :>
    log("CHANGE INTERNAL: startup diagnostic (resets on temp change)"),
    assert_belief(diagnostic_done).
internal_event(startup_diagnostic, 0, change([current_temp(_)]), true, forever).

%% Internal event with trigger (fires only when mode is cooling)
cooling_monitorI :>
    believes(current_temp(T)),
    log("TRIGGERED INTERNAL: Monitoring cooling, current temp: ~w", [T]).
internal_event(cooling_monitor, 0, forever, believes(mode(cooling)), forever).

%% Constraint: temperature must stay below 50 (DALI :~ syntax)
:~ (believes(current_temp(T)), T < 50) :-
    log("CONSTRAINT VIOLATED: Temperature ~w exceeds safe limit!", [T]),
    send(coordinator, emergency(overheating, T)).

%% Condition-action rule (DALI :< syntax, edge-triggered)
believes(mode(cooling)) :< (
    log("ON_CHANGE: Cooling mode just activated"),
    send(logger, log_event(mode_change, thermostat, cooling))
).

%% External event handlers (DALI :> syntax with E suffix)
set_tempE(NewTarget) :>
    log("Target temperature set to ~w", [NewTarget]),
    retract_belief(target_temp(_)),
    assert_belief(target_temp(NewTarget)).

update_tempE(T) :>
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
believes(calibrated(false)).

%% Past event lifetime (DALI syntax)
past_event(sensor_data(_), 30).
remember_event(sensor_data(_), 300).
remember_event_mod(sensor_data(_), number(10), last).

%% Periodic task [NEW]
every(15, log("Sensor heartbeat")).

%% Present event (monitor blackboard via on_present) [NEW]
sensor:on_present(bb_read(environment(temp, T))) :-
    log("PRESENT: Environment temperature from blackboard: ~w", [T]),
    send(thermostat, update_temp(T)).

%% Learning rules [NEW]
learn_from(read_temp(T), overheating) :- T > 80.
learn_from(read_temp(T), normal) :- T =< 80.

%% External event handler (DALI :> syntax)
read_tempE(T) :>
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
obt_goal(believes(calibrated(true))) :-
    log("Attempting calibration..."),
    send(coordinator, calibration_request).

%% External event handler
calibration_doneE :>
    log("Calibration confirmed!"),
    retract_belief(calibrated(_)),
    assert_belief(calibrated(true)).

%% ============================================================
%% COORDINATOR — reactive, tell/told, FIPA, goals, export past
%% ============================================================

:- agent(coordinator, [cycle(2)]).

%% Initial beliefs
believes(status(active)).
believes(alerts_received(0)).

%% Told rules (DALI communication.con style, 3-arg form)
told(_, emergency(_, _), 200) :- true.
told(_, alert(_, _), 100) :- true.
told(_, confirm(_), 90) :- true.
told(_, inform(_, _), 80) :- true.
told(_, accept_proposal(_), 70) :- true.
told(_, reject_proposal(_), 70) :- true.
told(_, query_ref(_), 60) :- true.
told(_, notify(_, _), 50) :- true.
told(_, sensor_data(_), 30) :- true.
told(_, calibration_request, 10) :- true.

%% Tell rules (DALI communication.con style, 3-arg form)
tell(_, _, calibration_done) :- true.
tell(_, _, response(_)) :- true.
tell(_, _, log_event(_, _, _)) :- true.
tell(_, _, propose(_)) :- true.
tell(_, _, confirm(_)) :- true.
tell(_, _, query_ref(_)) :- true.
tell(_, _, analyze(_)) :- true.

%% Multi-event (DALI conjunction of E-suffix events)
sensor_dataE(_), alertE(_, _) :>
    log("MULTI-EVENT: Both sensor data and alert received!"),
    send(logger, log_event(combined_alert, coordinator, multi_trigger)).

%% External event handlers (DALI :> syntax)
sensor_dataE(T) :>
    log("Coordinator received sensor data: ~w", [T]),
    ( T > 40 ->
        send(logger, log_event(high_temp, coordinator, T))
    ; true ).

alertE(Type, Value) :>
    log("Coordinator alert: ~w = ~w", [Type, Value]),
    believes(alerts_received(N)),
    N1 is N + 1,
    retract_belief(alerts_received(N)),
    assert_belief(alerts_received(N1)).

emergencyE(Type, Value) :>
    log("EMERGENCY: ~w = ~w", [Type, Value]),
    send(logger, log_event(emergency, coordinator, [Type, Value])),
    ( ai_available ->
        ask_ai(analyze(emergency(Type, Value)), Advice),
        log("AI advice for emergency: ~w", [Advice])
    ; true ).

calibration_requestE :>
    log("Processing calibration request"),
    send(sensor, calibration_done).

%% FIPA handlers
confirmE(Fact) :>
    log("FIPA CONFIRM received: ~w", [Fact]).

informE(Content, Meta) :>
    log("FIPA INFORM received: ~w meta=~w", [Content, Meta]).

accept_proposalE(Action) :>
    log("FIPA PROPOSAL ACCEPTED: ~w", [Action]).

reject_proposalE(Action) :>
    log("FIPA PROPOSAL REJECTED: ~w", [Action]).

request_analysisE(Data) :>
    log("Requesting analysis, proposing to worker..."),
    send(worker, propose(analyze(Data))).

test_rejectE :>
    log("Testing proposal rejection..."),
    send(worker, propose(impossible_task)).

send_confirmE(Fact) :>
    log("Sending FIPA confirm(~w) to worker", [Fact]),
    send(worker, confirm(Fact)).

query_workerE(Q) :>
    log("Sending FIPA query_ref(~w) to worker", [Q]),
    send(worker, query_ref(Q)).

%% Export past rules (DALI ~/ syntax)
%% When both alert and sensor_data in past, consume and react
send(logger, log_event(past_consumed, coordinator, [Type, Value])) ~/
    alert(Type, _), sensor_data(Value).

%% Export past NOT done (DALI </ syntax)
%% Warn if backup was NOT done but critical data exists
log("EXPORT PAST NOT_DONE: backup NOT done! critical_data needs attention!") </
    critical_data(_).

%% Residue goal test
start_residue_testE :>
    log("Starting residue goal test..."),
    achieve(has_past(residue_resolved)).

%% Test goal (DALI test_goal syntax)
test_goal(believes(alerts_received(N)), N > 0) :-
    log("Testing if any alerts received...").

%% ============================================================
%% LOGGER — ontology, helpers, condition monitor
%% ============================================================

:- agent(logger, [cycle(2)]).

%% Ontology [NEW]
ontology(same_as(log_event, log_entry)).
ontology(eq_property(log_event, record)).
ontology(symmetric(related_to)).

%% External ontology file [NEW]
ontology_file('examples/test_ontology.pl').

%% External event handler
log_eventE(Type, Source, Data) :>
    log("LOG [~w] from ~w: ~w", [Type, Source, Data]),
    assert_belief(logged(Type, Source)),
    helper(count_logs).

%% Helper [NEW]
helper(count_logs) :-
    findall(_, believes(logged(_, _)), Logs),
    length(Logs, N),
    log("Total log entries: ~w", [N]).

%% Condition monitor [NEW]
when(believes(logged(_, _))) :-
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
believes(available(true)).
believes(skill(data_analysis)).
believes(status(ready)).

%% Told rules (DALI communication.con style)
told(_, propose(_), 100) :- true.
told(_, confirm(_), 90) :- true.
told(_, query_ref(_), 80) :- true.
told(_, inform(_, _), 70) :- true.

%% Action proposal handlers [NEW]
on_proposal(analyze(Data)) :-
    believes(skill(data_analysis)),
    from(Sender),
    log("PROPOSAL: Accepting analyze(~w) from ~w", [Data, Sender]),
    accept_proposal(Sender, analyze(Data)),
    do(analyze(Data)).

on_proposal(impossible_task) :-
    from(Sender),
    log("PROPOSAL: Rejecting impossible_task from ~w", [Sender]),
    reject_proposal(Sender, impossible_task).

%% Action definition (DALI A suffix style)
analyzeA(Data) :-
    log("Executing analysis: ~w", [Data]),
    assert_belief(analysis_complete(Data)),
    send(coordinator, inform(analysis_result(Data), complete)).

%% External event handler
confirmE(Fact) :>
    log("FIPA CONFIRM received: ~w", [Fact]).

%% Export past rule (DALI ~/ syntax)
send(coordinator, inform(task_report(Task), complete)) ~/
    task_done(Task), report_needed(Task).
