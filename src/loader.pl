%% DALI2 Loader - Agent definition parser
%% Supports both DALI original syntax and DALI2 syntax.
%%
%% DALI original syntax (with agent prefix for multi-agent files):
%%   - Agent declarations:    :- agent(Name, Options).
%%   - External events:       Name:eventE(X) :> body.        (E suffix + :> operator)
%%   - Internal events:       Name:eventI(X) :> body.        (I suffix + :> operator)
%%   - Internal event config: Name:internal_event(Ev, Period, Rep, Start, Stop).
%%   - Actions:               Name:actionA(X) :- body.       (A suffix)
%%   - Present events:        Name:condN :- body.            (N suffix)
%%   - Condition-action:      Name:cond :< action.           (:< operator)
%%   - Export past:           Name:head ~/ past1, past2.     (~/ operator)
%%   - Export past not done:  Name:head </ past1, past2.     (</ operator)
%%   - Export past done:      Name:head ?/ past1, past2.     (?/ operator)
%%   - Constraints:           Name :~ condition.  /  Name :~ condition :- handler.
%%   - Told rules:            Name:told(Pattern, Priority).
%%   - Tell rules:            Name:tell(Pattern).
%%   - Past lifetime:         Name:past_event(Event, Duration).
%%   - Remember lifetime:     Name:remember_event(Event, Duration).
%%   - Remember limit:        Name:remember_event_mod(Event, number(N), Mode).
%%   - Obtain goal:           Name:obt_goal(Goal) :- Plan.
%%   - Test goal:             Name:test_goal(Goal) :- Plan.
%%   - Beliefs:               Name:believes(Fact).
%%   - Ontology:              Name:ontology(Declaration).
%%   - Learning:              Name:learn_from(Event, Outcome) :- Body.
%%
%% DALI2-only features (similar style):
%%   - Periodic tasks:        Name:every(Seconds, Goal).
%%   - Condition monitors:    Name:when(Condition) :- Body.
%%   - Helpers:               Name:helper(Head) :- Body.
%%   - Proposal handlers:     Name:on_proposal(Action) :- Body.
%%   - Ontology files:        Name:ontology_file(File).
%%   - AI Oracle:             ask_ai(Context, Result) (body predicate)
%%   - Blackboard:            bb_read/bb_write/bb_remove (body predicates)
%%
%% DALI2 syntax (backward compatible):
%%   - Name:on(Event) :- Body.
%%   - Name:internal(Event, [Options]) :- Body.
%%   - Name:do(Action) :- Body.
%%   - Name:on_present(Condition) :- Body.
%%   - Name:on_change(Condition) :- Body.
%%   - Name:on_past([Events]) :- Body.
%%   - Name:on_past_done(Action, [Events]) :- Body.
%%   - Name:on_past_not_done(Action, [Events]) :- Body.
%%   - Name:constraint(Condition) :- Body.
%%   - Name:on_all([Events]) :- Body.
%%   - Name:goal(achieve/test, Goal) :- Plan.
%%   - Name:past_lifetime(Pattern, Duration).
%%   - Name:remember_lifetime(Pattern, Duration).
%%   - Name:remember_limit(Pattern, N, Mode).

:- module(loader, [
    load_agents/1,
    load_agents_from_string/1,
    agent_def/2,
    agent_handler/3,
    agent_periodic/3,
    agent_monitor/3,
    agent_action/3,
    agent_belief/2,
    agent_helper/3,
    agent_internal/4,
    agent_told/3,
    agent_tell/2,
    agent_condition_action/3,
    agent_present/3,
    agent_multi_event/3,
    agent_constraint/3,
    agent_ontology/2,
    agent_learn_rule/4,
    agent_goal/4,
    agent_past_lifetime/3,
    agent_remember_lifetime/3,
    agent_remember_limit/4,
    agent_past_reaction/3,
    agent_past_done_reaction/4,
    agent_past_not_done_reaction/4,
    agent_ontology_file/2,
    agent_on_proposal/3,
    agent_internal_config/6,
    clear_definitions/0,
    transform_body/2
]).

:- use_module(library(lists)).

%% ============================================================
%% DALI OPERATORS - Must be defined before reading agent files
%% These mirror the original DALI operators from SICStus Prolog.
%% ============================================================
:- op(1200, xfx, :>).
:- op(1200, xfx, :<).
:- op(1200, xfx, ~/).
:- op(1200, xfx, </).
:- op(1200, xfx, ?/).
:- op(1200, xfx, :~).

