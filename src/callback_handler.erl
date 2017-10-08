-module(callback_handler).

-behaviour(gen_server).

-export([start_link/1, start_link/2]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-record(state, {
	id,
        callback
       }).

start_link([Id, Callback]) ->
    start_link([Id, Callback, infinity]).

start_link([Id, Callback, Timeout]) ->
    gen_server:start_link(?MODULE, [Id, Callback, Timeout], []).

init([Id, Callback, Timeout]) ->
    {ok, #state{id=Id, callback=Callback}, Timeout}.

handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast({recv, {_Type, _Topic, _Message}=Payload, DxlClient}, State) ->
    #state{callback=Callback} = State,
    lager:info("Executing do_callback for Callback: ~p", [Callback]),
    do_callback(Payload, DxlClient, Callback),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(timeout, State) ->
    {stop, normal, State};
  
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Internal functions

do_callback(Payload, DxlClient, {M,F,A}) ->
    erlang:apply(M, F, [Payload, DxlClient | A]);

do_callback(Payload, DxlClient, Callback) when is_function(Callback, 2) ->
    lager:info("Calling callback function ~p", [Callback]),
    Callback(Payload, DxlClient).

