-module(dxl_client).

-behaviour(gen_server).

-export([start_link/1,
	 is_connected/1,
	 subscribe/2,
	 unsubscribe/2,
	 subscriptions/1,
	 send_request/4,
	 send_request/5,
	 send_request_async/3,
	 send_request_async/5,
	 send_response/3,
	 send_error/3,
	 send_event/3
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
        parent						:: pid(), 
	gid						:: binary(),
	connected = false				:: true | false,
	opts = []					:: list(),
        mqttc,
	client_id = ""					:: string(),
	reply_to_topic = ""				:: string(),
	notif_man					:: pid()
       }).

%%%============================================================================
%%% API Functions
%%%============================================================================
start_link([GID, MqttOpts]) ->
    Name = dxl_util:module_reg_name(GID, ?MODULE),
    gen_server:start_link({local, Name}, ?MODULE, [self(), GID, MqttOpts], []).

is_connected(Pid) ->
    gen_server:call(Pid, is_connected).

subscribe(Pid, Topic) ->
    gen_server:call(Pid, {subscribe, Topic}).

unsubscribe(Pid, Topic) ->
    gen_server:call(Pid, {unsubscribe, Topic}).

subscriptions(Pid) ->
    gen_server:call(Pid, subscriptions).

send_request(Pid, Topic, Message, Timeout) ->
    dxl_util:safe_gen_server_call(Pid, {send_request, Topic, Message}, Timeout).

send_request(Pid, From, Topic, Message, Timeout) ->
    dxl_util:safe_gen_server_call(Pid, {send_request, From, Topic, Message}, Timeout).

send_request_async(Pid, Topic, Message) ->
    gen_server:call(Pid, {send_request_async, Topic, Message}).

send_request_async(Pid, Topic, Message, Callback, Timeout) ->
    dxl_util:safe_gen_server_call(Pid, {send_request_async, Topic, Message, Callback, Timeout}, Timeout).

send_response(Pid, Request, Message) ->
    gen_server:call(Pid, {send_response, Request, Message}).

send_error(Pid, #dxlmessage{}=Request, Message) ->
    gen_server:call(Pid, {send_error, Request, Message}).

send_event(Pid, Topic, Message) ->
    gen_server:call(Pid, {send_event, Topic, Message}).
%%%============================================================================
%%% gen_server functions
%%%============================================================================
init([Parent, GID, MqttOpts]) ->
    ClientId = proplists:get_value(client_id, MqttOpts, dxl_util:generate_uuid()),
    ReplyToTopic = list_to_bitstring("/mcafee/client/" ++ ClientId),
    {ok, Conn} = emqttc:start_link(MqttOpts),
    emqttc:subscribe(Conn, ReplyToTopic),
    State = #state{parent=Parent,
		   gid=GID,
		   opts=MqttOpts,
		   mqttc=Conn,
		   client_id=ClientId,
		   reply_to_topic=ReplyToTopic,
		   notif_man=dxl_util:module_reg_name(GID, dxl_notif_man)},
    {ok, State}.

handle_call(is_connected, _From, State) ->
    #state{mqttc=C} = State,
    R = emqttc:is_connected(C),
    {reply, R, State};
    %%{reply, Connected, State};

handle_call({subscribe, Topic}, _From, State) ->
    #state{mqttc=C} = State,
    ok = emqttc:subscribe(C, Topic),
    {reply, ok, State};

handle_call({unsubscribe, Topic}, _From, State) ->
    #state{mqttc=C} = State,
    ok = emqttc:unsubscribe(C, Topic),
    {reply, ok, State};

handle_call(subscriptions, _From, State) ->
    #state{mqttc=C} = State,
    [Topic || {Topic, _Qos} <- emqttc:topics(C)];
  