%% ============================================================
%% STORED DEFINITIONS
%% ============================================================
:- dynamic agent_def/2.              % agent_def(Name, Options)
:- dynamic agent_handler/3.          % agent_handler(Name, Event, Body)
:- dynamic agent_periodic/3.         % agent_periodic(Name, Seconds, Body)
:- dynamic agent_monitor/3.          % agent_monitor(Name, Condition, Body)
:- dynamic agent_action/3.           % agent_action(Name, Action, Body)
:- dynamic agent_belief/2.           % agent_belief(Name, Fact)
:- dynamic agent_helper/3.           % agent_helper(Name, Head, Body)
:- dynamic agent_internal/4.         % agent_internal(Name, Event, Options, Body)
:- dynamic agent_told/3.             % agent_told(Name, Pattern, Priority)
:- dynamic agent_tell/2.             % agent_tell(Name, Pattern)
:- dynamic agent_condition_action/3. % agent_condition_action(Name, Condition, Body)
:- dynamic agent_present/3.          % agent_present(Name, Condition, Body)
:- dynamic agent_multi_event/3.      % agent_multi_event(Name, EventList, Body)
:- dynamic agent_constraint/3.       % agent_constraint(Name, Condition, Body)
:- dynamic agent_ontology/2.         % agent_ontology(Name, Declaration)
:- dynamic agent_learn_rule/4.       % agent_learn_rule(Name, Event, Outcome, Body)
:- dynamic agent_goal/4.             % agent_goal(Name, Type, Goal, Plan)
:- dynamic agent_past_lifetime/3.    % agent_past_lifetime(Name, Pattern, Duration)
:- dynamic agent_remember_lifetime/3. % agent_remember_lifetime(Name, Pattern, Duration)
:- dynamic agent_remember_limit/4.   % agent_remember_limit(Name, Pattern, N, Mode)
:- dynamic agent_past_reaction/3.    % agent_past_reaction(Name, EventList, Body)
:- dynamic agent_past_done_reaction/4. % agent_past_done_reaction(Name, Action, EventList, Body)
:- dynamic agent_past_not_done_reaction/4. % agent_past_not_done_reaction(Name, Action, EventList, Body)
:- dynamic agent_ontology_file/2.    % agent_ontology_file(Name, File)
:- dynamic agent_on_proposal/3.      % agent_on_proposal(Name, ActionPattern, Body)
:- dynamic agent_internal_config/6.  % agent_internal_config(Name, Event, Period, Repetition, StartCond, StopCond)

%% ============================================================
%% CLEAR / LOAD
%% ============================================================

%% clear_definitions/0 - Remove all loaded definitions
clear_definitions :-
    retractall(agent_def(_, _)),
    retractall(agent_handler(_, _, _)),
    retractall(agent_periodic(_, _, _)),
    retractall(agent_monitor(_, _, _)),
    retractall(agent_action(_, _, _)),
    retractall(agent_belief(_, _)),
    retractall(agent_helper(_, _, _)),
    retractall(agent_internal(_, _, _, _)),
    retractall(agent_told(_, _, _)),
    retractall(agent_tell(_, _)),
    retractall(agent_condition_action(_, _, _)),
    retractall(agent_present(_, _, _)),
    retractall(agent_multi_event(_, _, _)),
    retractall(agent_constraint(_, _, _)),
    retractall(agent_ontology(_, _)),
    retractall(agent_learn_rule(_, _, _, _)),
    retractall(agent_goal(_, _, _, _)),
    retractall(agent_past_lifetime(_, _, _)),
    retractall(agent_remember_lifetime(_, _, _)),
    retractall(agent_remember_limit(_, _, _, _)),
    retractall(agent_past_reaction(_, _, _)),
    retractall(agent_past_done_reaction(_, _, _, _)),
    retractall(agent_past_not_done_reaction(_, _, _, _)),
    retractall(agent_ontology_file(_, _)),
    retractall(agent_on_proposal(_, _, _)),
    retractall(agent_internal_config(_, _, _, _, _, _)).

%% load_agents(+File) - Load agent definitions from a file
load_agents(File) :-
    clear_definitions,
    read_file_terms(File, Terms),
    process_terms(Terms),
    post_process_internals.

%% load_agents_from_string(+String) - Load agent definitions from a string
load_agents_from_string(String) :-
    clear_definitions,
    term_string(Terms, String),
    (is_list(Terms) ->
        process_terms(Terms)
    ;
        process_terms([Terms])
    ),
    post_process_internals.

