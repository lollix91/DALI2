%% DALI2 Communication - Message passing between agents (local + remote)
%% Replaces DALI's communication_fipa.pl + communication_onto*.pl
%%
%% In process-based mode, messages are routed to agent processes via HTTP.
%% The master server acts as the message router.
%% Remote messages (federation) are forwarded to peer instances via HTTP.
%% Format: message(From, To, Content, Timestamp)

:- module(communication, [
    send/3,
    send/2,
    receive/2,
    receive_all/2,
    broadcast/2,
    deliver_remote/3,     % deliver_remote(+From, +To, +Content)
    deliver_to_process/3  % deliver_to_process(+From, +To, +Content)
]).

:- use_module(blackboard).
:- use_module(federation).
:- use_module(library(http/http_open)).
:- use_module(library(http/http_json)).

%% send(+From, +To, +Content) - Send a message to an agent (process, local, or remote)
send(From, To, Content) :-
    get_time(Stamp),
    T is truncate(Stamp * 1000),
    %% First check if the target is running as a separate OS process
    (catch(engine:agent_process_url(To, AgentUrl), _, fail) ->
        %% Agent is a separate process — deliver via HTTP
        deliver_to_process_http(From, To, Content, AgentUrl)
    ;
        %% Check if local (blackboard-registered) or remote (federation)
        (federation:fed_is_local(To) ->
            bb_put(message(From, To, Content, T))
        ;
            (federation:fed_find_agent(To, PeerName) ->
                federation:fed_remote_send(PeerName, From, To, Content)
            ;
                %% Agent not found — deliver locally anyway (may be started later)
                bb_put(message(From, To, Content, T))
            )
        )
    ).

%% send(+To, +Content) - Send from current thread/process agent (convenience)
send(To, Content) :-
    (catch(thread_self(Tid), _, fail),
     atom_concat('agent_', Name, Tid) ->
        send(Name, To, Content)
    ;
        send(system, To, Content)
    ).

%% deliver_to_process(+From, +To, +Content) - Deliver message to agent process
deliver_to_process(From, To, Content) :-
    (catch(engine:agent_process_url(To, AgentUrl), _, fail) ->
        deliver_to_process_http(From, To, Content, AgentUrl)
    ;
        %% Fallback to blackboard
        get_time(Stamp), T is truncate(Stamp * 1000),
        bb_put(message(From, To, Content, T))
    ).

%% deliver_to_process_http(+From, +To, +Content, +AgentUrl) - HTTP delivery
deliver_to_process_http(From, _To, Content, AgentUrl) :-
    term_to_atom(Content, ContentAtom),
    format(atom(MsgUrl), "~w/message", [AgentUrl]),
    atom_json_dict(Payload, _{from: From, content: ContentAtom}, []),
    catch(
        (http_open(MsgUrl, Reply, [
            method(post),
            post(atom('application/json', Payload)),
            status_code(_Code),
            timeout(5)
        ]),
        read_string(Reply, _, _),
        close(Reply)),
        _Error, true  % fire and forget
    ).

%% deliver_remote(+From, +To, +Content) - Deliver a message from a remote peer
%%   This is called when a remote instance forwards a message to us.
deliver_remote(From, To, Content) :-
    %% Try to deliver to agent process first
    (catch(engine:agent_process_url(To, AgentUrl), _, fail) ->
        deliver_to_process_http(From, To, Content, AgentUrl)
    ;
        %% Fallback to blackboard
        get_time(Stamp), T is truncate(Stamp * 1000),
        bb_put(message(From, To, Content, T))
    ).

%% receive(+AgentName, -Message) - Receive one message for agent (destructive)
%% NOTE: In process-based mode, agent processes receive messages via HTTP directly.
%% This is kept for backward compatibility with thread-based mode.
receive(AgentName, message(From, Content, T)) :-
    bb_take(message(From, AgentName, Content, T)), !.

%% receive_all(+AgentName, -Messages) - Receive all pending messages
receive_all(AgentName, Messages) :-
    findall(
        message(From, Content, T),
        bb_take(message(From, AgentName, Content, T)),
        Messages
    ).

%% broadcast(+From, +Content) - Send to all agents (processes + remote, except sender)
broadcast(From, Content) :-
    %% Local agents (both process-based and blackboard-registered)
    bb_agents(LocalAgents),
    forall(
        (member(To, LocalAgents), To \= From),
        send(From, To, Content)
    ),
    %% Remote agents (federation)
    forall(
        (federation:peer(PeerName, _, RemoteAgents),
         member(To, RemoteAgents), To \= From),
        federation:fed_remote_send(PeerName, From, To, Content)
    ).
