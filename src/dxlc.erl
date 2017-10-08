-module(dxlc).

-behaviour(gen_server).

-export([start_link/1]).

-export([subscribe/2,
         unsubscribe/2,
  	 subscriptions/1,
	 send_request/3,
	 send_request/4,
	 send_response/3,
	 send_error/3,
	 send_event/3,
         add_callback/3,
         add_callback/4,
         remove_callback/2
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
	opts = []					:: list(),
        mqttc,
	callback_manager				:: pid(),
	subs = sets:new(),
	callbacks = maps:new()				:: map(),
	pending_requests =  maps:new()			:: map(),
	client_id = ""					:: string(),
	reply_to_topic = ""				:: string()
       }).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Public Functions							       %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_link([Opts]) ->
    gen_server:start_link(?MODULE, [Opts], []).

subscribe(Pid, Topic) ->
    gen_server:call(Pid, {subscribe, Topic}).

unsubscribe(Pid, Topic) ->
    gen_server:call(Pid, {unsubscribe, Topic}).

subscriptions(Pid) ->
    gen_server:call(Pid, subscriptions).

send_request(Pid, Topic, Message) ->
    send_request(Pid, Topic, Message, ?DEF_REQ_TIMEOUT).

send_request(Pid, Topic, Message, Delay) ->
    try
        gen_server:call(Pid, {send_request, Topic, Message, Delay})
    catch
	exit:{timeout,_} -> {error, timeout}
    end.

send_async_request(Pid, Topic, Messagey, Callback, Delay) ->
    HandlerId = add_callback(Pid, response, Topic, Callback, Timeout);
    ok.

send_response(Pid, Topic, Message) when is_map(Message) ->
    gen_server:call(Pid, {send_response, Topic, Message}).

send_error(Pid, Topic, Message) when is_map(Message) ->
    gen_server:call(Pid, {send_error, Topic, Message}).

send_event(Pid, Topic, Message) when is_map(Message) ->
    gen_server:call(Pid, {send_event, Topic, Message}).

add_callback(Pid, Type, Callback) when is_atom(Type) ->
    add_callback(Pid, Type, <<"">>, Callback);

add_callback(Pid, Topic, Callback) when is_binary(Topic) ->
    add_callback(Pid, global, Topic, Callback).

add_callback(Pid, Type, Topic, Callback) ->
    add_callback(Pid, Type, Topic, Callback, infinity).

add_callback(Pid, Type, Topic, Callback, Timeout) ->
    gen_server:call(Pid, {add_callback, {Type, Topic}, Callback, Timeout}).

remove_callback(Pid, Id) when is_reference(Id); is_pid(Id) ->
    gen_server:call(Pid, {remove_callback, Id}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Private Functions							       %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
init([Opts]) ->
    ClientId = proplists:get_value(client_id, Opts, uuid:create()),
    ReplyToTopic = "/mcafee/client/" ++ ClientId,
    {ok, Conn} = emqttc:start_link(Opts),
    {ok, CallbackManager} = callback_manager:start_link(),
    State = #state{opts=Opts,
		   mqttc=Conn,
		   callback_manager=CallbackManager,
		   client_id=ClientId,
		   reply_to_topic=ReplyToTopic},
    {ok, State}.

