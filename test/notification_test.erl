-module(notification_test).

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").
-include("dxl.hrl").
-include("dxlc_test.hrl").

-export([process_message/2]).

mfa_callback_test() ->
    {ok, C} = dxlc_test_util:start_client(),
    Self = self(),
    {ok, NotifId} = dxlc:subscribe_notification(C, message_in, {?MODULE, process_message, [Self]}, []),

    TestTopic = dxlc_test_util:generate_test_topic(),
    dxlc:subscribe(C, TestTopic),
    dxlc:send_event(C, TestTopic, <<"test">>),

    receive
        ok -> ok
    end,
    ok.

process_message({Topic, _Message, _Client}, MyPid) ->
    ?debugFmt("Got Message: Topic=~p, MyPid=~p.", [Topic, MyPid]),
    MyPid ! ok.

-endif.