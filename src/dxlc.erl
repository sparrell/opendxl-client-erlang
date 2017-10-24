-module(dxlc).

-behaviour(gen_server).

-export([start/1,
         start_async/1
]).

-export([register_service/2,
         register_service/3,
         register_service_async/2,
         register_service_async/4,
         unregister_service/2,
         unregister_service/3,
         unregister_service_async/2,
         unregister_service_async/4,
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
    parent :: pid(),
    dxl_conn :: pid(),
    notif_man :: pid(),
    service_man :: pid(),
    subs = sets:new(),
    pending_requests = maps:new() :: map(),
    client_id = "" :: string(),
    reply_to_topic = "" :: string(),
    connected = false :: true | false
}).

%%%============================================================================
%%% API functions
%%%============================================================================
-spec start(Opts :: list()) -> {ok, Pid :: pid()} | {error, Error :: term()}.
start(Opts) ->
    GID = dxl_util:generate_uuid(),
    Name = dxl_util:module_reg_name(GID, ?MODULE),
    case gen_server:start_link({local, Name}, ?MODULE, [self(), GID, Opts], []) of
        {ok, Pid} ->
            gen_server:call(Pid, wait_until_connected),
            {ok, Pid};
        Other ->
            Other
    end.

-spec start_async(Opts :: list()) -> {ok, Pid :: pid()} | {error, Error :: term()}.
start_async(Opts) ->
    GID = dxl_util:generate_uuid(),
    Name = dxl_util:module_reg_name(GID, ?MODULE),
    gen_server:start_link({local, Name}, ?MODULE, [self(), GID, Opts], []).

-spec is_connected(Pid :: pid()) -> {true, Host :: string()} | false.
is_connected(Pid) ->
    gen_server:call(Pid, is_connected).

-spec register_service(Pid :: pid(), Service :: service_registry()) -> {ok, ServiceId :: binary()} | {error, Error :: term()}.
register_service(Pid, Service) ->
    register_service(Pid, Service, ?DEF_SVC_REG_TIMEOUT).

-spec register_service(Pid :: pid(), Service :: service_registry(), Timeout :: integer()) -> {ok, ServiceId :: binary()} | {error, Error :: term()}.
register_service(Pid, Service, Timeout) ->
    gen_server:call(Pid, {register_service, Service, Timeout}, infinity).

-spec register_service_async(Pid :: pid(), Service :: service_registry()) -> {ok, ServiceId :: service_id()}.
register_service_async(Pid, Service) ->
    register_service_async(Pid, Service, undefined, ?DEF_SVC_REG_TIMEOUT).

-spec register_service_async(Pid :: pid(), Service :: service_registry(), Callback :: callback(), Timeout :: integer()) -> {ok, ServiceId :: service_id()}.
register_service_async(Pid, Service, Callback, Timeout) ->
    gen_server:call(Pid, {register_service_async, Service, Callback, Timeout}, infinity).

-spec unregister_service(Pid :: pid(), Id :: service_id()) -> ok | {error, Error :: term()}.
unregister_service(Pid, Id) ->
    unregister_service(Pid, Id, ?DEF_SVC_REG_TIMEOUT).

-spec unregister_service(Pid :: pid(), Id :: service_id(), Timeout :: integer()) -> {ok, ServiceId :: service_id} | {error, Error :: term()}.
unregister_service(Pid, Id, Timeout) ->
    gen_server:call(Pid, {unregister_service, Id, Timeout}, infinity).

-spec unregister_service_async(Pid :: pid(), Id :: service_id()) -> ok | {error, Reason :: term()}.
unregister_service_async(Pid, Id) ->
    unregister_service_async(Pid, Id, undefined, ?DEF_SVC_REG_TIMEOUT).

-spec unregister_service_async(Pid :: pid(), Id :: service_id(), Callback :: callback(), Timeout :: integer()) -> ok | {error, Reason :: term()}.
unregister_service_async(Pid, Id, Callback, Timeout) ->
    gen_server:call(Pid, {unregister_service_async, Id, Callback, Timeout}, infinity).