%% read_file_terms(+File, -Terms) - Read all terms from a file
read_file_terms(File, Terms) :-
    setup_call_cleanup(
        open(File, read, Stream, []),
        read_all_terms(Stream, Terms),
        close(Stream)
    ).

read_all_terms(Stream, Terms) :-
    read_term(Stream, Term, [module(loader)]),
    (Term == end_of_file ->
        Terms = []
    ;
        Terms = [Term | Rest],
        read_all_terms(Stream, Rest)
    ).

%% process_terms(+Terms) - Process a list of terms into agent definitions
process_terms([]).
process_terms([Term | Rest]) :-
    (process_term(Term) -> true ;
        format(atom(Msg), "Warning: could not process term: ~w~n", [Term]),
        print_message(warning, format(Msg, []))
    ),
    process_terms(Rest).

%% ============================================================
%% SUFFIX UTILITIES - Extract DALI suffixes (E, I, A, N, P)
%% ============================================================

%% extract_suffix(+Atom, -Base, -Suffix)
%% Extracts the DALI suffix letter from a functor name.
%% E.g., extract_suffix(goE, go, 'E') succeeds.
extract_suffix(Atom, Base, Suffix) :-
    atom(Atom),
    atom_chars(Atom, Chars),
    Chars \= [],
    last(Chars, LastChar),
    member(LastChar, ['E', 'I', 'A', 'N', 'P']),
    append(BaseChars, [LastChar], Chars),
    BaseChars \= [],
    atom_chars(Base, BaseChars),
    atom_chars(Suffix, [LastChar]).

%% strip_suffix_term(+Term, -BaseTerm, -Suffix)
%% Strips the DALI suffix from a compound term or atom.
%% E.g., strip_suffix_term(goE(X), go(X), 'E').
strip_suffix_term(Term, BaseTerm, Suffix) :-
    (compound(Term) ->
        Term =.. [Functor | Args],
        extract_suffix(Functor, BaseFunctor, Suffix),
        BaseTerm =.. [BaseFunctor | Args]
    ;
        atom(Term),
        extract_suffix(Term, BaseTerm, Suffix)
    ).

%% ============================================================
%% BODY TRANSFORMATION - Convert DALI body predicates to DALI2
%% ============================================================

%% transform_body(+DaliBody, -Dali2Body)
%% Recursively transforms DALI-style body predicates into DALI2 equivalents.
transform_body(Var, Var) :- var(Var), !.
transform_body(true, true) :- !.
transform_body((A, B), (TA, TB)) :- !,
    transform_body(A, TA),
    transform_body(B, TB).
transform_body((A ; B), (TA ; TB)) :- !,
    transform_body(A, TA),
    transform_body(B, TB).
transform_body((A -> B), (TA -> TB)) :- !,
    transform_body(A, TA),
    transform_body(B, TB).
transform_body(\+(A), \+(TA)) :- !,
    transform_body(A, TA).
transform_body(not(A), not(TA)) :- !,
    transform_body(A, TA).

%% messageA(Dest, send_message(Content, _Me)) → send(Dest, Content)
transform_body(messageA(Dest, send_message(Content, _Me)), send(Dest, Content)) :- !.
transform_body(messageA(Dest, send_message(Content)), send(Dest, Content)) :- !.

%% evp(Event) → has_past(Event)  (DALI past event check)
transform_body(evp(Event), has_past(Event)) :- !.

%% clause(past(Event,_,_),_) → has_past(Event)  (DALI past check pattern)
transform_body(clause(past(Event,_,_),_), has_past(Event)) :- !.

%% clause(isa(Fact,_,_),_) → believes(Fact)  (DALI belief check pattern)
transform_body(clause(isa(Fact,_,_),_), believes(Fact)) :- !.

%% tenta_residuo(Goal) → achieve(Goal)  (DALI residue goal)
transform_body(tenta_residuo(Goal), achieve(Goal)) :- !.

%% Terms with A suffix in body (actions): actionA(Args) → do(action(Args))
%% But NOT messageA (already handled above)
transform_body(Term, do(BaseTerm)) :-
    nonvar(Term),
    \+ functor(Term, messageA, _),
    strip_suffix_term(Term, BaseTerm, 'A'), !.

%% Terms with P suffix in body (past check): eventP(Args) → has_past(event(Args))
transform_body(Term, has_past(BaseTerm)) :-
    nonvar(Term),
    strip_suffix_term(Term, BaseTerm, 'P'), !.

