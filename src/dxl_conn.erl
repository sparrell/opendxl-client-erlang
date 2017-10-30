%%%----------------------------------------------------------------------------
%%% @author Chris Waymire <chris@waymire.net>
%%% @doc
%%% The dxl_conn module manages the connection to, and interactions with, the
%%% DXL broker.
%%%
%%% This module is considered private and should not be accessed
%%% directly. DXL
%%% @end
%%%----------------------------------------------------------------------------
-module(dxl_conn).

-behaviour(gen_server).

-export([start_link/1,
         is_connected/1,
         subscribe/2,
         unsubscribe/2,
         subscriptions/1,
         send_request/3,
         send_request/5,
         send_request_async/3,
         send_request_async/4,
         send_request_async/5,
         send_response/3,
         send_error/3,
         send_event/3,
         set_client_id/2
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
    gid :: binary(),
    connected = false :: true | false,
    opts = [] :: list(),
    mqttc,
    client_id = "" :: string(),
    reply_to_topic = "" :: string(),
    client :: pid(),
    notif_man :: pid()
}).

%%%============================================================================
%%% API Functions
%%%============================================================================
start_link([GID, Opts]) ->
    Name = dxl_util:module_reg_name(GID, ?MODULE),
    gen_server:start_link({local, Name}, ?MODULE, [GID, Opts], []).

is_connected(Pid) ->
    gen_server:call(Pid, is_connected).

subscribe(Pid, Topic) ->
    gen_server:call(Pid, {subscribe, Topic}).

unsubscribe(Pid, Topic) ->
    gen_server:call(Pid, {unsubscribe, Topic}).

subscriptions(Pid) ->
    gen_server:call(Pid, subscriptions).

send_request(Pid, Topic, Message) ->
    gen_server:call(Pid, {send_request, Topic, Message}).

send_request(Pid, Sender, Topic, Message, Timeout) ->
    gen_server:call(Pid, {send_request, Sender, Topic, Message, Timeout}).

send_request_async(Pid, Topic, Message) ->
    gen_server:call(Pid, {send_request_async, Topic, Message}, infinity).

send_request_async(Pid, Topic, Message, Callback) ->
    send_request_async(Pid, Topic, Message, Callback, ?DEF_REQ_TIMEOUT).

send_request_async(Pid, Topic, Message, Callback, Timeout) ->
    gen_server:call(Pid, {send_request_async, Topic, Message, Callback, Timeout}).

send_response(Pid, Request, Message) ->
    gen_server:call(Pid, {send_response, Request, Message}).

send_error(Pid, #dxlmessage{} = Request, Message) ->
    gen_server:call(Pid, {send_error, Request, Message}).

send_event(Pid, Topic, Message) ->
    gen_server:call(Pid, {send_event, Topic, Message}).

set_client_id(Pid, ClientId) ->
    gen_server:call(Pid, {set_client_id, ClientId}).

%%%============================================================================
%%% gen_server functions
%%%============================================================================
init([GID, OptsIn]) ->
    Opts = init_opts(OptsIn),
    ClientId = proplists:get_value(client_id, Opts, dxl_util:generate_uuid()),
    ReplyToTopic = list_to_bitstring("/mcafee/client/" ++ ClientId),
    {ok, Conn} = emqttc:start_link(Opts),
    emqttc:subscribe(Conn, ReplyToTopic),
    State = #state{gid            = GID,
                   opts           = Opts,
                   mqttc          = Conn,
                   client_id      = ClientId,
                   reply_to_topic = ReplyToTopic,
                   client         = dxl_util:module_reg_name(GID, dxlc),
                   notif_man      = dxl_util:module_reg_name(GID, dxl_notif_man)},
    {ok, State}.

handle_call(is_connected, _From, State) ->
    Result = do_is_connected(State),
    {reply, Result, State};

handle_call({subscribe, Topic}, _From, State) ->
    Result = do_subscribe(Topic, State),
    {reply, Result, State};

handle_call({unsubscribe, Topic}, _From, State) ->
    Result = do_unsubscribe(Topic, State),
    {reply, Result, State};

handle_call(subscriptions, _From, State) ->
    Result = do_subscriptions(State),
    {reply, Result, State};

handle_call({send_request, Topic, Message}, _From, State) ->
    Result = do_send_request(Topic, Message, State),
    {reply, Result, State};

handle_call({send_request, Sender, Topic, Message, Timeout}, _From, State) ->
    Result = do_send_request(Sender, Topic, Message, Timeout, State),
    {reply, Result, State};

handle_call({send_request_async, Topic, Message}, _From, State) ->
    Result = do_send_request_async(Topic, Message, State),
    {reply, Result, State};

handle_call({send_request_async, Topic, Message, Callback, Timeout}, _From, State) ->
    Result = do_send_request_async(Topic, Message, Callback, Timeout, State),
    {reply, Result, State};

handle_call({send_response, Request, Message}, _From, State) ->
    Result = do_send_response(Request, Message, State),
    {reply, Result, State};

handle_call({send_error, Request, Message}, _From, State) ->
    Result = do_send_error(Request, Message, State),
    {reply, Result, State};

handle_call({send_event, Topic, Message}, _From, State) ->
    Result = do_send_event(Topic, Message, State),
    {reply, Result, State}.

