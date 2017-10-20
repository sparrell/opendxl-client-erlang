-module(dxlc).

-behaviour(gen_server).

-export([start/1,
	 start_async/1
	]).

-export([register_service/2,
	 register_service/3,
	 register_service_async/2,
	 register_service_async/3,
	 unregister_service/2,
	 update_service/3,
	 subscribe/2,
	 subscribe/3,
         unsubscribe/2,
  	 subscriptions/1,
	 send_request/3,
	 send_request/4,
	 send_request_async/3,
	 send_request_async/4,
	 send_request_async/5,
	 send_response/3,
	 send_error/3,
	 send_event/3,
	 subscribe_notification/4,
	 unsubscribe_notification/2,
	 is_connected/1
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
	notif_man					:: pid(),
	service_man					:: pid(),
	subs = sets:new(),
	pending_requests =  maps:new()			:: map(),
	client_id = ""					:: string(),
	reply_to_topic = ""				:: string(),
	connected = false				:: true | false
       }).

%%%============================================================================
%%% API functions
%%%============================================================================
start([Opts]) ->
    case gen_server:start_link(?MODULE, [Opts], []) of
        {ok, Pid} -> 
	    gen_server:call(Pid, wait_until_connected),
	    {ok, Pid};
        Other -> 
	    Other
    end.

start_async([Opts]) ->
    gen_server:start_link(?MODULE, [Opts], []).

is_connected(Pid) ->
    gen_server:call(Pid, is_connected).

register_service(Pid, Service) ->
    register_service(Pid, Service, ?DEF_SVC_REG_TIMEOUT).

register_service(Pid, Service, Timeout) ->
    gen_server:call(Pid, {register_service, Service, Timeout}, infinity).

register_service_async(Pid, Service) ->
    register_service_async(Pid, Service, ?DEF_SVC_REG_TIMEOUT).

register_service_async(Pid, Service, Timeout) ->
    gen_server:call(Pid, {register_service_async, Service, Timeout}, infinity).

unregister_service(Pid, Id) ->
    unregister_service(Pid, Id, ?DEF_SVC_REG_TIMEOUT).

unregister_service(Pid, Id, Timeout) ->
    gen_server:call(Pid, {unregister_service, Id, Timeout}, infinity).

update_service(Pid, Id, Service) ->
    update_service(Pid, Id, Service, ?DEF_SVC_REG_TIMEOUT).

update_service(Pid, Id, Service, Timeout) ->
    gen_server:call(Pid, {update_service, Id, Service, Timeout}, infinity).

subscribe(Pid, Topic) ->
    subscribe(Pid, Topic, none).

subscribe(Pid, Topic, Callback) ->
    gen_server:call(Pid, {subscribe, Topic, Callback}).

unsubscribe(Pid, Topic) ->
    gen_server:call(Pid, {unsubscribe, Topic}).

subscriptions(Pid) ->
    gen_server:call(Pid, subscriptions).

