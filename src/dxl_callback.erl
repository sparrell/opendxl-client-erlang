-module(dxl_callback).

-export([execute/2]).

execute({M,F,A}, Data) when is_atom(M) and is_atom(F) ->
    erlang:apply(M, F, [Data | A]);

execute(Callback, Data) when is_function(Callback, 1) ->
    Callback(Data);

execute(Pid, Data) when is_pid(Pid) ->
    Pid ! Data;

execute(undefined, _Data) ->
    ok.
