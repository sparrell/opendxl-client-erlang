%%% @author Chris Waymire <chris@waymire.net>
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(dxlc_broker_test).

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").
-include("dxl.hrl").
-include("dxlc_test.hrl").

active_service_count_test() ->
    TestTopic = dxlc_test_util:generate_test_topic(),
    TestType = dxlc_test_util:generate_test_topic(),

    {ok, C} = dxlc_test_util:start_client(),
    Payload = <<"response">>,
    Fun = fun({_, Msg, Client}) -> dxlc:send_response(Client, Msg, Payload) end,
    Topics = [{TestTopic, Fun}],
    Service = #service_registration{type = TestType, topics = Topics},
    {ok, ServiceId} = dxlc:register_service(C, Service),
    ?debugFmt("Registered Service: ~p", [ServiceId]),

    Services = dxlc:get_all_active_services(C, TestType),
    ?assertEqual(1, maps:size(Services)),

    dxlc:deregister_service(C, ServiceId),

    Services2 = dxlc:get_all_active_services(C, TestType),
    ?assertEqual(0, maps:size(Services2)),
    ok.

-endif.