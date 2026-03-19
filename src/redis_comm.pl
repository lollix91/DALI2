%% DALI2 Redis Communication Module
%%
%% Star-topology communication using Redis pub/sub:
%%
%%   LINDA channel — all agents subscribe. Messages are published as:
%%     PUBLISH LINDA "<TO>:<CONTENT>:<FROM>"
%%     where TO is the destination agent (or * for broadcast),
%%     CONTENT is the Prolog term (serialized), FROM is the sender.
%%
%%   LOGS channel — agents publish log entries (no subscription needed):
%%     PUBLISH LOGS "<AGENT>:<MESSAGE>"
%%     This channel is for external monitoring tools.
%%
%% Each agent process connects to Redis and:
%%   1. Subscribes to LINDA channel
%%   2. Filters messages addressed to itself (or broadcast *)
%%   3. Publishes outgoing messages to LINDA
%%   4. Publishes log entries to LOGS
%%
%% Redis connection is configured via environment variables:
%%   REDIS_HOST (default: localhost)
%%   REDIS_PORT (default: 6379)
%%
%% This replaces the HTTP point-to-point IPC from the previous architecture
%% with a simple, scalable star topology. Remote machines on the same LAN
%% just need to point to the same Redis instance.

:- module(redis_comm, [
    redis_init/0,
    redis_init/2,
    redis_subscribe_linda/1,     % redis_subscribe_linda(+AgentName)
    redis_publish_linda/3,       % redis_publish_linda(+From, +To, +Content)
    redis_publish_log/2,         % redis_publish_log(+AgentName, +Message)
    redis_poll_messages/2,       % redis_poll_messages(+AgentName, -Messages)
    redis_bb_write/1,            % redis_bb_write(+Tuple)
    redis_bb_read/1,             % redis_bb_read(+Pattern)
    redis_bb_remove/1,           % redis_bb_remove(+Pattern)
    redis_bb_all/2,              % redis_bb_all(+Pattern, -List)
    redis_connected/0
]).

:- use_module(library(redis)).
:- use_module(library(lists)).

:- dynamic redis_connection/1.       % redis_connection(Connection)
:- dynamic redis_sub_connection/1.   % redis_sub_connection(SubConnection)
:- dynamic redis_msg_queue/3.        % redis_msg_queue(To, Content, From) — buffered incoming
:- dynamic redis_is_connected/0.

%% ============================================================
%% INITIALIZATION
%% ============================================================

%% redis_init/0 — connect using environment variables or defaults
redis_init :-
    (getenv('REDIS_HOST', Host) -> true ; Host = localhost),
    (getenv('REDIS_PORT', PortAtom) ->
        atom_number(PortAtom, Port)
    ;
        Port = 6379
    ),
    redis_init(Host, Port).

%% redis_init/2 — connect to a specific Redis host:port
redis_init(Host, Port) :-
    (redis_is_connected -> true ;
        catch(
            (redis_server(dali2_redis, Host:Port, []),
             assert(redis_is_connected),
             format(user_error, "[Redis] Connected to ~w:~w~n", [Host, Port])),
            Error,
            format(user_error, "[Redis] Connection failed: ~w~n", [Error])
        )
    ).

redis_connected :- redis_is_connected.

%% ============================================================
%% LINDA CHANNEL — Message passing
%% ============================================================

%% redis_publish_linda(+From, +To, +Content)
%% Publishes a message on the LINDA channel.
%% Format: "TO:CONTENT_ATOM:FROM"
redis_publish_linda(From, To, Content) :-
    (redis_is_connected ->
        term_to_atom(Content, ContentAtom),
        format(atom(Msg), "~w:~w:~w", [To, ContentAtom, From]),
        catch(
            redis(dali2_redis, publish('LINDA', Msg), _),
            Error,
            format(user_error, "[Redis] Publish error: ~w~n", [Error])
        )
    ;
        format(user_error, "[Redis] Not connected, cannot publish~n", [])
    ).

%% redis_subscribe_linda(+AgentName)
%% Starts a background thread that subscribes to LINDA and buffers
%% messages addressed to this agent (or broadcast *).
redis_subscribe_linda(AgentName) :-
    (redis_is_connected ->
        thread_create(linda_subscriber_loop(AgentName), _,
            [detached(true), alias(redis_linda_sub)])
    ;
        format(user_error, "[Redis] Not connected, cannot subscribe~n", [])
    ).

linda_subscriber_loop(AgentName) :-
    catch(
        redis_subscribe(dali2_redis, ['LINDA'], _SubId,
            redis_comm:linda_callback(AgentName)),
        Error,
        (format(user_error, "[Redis] Subscribe error: ~w, retrying...~n", [Error]),
         sleep(2),
         linda_subscriber_loop(AgentName))
    ).

