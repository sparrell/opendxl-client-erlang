-module(dxlc_test).

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").
-include("dxl.hrl").

-define(TEST_TOPIC, <<"/test/topic">>).
-define(DEF_TIMEOUT, 1000).

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
    Payload = <<"response">>,
    Fun = fun({message_in, {_, Msg, Client}}) -> dxlc:send_response(Client, Msg, Payload) end,
    Topics = #{ TestTopic => Fun },
    Service = #service_registry{service_type= <<"/test/svc/type">>, topics=Topics},
    {ok, ServiceId} = dxlc:register_service(C, Service),
    ?debugFmt("Registered Service: ~p", [ServiceId]),
     #dxlmessage{type=response, payload = Payload} = dxlc:send_request(C, TestTopic, <<"test message">>, 1000).

service_async_test() ->
    TestTopic = generate_test_topic(),
    {ok, C} = start_client(),
    Payload = <<"response">>,
    Fun = fun({message_in, {_, Msg, Client}}) -> dxlc:send_response(Client, Msg, Payload) end,
    Topics = #{ TestTopic => Fun },
    Service = #service_registry{service_type= <<"/test/svc/type">>, topics=Topics},
    CallbackRef = make_ref(),
    Self = self(),
    Callback = fun({service_registered, _Id, _Type}) -> Self ! {ok, CallbackRef};
                  ({service_registration_failed, _Id, _Type, _Reason}) -> exit(registration_failed)
                end,
    {ok, ServiceId} = dxlc:register_service_async(C, Service, Callback, ?DEF_SVC_REG_TIMEOUT),
    block_until(CallbackRef),
    ?debugFmt("Registered Service: ~p", [ServiceId]),
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
    ok = dxlc:unregister_service(C, ServiceId),
    #dxlmessage{type=error} = dxlc:send_request(C, TestTopic, <<"test message">>, 100). 

service_unregister_unknown_test() ->
    {ok, C} = start_client(),
    ServiceId = dxl_util:generate_uuid(),
    {error, unknown_service} = dxlc:unregister_service(C, ServiceId).

service_unregister_async_test() ->
    TestTopic = generate_test_topic(),
    {ok, C} = start_client(),
    Payload = <<"response">>,
    Fun = fun({message_in, {_, Msg, _}}) -> dxlc:send_response(C, Msg, Payload) end,
    Topics = #{ TestTopic => Fun },
    Service = #service_registry{service_type= <<"/test/svc/type">>, topics=Topics},
    {ok, ServiceId} = dxlc:register_service(C, Service),
    #dxlmessage{type=response, payload = Payload} = dxlc:send_request(C, TestTopic, <<"test message">>, 1000),

    CallbackRef = make_ref(),
    Self = self(),
    Callback = fun({service_unregistered, _Id, _Type}) -> Self ! {ok, CallbackRef};
                  ({service_unregistration_failed, _Id, _Type, _Reason}) -> exit(unregistration_failed)
               end,

    ok = dxlc:unregister_service_async(C, ServiceId, Callback, ?DEF_SVC_REG_TIMEOUT),
    block_until(CallbackRef),
    #dxlmessage{type=error} = dxlc:send_request(C, TestTopic, <<"test message">>, 100).

service_request_timeout_test() ->
    TestTopic = generate_test_topic(),
    {ok, C} = start_client(),
    Fun = fun({message_in, {_, _, _}}) -> ok end,
    Topics = #{ TestTopic => Fun },
    Service = #service_registry{service_type= <<"/test/svc/type">>, topics=Topics},
    {ok, _ServiceId} = dxlc:register_service(C, Service),
    {error, timeout} = dxlc:send_request(C, TestTopic, <<"test message">>, 1000).

load_config() ->
    Dir = filename:dirname(filename:absname(".")),
    File = filename:join([Dir, "test", "dxlclient.config"]),
    {ok, _Config} = dxl_client_conf:read_from_file(File).

start_client() ->
    {ok, Config} = load_config(),
    start_client(Config).

start_client(Config) ->
    {ok, _Pid} = dxlc:start(Config).

generate_test_topic() ->
    GUID = dxl_util:generate_uuid(),
    <<"/test/topic/", GUID/binary>>.

block_until(Input) ->
    block_until(Input, ?DEF_TIMEOUT).

block_until(Ref, Timeout) ->
    receive
        {ok, Ref} -> ok
    after
        Timeout -> exit(timeout)
    end.

-endif.