%% Default: leave unchanged
transform_body(Term, Term).

%% ============================================================
%% EXPORT PAST BODY PARSING - Parse comma-separated past events
%% ============================================================

%% parse_past_list(+Body, -EventList)
%% Converts a comma-separated body into a list of past event patterns.
parse_past_list((A, B), [A | Rest]) :- !,
    parse_past_list(B, Rest).
parse_past_list(A, [A]).

%% ============================================================
%% TERM PROCESSING - Handle both DALI and DALI2 syntax
%% ============================================================

%% process_term(+Term) - Process a single term

%% --- Agent declaration ---
process_term(:- agent(Name, Options)) :- !,
    assert(agent_def(Name, Options)).
process_term(:- agent(Name)) :- !,
    assert(agent_def(Name, [])).

%% ============================================================
%% DALI SYNTAX: :> operator (external and internal events)
%% ============================================================

%% Name:headE(X) :> Body  →  external event handler (strip E suffix)
%% Name:headI(X) :> Body  →  internal event handler (strip I suffix)
%% Name:head1E(X), head2E(Y) :> Body  →  multi-event (conjunction of E-suffixed)
process_term(:>(Name:Head, Body)) :- !,
    transform_body(Body, TBody),
    process_reactive_rule(Name, Head, TBody).
%% Without agent prefix (single-agent file compatibility)
process_term(:>(Head, Body)) :-
    \+ (Head = _:_), !,
    transform_body(Body, TBody),
    %% Try to find current agent or use 'default'
    (agent_def(DefaultName, _) ->
        process_reactive_rule(DefaultName, Head, TBody)
    ;
        format(user_error, "DALI2 loader: :> rule without agent prefix, no agent defined: ~w~n", [Head])
    ).

%% process_reactive_rule(+Name, +Head, +Body)
%% Determines from the suffix whether this is an external event, internal event, or multi-event.
process_reactive_rule(Name, Head, Body) :-
    %% Check for multi-event (conjunction on LHS)
    (Head = (H1, H2) ->
        collect_multi_events(Head, EventList),
        assert(agent_multi_event(Name, EventList, Body))
    ;
        %% Single event — check suffix
        (strip_suffix_term(Head, BaseHead, Suffix) ->
            process_suffixed_reactive(Name, BaseHead, Suffix, Body)
        ;
            %% No recognized suffix — treat as external event handler
            assert(agent_handler(Name, Head, Body))
        )
    ).

%% process_suffixed_reactive(+Name, +BaseHead, +Suffix, +Body)
process_suffixed_reactive(Name, BaseHead, 'E', Body) :- !,
    assert(agent_handler(Name, BaseHead, Body)).
process_suffixed_reactive(Name, BaseHead, 'I', Body) :- !,
    %% Internal event handler — body from :> rule, config from internal_event/5 if present
    assert(agent_internal(Name, BaseHead, [forever], Body)).
process_suffixed_reactive(Name, BaseHead, _, Body) :-
    %% Unknown suffix with :> — treat as external event
    assert(agent_handler(Name, BaseHead, Body)).

%% collect_multi_events(+ConjHead, -EventList)
%% Flattens a conjunction of E-suffixed heads into a list of base events.
collect_multi_events((H1, H2), [Base1 | Rest]) :- !,
    (strip_suffix_term(H1, Base1, 'E') -> true ; Base1 = H1),
    collect_multi_events(H2, Rest).
collect_multi_events(H, [Base]) :-
    (strip_suffix_term(H, Base, 'E') -> true ; Base = H).

%% ============================================================
%% DALI SYNTAX: :< operator (condition-action rules)
%% ============================================================

%% Name:condition :< action  →  condition-action (edge-triggered)
process_term(:<(Name:Condition, Action)) :- !,
    transform_body(Action, TAction),
    assert(agent_condition_action(Name, Condition, TAction)).
process_term(:<(Condition, Action)) :-
    \+ (Condition = _:_), !,
    transform_body(Action, TAction),
    (agent_def(DefaultName, _) ->
        assert(agent_condition_action(DefaultName, Condition, TAction))
    ;
        format(user_error, "DALI2 loader: :< rule without agent, no agent defined~n", [])
    ).

%% ============================================================
%% DALI SYNTAX: ~/ operator (export past)
%% ============================================================

