-module(dxlc_test).

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").
-include("dxl.hrl").

-define(TEST_TOPIC, <<"/test/topic">>).

message_type_test() ->
    ?assertEqual(request, dxl_util:message_type(0)),
    ?assertEqual(response, dxl_util:message_type(1)),
    ?assertEqual(event, dxl_util:message_type(2)),
    ?assertEqual(error, dxl_util:message_type(3)),
    ?assertEqual(0, dxl_util:message_type(request)),
    ?assertEqual(1, dxl_util:message_type(response)),
    ?assertEqual(2, dxl_util:message_type(event)),
    ?assertEqual(3, dxl_util:message_type(error)).

event_test() ->
    {ok, C} = start_client(),
    {ok, _CallbackId} = dxlc:subscribe(C, <<"/test/topic">>, self()),
    {ok, _MessageId} = dxlc:send_event(C, <<"/test/topic">>, <<"test event">> ),
    receive
        {message_in, _} -> ok
    after
        1000 -> exit(timeout)
    end.

service_test() ->
    TestTopic = generate_test_topic(),
    {ok, C} = start_client(),
    Fun = fun({message_in, {_, Msg, _}}) -> dxlc:send_response(C, Msg, <<"response">>) end,
    Topics = #{ TestTopic => Fun },
    Service = #service_registry{service_type= <<"/test/svc/type">>, topics=Topics},
    {ok, _ServiceId} = dxlc:register_service(C, Service),
     #dxlmessage{type=response, payload = Payload} = dxlc:send_request(C, TestTopic, <<"test message">>, 1000).

service_unregister_test() ->
    TestTopic = generate_test_topic(),
    {ok, C} = start_client(),
    Payload = <<"response">>,
    Fun = fun({message_in, {_, Msg, _}}) -> dxlc:send_response(C, Msg, Payload) end,
    Topics = #{ TestTopic => Fun },
    Service = #service_registry{service_type= <<"/test/svc/type">>, topics=Topics},
    {ok, ServiceId} = dxlc:register_service(C, Service),
    #dxlmessage{type=response, payload = Payload} = dxlc:send_request(C, TestTopic, <<"test message">>, 1000),
    dxlc:unregister_service(C, ServiceId),
    #dxlmessage{type=error} = dxlc:send_request(C, TestTopic, <<"test message">>, 100). 

service_request_timeout_test() ->
    TestTopic = generate_test_topic(),
    {ok, C} = start_client(),
    Payload = <<"response">>,
    Fun = fun({message_in, {_, Msg, _}}) -> ok end,
    Topics = #{ TestTopic => Fun },
    Service = #service_registry{service_type= <<"/test/svc/type">>, topics=Topics},
    {ok, ServiceId} = dxlc:register_service(C, Service),
    {error, timeout} = dxlc:send_request(C, TestTopic, <<"test message">>, 1000).

load_config() ->
    Dir = filename:dirname(filename:absname(".")),
    File = filename:join([Dir, "test", "dxlclient.config"]),
    {ok, _Config} = dxl_client_conf:read_from_file(File).

start_client() ->
    {ok, Config} = load_config(),
    start_client(Config).

start_client(Config) ->
    {ok, _Pid} = dxlc:start([Config]).

generate_test_topic() ->
    GUID = dxl_util:generate_uuid(),
    <<"/test/topic/", GUID/binary>>.
-endif.
