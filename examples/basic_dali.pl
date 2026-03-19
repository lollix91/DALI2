%% DALI2 Example: Basic DALI Syntax (fully backward compatible)
%% No agent: prefix needed — identical to original DALI syntax.
%% Each :- agent(Name). sets the context for subsequent rules.

%% ============================================================
%% AGENT 1: sensor
%% ============================================================
:- agent(sensor, [cycle(2)]).

%% Initial beliefs (bare facts become beliefs)
notified(false).

%% External event handlers (E suffix + :> operator)
read_soilE(Moisture, PH, Field) :>
    log("Soil reading: moisture=~w, pH=~w, field=~w", [Moisture, PH, Field]),
    assert_belief(soil_state(Moisture, PH, Field)),
    messageA(advisor, send_message(soil_report(Moisture, PH, Field), sensor)).

%% Internal event handler (I suffix + :> operator)
check_alertI :>
    believes(soil_state(M, _PH, Field)),
    M < 30,
    log("ALERT: Low moisture ~w at ~w", [M, Field]),
    send(advisor, alert(low_moisture, Field)).

%% Internal event configuration (DALI internal_event/5)
internal_event(check_alert, 3, forever, true, until_cond(past(check_alert))).

%% Past event lifetime (DALI syntax)
past_event(soil_report(_, _, _), 60).
remember_event(soil_report(_, _, _), 3600).

%% ============================================================
%% AGENT 2: advisor
%% ============================================================
:- agent(advisor, [cycle(2)]).

believes(mode(normal)).

%% Told rules (DALI communication.con style)
told(_, alert(_, _), 100) :- true.
told(_, soil_report(_, _, _), 50) :- true.

%% External event handler
soil_reportE(Moisture, PH, Field) :>
    log("Advisor received soil report: M=~w, pH=~w, F=~w", [Moisture, PH, Field]),
    ( Moisture < 30 ->
        send(controller, irrigate(Field)),
        send(farmer, advisory(irrigate, Field))
    ; Moisture > 80 ->
        send(controller, reduce_water(Field))
    ;
        log("Soil normal at ~w", [Field])
    ).

alertE(Type, Field) :>
    log("Alert: ~w at ~w", [Type, Field]),
    send(farmer, notify(Type, Field)).

%% Condition-action rule (DALI :< operator)
believes(mode(emergency)) :<
    log("Emergency mode activated!"),
    send(farmer, advisory(emergency, all_fields)).

%% Export past (DALI ~/ operator)
send(farmer, combined_report(Type, Field)) ~/
    alert(Type, Field), soil_report(_, _, Field).

%% Obtain goal (DALI obt_goal)
obt_goal(believes(advisor_ready)) :-
    log("Trying to become ready..."),
    assert_belief(advisor_ready).

%% ============================================================
%% AGENT 3: controller
%% ============================================================
:- agent(controller, [cycle(2)]).

believes(status(idle)).

%% External event handlers
irrigateE(Field) :>
    log("Irrigating ~w", [Field]),
    retract_belief(status(_)),
    assert_belief(status(irrigating(Field))),
    send(farmer, status(irrigating, Field)).

reduce_waterE(Field) :>
    log("Reducing water at ~w", [Field]),
    send(farmer, status(reduced, Field)).

%% Action definition (DALI A suffix)
activate_irrigationA(Field) :-
    log("Activating irrigation system at ~w", [Field]).

%% ============================================================
%% AGENT 4: farmer
%% ============================================================
:- agent(farmer, [cycle(2)]).

%% External event handlers
advisoryE(Type, Field) :>
    log("Farmer received advisory: ~w at ~w", [Type, Field]).

notifyE(Type, Field) :>
    log("Farmer notified: ~w at ~w", [Type, Field]).

statusE(State, Field) :>
    log("Farmer status update: ~w at ~w", [State, Field]).

%% Periodic task (DALI2 new feature)
every(30, log("Farmer checking dashboard")).

%% Learning rule (DALI2 new feature)
learn_from(advisory(irrigate, _), irrigation_needed) :- true.