-spec update_service(Pid :: pid(), Id :: service_id(), Service :: service_registry()) -> ok.
update_service(Pid, Id, Service) ->
    update_service(Pid, Id, Service, ?DEF_SVC_REG_TIMEOUT).

-spec update_service(Pid :: pid(), Id :: service_id(), Service :: service_registry(), Timeout :: integer()) -> ok.
update_service(Pid, Id, Service, Timeout) ->
    gen_server:call(Pid, {update_service, Id, Service, Timeout}, infinity).

-spec subscribe(Pid :: pid(), Topic :: topic()) -> ok.
subscribe(Pid, Topic) ->
    subscribe(Pid, Topic, undefined).

-spec subscribe(Pid :: pid(), Topic :: topic(), Callback :: callback()) -> {ok, NotificationId :: reference()}.
subscribe(Pid, Topic, Callback) ->
    gen_server:call(Pid, {subscribe, Topic, Callback}).

-spec unsubscribe(Pid :: pid(), Topic :: topic()) -> ok.
unsubscribe(Pid, Topic) ->
    gen_server:call(Pid, {unsubscribe, Topic}).

-spec subscriptions(Pid :: pid()) -> [topic()].
subscriptions(Pid) ->
    gen_server:call(Pid, subscriptions).

-spec send_request(Pid :: pid(), Topic :: topic(), MessageOut :: payload() | dxlmessage()) -> MessageIn :: dxlmessage() | {error, Reason :: term()}.
send_request(Pid, Topic, Message) when is_binary(Message) ->
    send_request(Pid, Topic, #dxlmessage{payload = Message});

send_request(Pid, Topic, #dxlmessage{} = Message) ->
    send_request(Pid, Topic, Message, ?DEF_REQ_TIMEOUT).

-spec send_request(Pid :: pid(), Topic :: topic(), MessageOut :: payload() | dxlmessage(), Timeout :: integer()) -> MessageIn :: dxlmessage() | {error, Reason :: term()}.
send_request(Pid, Topic, Payload, Timeout) when is_binary(Payload) ->
    send_request(Pid, Topic, #dxlmessage{payload = Payload}, Timeout);

send_request(Pid, Topic, #dxlmessage{} = Message, Timeout) ->
    dxl_util:safe_gen_server_call(Pid, {send_request, Topic, Message, Timeout}, Timeout).

-spec send_request_async(Pid :: pid(), Topic :: topic(), MessageOut :: payload() | dxlmessage()) -> MessageIn :: dxlmessage() | {error, Reason :: term()}.
send_request_async(Pid, Topic, Message) when is_binary(Message) ->
    send_request_async(Pid, Topic, #dxlmessage{payload = Message}, undefined, ?DEF_SVC_REG_TIMEOUT);

send_request_async(Pid, Topic, #dxlmessage{} = Message) ->
    send_request_async(Pid, Topic, Message, undefined, ?DEF_SVC_REG_TIMEOUT).

-spec send_request_async(Pid :: pid(), Topic :: topic(), MessageOut :: payload() | dxlmessage(), Callback :: callback()) -> MessageIn :: dxlmessage() | {error, Reason :: term()}.
send_request_async(Pid, Topic, Message, Callback) when is_binary(Message) ->
    send_request_async(Pid, Topic, #dxlmessage{payload = Message}, Callback, ?DEF_SVC_REG_TIMEOUT);

send_request_async(Pid, Topic, #dxlmessage{} = Message, Callback) ->
    send_request_async(Pid, Topic, Message, Callback, ?DEF_REQ_TIMEOUT).

-spec send_request_async(Pid :: pid(), Topic :: topic(), MessageOut :: payload() | dxlmessage(), Callback :: callback(), Timeout :: integer()) -> MessageIn :: dxlmessage() | {error, Reason :: term()}.
send_request_async(Pid, Topic, Message, Callback, Timeout) when is_binary(Message) ->
    send_request_async(Pid, Topic, #dxlmessage{payload = Message}, Callback, Timeout);

send_request_async(Pid, Topic, #dxlmessage{} = Message, Callback, Timeout) ->
    dxl_util:safe_gen_server_call(Pid, {send_request_async, Topic, Message, Callback, Timeout}, infinity).

-spec send_response(Pid :: pid(), Request :: dxlmessage(), Message :: payload() | dxlmessage()) -> {ok, MessageId :: binary()}.
send_response(Pid, #dxlmessage{} = Request, #dxlmessage{} = Message) ->
    gen_server:call(Pid, {send_response, Request, Message});

send_response(Pid, #dxlmessage{} = Request, Message) when is_binary(Message) ->
    gen_server:call(Pid, {send_response, Request, #dxlmessage{payload = Message}}).

-spec send_error(Pid :: pid(), Request :: dxlmessage(), Message :: payload() | dxlmessage()) -> {ok, MessageId :: binary()}.
send_error(Pid, #dxlmessage{} = Request, #dxlmessage{} = Message) ->
    gen_server:call(Pid, {send_error, Request, Message});

send_error(Pid, #dxlmessage{} = Request, Message) when is_binary(Message) ->
    gen_server:call(Pid, {send_error, Request, #dxlmessage{payload = Message}}).

-spec send_event(Pid :: pid(), Request :: dxlmessage(), Message :: payload() | dxlmessage()) -> {ok, MessageId :: binary()}.
send_event(Pid, Topic, Message) when is_binary(Message) ->
    send_event(Pid, Topic, #dxlmessage{payload = Message});

send_event(Pid, Topic, #dxlmessage{} = Message) ->
    gen_server:call(Pid, {send_event, Topic, Message}).

-spec subscribe_notification(Pid :: pid(), Event :: atom(), Callback :: callback(), Opts :: list()) -> {ok, NotificationId :: binary()}.
subscribe_notification(Pid, Event, Callback, Opts) ->
    gen_server:call(Pid, {subscribe_notification, Event, Callback, Opts}).

-spec unsubscribe_notification(Pid :: pid(), NotificationId :: binary()) -> ok.
unsubscribe_notification(Pid, NotificationId) ->
    gen_server:call(Pid, {unsubscribe_notification, NotificationId}).

%%%============================================================================
%%% gen_server functions
%%%============================================================================
init([Parent, GID, MqttOpts]) ->
    {ok, NotifMan} = dxl_notif_man:start_link(GID),
    {ok, ServiceMan} = dxl_service_man:start_link(GID),
    {ok, DxlConn} = dxl_conn:start_link([GID, MqttOpts]),

    {ok, #state{parent      = Parent,
                dxl_conn    = DxlConn,
                notif_man   = NotifMan,
                service_man = ServiceMan}}.

%%% DXL Client functions
handle_call(is_connected, _From, State) ->
    #state{dxl_conn = DxlConn} = State,
    Response = dxl_conn:is_connected(DxlConn),
    {reply, Response, State};

handle_call({subscribe, Topic, Callback}, _From, State) ->
    #state{dxl_conn = DxlConn, notif_man = N} = State,
    dxl_conn:subscribe(DxlConn, Topic),
    case Callback of
        none -> {reply, ok, State};
        _ ->
            Filter = dxl_util:create_topic_filter(Topic),
            {ok, Id} = dxl_notif_man:subscribe(N, message_in, Callback, [{filter, Filter}]),
            {reply, {ok, Id}, State}
    end;

handle_call({unsubscribe, Topic}, _From, State) ->
    #state{dxl_conn = DxlConn} = State,
    ok = dxl_conn:unsubscribe(DxlConn, Topic),
    {reply, ok, State};

handle_call(subscriptions, _From, State) ->
    #state{dxl_conn = DxlConn} = State,
    Subs = dxl_conn:subscriptions(DxlConn),
    {reply, {ok, Subs}, State};

handle_call({send_request, Topic, Message, Timeout}, From, State) ->
    #state{dxl_conn = DxlConn} = State,
    dxl_conn:send_request(DxlConn, From, Topic, Message, Timeout),
    {noreply, State};

handle_call({send_request_async, Topic, Message}, _From, State) ->
    #state{dxl_conn = DxlConn} = State,
    {ok, MessageId} = dxl_conn:send_request_async(DxlConn, Topic, Message),
    {reply, {ok, MessageId}, State};

handle_call({send_request_async, Topic, Message, Callback, Timeout}, _From, State) ->
    #state{dxl_conn = DxlConn} = State,
    {ok, MessageId} = dxl_conn:send_request_async(DxlConn, Topic, Message, Callback, Timeout),
    {reply, {ok, MessageId}, State};

handle_call({send_response, Request, Message}, _From, State) ->
    #state{dxl_conn = DxlConn} = State,
    Result = dxl_conn:send_response(DxlConn, Request, Message),
    {reply, Result, State};

handle_call({send_error, Request, Message}, _From, State) ->
    #state{dxl_conn = DxlConn} = State,
    Result = dxl_conn:send_error(DxlConn, Request, Message),
    {reply, Result, State};

handle_call({send_event, Topic, Message}, _From, State) ->
    #state{dxl_conn = DxlConn} = State,
    Result = dxl_conn:send_event(DxlConn, Topic, Message),
    {reply, Result, State};

%%% Notification functions
handle_call({subscribe_notification, Event, Callback, Opts}, _From, State) ->
    #state{notif_man = NotifMgr} = State,
    Result = dxl_notif_man:subscribe(NotifMgr, Event, Callback, Opts),
    {reply, Result, State};

handle_call({unsubscribe_notification, Id}, _From, State) ->
    #state{notif_man = NotifMgr} = State,
    Result = dxl_notif_man:unsubscribe(NotifMgr, Id),
    {reply, Result, State};

%%% Service functions
handle_call({register_service, Service, Timeout}, From, State) ->
    #state{service_man = ServiceMan} = State,
    dxl_service_man:register_service(ServiceMan, From, Service, Timeout),
    {noreply, State};

handle_call({register_service_async, Service, Callback, Timeout}, _From, State) ->
    #state{service_man = ServiceMan} = State,
    {ok, ServiceId} = dxl_service_man:register_service_async(ServiceMan, Service, Callback, Timeout),
    {reply, {ok, ServiceId}, State};

handle_call({unregister_service, Id, Timeout}, From, State) ->
    #state{service_man = ServiceMan} = State,
    dxl_service_man:unregister_service(ServiceMan, From, Id, Timeout),
    {noreply, State};

handle_call({unregister_service_async, Id, Callback, Timeout}, _From, State) ->
    #state{service_man = ServiceMan} = State,
    dxl_service_man:unregister_service_async(ServiceMan, Id, Callback, Timeout),
    {reply, ok, State};

handle_call({update_service, Id, Service, Timeout}, _From, State) ->
    #state{service_man = ServiceMan} = State,
    Result = dxl_service_man:update_service(ServiceMan, Id, Service, Timeout),
    {reply, Result, State};

%%% Misc functions
handle_call(wait_until_connected, From, State) ->
    #state{notif_man = NotifMan} = State,
    F = fun(_) -> gen_server:reply(From, ok) end,
    dxl_notif_man:subscribe(NotifMan, connected, F),
    {noreply, State};

handle_call(Request, _From, State) ->
    lager:debug("[~s]: Ignoring unexpected call: ~p", [?MODULE, Request]),
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({connected, _Client}, State) ->
    {noreply, State#state{connected = true}};

handle_info({disconnected, _Client}, State) ->
    {noreply, State#state{connected = false}};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%============================================================================
%%% Internal functions
%%%============================================================================
