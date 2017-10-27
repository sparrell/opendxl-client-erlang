-module(dxlc_test_util).

%% API
-export([load_config/0,
         start_client/0,
         start_client/1,
         generate_test_topic/0,
         block_until/1,
         block_until/2]).

-include("dxlc_test.hrl").

load_config() ->
    Dir = filename:dirname(filename:absname(".")),
    File = filename:join([Dir, "test", "dxlclient.config"]),
    {ok, Config} = dxl_client_conf:read_from_file(File),
    Config.

start_client() ->
    Config = load_config(),
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