handle_call({subscribe, Topic}, _From, State) ->
    #state{mqttc=MQTTC, subs=Subs} = State,
    emqttc:subscribe(MQTTC, Topic),
    NewSubs = sets:add_element(Topic, Subs),
    {reply, ok, State#state{subs=NewSubs}};

handle_call({unsubscribe, Topic}, _From, State) ->
    #state{mqttc=MQTTC, subs=Subs} = State,
    emqttc:unsubscribe(MQTTC, Topic),
    NewSubs = sets:del_element(Topic, Subs),
    {reply, ok, State#state{subs=NewSubs}};

handle_call(subscriptions, _From, State) ->
    #state{subs=Subs} = State,
    {reply, sets:to_list(Subs), State};
  
handle_call({send_request, Topic, Message, Delay}, From, State) ->
    #state{mqttc=MQTTC, pending_requests=PendingReqs, reply_to_topic=ReplyToTopic} = State,
    Message1 = pre_process_message_out(request, Message, State),
    Message2 = Message1#{reply_to_topic=>ReplyToTopic},
    PendingReqs1 = maps:put(maps:get(message_id, Message2), From, PendingReqs),
    post(MQTTC, Topic, Message1, State),
    {noreply, State#state{pending_requests=PendingReqs1}, Delay};

handle_call({send_response, Topic, Message}, _From, State) ->
    #state{mqttc=MQTTC} = State,
    Message1 = pre_process_message_out(response, Message, State),
    post(MQTTC, Topic, Message1, State),
    {reply, ok, State};

handle_call({send_error, Topic, Message}, _From, State) ->
    #state{mqttc=MQTTC} = State,
    Message1 = pre_process_message_out(error, Message, State),
    post(MQTTC, Topic, Message1, State),
    {reply, ok, State};

handle_call({send_event, Topic, Message}, _From, State) ->
    #state{mqttc=MQTTC} = State,
    Message1 = pre_process_message_out(event, Message, State),
    post(MQTTC, Topic, Message1, State),
    {reply, ok, State};

handle_call({add_callback, Dest, Callback}, _From, State) ->
    #state{callback_manager=CallbackManager} = State,
    Result = gen_server:call(CallbackManager, {add_callback, Dest, Callback}),
    {reply, Result, State};

handle_call({remove_callback, Id}, _From, State) ->
    #state{callback_manager=CallbackManager} = State,
    Result = gen_server:call(CallbackManager, {remove_callback, Id}),
    {reply, Result, State};

handle_call(Request, _From, State) ->
    lager:debug("Ignoring unexpected call: ~p", [Request]),
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({mqttc, C, connected}, #state{mqttc=C}=State) ->
    lager:info("DXL Client ~p connected.", [C]),
    {noreply, State#state{mqttc=C}};

handle_info({mqttc, C, disconnected}, #state{mqttc=C}=State) ->
    lager:info("DXL Client ~p disconnected.", [C]),
    {noreply, State};

handle_info({publish, Topic, Binary}, State) ->
    #state{callback_manager=CallbackManager} = State,
    Message = dxldecoder:decode(Binary),
    Type = maps:get(type, Message),
    process_message_in(Type, Message, State),
    gen_server:cast(CallbackManager, {notify, {Type, Topic, Message}, self()}),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

post(MQTTC, Topic, Message, _State) ->
    Encoded = dxlencoder:encode(Message),
    %% {ok, MsgId} or {error, timeout}
    Result = emqttc:publish(MQTTC, Topic, Encoded),
    Result.

pre_process_message_out(Type, Message, State) when is_atom(Type) ->
    #state{client_id=ClientId} = State,
    MessageId = uuid:create(),
    Message#{type=>Type, message_id=>MessageId, src_client_id=>ClientId}.

process_message_in(response, Message, State) ->
    #state{pending_requests=PendingRequests} = State,
    State1 = case maps:get(request_message_id, Message, undefined) of
        undefined -> State;
	RequestMessageId ->
	    case maps:get(RequestMessageId, PendingRequests, undefined) of
	        undefined -> 
	  	    #{message_id := MessageId} = Message,
		    lager:info("Received response with no matching pending request. "
			       "Message ID = ~p, Request Message ID = ~p.", [MessageId, RequestMessageId]),
		    State;
	 	Sender ->
	  	    gen_server:reply(Sender, {ok, Message}), 
		    NewPendingReqs = maps:remove(RequestMessageId, PendingRequests),
		    State#state{pending_requests=NewPendingReqs}
            end
    end,
	    
    State1;

process_message_in(_Type, _Message, State) ->
    State.