handle_call({send_request, From, Topic, Message}, _From, State) ->
    #state{notif_man=NotifMgr, reply_to_topic=ReplyToTopic} = State,
    Message1 = Message#dxlmessage{reply_to_topic=ReplyToTopic},
    {ok, MessageId} = publish(request, Topic, Message1, State),
    Filter = dxl_util:create_response_filter(Message1#dxlmessage{message_id=MessageId}),
    Fun = fun({message_in, {_,M,_}}) -> 
		dxl_util:print_dxlmessage("FOO", [M]),
		gen_server:reply(From, M) 
	  end,
    Opts = [{one_time_only, true}, {filter, Filter}],
    {ok, _} = dxl_notif_man:subscribe(NotifMgr, message_in, Fun, Opts),
    {reply, ok, State};

handle_call({send_request, Topic, Message}, From, State) ->
    #state{notif_man=NotifMgr, reply_to_topic=ReplyToTopic} = State,
    Message1 = Message#dxlmessage{reply_to_topic=ReplyToTopic},
    {ok, MessageId} = publish(request, Topic, Message1, State),
    Filter = dxl_util:create_response_filter(Message1#dxlmessage{message_id=MessageId}),
    Fun = fun({message_in, {_,M,_}}) -> gen_server:reply(From, M) end,
    Opts = [{one_time_only, true}, {filter, Filter}],
    {ok, _} = dxl_notif_man:subscribe(NotifMgr, message_in, Fun, Opts),
    {noreply, State};

handle_call({send_request_async, Topic, Message}, _From, State) ->
    #state{reply_to_topic=ReplyToTopic} = State,
    Message1 = Message#dxlmessage{reply_to_topic=ReplyToTopic},
    {ok, _MessageId} = publish(request, Topic, Message1, State),
    {reply, ok, State};

handle_call({send_request_async, Topic, Message, Callback, Timeout}, _From, State) ->
    #state{reply_to_topic=ReplyToTopic, notif_man=NotifMan} = State,
    Message1 = Message#dxlmessage{reply_to_topic=ReplyToTopic},
    {ok, MessageId} = publish(request, Topic, Message1, State),
    Filter = dxl_util:create_response_filter(Message1#dxlmessage{message_id=MessageId}),
    Opts = [{one_time_only, true}, {filter, Filter}, {timeout, Timeout}],
    {ok, NotifId} = dxl_notif_man:subscribe(NotifMan, message_in, Callback, Opts),
    {reply, {ok, NotifId}, State};

handle_call({send_response, Request, Message}, _From, State) ->
    #dxlmessage{reply_to_topic=ReplyToTopic} = Request,
    Message1 = populate_response_from_request(Request, Message),
    Result = publish(response, ReplyToTopic, Message1, State),
    {reply, Result, State};

handle_call({send_error, Request, Message}, _From, State) ->
    #dxlmessage{reply_to_topic=ReplyToTopic} = Request,
    Message1 = populate_response_from_request(Request, Message),
    Result = publish(error, ReplyToTopic, Message1, State),
    {reply, Result, State};

handle_call({send_event, Topic, Message}, _From, State) ->
    Result = publish(event, Topic, Message, State),
    {reply, Result, State};

handle_call(Request, _From, State) ->
    lager:debug("[~s]: Ignoring unexpected call: ~p", [?MODULE, Request]),
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({mqttc, C, connected}, #state{mqttc=C}=State) ->
    #state{notif_man=NotifManager} = State,
    lager:info("DXL Client ~p connected.", [C]),
    dxl_notif_man:publish(NotifManager, connected, {connected, self()}),
    {noreply, State#state{mqttc=C, connected=true}};

handle_info({mqttc, C, disconnected}, #state{mqttc=C}=State) ->
    #state{parent=Parent, notif_man=NotifManager} = State,
    dxl_notif_man:publish(NotifManager, disconnected, {disconnected, Parent}),
    lager:info("DXL Client ~p disconnected.", [C]),
    {noreply, State#state{connected=false}};

handle_info({publish, Topic, Binary}, State) ->
    #state{parent=Parent, notif_man=NotifManager} = State,
    Message = dxl_decoder:decode(Binary),
    dxl_util:log_dxlmessage("Inbound MQTT Message", Message),
    dxl_notif_man:publish(NotifManager, message_in, {message_in, {Topic, Message, Parent}}),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%============================================================================
%%% Internal functions
%%%============================================================================
populate_response_from_request(Request, Response) ->
    #dxlmessage{message_id=RequestMessageId, service_id=ServiceId} = Request,
    Response#dxlmessage{request_message_id=RequestMessageId, service_id=ServiceId}.
    
publish(Type, Topic, Message, State) ->
    #state{mqttc=C, client_id=ClientId} = State,
    MessageId = dxl_util:generate_uuid(),
    Message1 = Message#dxlmessage{type=Type, message_id=MessageId, src_client_id=ClientId},
    Encoded = dxl_encoder:encode(Message1),
    %% {ok, MsgId} or {error, timeout}
    ok = emqttc:publish(C, Topic, Encoded),
    {ok, MessageId}.

