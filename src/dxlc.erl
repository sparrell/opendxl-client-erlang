-module(dxlc).

-behaviour(gen_server).

-export([start_link/1]).

-export([subscribe/2,
	 subscribe/3,
	 sync_subscribe/2,
	 sync_subscribe/3,
         unsubscribe/2,
  	 subscriptions/1,
	 send_request/3,
	 send_request/4,
	 send_async_request/5,
	 send_response/3,
	 send_error/3,
	 send_event/3,
	 subscribe_notification/4,
	 unsubscribe_notification/2
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

-record(state, {
	dxl_client					:: pid(),
	notification_manager				:: pid(),
	service_manager					:: pid(),
	subs = sets:new(),
	pending_requests =  maps:new()			:: map(),
	client_id = ""					:: string(),
	reply_to_topic = ""				:: string()
       }).

%%%============================================================================
%%% API functions
%%%============================================================================
start_link([Opts]) ->
    gen_server:start_link(?MODULE, [Opts], []).

subscribe(Pid, Topic) ->
    subscribe(Pid, Topic, none).

subscribe(Pid, Topic, Callback) ->
    gen_server:call(Pid, {subscribe, Topic, Callback}).

sync_subscribe(Pid, Topic) ->
    sync_subscribe(Pid, Topic, none).

sync_subscribe(Pid, Topic, Callback) ->
    gen_server:call(Pid, {sync_subscribe, Topic, Callback}).

unsubscribe(Pid, Topic) ->
    gen_server:call(Pid, {unsubscribe, Topic}).

subscriptions(Pid) ->
    gen_server:call(Pid, subscriptions).

send_request(Pid, Topic, Message) ->
    send_request(Pid, Topic, Message, ?DEF_REQ_TIMEOUT).

send_request(Pid, Topic, Message, Timeout) ->
    gen_server:call(Pid, {send_request, Topic, Message, Timeout}).

send_async_request(Pid, Topic, Message, Callback, Timeout) ->
    gen_server:call(Pid, {send_async_request, Topic, Message, Callback, Timeout}).

send_response(Pid, Topic, Message) when is_map(Message) ->
    gen_server:call(Pid, {send_response, Topic, Message}).

send_error(Pid, Topic, Message) when is_map(Message) ->
    gen_server:call(Pid, {send_error, Topic, Message}).

send_event(Pid, Topic, Message) when is_map(Message) ->
    gen_server:call(Pid, {send_event, Topic, Message}).

subscribe_notification(Pid, Event, Callback, Opts) ->
    gen_server:call(Pid, {subscribe_notification, Event, Callback, Opts}).

unsubscribe_notification(Pid, Id) ->
    gen_server:call(Pid, {unsubscribe_notification, Id}).

%%%============================================================================
%%% gen_server functions
%%%============================================================================
init([MqttOpts]) ->
    GID = dxl_util:generate_uuid(),
    {ok, _} = dxl_registry:start_link(),
    {ok, NotifMgr} = dxl_notification_man:start_link(GID),
    {ok, SvcMgr} = dxl_service_man:start_link(GID),
    {ok, DxlClient} = dxl_client:start_link([GID, MqttOpts]),

    {ok, #state{dxl_client=DxlClient,
		notification_manager=NotifMgr,
		service_manager=SvcMgr}}.

%%% DXL Client functions
handle_call({subscribe, Topic, Callback}, _From, State) ->
    #state{dxl_client=C, notification_manager=N} = State,
    ok = dxl_client:subscribe(C, Topic),
    case Callback of
        none -> {reply, ok, State};
	_ -> 
            Filter = dxl_notification_man:create_topic_filter(Topic),
            {ok, Id} = dxl_notification_man:subscribe(N, message_in, Callback, [{filter,Filter}]),
            {reply, {ok, Id}, State}
    end;
    
handle_call({sync_subscribe, Topic, Callback}, _From, State) ->
    #state{dxl_client=C, notification_manager=N} = State,
    ok = dxl_client:subscribe(C, Topic),
    case Callback of
        none -> {reply, ok, State};
	_ ->
            Filter = dxl_notification_man:create_topic_filter(Topic),
	    {ok, Id} = dxl_notification_man:subscribe(N, message_in, Callback, [{filter,Filter}]),
            {reply, {ok, Id}, State}
    end;

handle_call({unsubscribe, Topic}, _From, State) ->
    #state{dxl_client=C} = State,
    ok = dxl_client:unsubscribe(C, Topic),
    {reply, ok, State};

handle_call(subscriptions, _From, State) ->
    #state{dxl_client=C} = State,
    Subs = dxl_client:subscriptions(C),
    {reply, {ok, Subs}, State};
  
handle_call({send_request, Topic, Message, Timeout}, _From, State) ->
    #state{dxl_client=C} = State,
    Result = dxl_client:send_request(C, Topic, Message, Timeout),
    {reply, Result, State};

handle_call({send_response, Topic, Message}, _From, State) ->
    #state{dxl_client=C} = State,
    Result = dxl_client:send_response(C, Topic, Message),
    {reply, Result, State};

handle_call({send_error, Topic, Message}, _From, State) ->
    #state{dxl_client=C} = State,
    Result = dxl_client:send_error(C, Topic, Message),
    {reply, Result, State};

handle_call({send_event, Topic, Message}, _From, State) ->
    #state{dxl_client=C} = State,
    Result = dxl_client:send_event(C, Topic, Message),
    {reply, Result, State};

%%% Notification functions
handle_call({subscribe_notification, Event, Callback, Opts}, _From, State) ->
    #state{notification_manager=NotifMgr} = State,
    Result = dxl_notification_man:subscribe(NotifMgr, Event, Callback, Opts),
    {reply, Result, State};

handle_call({unsubscribe_notification, Id}, _From, State) ->
    #state{notification_manager=NotifMgr} = State,
    Result = dxl_notification_man:unsubscribe(NotifMgr, Id),
    {reply, Result, State};
    
%%% Misc functions
handle_call(Request, _From, State) ->
    lager:debug("Ignoring unexpected call: ~p", [Request]),
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%============================================================================
%%% Internal functions
%%%============================================================================

