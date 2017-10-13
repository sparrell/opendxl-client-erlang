-module(response_handler).

-export([handle_response/4]).

-include("dxl.hrl").


handle_response(_Topic, #dxlmessage{request_message_id=MessageId}=Message, _DxlClient, [Sender, MessageId]) ->
    gen_server:reply(Sender, Message),
    ok;

handle_response(_, _, _, _) ->
    ok.
