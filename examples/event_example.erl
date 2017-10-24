-module(event_example).

-export([start/0]).

-include("dxl.hrl").

-define(EVENT_TOPIC, <<"/isecg/sample/event">>).

start() ->
    Config = load_config(),
    lager:info("Connecting to broker...", []),
    {ok, Client} = dxlc:start(Config),
    lager:info("Connected.", []),
    lager:info("Subscribing to event: ~s.", [?EVENT_TOPIC]),
    F = fun({message_in, {_Topic,Message,_}}) -> dxl_util:log_dxlmessage("Received Event", Message) end,
    dxlc:subscribe(Client, ?EVENT_TOPIC, F),
    lager:info("Publishing event.", []),
    dxlc:send_event(Client, ?EVENT_TOPIC, <<"Test Message.">>),
    timer:sleep(1000),
    ok.

load_config() ->
    Dir = filename:dirname(filename:absname(".")),
    File = filename:join([Dir, "examples", "dxlclient.config"]),
    lager:info("Reading configuration from file: ~s.", [File]),
    {ok, Config} = dxl_client_conf:read_from_file(File),
    Config.