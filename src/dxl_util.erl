-module(dxl_util).

-export([message_type/1,
         process_is_alive/1,
         generate_uuid/0,
         module_reg_name/2,
         parse_ini/1,
         safe_gen_server_call/3,
         log_dxlmessage/2,
         print_dxlmessage/2,
         message_is_a_reply/1,
         message_is_a_reply/2,
         create_topic_filter/1,
         create_topic_filter/2,
         create_request_filter/1,
         create_response_filter/1,
         json_bin_to_term/1,
         term_to_json_bin/1,
         trailing0/1
]).

-include("dxl.hrl").

message_type(0)        -> request;
message_type(1)        -> response;
message_type(2)        -> event;
message_type(3)        -> error;
message_type(request)  -> 0;
message_type(response) -> 1;
message_type(event)    -> 2;
message_type(error)    -> 3;
message_type(_)        -> invalid.

process_is_alive(Pid) ->
    case process_info(Pid) of
        undefined -> false;
        _ -> true
    end.

generate_uuid() ->
    <<A:32, B:16, C:16, D:16, E:48>> = crypto:strong_rand_bytes(16),
    Str = io_lib:format("~8.16.0b-~4.16.0b-4~3.16.0b-~4.16.0b-~12.16.0b", [A, B, C band 16#0fff, D band 16#3fff bor 16#8000, E]),
    list_to_binary(Str).

module_reg_name(UUID, Mod) when is_binary(UUID),
                                is_atom(Mod) ->
    Sep = <<"_">>,
    ModName = atom_to_binary(Mod, utf8),
    binary_to_atom(<<UUID/binary, Sep/binary, ModName/binary>>, utf8).

parse_ini(Filename) ->
    case file:read_file(Filename) of
        {ok, Contents} ->
            eini:parse(Contents);
        {error, Reason} ->
            {error, Reason}
    end.


safe_gen_server_call(Pid, Msg, Timeout) ->
    try
        gen_server:call(Pid, Msg, Timeout)
    catch
        exit:{timeout, _} -> {error, timeout}
    end.

log_dxlmessage(Prefix, Message) ->
    Output = io_lib_pretty:print(Message, fun(dxlmessage, 15) -> record_info(fields, dxlmessage) end),
    lager:debug("~s: ~s", [Prefix, Output]),
    ok.

print_dxlmessage(Prefix, Message) ->
    Output = io_lib_pretty:print(Message, fun(dxlmessage, 15) -> record_info(fields, dxlmessage) end),
    io:format("~s: ~s~n", [Prefix, Output]),
    ok.

message_is_a_reply(#dxlmessage{} = Message) ->
    #dxlmessage{type = Type} = Message,
    case Type of
        error -> true;
        response -> true;
        _ -> false
    end.

message_is_a_reply(#dxlmessage{} = Message, #dxlmessage{} = Request) ->
    #dxlmessage{request_message_id = ReqMessageId} = Message,
    #dxlmessage{message_id = MessageId} = Request,
    case {ReqMessageId, MessageId} of
        {X, X} -> message_is_a_reply(Message);
        _ -> false
    end.

create_topic_filter(Topic) ->
    fun({T, _, _}) -> Topic =:= T end.

create_topic_filter(TypeIn, TopicIn) ->
    fun({Topic, #dxlmessage{type = Type}, _}) when Type =:= TypeIn, Topic =:= TopicIn -> true;
       ({_, _, _}) -> false
    end.

create_request_filter(Topic) ->
    create_topic_filter(request, Topic).

create_response_filter(#dxlmessage{} = Request) ->
    fun({_, #dxlmessage{} = Message, _}) -> dxl_util:message_is_a_reply(Message, Request);
       ({_, _, _}) -> false
    end.


json_bin_to_term(JSON) ->
    jiffy:decode(trailing0(JSON), [return_maps]).

term_to_json_bin(Term) ->
    jiffy:encode(Term).

trailing0(B) when is_binary(B) ->
    S = byte_size(B) - 1,
    case B of
        <<Prefix:S/bytes, 0>> -> trailing0(Prefix);
        _ -> B
    end;

trailing0(B) -> error(badarg, [B]).