%% Name:action ~/ past1, past2  →  on_past reaction
process_term(~/(Name:Action, PastBody)) :- !,
    parse_past_list(PastBody, EventList),
    transform_body(Action, TAction),
    assert(agent_past_reaction(Name, EventList, TAction)).
process_term(~/(Action, PastBody)) :-
    \+ (Action = _:_), !,
    parse_past_list(PastBody, EventList),
    transform_body(Action, TAction),
    (agent_def(DefaultName, _) ->
        assert(agent_past_reaction(DefaultName, EventList, TAction))
    ;
        format(user_error, "DALI2 loader: ~/ rule without agent, no agent defined~n", [])
    ).

%% ============================================================
%% DALI SYNTAX: </ operator (export past NOT done)
%% ============================================================

%% Name:action </ past1, past2  →  on_past_not_done reaction
process_term(</(Name:Action, PastBody)) :- !,
    parse_past_list(PastBody, EventList),
    assert(agent_past_not_done_reaction(Name, Action, EventList, true)).
process_term(</(Action, PastBody)) :-
    \+ (Action = _:_), !,
    parse_past_list(PastBody, EventList),
    (agent_def(DefaultName, _) ->
        assert(agent_past_not_done_reaction(DefaultName, Action, EventList, true))
    ;
        format(user_error, "DALI2 loader: </ rule without agent, no agent defined~n", [])
    ).

%% ============================================================
%% DALI SYNTAX: ?/ operator (export past done)
%% ============================================================

%% Name:action ?/ past1, past2  →  on_past_done reaction
process_term(?/(Name:Action, PastBody)) :- !,
    parse_past_list(PastBody, EventList),
    assert(agent_past_done_reaction(Name, Action, EventList, true)).
process_term(?/(Action, PastBody)) :-
    \+ (Action = _:_), !,
    parse_past_list(PastBody, EventList),
    (agent_def(DefaultName, _) ->
        assert(agent_past_done_reaction(DefaultName, Action, EventList, true))
    ;
        format(user_error, "DALI2 loader: ?/ rule without agent, no agent defined~n", [])
    ).

%% ============================================================
%% DALI SYNTAX: :~ operator (constraints)
%% ============================================================

%% Name :~ Condition :- Handler  →  constraint with handler
process_term(:~(Name, (Condition :- Handler))) :-
    atom(Name), !,
    transform_body(Handler, THandler),
    assert(agent_constraint(Name, Condition, THandler)).

%% Name :~ Condition  →  constraint without handler
process_term(:~(Name, Condition)) :-
    atom(Name), !,
    assert(agent_constraint(Name, Condition, true)).

%% ============================================================
%% DALI SYNTAX: internal_event/5 configuration
%% ============================================================

%% Name:internal_event(Event, Period, Repetition, StartCond, StopCond).
process_term(Name:internal_event(Event, Period, Repetition, StartCond, StopCond)) :- !,
    assert(agent_internal_config(Name, Event, Period, Repetition, StartCond, StopCond)).

%% ============================================================
%% DALI SYNTAX: past_event/2, remember_event/2, remember_event_mod/3
%% ============================================================

%% Name:past_event(Pattern, Duration).  →  past_lifetime
process_term(Name:past_event(Pattern, Duration)) :- !,
    assert(agent_past_lifetime(Name, Pattern, Duration)).

%% Name:remember_event(Pattern, Duration).  →  remember_lifetime
process_term(Name:remember_event(Pattern, Duration)) :- !,
    assert(agent_remember_lifetime(Name, Pattern, Duration)).

%% Name:remember_event_mod(Pattern, number(N), Mode).  →  remember_limit
process_term(Name:remember_event_mod(Pattern, number(N), Mode)) :- !,
    assert(agent_remember_limit(Name, Pattern, N, Mode)).

%% ============================================================
%% DALI SYNTAX: obt_goal/test_goal (goal declarations)
%% ============================================================

%% Name:obt_goal(Goal) :- Plan.  →  achieve goal
process_term((Name:obt_goal(Goal) :- Plan)) :- !,
    transform_body(Plan, TPlan),
    assert(agent_goal(Name, achieve, Goal, TPlan)).

%% Name:obt_goal(Goal).  →  achieve goal (no plan)
process_term(Name:obt_goal(Goal)) :- !,
    assert(agent_goal(Name, achieve, Goal, true)).

%% Name:test_goal(Goal) :- Plan.  →  test goal
process_term((Name:test_goal(Goal) :- Plan)) :- !,
    transform_body(Plan, TPlan),
    assert(agent_goal(Name, test, Goal, TPlan)).

