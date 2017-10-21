-module(message_filter_example).

-export([start/0]).

-include("dxl.hrl").

-define(CONFIG_FILE, "/tmp/dxlclient.config").
-define(EVENT_TOPIC, <<"/isecg/sample/event">>).

start() ->
    lager:info("Reading configuration from file: ~s.", [?CONFIG_FILE]),
    {ok, Config} = dxl_client_conf:read_from_file(?CONFIG_FILE),
    lager:info("Connecting to broker...", []),
    {ok, Client} = dxlc:start([Config]),
    lager:info("Connected.", []),
    lager:info("Subscribing to event: ~s.", [?EVENT_TOPIC]),
    dxlc:subscribe(Client, ?EVENT_TOPIC),
    lager:info("Registering notification.", []),
    Filter = fun({?EVENT_TOPIC, #dxlmessage{payload = <<"Test:",_Rest/bitstring>> } = Message, _}) -> true;
	        (_) -> false
	     end,
    Func = fun({_Topic, Message, _DxlClient}) -> dxl_util:log_dxlmessage("Got Message", Message) end,
    {ok, NotificationId} = dxlc:subscribe_notification(Client, message_in, Func, [{filter, Filter}]),

    lager:info("Publishing event1.", []),
    dxlc:send_event(Client, ?EVENT_TOPIC, <<"This should not be caught.">>),
    timer:sleep(1000),
    lager:info("Publishing event2.", []),
    dxlc:send_event(Client, ?EVENT_TOPIC, <<"Test: Message.">>),
    timer:sleep(1000),
    lager:info("De-registering notification.", []),
    dxlc:unsubscribe_notification(Client, NotificationId),
    lager:info("Unsubscribing from event.", []),
    dxlc:unsubscribe(Client, ?EVENT_TOPIC),
    ok. 
