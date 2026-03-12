%% DALI2 Loader - Agent definition parser
%% Replaces DALI's tokefun.pl + togli_var.pl + metti_var.pl + leggi_mul.pl
%%
%% Reads a single agents.pl file and extracts:
%%   - Agent declarations:  :- agent(Name, Options).
%%   - Event handlers:      Name:on(Event) :- Body.
%%   - Periodic rules:      Name:every(Seconds, Goal).
%%   - Condition monitors:  Name:when(Condition) :- Body.
%%   - Actions:             Name:do(Action) :- Body.
%%   - Beliefs:             Name:believes(Fact).
%%   - Helper clauses:      Name:helper(Head) :- Body.

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
    clear_definitions/0
]).

:- use_module(library(lists)).

%% Stored definitions
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
    retractall(agent_on_proposal(_, _, _)).

%% load_agents(+File) - Load agent definitions from a file
load_agents(File) :-
    clear_definitions,
    read_file_terms(File, Terms),
    process_terms(Terms).

%% load_agents_from_string(+String) - Load agent definitions from a string
load_agents_from_string(String) :-
    clear_definitions,
    term_string(Terms, String),
    (is_list(Terms) ->
        process_terms(Terms)
    ;
        process_terms([Terms])
    ).

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

%% process_term(+Term) - Process a single term

% Agent declaration: :- agent(Name, Options).
process_term(:- agent(Name, Options)) :- !,
    assert(agent_def(Name, Options)).

% Agent declaration without options: :- agent(Name).
process_term(:- agent(Name)) :- !,
    assert(agent_def(Name, [])).

% Event handler: Name:on(Event) :- Body.
process_term((Name:on(Event) :- Body)) :- !,
    assert(agent_handler(Name, Event, Body)).

% Event handler without body: Name:on(Event).
process_term(Name:on(Event)) :- !,
    assert(agent_handler(Name, Event, true)).

% Periodic rule: Name:every(Seconds, Goal).
process_term(Name:every(Seconds, Goal)) :- !,
    assert(agent_periodic(Name, Seconds, Goal)).

% Periodic rule with body: Name:every(Seconds) :- Body.
process_term((Name:every(Seconds) :- Body)) :- !,
    assert(agent_periodic(Name, Seconds, Body)).

% Condition monitor: Name:when(Condition) :- Body.
process_term((Name:when(Condition) :- Body)) :- !,
    assert(agent_monitor(Name, Condition, Body)).

% Condition monitor with two conditions: Name:when(C1, C2) :- Body.
process_term((Name:when(C1, C2) :- Body)) :- !,
    assert(agent_monitor(Name, (C1, C2), Body)).

% Action: Name:do(Action) :- Body.
process_term((Name:do(Action) :- Body)) :- !,
    assert(agent_action(Name, Action, Body)).

% Action without body: Name:do(Action).
process_term(Name:do(Action)) :- !,
    assert(agent_action(Name, Action, true)).

% Belief: Name:believes(Fact).
process_term(Name:believes(Fact)) :- !,
    assert(agent_belief(Name, Fact)).

% Helper clause: Name:helper(Head) :- Body.
process_term((Name:helper(Head) :- Body)) :- !,
    assert(agent_helper(Name, Head, Body)).

% Helper clause without body: Name:helper(Head).
process_term(Name:helper(Head)) :- !,
    assert(agent_helper(Name, Head, true)).

% Internal event with options: Name:internal(Event, Options) :- Body.
process_term((Name:internal(Event, Options) :- Body)) :- !,
    (is_list(Options) -> Opts = Options ; Opts = [Options]),
    assert(agent_internal(Name, Event, Opts, Body)).

% Internal event without options (forever): Name:internal(Event) :- Body.
process_term((Name:internal(Event) :- Body)) :- !,
    assert(agent_internal(Name, Event, [forever], Body)).

% Internal event fact: Name:internal(Event).
process_term(Name:internal(Event)) :- !,
    assert(agent_internal(Name, Event, [forever], true)).

% Internal event fact with options: Name:internal(Event, Options).
process_term(Name:internal(Event, Options)) :- !,
    (is_list(Options) -> Opts = Options ; Opts = [Options]),
    assert(agent_internal(Name, Event, Opts, true)).

% Told rule with priority: Name:told(Pattern, Priority).
process_term(Name:told(Pattern, Priority)) :- !,
    assert(agent_told(Name, Pattern, Priority)).

% Told rule: Name:told(Pattern).
process_term(Name:told(Pattern)) :- !,
    assert(agent_told(Name, Pattern, 0)).

% Tell rule: Name:tell(Pattern).
process_term(Name:tell(Pattern)) :- !,
    assert(agent_tell(Name, Pattern)).

% Condition-action (edge-triggered): Name:on_change(Condition) :- Body.
process_term((Name:on_change(Condition) :- Body)) :- !,
    assert(agent_condition_action(Name, Condition, Body)).