%% Name:test_goal(Goal).  →  test goal (no plan)
process_term(Name:test_goal(Goal)) :- !,
    assert(agent_goal(Name, test, Goal, true)).

%% ============================================================
%% DALI SYNTAX: told/tell (communication filtering)
%% ============================================================

%% DALI-style: Name:told(_, Pattern, Priority).
process_term(Name:told(_, Pattern, Priority)) :- !,
    assert(agent_told(Name, Pattern, Priority)).

%% DALI-style: Name:tell(_, _, Pattern).
process_term(Name:tell(_, _, Pattern)) :- !,
    assert(agent_tell(Name, Pattern)).

%% ============================================================
%% DALI SYNTAX: Action definitions with A suffix
%% ============================================================

%% Name:actionA(Args) :- Body.  →  action definition (strip A suffix)
process_term((Name:Head :- Body)) :-
    strip_suffix_term(Head, BaseHead, 'A'), !,
    transform_body(Body, TBody),
    assert(agent_action(Name, BaseHead, TBody)).

%% Name:actionA(Args).  →  action definition with true body
process_term(Name:Head) :-
    nonvar(Head),
    strip_suffix_term(Head, BaseHead, 'A'),
    %% Avoid matching told/tell/believes etc.
    \+ functor(BaseHead, told, _),
    \+ functor(BaseHead, tell, _),
    \+ functor(BaseHead, believes, _), !,
    assert(agent_action(Name, BaseHead, true)).

%% ============================================================
%% DALI SYNTAX: Present event with N suffix
%% ============================================================

%% Name:condN(Args) :- Body.  →  present/environment event (strip N suffix)
process_term((Name:Head :- Body)) :-
    strip_suffix_term(Head, BaseHead, 'N'), !,
    transform_body(Body, TBody),
    assert(agent_present(Name, BaseHead, TBody)).

%% ============================================================
%% DALI2 SYNTAX (backward compatible)
%% ============================================================

%% Event handler: Name:on(Event) :- Body.
process_term((Name:on(Event) :- Body)) :- !,
    transform_body(Body, TBody),
    assert(agent_handler(Name, Event, TBody)).

%% Event handler without body: Name:on(Event).
process_term(Name:on(Event)) :- !,
    assert(agent_handler(Name, Event, true)).

%% Periodic rule: Name:every(Seconds, Goal).
process_term(Name:every(Seconds, Goal)) :- !,
    assert(agent_periodic(Name, Seconds, Goal)).

%% Periodic rule with body: Name:every(Seconds) :- Body.
process_term((Name:every(Seconds) :- Body)) :- !,
    transform_body(Body, TBody),
    assert(agent_periodic(Name, Seconds, TBody)).

%% Condition monitor: Name:when(Condition) :- Body.
process_term((Name:when(Condition) :- Body)) :- !,
    transform_body(Body, TBody),
    assert(agent_monitor(Name, Condition, TBody)).

%% Condition monitor with two conditions: Name:when(C1, C2) :- Body.
process_term((Name:when(C1, C2) :- Body)) :- !,
    transform_body(Body, TBody),
    assert(agent_monitor(Name, (C1, C2), TBody)).

%% Action: Name:do(Action) :- Body.
process_term((Name:do(Action) :- Body)) :- !,
    transform_body(Body, TBody),
    assert(agent_action(Name, Action, TBody)).

%% Action without body: Name:do(Action).
process_term(Name:do(Action)) :- !,
    assert(agent_action(Name, Action, true)).

%% Belief: Name:believes(Fact).
process_term(Name:believes(Fact)) :- !,
    assert(agent_belief(Name, Fact)).

%% Helper clause: Name:helper(Head) :- Body.
process_term((Name:helper(Head) :- Body)) :- !,
    transform_body(Body, TBody),
    assert(agent_helper(Name, Head, TBody)).

%% Helper clause without body: Name:helper(Head).
process_term(Name:helper(Head)) :- !,
    assert(agent_helper(Name, Head, true)).

%% Internal event with options: Name:internal(Event, Options) :- Body.
process_term((Name:internal(Event, Options) :- Body)) :- !,
    (is_list(Options) -> Opts = Options ; Opts = [Options]),
    transform_body(Body, TBody),
    assert(agent_internal(Name, Event, Opts, TBody)).

