-module(dxl_service_man).

-behaviour(gen_server).

%% API
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
	parent					:: pid(),
	gid					:: binary(),
	services = maps:new()			:: map()
      }).

%%%============================================================================
%%% API functions
%%%============================================================================

start_link(GID) ->
    gen_server:start_link(?MODULE, [self(), GID], []).

%%%============================================================================
%%% gen_server functions
%%%============================================================================
init([Parent, GID]) ->
    dxl_registry:register_process({GID, ?MODULE}),
    State = #state{parent=Parent},
    {ok, State}.

handle_call({regiser, Info}, _From, State) ->
    {Id, State1} = register_service(Info, State),
    {reply, {ok, Id} , State1};

handle_call({unregister, Id}, _From, State) ->
    {ok, State1} = unregister_service(Id, State),
    {reply, ok, State1};

handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%============================================================================
%%% Internal functions
%%%============================================================================

register_service(Info, State) ->
    #state{services=Services} = State,
    lager:debug("Adding service: ~p", [Info]),
    {ok, {Id, Pid}} = dxl_service:start_link(Info),
    {Id, State#state{services=maps:put(Id, {Pid, Info})}}.

unregister_service(Id, State) ->
    #state{services=Services} = State,
    case maps:get(Id, Services) of
        {badkey,_} -> 
	    {err, unknown};
	Pid -> 
	    gen_server:cast(Pid, shutdown),
	    ok
    end.

