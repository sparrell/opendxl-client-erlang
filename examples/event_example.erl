-module(event_example).

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
    F = fun({_Topic,Message,_}) -> dxl_util:log_dxlmessage("Received Event", Message) end,
    dxlc:subscribe(Client, ?EVENT_TOPIC, F),
    lager:info("Publishing event.", []),
    dxlc:send_event(Client, ?EVENT_TOPIC, <<"Test Message.">>),
    timer:sleep(1000),
    ok. 