%% Internal event without options (forever): Name:internal(Event) :- Body.
process_term((Name:internal(Event) :- Body)) :- !,
    transform_body(Body, TBody),
    assert(agent_internal(Name, Event, [forever], TBody)).

%% Internal event fact: Name:internal(Event).
process_term(Name:internal(Event)) :- !,
    assert(agent_internal(Name, Event, [forever], true)).

%% Internal event fact with options: Name:internal(Event, Options).
process_term(Name:internal(Event, Options)) :- !,
    (is_list(Options) -> Opts = Options ; Opts = [Options]),
    assert(agent_internal(Name, Event, Opts, true)).

%% Told rule with priority: Name:told(Pattern, Priority).
process_term(Name:told(Pattern, Priority)) :- !,
    assert(agent_told(Name, Pattern, Priority)).

%% Told rule: Name:told(Pattern).
process_term(Name:told(Pattern)) :- !,
    assert(agent_told(Name, Pattern, 0)).

%% Tell rule: Name:tell(Pattern).
process_term(Name:tell(Pattern)) :- !,
    assert(agent_tell(Name, Pattern)).

%% Condition-action (edge-triggered): Name:on_change(Condition) :- Body.
process_term((Name:on_change(Condition) :- Body)) :- !,
    transform_body(Body, TBody),
    assert(agent_condition_action(Name, Condition, TBody)).

%% Condition-action with two conditions: Name:on_change(C1, C2) :- Body.
process_term((Name:on_change(C1, C2) :- Body)) :- !,
    transform_body(Body, TBody),
    assert(agent_condition_action(Name, (C1, C2), TBody)).

%% Present/environment event: Name:on_present(Condition) :- Body.
process_term((Name:on_present(Condition) :- Body)) :- !,
    transform_body(Body, TBody),
    assert(agent_present(Name, Condition, TBody)).

%% Present event with two conditions: Name:on_present(C1, C2) :- Body.
process_term((Name:on_present(C1, C2) :- Body)) :- !,
    transform_body(Body, TBody),
    assert(agent_present(Name, (C1, C2), TBody)).

%% Multi-event (all must occur): Name:on_all(EventList) :- Body.
process_term((Name:on_all(EventList) :- Body)) :- !,
    transform_body(Body, TBody),
    assert(agent_multi_event(Name, EventList, TBody)).

%% Constraint with handler: Name:constraint(Condition) :- Body.
process_term((Name:constraint(Condition) :- Body)) :- !,
    transform_body(Body, TBody),
    assert(agent_constraint(Name, Condition, TBody)).

%% Constraint with two conditions and handler: Name:constraint(C1, C2) :- Body.
process_term((Name:constraint(C1, C2) :- Body)) :- !,
    transform_body(Body, TBody),
    assert(agent_constraint(Name, (C1, C2), TBody)).

%% Constraint without handler: Name:constraint(Condition).
process_term(Name:constraint(Condition)) :- !,
    assert(agent_constraint(Name, Condition, true)).

%% Constraint with two conditions, no handler: Name:constraint(C1, C2).
process_term(Name:constraint(C1, C2)) :- !,
    assert(agent_constraint(Name, (C1, C2), true)).

%% Ontology declaration: Name:ontology(Declaration).
process_term(Name:ontology(Declaration)) :- !,
    assert(agent_ontology(Name, Declaration)).

%% Learning rule: Name:learn_from(Event, Outcome) :- Body.
process_term((Name:learn_from(Event, Outcome) :- Body)) :- !,
    transform_body(Body, TBody),
    assert(agent_learn_rule(Name, Event, Outcome, TBody)).

%% Learning rule without body: Name:learn_from(Event, Outcome).
process_term(Name:learn_from(Event, Outcome)) :- !,
    assert(agent_learn_rule(Name, Event, Outcome, true)).

%% Goal: Name:goal(Type, GoalCondition) :- Plan.
process_term((Name:goal(Type, Goal) :- Plan)) :- !,
    transform_body(Plan, TPlan),
    assert(agent_goal(Name, Type, Goal, TPlan)).

%% Goal with extra condition: Name:goal(Type, GoalCond, ExtraCond) :- Plan.
process_term((Name:goal(Type, Goal, Extra) :- Plan)) :- !,
    transform_body(Plan, TPlan),
    assert(agent_goal(Name, Type, (Goal, Extra), TPlan)).

%% Goal without plan: Name:goal(Type, GoalCondition).
process_term(Name:goal(Type, Goal)) :- !,
    assert(agent_goal(Name, Type, Goal, true)).

