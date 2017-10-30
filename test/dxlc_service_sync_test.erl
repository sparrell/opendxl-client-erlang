%%%-------------------------------------------------------------------
%%% @author Chris Waymire <chris@waymire.net>
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(dxlc_service_sync_test).

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").
-include("dxl.hrl").
-include("dxlc_test.hrl").

service_test() ->
    TestTopic = dxlc_test_util:generate_test_topic(),
    {ok, C} = dxlc_test_util:start_client(),
    Payload = <<"response">>,
    Fun = fun({_, Msg, Client}) -> dxlc:send_response(Client, Msg, Payload) end,
    Topics = [{TestTopic, Fun}],
    Service = #service_registration{type = <<"/test/svc/type">>, topics = Topics},
    {ok, ServiceId} = dxlc:register_service(C, Service),
    ?debugFmt("Registered Service: ~p", [ServiceId]),
    #dxlmessage{type = response, payload = Payload} = dxlc:send_request(C, TestTopic, <<"test message">>, 1000),
    dxlc:deregister_service_async(C, ServiceId),
    ok.

service_deregister_test() ->
    TestTopic = dxlc_test_util:generate_test_topic(),
    {ok, C} = dxlc_test_util:start_client(),
    Payload = <<"response">>,
    Fun = fun({_, Msg, _}) -> dxlc:send_response(C, Msg, Payload) end,
    Topics = #{TestTopic => Fun},
    Service = #service_registration{type = <<"/test/svc/type">>, topics = Topics},
    {ok, ServiceId} = dxlc:register_service(C, Service),
    #dxlmessage{type = response, payload = Payload} = dxlc:send_request(C, TestTopic, <<"test message">>, 1000),
    ok = dxlc:deregister_service(C, ServiceId),
    #dxlmessage{type = error} = dxlc:send_request(C, TestTopic, <<"test message">>, 1000),
    ok.

service_deregister_unknown_test() ->
    {ok, C} = dxlc_test_util:start_client(),
    ServiceId = dxl_util:generate_uuid(),
    {error, unknown_service} = dxlc:deregister_service(C, ServiceId),
    ok.

service_request_timeout_test() ->
    TestTopic = dxlc_test_util:generate_test_topic(),
    {ok, C} = dxlc_test_util:start_client(),
    Fun = fun({_, _, _}) -> ok end,
    Topics = #{TestTopic => Fun},
    Service = #service_registration{type = <<"/test/svc/type">>, topics = Topics},
    {ok, ServiceId} = dxlc:register_service(C, Service),
    {error, timeout} = dxlc:send_request(C, TestTopic, <<"test message">>, 1000),
    dxlc:deregister_service_async(C, ServiceId),
    ok.

service_conversation_test() ->
    TestTopic = dxlc_test_util:generate_test_topic(),
    Payload = <<"response">>,
    Fun = fun({_, Msg, Client}) -> dxlc:send_response(Client, Msg, Payload) end,
    Topics = [{TestTopic, Fun}],
    Service = #service_registration{type = <<"/test/svc/type">>, topics = Topics},

    {ok, C1} = dxlc_test_util:start_client(),
    {ok, Service1Id} = dxlc:register_service(C1, Service),
    ?debugFmt("Registered Service 1: ~p", [Service1Id]),

    {ok, C2} = dxlc_test_util:start_client(),
    {ok, Service2Id} = dxlc:register_service(C2, Service),
    ?debugFmt("Registered Service 2: ~p", [Service2Id]),

    {ok, C3} = dxlc_test_util:start_client(),
    Request = #dxlmessage{service_id = Service1Id, payload = <<"test message">>},
    [#dxlmessage{type = response, service_id = Service1Id} = dxlc:send_request(C3, TestTopic, Request, 1000) || _ <- lists:seq(1, 10)],

    dxlc:deregister_service_async(C1, Service1Id),
    dxlc:deregister_service_async(C2, Service2Id),
    ok.

-endif.