handle_cast({verify_client_id, ActiveClientId}, State) ->
    #state{client = Client, client_id = CurrentClientId, notif_man = NotifMan} = State,
    case CurrentClientId =:= ActiveClientId of
        true ->
            lager:info("Client ID has been set to ~p.", [ActiveClientId]);
        false ->
            lager:info("Client ID has been changed from ~p to ~p.", [CurrentClientId, ActiveClientId]),
            do_unsubscribe(<<?CLIENT_TOPIC_PREFIX, CurrentClientId/binary>>, State)
    end,

    ClientTopic = <<?CLIENT_TOPIC_PREFIX, ActiveClientId/binary>>,
    case lists:member(ClientTopic, do_subscriptions(State)) of
        true -> ok;
        false ->
            lager:info("Subscribing to client topic: ~p.", [ClientTopic]),
            do_subscribe(ClientTopic, State)
    end,
    dxl_notif_man:publish(NotifMan, connection, {connected, Client}),
    {noreply, State#state{client_id = ActiveClientId, reply_to_topic = ClientTopic}};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({mqttc, C, connected}, #state{mqttc = C} = State) ->
    lager:info("DXL Client ~p connected.", [C]),
    verify_client_id(State),
    {noreply, State#state{mqttc = C, connected = true}};

handle_info({mqttc, C, disconnected}, #state{mqttc = C} = State) ->
    #state{client = Client, notif_man = NotifMan} = State,
    dxl_notif_man:publish(NotifMan, connection, {disconnected, Client}),
    lager:info("DXL Client ~p disconnected.", [C]),
    {noreply, State#state{connected = false}};

handle_info({publish, Topic, Binary}, State) ->
    #state{client = Client, notif_man = NotifMan} = State,
    Message = dxl_decoder:decode(Binary),
    dxl_util:log_dxlmessage("Inbound DXL Message", Message),
    dxl_notif_man:publish(NotifMan, message_in, {Topic, Message, Client}),
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
init_opts(Opts) ->
    DxlConnOpts = [{logger, {lager, info}}, auto_resub],
    lists:flatten([DxlConnOpts | Opts]).

do_is_connected(State) ->
    #state{mqttc = C} = State,
    R = emqttc:is_connected(C),
    R.

do_subscribe(Topic, State) ->
    #state{mqttc = C} = State,
    ok = emqttc:subscribe(C, Topic),
    ok.

do_unsubscribe(Topic, State) ->
    #state{mqttc = C} = State,
    ok = emqttc:unsubscribe(C, Topic),
    ok.

do_subscriptions(State) ->
    #state{mqttc = C} = State,
    [Topic || {Topic, _Qos} <- emqttc:topics(C)].

do_send_request(Topic, Message, State) ->
    #state{reply_to_topic = ReplyToTopic} = State,
    Message1 = Message#dxlmessage{reply_to_topic = ReplyToTopic},
    ok = publish(request, Topic, Message1, State).

do_send_request(Sender, Topic, Message, Timeout, State) ->
    #state{reply_to_topic = ReplyToTopic, notif_man = NotifMan} = State,
    Message1 = Message#dxlmessage{reply_to_topic = ReplyToTopic},
    Callback = fun({_, M, _}) -> gen_server:reply(Sender, M) end,
    Filter = dxl_util:create_response_filter(Message),
    Opts = [{single_use, true}, {filter, Filter}, {timeout, Timeout}],
    {ok, _} = dxl_notif_man:subscribe(NotifMan, message_in, Callback, Opts),
    ok = publish(request, Topic, Message1, State).

do_send_request_async(Topic, Message, State) ->
    #state{reply_to_topic = ReplyToTopic} = State,
    Message1 = Message#dxlmessage{reply_to_topic = ReplyToTopic},
    ok = publish(request, Topic, Message1, State),
    ok.

do_send_request_async(Topic, Message, Callback, Timeout, State) ->
    #state{reply_to_topic = ReplyToTopic, notif_man = NotifMan} = State,
    Message1 = Message#dxlmessage{reply_to_topic = ReplyToTopic},
    Filter = dxl_util:create_response_filter(Message1),
    Opts = [{single_use, true}, {filter, Filter}, {timeout, Timeout}],
    {ok, NotifId} = dxl_notif_man:subscribe(NotifMan, message_in, Callback, Opts),
    ok = publish(request, Topic, Message1, State),
    {ok, NotifId}.

do_send_response(Request, Message, State) ->
    #dxlmessage{reply_to_topic = ReplyToTopic} = Request,
    Message1 = populate_response_from_request(Request, Message),
    publish(response, ReplyToTopic, Message1, State).

do_send_error(Request, Message, State) ->
    #dxlmessage{reply_to_topic = ReplyToTopic} = Request,
    Message1 = populate_response_from_request(Request, Message),
    publish(error, ReplyToTopic, Message1, State).

do_send_event(Topic, Message, State) ->
    publish(event, Topic, Message, State).

populate_response_from_request(Request, Response) ->
    #dxlmessage{message_id = RequestMessageId, service_id = ServiceId} = Request,
    Response#dxlmessage{request_message_id = RequestMessageId, service_id = ServiceId}.

publish(Type, Topic, Message, State) ->
    #state{mqttc = C, client_id = ClientId, reply_to_topic = ReplyToTopic} = State,
    Message1 = Message#dxlmessage{type = Type, src_client_id = ClientId, reply_to_topic = ReplyToTopic},
    Encoded = dxl_encoder:encode(Message1),
    dxl_util:log_dxlmessage("Outbound DXL Message", Message1),
    ok = emqttc:publish(C, Topic, Encoded),
    ok.

verify_client_id(State) ->
    BadTopic = list_to_bitstring("/bad/topic/" ++ dxl_util:generate_uuid()),
    Self = self(),
    Callback = fun({_, #dxlmessage{client_ids = [ClientId | _]}, _}) -> gen_server:cast(Self, {verify_client_id, ClientId}) end,
    do_send_request_async(BadTopic, #dxlmessage{}, Callback, 3000, State).