send_request(Pid, Topic, Message) when is_binary(Message) ->
    send_request(Pid, Topic, #dxlmessage{payload=Message});

send_request(Pid, Topic, #dxlmessage{}=Message) ->
    send_request(Pid, Topic, Message, ?DEF_REQ_TIMEOUT).

send_request(Pid, Topic, Message, Timeout) when is_binary(Message) ->
    send_request(Pid, Topic, #dxlmessage{payload=Message}, Timeout);

send_request(Pid, Topic, #dxlmessage{}=Message, Timeout) ->
    gen_server:call(Pid, {send_request, Topic, Message, Timeout}, infinity).

send_request_async(Pid, Topic, Message) ->
    gen_server:call(Pid, {send_request_async, Topic, Message}, infinity).

send_request_async(Pid, Topic, Message, Callback) ->
    send_request_async(Pid, Topic, Message, Callback, ?DEF_REQ_TIMEOUT).

send_request_async(Pid, Topic, Message, Callback, Timeout) ->
    gen_server:call(Pid, {send_request_async, Topic, Message, Callback, Timeout}, infinity).

send_response(Pid, #dxlmessage{}=Request, #dxlmessage{}=Message) ->
    gen_server:call(Pid, {send_response, Request, Message});

send_response(Pid, #dxlmessage{}=Request, Message) when is_binary(Message) ->
    gen_server:call(Pid, {send_response, Request, #dxlmessage{payload=Message}}).

send_error(Pid, #dxlmessage{}=Request, #dxlmessage{}=Message) ->
    gen_server:call(Pid, {send_error, Request, Message});

send_error(Pid, #dxlmessage{}=Request, Message) when is_binary(Message) ->
    gen_server:call(Pid, {send_error, Request, #dxlmessage{payload=Message}}).

send_event(Pid, Topic, Message) when is_binary(Message) ->
    send_event(Pid, Topic, #dxlmessage{payload=Message});

send_event(Pid, Topic, #dxlmessage{}=Message) ->
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
    {ok, NotifMan} = dxl_notif_man:start_link(GID),
    {ok, ServiceMan} = dxl_service_man:start_link(GID),
    {ok, DxlClient} = dxl_client:start_link([GID, MqttOpts]),

    {ok, #state{dxl_client=DxlClient,
		notif_man=NotifMan,
		service_man=ServiceMan}}.

%%% DXL Client functions
handle_call(is_connected, _From, State) ->
    #state{dxl_client=DxlClient} = State,
    Response = dxl_client:is_connected(DxlClient),
    {reply, Response, State};

handle_call({subscribe, Topic, Callback}, _From, State) ->
    #state{dxl_client=DxlClient, notif_man=N} = State,
    dxl_client:subscribe(DxlClient, Topic),
    case Callback of
        none -> {reply, ok, State};
	_ -> 
            Filter = dxl_notif_man:create_topic_filter(Topic),
            {ok, Id} = dxl_notif_man:subscribe(N, message_in, Callback, [{filter,Filter}]),
            {reply, {ok, Id}, State}
    end;
    
handle_call({unsubscribe, Topic}, _From, State) ->
    #state{dxl_client=DxlClient} = State,
    ok = dxl_client:unsubscribe(DxlClient, Topic),
    {reply, ok, State};

handle_call(subscriptions, _From, State) ->
    #state{dxl_client=DxlClient} = State,
    Subs = dxl_client:subscriptions(DxlClient),
    {reply, {ok, Subs}, State};
  
handle_call({send_request, Topic, Message, Timeout}, From, State) ->
    #state{dxl_client=DxlClient} = State,
    dxl_client:send_request(DxlClient, From, Topic, Message, Timeout),
    {noreply, State};

handle_call({send_request_async, Topic, Message, Callback, Timeout}, _From, State) ->
    #state{dxl_client=DxlClient} = State,
    Result = dxl_client:send_request_async(DxlClient, Topic, Message, Callback, Timeout),
    {reply, Result, State};

handle_call({send_response, Request, Message}, _From, State) ->
    #state{dxl_client=DxlClient} = State,
    Result = dxl_client:send_response(DxlClient, Request, Message),
    {reply, Result, State};

handle_call({send_error, Request, Message}, _From, State) ->
    #state{dxl_client=DxlClient} = State,
    Result = dxl_client:send_error(DxlClient, Request, Message),
    {reply, Result, State};

handle_call({send_event, Topic, Message}, _From, State) ->
    #state{dxl_client=DxlClient} = State,
    Result = dxl_client:send_event(DxlClient, Topic, Message),
    {reply, Result, State};

%%% Notification functions
handle_call({subscribe_notification, Event, Callback, Opts}, _From, State) ->
    #state{notif_man=NotifMgr} = State,
    Result = dxl_notif_man:subscribe(NotifMgr, Event, Callback, Opts),
    {reply, Result, State};

handle_call({unsubscribe_notification, Id}, _From, State) ->
    #state{notif_man=NotifMgr} = State,
    Result = dxl_notif_man:unsubscribe(NotifMgr, Id),
    {reply, Result, State};
    
%%% Service functions
handle_call({register_service, Service, Timeout}, _From, State) ->
    #state{service_man=ServiceMan} = State,
    Result = dxl_service_man:register_service(ServiceMan, Service, Timeout),
    {reply, Result, State};

handle_call({register_service_async, Service, Timeout}, _From, State) ->
    #state{service_man=ServiceMan} = State,
    Result = dxl_service_man:register_service_async(ServiceMan, Service, Timeout),
    {reply, Result, State};

handle_call({unregister_service, Id, Timeout}, _From, State) ->
    #state{service_man=ServiceMan} = State,
    Result = dxl_service_man:unregister_service(ServiceMan, Id, Timeout),
    {reply, Result, State};

handle_call({update_service, Id, Service, Timeout}, _From, State) ->
    #state{service_man=ServiceMan} = State,
    Result = dxl_service_man:update_service(ServiceMan, Id, Service, Timeout),
    {reply, Result, State};

%%% Misc functions
handle_call(wait_until_connected, From, State) ->
    #state{notif_man=NotifMan} = State,
    F = fun(_) -> gen_server:reply(From, ok) end,
    dxl_notif_man:subscribe(NotifMan, connected, F),
    {noreply, State};

handle_call(Request, _From, State) ->
    lager:debug("[~s]: Ignoring unexpected call: ~p", [?MODULE, Request]),
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({connected, _Client}, State) ->
    {noreply, State#state{connected=true}};

handle_info({disconnected, _Client}, State) ->
    {noreply, State#state{connected=false}};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%============================================================================
%%% Internal functions
%%%============================================================================
