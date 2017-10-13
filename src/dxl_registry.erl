-module(dxl_registry).

-behaviour(gen_server).

%% API
-export([start_link/0,
	 register_process/1,
	 register_process/2,
	 unregister_process/1,
	 lookup_process/1
	]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-record(state, {
	mappings = maps:new()			:: map()
      }).

%%%============================================================================
%%% API functions
%%%============================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

register_process(Key) ->
    register_process(Key, self()).

register_process(Key, Pid) ->
    gen_server:call(?MODULE, {register, {Key, Pid}}).

unregister_process(Key) ->
    gen_server:call(?MODULE, {unregister, Key}).

lookup_process(Key) ->
    gen_server:call(?MODULE, {lookup, Key}).
%%%============================================================================
%%% gen_server functions
%%%============================================================================
init([]) ->
    {ok, #state{}}.

handle_call({register, {Key, Pid}}, _From, State) ->
    #state{mappings=Mappings} = State,
    case maps:is_key(Key, Mappings) of
        false ->
            Ref = erlang:monitor(process, Pid),
            {reply, ok, State#state{mappings=maps:put(Key, {Key, Ref, Pid}, Mappings)}}; 
	true ->
	    {reply, {err, already_registered}, State}
    end;

handle_call({unregister, Key}, _From, State) ->
    #state{mappings=Mappings} = State,
    case maps:is_key(Key, Mappings) of
        true ->
	    {_Key, Ref, _Pid} = maps:get(Key, Mappings),
	    erlang:demonitor(Ref),
            {reply, ok, State#state{mappings=maps:remove(Key, Mappings)}};
	false ->
	    {reply, {err, not_registered}, State}
    end;

handle_call({lookup, Key}, _From, State) ->
    #state{mappings=Mappings} = State,
    case maps:get(Key, Mappings) of
        {badkey,_}  -> {reply, {badkey, Key}, State};
	{_, _, Pid} -> {reply, {ok, Pid}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'DOWN', Reference, process, _Pid, _Reason}, State) ->
    #state{mappings=Mappings} = State,
    [{Key, _, _} | _] = lists:filter(fun({_, Ref, _}) -> Reference =:= Ref end, maps:to_list(Mappings)),
    {noreply, State#state{mappings=maps:remove(Key, Mappings)}};
 
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%============================================================================
%%% Internal functions
%%%============================================================================