%% Directives (other :- terms) - execute them
process_term(:- Goal) :- !,
    catch(call(Goal), _, true).

%% Past lifetime: Name:past_lifetime(Pattern, Duration).
process_term(Name:past_lifetime(Pattern, Duration)) :- !,
    assert(agent_past_lifetime(Name, Pattern, Duration)).

%% Remember lifetime: Name:remember_lifetime(Pattern, Duration).
process_term(Name:remember_lifetime(Pattern, Duration)) :- !,
    assert(agent_remember_lifetime(Name, Pattern, Duration)).

%% Remember limit: Name:remember_limit(Pattern, N, Mode).
process_term(Name:remember_limit(Pattern, N, Mode)) :- !,
    assert(agent_remember_limit(Name, Pattern, N, Mode)).

%% Export past reaction (~/): Name:on_past(EventList) :- Body.
process_term((Name:on_past(EventList) :- Body)) :- !,
    transform_body(Body, TBody),
    assert(agent_past_reaction(Name, EventList, TBody)).

%% Export past done (?/): Name:on_past_done(Action, EventList) :- Body.
process_term((Name:on_past_done(Action, EventList) :- Body)) :- !,
    transform_body(Body, TBody),
    assert(agent_past_done_reaction(Name, Action, EventList, TBody)).

%% Export past not done (</): Name:on_past_not_done(Action, EventList) :- Body.
process_term((Name:on_past_not_done(Action, EventList) :- Body)) :- !,
    transform_body(Body, TBody),
    assert(agent_past_not_done_reaction(Name, Action, EventList, TBody)).

%% Ontology file: Name:ontology_file(File).
process_term(Name:ontology_file(File)) :- !,
    assert(agent_ontology_file(Name, File)).

%% On proposal handler: Name:on_proposal(Action) :- Body.
process_term((Name:on_proposal(Action) :- Body)) :- !,
    transform_body(Body, TBody),
    assert(agent_on_proposal(Name, Action, TBody)).

%% Standalone facts/rules (without agent prefix) - skip with warning
process_term(Term) :-
    format(user_error, "DALI2 loader: ignoring unrecognized term: ~w~n", [Term]).

%% ============================================================
%% POST-PROCESSING: Merge internal_event/5 configs with I-suffix handlers
%% ============================================================

%% post_process_internals/0
%% Combines agent_internal_config/6 (from DALI internal_event/5 declarations)
%% with agent_internal/4 (from I-suffix :> handlers) to produce complete
%% internal event definitions with proper options.
post_process_internals :-
    forall(
        agent_internal_config(Name, Event, Period, Repetition, StartCond, StopCond),
        merge_internal_config(Name, Event, Period, Repetition, StartCond, StopCond)
    ).

merge_internal_config(Name, Event, Period, Repetition, StartCond, StopCond) :-
    %% Build options list from DALI internal_event/5 parameters
    build_internal_options(Period, Repetition, StartCond, StopCond, Options),
    %% Find the matching handler body (from eventI :> body)
    (retract(agent_internal(Name, Event, _OldOpts, Body)) ->
        assert(agent_internal(Name, Event, Options, Body))
    ;
        %% No handler found — create with true body
        assert(agent_internal(Name, Event, Options, true))
    ).

%% build_internal_options(+Period, +Repetition, +StartCond, +StopCond, -Options)
build_internal_options(Period, Repetition, StartCond, StopCond, Options) :-
    %% Interval
    (number(Period), Period > 0 ->
        IntervalOpts = [interval(Period)]
    ;
        IntervalOpts = []
    ),
    %% Repetition
    (Repetition == forever ->
        RepOpts = [forever]
    ;
        (number(Repetition) ->
            RepOpts = [times(Repetition)]
        ;
            %% Check for change condition
            (Repetition = change(FactList) ->
                RepOpts = [change(FactList)]
            ;
                RepOpts = [forever]
            )
        )
    ),
    %% Start condition
    (StartCond == true ->
        StartOpts = []
    ;
        StartOpts = [trigger(StartCond)]
    ),
    %% Stop condition
    (StopCond = until_cond(Cond) ->
        StopOpts = [until(Cond)]
    ;
        (StopCond = in_date(D1, D2) ->
            StopOpts = [between(D1, D2)]
        ;
            StopOpts = []
        )
    ),
    append([IntervalOpts, RepOpts, StartOpts, StopOpts], Options).
