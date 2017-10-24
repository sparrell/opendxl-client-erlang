-module(dxl_service).

-behaviour(gen_server).

%% API
-export([start_link/2]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-include("dxl.hrl").

-record(service_info, {
        service_type = <<"">>                           :: binary(),
        service_id = <<"">>                             :: binary(),
        metadata = maps:new()                           :: map(),
        topics = []					:: map() | list(),
        ttl=60                                          :: integer(),
        dst_tenant_ids = []                             :: list()
       }).
-type service_info() :: #service_info{}.

-record(state, {
	parent						:: pid(),
	gid = <<"">>					:: binary(),
	dxlc						:: pid(),
	id = <<"">>					:: binary(),
	type = <<"">>					:: binary(),
	metadata = maps:new()				:: map(),
 	topics = []					:: map() | list(),
	notifications = maps:new()			:: map(),
	dst_tenant_ids = []				:: list(),
	ttl=60						:: integer(),
	ttl_timer = make_ref()				:: reference(),
	connected = false				:: true | false,
	registered = false				:: true | false,
	shutdown = false				:: true | false,
	client						:: term(),
        notif_man					:: term()
      }).

%%%============================================================================
%%% API functions
%%%============================================================================
start_link(GID, Service) ->
    Id = dxl_util:generate_uuid(),
    case gen_server:start_link(?MODULE, [self(), GID, Id, Service], []) of
        {ok, Pid} -> {ok, {Id, Pid}};
        R -> R
    end.

%%%============================================================================
%%% gen_server functions
%%%============================================================================
init([Parent, GID, Id, Service]) ->
    Client = dxl_util:module_reg_name(GID, dxlc),
    NotifMan = dxl_util:module_reg_name(GID, dxl_notif_man),
    Connected = dxlc:is_connected(Client),
    BaseState = #state{parent=Parent,
		       gid=GID,
		       id=Id,
		       client=Client,
		       notif_man=NotifMan,
		       connected=Connected},

    State = update_state_from_service(Service, BaseState),

    dxl_notif_man:subscribe(NotifMan, connected, self()),
    dxl_notif_man:subscribe(NotifMan, disconnected, self()),

    case Connected of
        true -> gen_server:cast(self(), update);
	false -> ok
    end,

    {ok, State}.


handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast(update, State) ->
    State1 = do_update(State),
    {noreply, State1};

handle_cast({update, Service}, State) ->
    State1 = do_update(Service, State),
    {noreply, State1};

