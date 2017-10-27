%%%----------------------------------------------------------------------------
%%% @author Chris Waymire <chris@waymire.net>
%%% @private
%%%----------------------------------------------------------------------------
-module(dxl_service).

-behaviour(gen_server).

%% API
-export([start_link/4,
         stop/2,
         refresh/2,
         update/3
]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3
]).

-include("dxl.hrl").

-record(service_info, {
    service_type = <<"">> :: binary(),
    service_id = <<"">> :: binary(),
    metadata = maps:new() :: map(),
    topics = [] :: list(),
    ttl = 60 :: integer(),
    dst_tenant_ids = [] :: list()
}).
-type service_info() :: #service_info{}.

-record(state, {
    gid :: binary(),
    client :: atom(),
    dxl_conn :: atom(),
    notif_man :: atom(),

    id = <<"">> :: binary(),
    type = <<"">> :: binary(),
    metadata = maps:new() :: map(),
    topics = [] :: list(),
    dst_tenant_ids = [] :: list(),
    ttl = 60 :: integer(),
    ttl_timer = make_ref() :: reference(),

    connected = false :: true | false,
    registered = false :: true | false,
    subscribed = false :: true | false,
    shutdown = false :: true | false,
    registration_timer = make_ref() :: reference()
}).
-type state() :: #state{}.

%%%----------------------------------------------------------------------------
%%% Public functions
%%%----------------------------------------------------------------------------
start_link(GID, Id, Service, Timeout) ->
    gen_server:start_link(?MODULE, [GID, Id, Service, Timeout], []).

stop(Pid, Timeout) ->
    gen_server:call(Pid, {stop, Timeout}).

update(Pid, Service, Timeout) ->
    gen_server:call(Pid, {update, Service, Timeout}).

refresh(Pid, Timeout) ->
    gen_server:call(Pid, {update, Timeout}).

