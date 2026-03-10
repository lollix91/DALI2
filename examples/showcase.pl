%% DALI2 Example: Feature Showcase
%% Demonstrates ALL DALI2 rule types and DSL predicates.
%%
%% Agents:
%%   - thermostat:     internal events, constraints, condition-action, beliefs
%%   - sensor:         periodic tasks, present events, learning, blackboard
%%   - coordinator:    reactive rules, tell/told filtering, multi-events, goals
%%   - logger:         ontology-aware matching, helpers
%%
%% Run with:  AGENT_FILE=examples/showcase.pl docker compose up --build
%% Or:        swipl -l src/server.pl -g main -t halt -- 8080 examples/showcase.pl
%%
%% Then inject events via the web UI or curl:
%%   curl -X POST http://localhost:8080/api/send \
%%     -H "Content-Type: application/json" \
%%     -d '{"to":"sensor","content":"read_temp(85)"}'

%% ============================================================
%% THERMOSTAT — internal events, constraints, on_change
%% ============================================================

:- agent(thermostat, [cycle(2)]).

%% Initial beliefs
thermostat:believes(target_temp(22)).
thermostat:believes(current_temp(20)).
thermostat:believes(mode(idle)).

%% Internal event: check temperature every cycle, but only during work hours
thermostat:internal(temp_check, [between(time(0,0), time(23,59))]) :-
    log("Internal: periodic temperature check").

%% Internal event: fire at most 3 times
thermostat:internal(startup_diagnostic, times(3)) :-
    log("Running startup diagnostic..."),
    assert_belief(diagnostic_done).

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
%% SENSOR — periodic, present events, learning, blackboard
%% ============================================================

:- agent(sensor, [cycle(2)]).

%% Initial beliefs
sensor:believes(calibrated(false)).

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

%% Goal: achieve calibration
sensor:goal(achieve, believes(calibrated(true))) :-
    log("Attempting calibration..."),
    send(coordinator, calibration_request).

%% React to calibration confirmation
sensor:on(calibration_done) :-
    log("Calibration confirmed!"),
    retract_belief(calibrated(_)),
    assert_belief(calibrated(true)).

%% ============================================================
%% COORDINATOR — reactive, tell/told, multi-events, goals
%% ============================================================

:- agent(coordinator, [cycle(2)]).

%% Initial beliefs
coordinator:believes(status(active)).
coordinator:believes(alerts_received(0)).

%% Tell/told: coordinator accepts specific message types
coordinator:told(sensor_data(_)).
coordinator:told(alert(_, _), 100).
coordinator:told(emergency(_, _), 200).
coordinator:told(notify(_, _), 50).
coordinator:told(calibration_request, 10).

%% Tell: coordinator can only send these message types
coordinator:tell(calibration_done).
coordinator:tell(response(_)).
coordinator:tell(log_event(_, _, _)).
coordinator:tell(system_ready).

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

%% React to emergency
coordinator:on(emergency(Type, Value)) :-
    log("EMERGENCY: ~w = ~w", [Type, Value]),
    send(logger, log_event(emergency, coordinator, [Type, Value])).

%% React to calibration requests
coordinator:on(calibration_request) :-
    log("Processing calibration request"),
    send(sensor, calibration_done).

%% Goal: test that we have received at least one alert
coordinator:goal(test, believes(alerts_received(N)), N > 0) :-
    log("Testing if any alerts received...").

%% ============================================================
%% LOGGER — ontology-aware, helpers
%% ============================================================

:- agent(logger, [cycle(2)]).

%% Ontology: treat different terms as equivalent
logger:ontology(same_as(log_event, log_entry)).
logger:ontology(eq_property(log_event, record)).
logger:ontology(symmetric(related_to)).

%% React to log events (also matches log_entry thanks to ontology)
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
