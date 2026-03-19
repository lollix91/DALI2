%% DALI2 Communication - Message passing between agents via Redis
%%
%% Star-topology communication using Redis pub/sub:
%%   LINDA channel — all agents subscribe. Messages published as "TO:CONTENT:FROM"
%%   LOGS channel — log entries for monitoring
%%   BB (Redis SET) — shared blackboard (replaces Linda tuple space)
%%
%% Remote machines on the same LAN just point to the same Redis instance.
%% Format: message(From, Content, Timestamp)

:- module(communication, [
    send/3,
    send/2,
    broadcast/2,
    deliver_remote/3
]).

:- use_module(redis_comm).
:- use_module(federation).

%% send(+From, +To, +Content) - Send a message to an agent via Redis LINDA channel
send(From, To, Content) :-
    %% First try Redis (local or remote agents on same Redis)
    (redis_comm:redis_connected ->
        redis_comm:redis_publish_linda(From, To, Content)
    ;
        %% Fallback: federation for remote peers on different Redis
        (federation:fed_find_agent(To, PeerName) ->
            federation:fed_remote_send(PeerName, From, To, Content)
        ;
            format(user_error, "[comm] Cannot deliver to ~w: no Redis, no federation~n", [To])
        )
    ).

%% send(+To, +Content) - Send from current thread/process (convenience)
send(To, Content) :-
    (catch(thread_self(Tid), _, fail),
     atom_concat('agent_', Name, Tid) ->
        send(Name, To, Content)
    ;
        send(system, To, Content)
    ).

%% deliver_remote(+From, +To, +Content) - Deliver a message from a remote peer
deliver_remote(From, To, Content) :-
    (redis_comm:redis_connected ->
        redis_comm:redis_publish_linda(From, To, Content)
    ;
        format(user_error, "[comm] Cannot deliver remote to ~w: no Redis~n", [To])
    ).

%% broadcast(+From, +Content) - Send to all agents (via Redis * broadcast)
broadcast(From, Content) :-
    (redis_comm:redis_connected ->
        redis_comm:redis_publish_linda(From, '*', Content)
    ;
        true
    ),
    %% Also forward to federation peers
    forall(
        (federation:peer(PeerName, _, RemoteAgents),
         member(To, RemoteAgents), To \= From),
        federation:fed_remote_send(PeerName, From, To, Content)
    ).