%% linda_callback(+AgentName, +Channel, +Message)
%% Called for each message on the LINDA channel.
%% Parses "TO:CONTENT:FROM" and queues if addressed to us or broadcast.
:- meta_predicate linda_callback(+, +, +).
linda_callback(AgentName, 'LINDA', Message) :-
    atom_string(MsgAtom, Message),
    parse_linda_message(MsgAtom, To, ContentAtom, From),
    (To == AgentName ; To == '*' ; To == all),
    From \== AgentName,  % don't receive own broadcasts
    !,
    catch(term_to_atom(Content, ContentAtom), _, Content = ContentAtom),
    with_mutex(redis_queue_mutex,
        assert(redis_msg_queue(AgentName, Content, From))
    ).
linda_callback(_, _, _).  % ignore messages not for us

%% parse_linda_message(+Msg, -To, -Content, -From)
%% Parses "TO:CONTENT:FROM" — splits on first and last colon.
parse_linda_message(Msg, To, Content, From) :-
    atom_string(Msg, Str),
    %% Find first ':'
    sub_string(Str, BeforeTo, 1, _, ":"),
    sub_string(Str, 0, BeforeTo, _, ToStr),
    AfterTo is BeforeTo + 1,
    sub_string(Str, AfterTo, _, 0, Rest),
    %% Find last ':' in Rest (for From)
    atom_string(RestAtom, Rest),
    atom_chars(RestAtom, RestChars),
    last_colon_split(RestChars, ContentChars, FromChars),
    atom_chars(Content, ContentChars),
    atom_chars(From, FromChars),
    atom_string(To, ToStr).

last_colon_split(Chars, Before, After) :-
    append(Before, [':'|After], Chars),
    \+ member(':', After), !.

%% redis_poll_messages(+AgentName, -Messages)
%% Retrieves and clears all buffered messages for an agent.
redis_poll_messages(AgentName, Messages) :-
    with_mutex(redis_queue_mutex, (
        findall(
            message(From, Content, T),
            (retract(redis_msg_queue(AgentName, Content, From)),
             get_time(Stamp), T is truncate(Stamp * 1000)),
            Messages
        )
    )).

%% ============================================================
%% LOGS CHANNEL — Monitoring
%% ============================================================

%% redis_publish_log(+AgentName, +Message)
%% Publishes a log entry on the LOGS channel.
%% Format: "AGENT:MESSAGE"
redis_publish_log(AgentName, Message) :-
    (redis_is_connected ->
        format(atom(LogMsg), "~w:~w", [AgentName, Message]),
        catch(
            redis(dali2_redis, publish('LOGS', LogMsg), _),
            _Error, true  % fire and forget
        )
    ;
        true
    ).

%% ============================================================
%% BLACKBOARD via Redis (replaces in-memory blackboard)
%% Uses Redis SET "BB" as a simple tuple space.
%% Each tuple is stored as a member of the set.
%% ============================================================

%% redis_bb_write(+Tuple) — Add a tuple to the blackboard
redis_bb_write(Tuple) :-
    (redis_is_connected ->
        term_to_atom(Tuple, TupleAtom),
        catch(
            redis(dali2_redis, sadd('BB', TupleAtom), _),
            _Error, true
        )
    ;
        true
    ).

%% redis_bb_read(+Pattern) — Read a matching tuple (non-destructive)
redis_bb_read(Pattern) :-
    redis_is_connected,
    catch(
        redis(dali2_redis, smembers('BB'), Members),
        _, fail
    ),
    member(MemberStr, Members),
    atom_string(MemberAtom, MemberStr),
    catch(term_to_atom(Term, MemberAtom), _, fail),
    subsumes_term(Pattern, Term),
    Pattern = Term.

%% redis_bb_remove(+Pattern) — Remove a matching tuple
redis_bb_remove(Pattern) :-
    redis_is_connected,
    catch(
        redis(dali2_redis, smembers('BB'), Members),
        _, fail
    ),
    member(MemberStr, Members),
    atom_string(MemberAtom, MemberStr),
    catch(term_to_atom(Term, MemberAtom), _, fail),
    subsumes_term(Pattern, Term),
    Pattern = Term,
    catch(
        redis(dali2_redis, srem('BB', MemberAtom), _),
        _, true
    ).

%% redis_bb_all(+Pattern, -List) — Get all matching tuples
redis_bb_all(Pattern, List) :-
    (redis_is_connected ->
        catch(
            redis(dali2_redis, smembers('BB'), Members),
            _, Members = []
        ),
        findall(Term,
            (member(MemberStr, Members),
             atom_string(MemberAtom, MemberStr),
             catch(term_to_atom(Term, MemberAtom), _, fail),
             subsumes_term(Pattern, Term)),
            List)
    ;
        List = []
    ).
