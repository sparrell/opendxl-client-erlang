%%%-------------------------------------------------------------------
%%% @author Chris Waymire <chris@waymire.net>
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(dxlc_service_async_test).

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").
-include("dxl.hrl").
-include("dxlc_test.hrl").

service_async_test() ->
    TestTopic = dxlc_test_util:generate_test_topic(),
    {ok, C} = dxlc_test_util:start_client(),
    Payload = <<"response">>,
    Fun = fun({message_in, {_, Msg, Client}}) -> dxlc:send_response(Client, Msg, Payload) end,
    Topics = #{ TestTopic => Fun },
    Service = #service_registration{type= <<"/test/svc/type">>, topics=Topics},
    CallbackRef = make_ref(),
    Self = self(),
    Callback = fun({service_registered, _Id, _Type}) -> Self ! {ok, CallbackRef};
                  ({service_registration_failed, _Id, _Type, _Reason}) -> exit(registration_failed)
               end,
    {ok, ServiceId} = dxlc:register_service_async(C, Service, Callback, ?DEF_SVC_REG_TIMEOUT),
    dxlc_test_util:block_until(CallbackRef),
    ?debugFmt("Registered Service: ~p", [ServiceId]),
    #dxlmessage{type=response, payload = Payload} = dxlc:send_request(C, TestTopic, <<"test message">>, 1000).


service_deregister_async_test() ->
    TestTopic = dxlc_test_util:generate_test_topic(),
    {ok, C} = dxlc_test_util:start_client(),
    Payload = <<"response">>,
    Fun = fun({message_in, {_, Msg, _}}) -> dxlc:send_response(C, Msg, Payload) end,
    Topics = #{ TestTopic => Fun },
    Service = #service_registration{type= <<"/test/svc/type">>, topics=Topics},
    {ok, ServiceId} = dxlc:register_service(C, Service),
    #dxlmessage{type=response, payload = Payload} = dxlc:send_request(C, TestTopic, <<"test message">>, 1000),

    CallbackRef = make_ref(),
    Self = self(),
    Callback = fun({service_deregistered, _Id, _Type}) -> Self ! {ok, CallbackRef};
                  ({service_deregistration_failed, _Id, _Type, _Reason}) -> exit(deregistration_failed)
               end,

    ok = dxlc:deregister_service_async(C, ServiceId, Callback, ?DEF_SVC_REG_TIMEOUT),
    dxlc_test_util:block_until(CallbackRef),
    #dxlmessage{type=error} = dxlc:send_request(C, TestTopic, <<"test message">>, 1000).

-endif.
