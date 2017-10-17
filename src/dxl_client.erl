-module(dxl_client).

-behaviour(gen_server).

-export([start_link/1,
	 connected/1,
	 subscribe/2,
	 sync_subscribe/2,
	 unsubscribe/2,
	 subscriptions/1,
	 send_request/3,
	 send_request/4,
	 send_async_request/4,
	 send_async_request/5,
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
    gen_server:start_link({local, Name}, ?MODULE, [GID, MqttOpts], []).

connected(Pid) ->
    gen_server:call(Pid, connected).

subscribe(Pid, Topic) ->
    gen_server:call(Pid, {subscribe, Topic}).

sync_subscribe(Pid, Topic) ->
    gen_server:call(Pid, {sync_subscribe, Topic}).

unsubscribe(Pid, Topic) ->
    gen_server:call(Pid, {unsubscribe, Topic}).

subscriptions(Pid) ->
    gen_server:call(Pid, subscriptions).

send_request(Pid, Topic, Message) ->
    send_request(Pid, Topic, Message, ?DEF_REQ_TIMEOUT).

send_request(Pid, Topic, Message, Timeout) ->
    try
        gen_server:call(Pid, {send_request, Topic, Message}, Timeout)
    catch
        exit:{timeout,_} -> {error, timeout}
    end.

send_async_request(Pid, Topic, Message, Callback) ->
    send_async_request(Pid, Topic, Message, Callback, ?DEF_REQ_TIMEOUT).

send_async_request(Pid, Topic, Message, Callback, Timeout) ->
    gen_server:call(Pid, {send_async_request, Topic, Message, Callback, Timeout}).

send_response(Pid, Topic, Message) ->
    gen_server:call(Pid, {send_response, Topic, Message}).

send_error(Pid, Topic, Message) ->
    gen_server:call(Pid, {send_error, Topic, Message}).

send_event(Pid, Topic, Message) ->
    gen_server:call(Pid, {send_event, Topic, Message}).
%%%============================================================================
%%% gen_server functions
%%%============================================================================
init([GID, MqttOpts]) ->
    ClientId = proplists:get_value(client_id, MqttOpts, dxl_util:generate_uuid()),
    ReplyToTopic = list_to_bitstring("/mcafee/client/" ++ ClientId),
    {ok, Conn} = emqttc:start_link(MqttOpts),
    emqttc:subscribe(Conn, ReplyToTopic),
    State = #state{gid=GID,
		   opts=MqttOpts,
		   mqttc=Conn,
		   client_id=ClientId,
		   reply_to_topic=ReplyToTopic,
		   notif_man=dxl_util:module_reg_name(GID, dxl_notif_man)},
    {ok, State}.

handle_call(connected, _From, State) ->
    #state{connected=Connected} = State,
    {reply, Connected, State};

handle_call({subscribe, Topic}, _From, State) ->
    #state{mqttc=C} = State,
    ok = emqttc:subscribe(C, Topic),
    {reply, ok, State};

handle_call({sync_subscribe, Topic}, _From, State) ->
    #state{mqttc=C} = State,
    {ok, _Qos} = emqttc:sync_subscribe(C, Topic),
    {reply, ok, State};

handle_call({unsubscribe, Topic}, _From, State) ->
    #state{mqttc=C} = State,
    ok = emqttc:unsubscribe(C, Topic),
    {reply, ok, State};

handle_call(subscriptions, _From, State) ->
    #state{mqttc=C} = State,
    [Topic || {Topic, _Qos} <- emqttc:topics(C)];
  
handle_call({send_request, Topic, Message}, From, State) ->
    #state{notif_man=NotifMgr, reply_to_topic=ReplyToTopic} = State,
    Message1 = Message#dxlmessage{reply_to_topic=ReplyToTopic},
    lager:debug("publishing message", []),
    {ok, MessageId} = publish(request, Topic, Message1, State),
    Filter = dxl_notif_man:create_response_filter(MessageId),
    Fun = fun({_,M,_}) -> 
	      io:format("~n~n~nGOT RESPONSE~n~n~n", []),
              gen_server:reply(From, M)
	  end,
    lager:debug("registering notification", []),
    {ok, _} = dxl_notif_man:subscribe(NotifMgr, message_in, Fun, [{one_time_only, true}, {filter, Filter}]),
    lager:debug("returning.", []),
    {noreply, State};

handle_call({send_async_request, Topic, Message}, _From, State) ->
    #state{reply_to_topic=ReplyToTopic} = State,
    Message1 = Message#dxlmessage{reply_to_topic=ReplyToTopic},
    Result = publish(request, Topic, Message1, State),
    {reply, Result, State};

handle_call({send_response, Topic, Message}, _From, State) ->
    Result = publish(response, Topic, Message, State),
    {reply, Result, State};

handle_call({send_error, Topic, Message}, _From, State) ->
    Result = publish(error, Topic, Message, State),
    {reply, Result, State};

handle_call({send_event, Topic, Message}, _From, State) ->
    Result = publish(event, Topic, Message, State),
    {reply, Result, State};

handle_call(Request, _From, State) ->
    lager:debug("Ignoring unexpected call: ~p", [Request]),
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({mqttc, C, connected}, #state{mqttc=C}=State) ->
    #state{notif_man=NotifManager} = State,
    lager:info("DXL Client ~p connected.", [C]),
    dxl_notif_man:publish(NotifManager, connected, self()),
    {noreply, State#state{mqttc=C, connected=true}};

handle_info({mqttc, C, disconnected}, #state{mqttc=C}=State) ->
    #state{notif_man=NotifManager} = State,
    dxl_notif_man:publish(NotifManager, disconnected, self()),
    lager:info("DXL Client ~p disconnected.", [C]),
    {noreply, State#state{connected=false}};

handle_info({publish, Topic, Binary}, State) ->
    #state{notif_man=NotifManager} = State,
    Message = dxl_decoder:decode(Binary),
    dxl_notif_man:publish(NotifManager, message_in, {Topic, Message, self()}),
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
publish(Type, Topic, Message, State) ->
    #state{mqttc=C, client_id=ClientId} = State,
    MessageId = dxl_util:generate_uuid(),
    Message1 = Message#dxlmessage{type=Type, message_id=MessageId, src_client_id=ClientId},
    Encoded = dxl_encoder:encode(Message1),
    %% {ok, MsgId} or {error, timeout}
    ok = emqttc:publish(C, Topic, Encoded),
    {ok, MessageId}.