% Condition-action with two conditions: Name:on_change(C1, C2) :- Body.
process_term((Name:on_change(C1, C2) :- Body)) :- !,
    assert(agent_condition_action(Name, (C1, C2), Body)).

% Present/environment event: Name:on_present(Condition) :- Body.
process_term((Name:on_present(Condition) :- Body)) :- !,
    assert(agent_present(Name, Condition, Body)).

% Present event with two conditions: Name:on_present(C1, C2) :- Body.
process_term((Name:on_present(C1, C2) :- Body)) :- !,
    assert(agent_present(Name, (C1, C2), Body)).

% Multi-event (all must occur): Name:on_all(EventList) :- Body.
process_term((Name:on_all(EventList) :- Body)) :- !,
    assert(agent_multi_event(Name, EventList, Body)).

% Constraint with handler: Name:constraint(Condition) :- Body.
process_term((Name:constraint(Condition) :- Body)) :- !,
    assert(agent_constraint(Name, Condition, Body)).

% Constraint with two conditions and handler: Name:constraint(C1, C2) :- Body.
process_term((Name:constraint(C1, C2) :- Body)) :- !,
    assert(agent_constraint(Name, (C1, C2), Body)).

% Constraint without handler: Name:constraint(Condition).
process_term(Name:constraint(Condition)) :- !,
    assert(agent_constraint(Name, Condition, true)).

% Constraint with two conditions, no handler: Name:constraint(C1, C2).
process_term(Name:constraint(C1, C2)) :- !,
    assert(agent_constraint(Name, (C1, C2), true)).

% Ontology declaration: Name:ontology(Declaration).
process_term(Name:ontology(Declaration)) :- !,
    assert(agent_ontology(Name, Declaration)).

% Learning rule: Name:learn_from(Event, Outcome) :- Body.
process_term((Name:learn_from(Event, Outcome) :- Body)) :- !,
    assert(agent_learn_rule(Name, Event, Outcome, Body)).

% Learning rule without body: Name:learn_from(Event, Outcome).
process_term(Name:learn_from(Event, Outcome)) :- !,
    assert(agent_learn_rule(Name, Event, Outcome, true)).

% Goal: Name:goal(Type, GoalCondition) :- Plan.
process_term((Name:goal(Type, Goal) :- Plan)) :- !,
    assert(agent_goal(Name, Type, Goal, Plan)).

% Goal with extra condition: Name:goal(Type, GoalCond, ExtraCond) :- Plan.
process_term((Name:goal(Type, Goal, Extra) :- Plan)) :- !,
    assert(agent_goal(Name, Type, (Goal, Extra), Plan)).

% Goal without plan: Name:goal(Type, GoalCondition).
process_term(Name:goal(Type, Goal)) :- !,
    assert(agent_goal(Name, Type, Goal, true)).

% Directives (other :- terms) - execute them
process_term(:- Goal) :- !,
    catch(call(Goal), _, true).

% Past lifetime: Name:past_lifetime(Pattern, Duration).
process_term(Name:past_lifetime(Pattern, Duration)) :- !,
    assert(agent_past_lifetime(Name, Pattern, Duration)).

% Remember lifetime: Name:remember_lifetime(Pattern, Duration).
process_term(Name:remember_lifetime(Pattern, Duration)) :- !,
    assert(agent_remember_lifetime(Name, Pattern, Duration)).

% Remember limit: Name:remember_limit(Pattern, N, Mode).
process_term(Name:remember_limit(Pattern, N, Mode)) :- !,
    assert(agent_remember_limit(Name, Pattern, N, Mode)).

% Export past reaction (~/): Name:on_past(EventList) :- Body.
process_term((Name:on_past(EventList) :- Body)) :- !,
    assert(agent_past_reaction(Name, EventList, Body)).

% Export past done (?/): Name:on_past_done(Action, EventList) :- Body.
process_term((Name:on_past_done(Action, EventList) :- Body)) :- !,
    assert(agent_past_done_reaction(Name, Action, EventList, Body)).

% Export past not done (</): Name:on_past_not_done(Action, EventList) :- Body.
process_term((Name:on_past_not_done(Action, EventList) :- Body)) :- !,
    assert(agent_past_not_done_reaction(Name, Action, EventList, Body)).

% Ontology file: Name:ontology_file(File).
process_term(Name:ontology_file(File)) :- !,
    assert(agent_ontology_file(Name, File)).

% On proposal handler: Name:on_proposal(Action) :- Body.
process_term((Name:on_proposal(Action) :- Body)) :- !,
    assert(agent_on_proposal(Name, Action, Body)).

% Standalone facts/rules (without agent prefix) - skip with warning
process_term(Term) :-
    format(user_error, "DALI2 loader: ignoring unrecognized term: ~w~n", [Term]).