%%%----------------------------------------------------------------------------
%%% gen_server functions
%%%----------------------------------------------------------------------------
init([GID, Id, #service_registration{} = Registration, Timeout]) ->
    Client = dxl_util:module_reg_name(GID, dxlc),
    DxlConn = dxl_util:module_reg_name(GID, dxl_conn),
    NotifMan = dxl_util:module_reg_name(GID, dxl_notif_man),
    Connected = is_connected(DxlConn),
    State1 = #state{gid          = GID,
                    id           = Id,
                    client       = Client,
                    notif_man    = NotifMan,
                    dxl_conn     = DxlConn,
                    connected    = Connected
    },
    State2 = update_state_from_registration(Registration, State1),

    lager:debug("Starting service: ~p (~p).", [State2#state.type, Id]),
    dxl_notif_man:subscribe(NotifMan, connection, self()),
    RegTimer = erlang:send_after(Timeout, self(), {registration_failed, timeout}),
    {ok, State2#state{registration_timer = RegTimer}, 0}.


terminate(_Reason, #state{connected = true, registered = true} = State) ->
    do_deregister(State),
    ok;

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

handle_call({stop, Timeout}, From, State) ->
    #state{id = Id} = State,
    lager:debug("[Service:~p] Received stop request from: ~p", [Id, From]),
    Timer = erlang:send_after(Timeout, self(), {deregistration_failed, timeout}),
    do_deregister(State),
    {reply, ok, State#state{shutdown = true, registration_timer = Timer}}.

handle_cast(registration_success, State) ->
    #state{id = Id, type = Type, notif_man = NotifMan, registration_timer = RegTimer} = State,
    lager:debug("[Service:~p] Registration succeeded.", [Id]),
    erlang:cancel_timer(RegTimer),
    State1 = register_topics(State),
    dxl_notif_man:publish(NotifMan, service, {service_registered, Id, Type}),
    {noreply, State1#state{registered = true}};

handle_cast({registration_failed, Reason}, State) ->
    #state{id = Id, type = Type, notif_man = NotifMan, registration_timer = RegTimer} = State,
    lager:debug("[Service:~p] Registration failed.", [Id]),
    erlang:cancel_timer(RegTimer),
    dxl_notif_man:publish(NotifMan, service, {service_registration_failed, Id, Type, Reason}),
    {stop, normal, State#state{registered = false}};

handle_cast(deregistration_success, State) ->
    #state{id = Id, type = Type, notif_man = NotifMan, registration_timer = RegTimer} = State,
    lager:debug("[Service:~p] De-Registration succeeded.", [Id]),
    erlang:cancel_timer(RegTimer),
    State1 = deregister_topics(State),
    dxl_notif_man:publish(NotifMan, service, {service_deregistered, Id, Type}),
    {stop, normal, State1#state{registered = false}};

handle_cast({deregistration_failed, Reason}, State) ->
    #state{id = Id} = State,
    lager:debug("[Service:~p] De-Registration failed.", [Id]),
    #state{id = Id, type = Type, notif_man = NotifMan, registration_timer = RegTimer} = State,
    erlang:cancel_timer(RegTimer),
    State1 = deregister_topics(State),
    dxl_notif_man:publish(NotifMan, service, {service_deregisteration_failed, Id, Type, Reason}),
    {stop, normal, State1#state{registered = false}}.

handle_info({connected, _Client}, #state{connected = false, shutdown = true} = State) ->
    #state{id = Id} = State,
    lager:debug("[Service:~p] Processing the pending shutdown request.", [Id]),
    State1 = do_deregister(State#state{connected = true}),
    {stop, normal, State1};

handle_info({connected, _Client}, #state{connected = false, shutdown = false} = State) ->
    #state{id = Id} = State,
    lager:debug("[Service:~p] Client connected. Starting registration.", [Id]),
    State1 = do_register(State#state{connected = true}),
    {noreply, State1};

handle_info({disconnected, _Client}, #state{connected = true} = State) ->
    #state{id = Id} = State,
    lager:debug("[Service:~p] Client disconnected. Going idle.", [Id]),
    State1 = clear_ttl_timer(State),
    {noreply, State1#state{connected = false}};

handle_info(timeout, #state{connected=false} = State) ->
    {noreply, State};

handle_info(timeout, #state{connected=true} = State) ->
    State1 = do_register(State),
    {noreply, State1}.

%%%----------------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------------
do_register(State) ->
    #state{id = Id} = State,
    lager:debug("[Service:~p] Starting service registration.", [Id]),
    send_registration_request(State),
    State1 = reset_ttl_timer(State),
    State1#state{registered = false}.

send_registration_request(State) ->
    #state{id = Id, dxl_conn = DxlConn} = State,
    lager:debug("[Service:~p] Sending DXL service registration request.", [Id]),
    Payload = build_registration_payload(State),
    Request = #dxlmessage{payload = Payload, dst_tenant_ids = State#state.dst_tenant_ids},
    Self = self(),
    Fun = fun({message_in, {_, #dxlmessage{type = response}, _}}) ->
                 gen_server:cast(Self, registration_success);
             ({message_in, {_, #dxlmessage{type = error, error_code = ErrCode, error_message = ErrMsg}, _}}) ->
                 gen_server:cast(Self, {registration_failed, {error, {ErrCode, ErrMsg}}})
          end,
    dxl_conn:send_request_async(DxlConn, ?SVC_REG_REQ_TOPIC, Request, Fun, infinity),
    ok.

register_topics(#state{subscribed = true} = State) ->
    State;

register_topics(#state{subscribed = false} = State) ->
    #state{id = Id, topics = Topics} = State,
    lager:debug("[Service:~p] Subscribing to topics and registering callbacks.", [Id]),
    register_topics(Topics, State#state{subscribed = true}).

register_topics([{Topic, Callback, _} | Rest], State) ->
    #state{id = Id, dxl_conn = DxlConn, notif_man = NotifMan, topics = Topics} = State,
    lager:debug("[Service:~p] Registering callback for topic: ~p.", [Id, Topic]),
    NotifId = subscribe_to_notification(Topic, Callback, NotifMan),
    lager:debug("[Service:~p] Subscribing to topic: ~p.", [Id, Topic]),
    dxl_conn:subscribe(DxlConn, Topic),
    UpdatedTopics = [{Topic, Callback, NotifId} | proplists:delete(Topic, Topics)],
    register_topics(Rest, State#state{topics = UpdatedTopics});

register_topics([], State) ->
    State.

subscribe_to_notification(_Topic, undefined, _NotifMan) ->
    undefined;

subscribe_to_notification(Topic, Callback, NotifMan) ->
    Filter = fun({message_in, {TopicIn, #dxlmessage{type = TypeIn}, _}}) ->
        (TypeIn =:= request) and (TopicIn =:= Topic)
             end,
    {ok, NotifId} = dxl_notif_man:subscribe(NotifMan, message_in, Callback, [{filter, Filter}]),
    NotifId.

do_deregister(State) ->
    #state{id = Id} = State,
    lager:debug("[Service:~p] Starting service deregistration.", [Id]),
    send_deregistration_request(State),
    clear_ttl_timer(State).

send_deregistration_request(State) ->
    #state{id = Id, dxl_conn = DxlConn} = State,
    lager:debug("[Service:~p] Sending DXL service registration request.", [Id]),
    Payload = build_deregistration_payload(State),
    Request = #dxlmessage{payload = Payload},
    Self = self(),
    Fun = fun({message_in, {_, #dxlmessage{type = response}, _}}) ->
                 gen_server:cast(Self, deregistration_success);
             ({message_in, {_, #dxlmessage{type = error, error_code = ErrCode, error_message = ErrMsg}, _}}) ->
                 gen_server:cast(Self, {deregistration_failed, {ErrCode, ErrMsg}})
          end,
    dxl_conn:send_request_async(DxlConn, ?SVC_UNREG_REQ_TOPIC, Request, Fun, infinity),
    State.

deregister_topics(State) ->
    #state{id = Id, topics = Topics} = State,
    lager:debug("[Service:~p] Unsubscribing from topics and deregistering callbacks.", [Id]),
    deregister_topics(Topics, State).

deregister_topics([{Topic, _Callback, NotifId} | Rest], State) ->
    #state{id = Id, dxl_conn = DxlConn, notif_man = NotifMan, topics = Topics} = State,
    lager:debug("[Service:~p] Unsubscribing from topic: ~p.", [Id, Topic]),
    dxl_conn:unsubscribe(DxlConn, Topic),
    lager:debug("[Service:~p] De-Registering callback for topic: ~p.", [Id, Topic]),
    dxl_notif_man:unsubscribe(NotifMan, NotifId),
    UpdatedTopics = proplists:delete(Topic, Topics),
    deregister_topics(Rest, State#state{topics = UpdatedTopics});

deregister_topics([], State) ->
    State.

%%%----------------------------------------------------------------------------
%%% TTL timer functions
%%%----------------------------------------------------------------------------
reset_ttl_timer(State) ->
    #state{id = Id, ttl_timer = Timer, ttl = TTL} = State,
    lager:debug("[Service:~p] Resetting TTL timer.", [Id]),
    stop_ttl_timer(Timer),
    NewTimer = start_ttl_timer(TTL),
    State#state{ttl_timer = NewTimer}.

clear_ttl_timer(State) ->
    #state{id = Id, ttl_timer = Timer} = State,
    lager:debug("[Service:~p] Clearing TTL timer.", [Id]),
    stop_ttl_timer(Timer),
    State#state{ttl_timer = undefined}.

start_ttl_timer(TTLMins) ->
    TTLMillis = TTLMins * 60 * 1000,
    erlang:send_after(TTLMillis, self(), ttl_timeout).

stop_ttl_timer(Timer) when is_reference(Timer) ->
    erlang:cancel_timer(Timer),
    ok;

stop_ttl_timer(_Timer) ->
    ok.

%%%----------------------------------------------------------------------------
%%% Registration payload functions
%%%----------------------------------------------------------------------------
build_registration_payload(State) ->
    jiffy:encode({[{serviceGuid, State#state.id},
                   {serviceType, State#state.type},
                   {metaData, State#state.metadata},
                   {ttlMins, State#state.ttl},
                   {requestChannels, proplists:get_keys(State#state.topics)}]}).

build_deregistration_payload(State) ->
    jiffy:encode({[{serviceGuid, State#state.id}]}).


%%%----------------------------------------------------------------------------
%%% Misc functions
%%%----------------------------------------------------------------------------

is_connected(DxlConn) ->
    case dxl_conn:is_connected(DxlConn) of
        {true, _} -> true;
        false -> false
    end.

normalize_topics(Topics) when is_map(Topics) ->
    normalize_topics(maps:to_list(Topics));

normalize_topics(Topics) when is_list(Topics) ->
    [{K, V, undefined} || {K, V} <- proplists:unfold(Topics)].

update_state_from_registration(Registration, State) ->
    State#state{type     = Registration#service_registration.type,
                metadata = Registration#service_registration.metadata,
                topics   = normalize_topics(Registration#service_registration.topics),
                ttl      = Registration#service_registration.ttl}.