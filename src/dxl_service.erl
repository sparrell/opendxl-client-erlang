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
        topics = maps:new()				:: map(),
        ttl=60                                          :: integer(),
        dst_tenant_ids = []                             :: list()
       }).
-type service_info() :: #service_info{}.

-record(state, {
	gid = <<"">>					:: binary(),
	id = <<"">>					:: binary(),
	type = <<"">>					:: binary(),
	metadata = maps:new()				:: map(),
 	topics = maps:new()				:: map(),	
	notifications = maps:new()			:: map(),
	dst_tenant_ids = []				:: list(),
	ttl=60						:: integer(),
	ttl_timer = make_ref()				:: reference(),
	connected = false				:: true | false,
	registered = false				:: true | false,
	dxl_client					:: term(),
        notif_man					:: term()
      }).

%%%============================================================================
%%% API functions
%%%============================================================================
start_link(GID, Service) ->
    Id = dxl_util:generate_uuid(),
    Result = gen_server:start_link(?MODULE, [GID, Id, Service], []),
    case Result of
        {ok, Pid} -> {ok, {Id, Pid}};
                _ -> Result
    end.

%%%============================================================================
%%% gen_server functions
%%%============================================================================
init([GID, Id, Service]) ->
    DxlClient = dxl_util:module_reg_name(GID, dxl_client),
    NotifMan = dxl_util:module_reg_name(GID, dxl_notif_man),
    Connected = dxl_client:connected(DxlClient),
    State = init(#state{gid=GID,
			id=Id,
                   	type=Service#service_registry.service_type,
                        metadata=Service#service_registry.metadata,
                   	topics=Service#service_registry.topics,
                   	ttl=Service#service_registry.ttl,
		   	dxl_client=DxlClient,
	 	   	notif_man=NotifMan,
		   	connected=Connected,
		   	registered=false}),

    State1 = do_register(State),
    {ok, State1};

init(#state{connected=true} = State) ->
    #state{ttl=TTL} = State,
    Timer = start_ttl_timer(TTL),
    State#state{ttl_timer=Timer};

init(#state{connected=false} = State) ->
    State.

handle_call({update, _Info}, _From, State) ->
    {reply, ok, State};

handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast(shutdown, State) ->
    State1 = do_unregister(State),
    {stop, normal, State1};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(connected, #state{connected=false}=State) ->
    #state{ttl=TTL} = State,
    Timer = start_ttl_timer(TTL),
    {noreply, State#state{ttl_timer=Timer, connected=true}};

handle_info(disconnected, #state{connected=true}=State) ->
    #state{ttl_timer=Timer} = State,
    stop_ttl_timer(Timer),
    {noreply, State#state{connected=false}};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, State) ->
    do_unregister(State),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%============================================================================
%%% Internal functions
%%%============================================================================
stop_ttl_timer(Timer) ->
    erlang:cancel_timer(Timer),
    ok.
 
start_ttl_timer(TTLMins) ->
    TTLMillis = TTLMins * 60 * 1000,
    erlang:send_after(TTLMillis, self(), ttl_timeout).

do_register(State) ->
    #state{id=Id, type=Type} = State,
    lager:debug("Registering service: ~p (~p).", [Type, Id]),
    send_register(State),
    send_subscribe(State),
    State1 = register_callbacks(State),
    State1#state{registered=true}.

send_register(State) ->
    #state{id=Id, type=Type, dxl_client=DxlClient} = State,
    lager:debug("Sending DXL service registration: ~p (~p).", [Type, Id]),
    Payload = build_registration_payload(State),
    Request = #dxlmessage{payload=Payload, dst_tenant_ids=State#state.dst_tenant_ids},
    _Response = dxl_client:send_request(DxlClient, ?SVC_REG_REQ_TOPIC, Request),
    ok.

send_subscribe(State) ->
    #state{topics=Topics, dxl_client=DxlClient} = State,
    send_subscribe(maps:keys(Topics), DxlClient).

send_subscribe([Topic | Rest], DxlClient) ->
    lager:debug("Subscribing to topic: ~p.", [Topic]),
    dxl_client:subscribe(DxlClient, Topic),
    send_subscribe(Rest, DxlClient),
    ok;

send_subscribe([], _DxlClient) ->
    ok.

register_callbacks(State) ->
    #state{topics=Topics} = State,
    register_callbacks(maps:to_list(Topics), State).

register_callbacks([{Topic, Callback} | Rest], State) ->
    #state{notif_man=NotifMan, notifications=Notifications} = State,
    lager:debug("Registering topic notification: ~p.", [Topic]),
    Filter = fun({TopicIn, #dxlmessage{type=TypeIn}, _}) -> (TypeIn =:= request) and (TopicIn =:= Topic) end,
    {ok, Id} = dxl_notif_man:subscribe(NotifMan, message_in, Callback, [{filter, Filter}]),
    NewNotifications = maps:put(Topic, Id, Notifications),
    register_callbacks(Rest, State#state{notifications=NewNotifications});

register_callbacks([], State) ->
    State.

do_unregister(State) ->
    #state{id=Id, type=Type} = State,
    lager:debug("Unregistering service: ~p (~p).", [Type, Id]),
    send_unregister(State),
    send_unsubscribe(State),
    State1 = unregister_callbacks(State),
    State1.

send_unregister(State) ->
    #state{id=Id, type=Type, dxl_client=DxlClient} = State,
    lager:debug("Sending DXL service unregistration: ~p (~p).", [Type, Id]),
    Payload = jiffy:encode({serviceGuid, Id}),
    Request = #dxlmessage{payload=Payload},
    _Response = dxl_client:send_request(DxlClient, ?SVC_UNREG_REQ_TOPIC, Request),
    ok.

send_unsubscribe(State) ->
    #state{dxl_client=DxlClient, topics=Topics} = State,
    send_unsubscribe(maps:key(Topics), DxlClient).

send_unsubscribe([], _DxlClient) ->
    ok;

send_unsubscribe([Topic | Rest], DxlClient) ->
    lager:debug("Unsubscribing from topic: ~p.", [Topic]),
    dxl_client:unsubscribe(DxlClient, Topic),
    send_unsubscribe(Rest, DxlClient),
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
                 {requestChannels, maps:keys(State#state.topics)}]}).
