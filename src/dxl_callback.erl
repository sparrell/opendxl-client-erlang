-module(dxl_callback).

-behaviour(gen_server).

-export([start_link/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-include("dxl.hrl").

-record(state, {
	info
       }).

%%%============================================================================
%%% API functions
%%%============================================================================
-spec start_link(Info :: callback_info()) -> {ok, {Id :: reference(), Pid :: pid()}} | {Error :: atom(), Reason :: atom()}.
start_link(Info) ->
    Id = make_ref(),
    Result = gen_server:start_link(?MODULE, [Info#callback_info{id=Id}], []),
    case Result of
        {ok, Pid} -> {ok, {Id, Pid}};
	        _ -> Result
    end.

%%%============================================================================
%%% gen_server callbacks
%%%============================================================================
init([Info]) ->
    {ok, #state{info=Info}}.

handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast({recv, Topic, Message, DxlClient}, State) ->
    #state{info=Info} = State,
    #callback_info{callback=Callback, filter=Filter, single_use=SingleUse} = Info,
    MatchesFilter = meets_filter_criteria(Filter, Topic, Message),
    case MatchesFilter of
        false -> {noreply, State};
	true ->
	    execute_callback(Callback, Topic, Message, DxlClient),
	    case SingleUse of
	        false -> {noreply, State};
	 	true -> {stop, normal, State}
	    end
    end;

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
meets_filter_criteria({M,F,A}, Topic, Message) ->
    M:F([Topic, Message | A]);

meets_filter_criteria(Func, Topic, Message) when is_function(Func, 1) ->
    Func(Topic, Message);

meets_filter_criteria(_Func, _Topic, _Message) ->
    true.

execute_callback({M,F,A}, Topic, Message, DxlClient) ->
    lager:info("Executing callback: ~p:~p.", [M,F]),
    erlang:apply(M, F, [Topic, Message, DxlClient | A]);

execute_callback(Callback, Topic, Message, DxlClient) when is_function(Callback, 3) ->
    lager:info("Calling callback function ~p", [Callback]),
    Callback(Topic, Message, DxlClient);

execute_callback(Pid, Topic, Message, DxlClient) when is_pid(Pid) ->
    Pid ! {dxl_message, Topic, Message, DxlClient}.
 