handle_cast(shutdown, #state{registered=false}=State) ->
    {stop, normal, State};

handle_cast(shutdown, #state{connected=true}=State) ->
    State1 = do_unregister(State),
    {stop, normal, State1#state{shutdown=true}};

handle_cast(shutdown, State) ->
   lager:debug("Delaying shutdown until connected.", []),
   {noreply, State#state{shutdown=true}}; 

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({connected, _Client}, #state{connected=false, shutdown=true}=State) ->
    lager:debug("Processing shutdown request.", []),
    State1 = do_unregister(State#state{connected=true}),
    {stop, normal, State1};

handle_info({connected, _Client}, #state{connected=false, shutdown=false}=State) ->
    State1 = do_register(State#state{connected=true}),
    State2 = reset_ttl_timer(State1), 
    {noreply, State2};

handle_info({disconnected, _Client}, #state{connected=true}=State) ->
    State1 = clear_ttl_timer(State),
    {noreply, State1#state{connected=false}};

handle_info(Info, State) ->
    lager:debug("ignoring message: ~p", [Info]),
    {noreply, State}.

terminate(_Reason, #state{registered=true}=State) ->
    do_unregister(State),
    ok;

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%============================================================================
%%% Internal functions
%%%============================================================================
do_update(State) ->
    do_register(State).

do_update(Service, State) ->
    State1 = update_state_from_service(Service, State),
    do_register(State1).

reset_ttl_timer(State) ->
    #state{ttl_timer=Timer, ttl=TTL} = State,
    stop_ttl_timer(Timer),
    NewTimer = start_ttl_timer(TTL),
    State#state{ttl_timer=NewTimer}.

clear_ttl_timer(State) ->
    #state{ttl_timer=Timer} = State,
    stop_ttl_timer(Timer),
    State#state{ttl_timer=undefined}.

stop_ttl_timer(Timer) when is_reference(Timer) ->
    erlang:cancel_timer(Timer),
    ok;
 
stop_ttl_timer(_Timer) ->
    ok.

start_ttl_timer(TTLMins) ->
    TTLMillis = TTLMins * 60 * 1000,
    erlang:send_after(TTLMillis, self(), ttl_timeout).

do_register(#state{connected=true}=State) ->
    #state{id=Id, type=Type, notif_man=NotifMan} = State,
    lager:debug("Registering service: ~p (~p).", [Type, Id]),
    send_register(State),
    send_subscribe(State),
    State1 = register_callbacks(State),
    dxl_notif_man:publish(NotifMan, service_registered, {service_registered, Id, Type}), 
    State1#state{registered=true};

do_register(State) ->
    State.

send_register(State) ->
    #state{id=Id, type=Type, parent=Parent} = State,
    lager:debug("Sending DXL service registration: ~p (~p).", [Type, Id]),
    Payload = build_registration_payload(State),
    Request = #dxlmessage{payload=Payload, dst_tenant_ids=State#state.dst_tenant_ids},
    Self = self(),
    Fun = fun({message_in, {_, #dxlmessage{type=response}, _}}) -> 
	         gen_server:cast(Self, registration_success);
    	     ({message_in, {_, #dxlmessage{type=error, error_code=ErrCode, error_message=ErrMsg}, _}}) -> 
	         gen_server:cast(Self, {registration_failed, {ErrCode, ErrMsg}})
	  end,
    dxlc:send_request_async(Parent, ?SVC_REG_REQ_TOPIC, Request, Fun, infinity),
    ok.

send_subscribe(State) ->
    #state{client=Client} = State,
    send_subscribe(get_topic_list(State), Client).

send_subscribe([Topic | Rest], Client) ->
    lager:debug("Subscribing to topic: ~p.", [Topic]),
    dxlc:subscribe(Client, Topic),
    send_subscribe(Rest, Client),
    ok;

send_subscribe([], _Client) ->
    ok.

register_callbacks(State) ->
    #state{id=Id, type=Type, topics=Topics} = State,
    case is_map(Topics) of
        true ->
	    lager:debug("Registering service callbacks: ~p (~p).", [Type, Id]),
            register_callbacks(maps:to_list(Topics), State);
	false ->
    	    State
    end.

register_callbacks([{Topic, Callback} | Rest], State) ->
    #state{notif_man=NotifMan, notifications=Notifications} = State,
    lager:debug("Registering topic notification: ~p.", [Topic]),
    Filter = fun({message_in, {TopicIn, #dxlmessage{type=TypeIn}, _}}) -> 
            (TypeIn =:= request) and (TopicIn =:= Topic) 
    end,
    {ok, NotifId} = dxl_notif_man:subscribe(NotifMan, message_in, Callback, [{filter, Filter}]),
    NewNotifications = maps:put(Topic, NotifId, Notifications),
    register_callbacks(Rest, State#state{notifications=NewNotifications});

register_callbacks([], State) ->
    State.

do_unregister(#state{connected=true}=State) ->
    #state{id=Id, type=Type, notif_man=NotifMan} = State,
    lager:debug("Unregistering service: ~p (~p).", [Type, Id]),
    send_unregister(State),
    send_unsubscribe(State),
    State1 = unregister_callbacks(State),
    dxl_notif_man:publish(NotifMan, service_unregistered, {service_unregistered, Id, Type}), 
    State1#state{registered=false};

do_unregister(State) ->
    State.

send_unregister(State) ->
    #state{id=Id, type=Type, parent=Parent} = State,
    lager:debug("Sending DXL service unregistration: ~p (~p).", [Type, Id]),
    Payload = build_unregistration_payload(State),
    Request = #dxlmessage{payload=Payload},
    dxlc:send_request_async(Parent, ?SVC_UNREG_REQ_TOPIC, Request),
    ok.

send_unsubscribe(State) ->
    #state{client=Client, topics=Topics} = State,
    send_unsubscribe(maps:keys(Topics), Client).

send_unsubscribe([], _Client) ->
    ok;

send_unsubscribe([Topic | Rest], Client) ->
    lager:debug("Unsubscribing from topic: ~p.", [Topic]),
    dxlc:unsubscribe(Client, Topic),
    send_unsubscribe(Rest, Client),
    ok.

unregister_callbacks(State) ->
    #state{notifications=Notifications} = State,
    unregister_callbacks(maps:to_list(Notifications), State).

unregister_callbacks([{Topic, Id} | Rest], State) ->
    #state{notif_man=NotifMan, notifications=Notifications} = State,
    lager:debug("Unregistering topic notification: ~p.", [Topic]),
    dxl_notif_man:unsubscribe(NotifMan, Id),
    NewNotifications = maps:remove(Topic, Notifications),
    unregister_callbacks(Rest, State#state{notifications=NewNotifications});
 
unregister_callbacks([], State) ->
    State.

build_registration_payload(State) ->
    jiffy:encode({[{serviceType, State#state.type},
                   {serviceGuid, State#state.id},
                   {metaData, State#state.metadata},
                   {ttlMins, State#state.ttl},
                   {requestChannels, get_topic_list(State)}]}).

build_unregistration_payload(State) ->
    jiffy:encode({[{serviceGuid, State#state.id}]}).

update_state_from_service(Service, State) ->
    State#state{type=Service#service_registry.service_type,
                metadata=Service#service_registry.metadata,
                topics=Service#service_registry.topics,
                ttl=Service#service_registry.ttl}.

get_topic_list(State) ->
    #state{topics=Topics} = State, 
    case Topics of
        T when is_map(T) -> maps:keys(T);
        T when is_list(T) -> T
    end.
