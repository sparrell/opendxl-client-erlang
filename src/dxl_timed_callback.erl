-module(dxl_timed_callback).

-behaviour(gen_server).

-export([start_link/2]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-include("dxl.hrl").

-record(state, { callback }).

%%%============================================================================
%%% API functions
%%%============================================================================
start_link(Callback, Timeout) ->
    gen_server:start_link(?MODULE, [Callback, Timeout], []).

%%%============================================================================
%%% gen_server callbacks
%%%============================================================================
init([Callback, Timeout]) ->
    {ok, #state{callback=Callback}, Timeout}.

handle_call(_Request, _From, State) ->
    {stop, normal, State}.

handle_cast(_Msg, State) ->
    {stop, normal, State}.

handle_info({notification, Data}, State) ->
    #state{callback=Callback} = State,
    execute_callback(Callback, Data),
    {stop, normal, State};

handle_info(timeout, State) ->
    {stop, normal, State};
  
handle_info(_Info, State) ->
    {stop, normal, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

execute_callback({M,F,A}, Data) ->
    erlang:apply(M, F, [Data | A]);

execute_callback(Callback, Data) when is_function(Callback, 1) ->
    Callback(Data).

