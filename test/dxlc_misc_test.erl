-module(dxlc_misc_test).

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").
-include("dxl.hrl").
-include("dxlc_test.hrl").

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
    TestTopic = dxlc_test_util:generate_test_topic(),
    {ok, C} = dxlc_test_util:start_client(),
    {ok, _CallbackId} = dxlc:subscribe(C, TestTopic, self()),
    ok = dxlc:send_event(C, TestTopic, <<"test event">> ),
    receive
        _ -> ok
    after
        3000 -> exit(timeout)
    end.

-endif.
