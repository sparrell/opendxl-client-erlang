-module(notification_test).

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").
-include("dxl.hrl").
-include("dxlc_test.hrl").

-export([mfa_callback_test_process_message/2,
         callback_timeout_callback/2
]).

mfa_callback_test() ->
    {ok, C} = dxlc_test_util:start_client(),
    Self = self(),
    dxlc:subscribe_notification(C, message_in, {?MODULE, mfa_callback_test_process_message, [Self]}, []),
    TestTopic = dxlc_test_util:generate_test_topic(),
    dxlc:subscribe(C, TestTopic),
    dxlc:send_event(C, TestTopic, <<"test">>),
    block_until_message(),
    ok.

single_use_filter_test() ->
    {ok, C} = dxlc_test_util:start_client(),
    dxlc:subscribe_notification(C, message_in, self(), [{single_use, true}]),
    TestTopic = dxlc_test_util:generate_test_topic(),
    dxlc:subscribe(C, TestTopic),
    dxlc:send_event(C, TestTopic, <<"test">>),
    block_until_message(),
    dxlc:send_event(C, TestTopic, <<"test">>),
    Result = receive
                 _ -> not_ok
             after
                 3000 -> ok
             end,
    ?assertEqual(ok, Result),
    ok.

callback_timeout_test() ->
    {ok, C} = dxlc_test_util:start_client(),
    TestTopic = dxlc_test_util:generate_test_topic(),
    dxlc:subscribe(C, TestTopic),
    dxlc:subscribe_notification(C, message_in, self(), [{single_use, true}, {timeout, 1000}]),
    timer:sleep(1500),
    Result = receive
                 _ -> not_ok
             after
                 2000 -> ok
             end,
    ?assertEqual(ok, Result),

    dxlc:subscribe_notification(C, message_in, self(), [{single_use, true}, {timeout, 1000}]),
    timer:sleep(500),
    dxlc:send_event(C, TestTopic, <<"test">>),
    block_until_message(),
    ok.

callback_timeout_callback_test() ->
    {ok, C} = dxlc_test_util:start_client(),
    TestTopic = dxlc_test_util:generate_test_topic(),
    dxlc:subscribe(C, TestTopic),
    Self = self(),
    dxlc:subscribe_notification(C, message_in, self(), [{single_use, true}, {timeout, {1000, {?MODULE, callback_timeout_callback, [Self]}}}]),
    timer:sleep(1500),
    Result = receive
                 got_timeout -> ok
             after
                 1000 -> not_ok
             end,
    ?assertEqual(ok, Result),
    ok.

mfa_callback_test_process_message({Topic, _Message, _Client}, MyPid) ->
    ?debugFmt("Got Message: Topic=~p, MyPid=~p.", [Topic, MyPid]),
    MyPid ! ok.

callback_timeout_callback(_Data, Pid) ->
    Pid ! got_timeout,
    ok.

block_until_message() ->
    receive
        _ -> ok
    end.

-endif.