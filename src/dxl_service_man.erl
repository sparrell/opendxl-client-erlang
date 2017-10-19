-module(dxl_service_man).

-behaviour(gen_server).

%% API
-export([start_link/1,
	 register_service/3,
	 register_service_async/2,
	 unregister_service/2,
	 update_service/3
	]).

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
	dxl_client				:: pid(),
	notif_man				:: pid(),
	services = maps:new()			:: map()
      }).

%%%============================================================================
%%% API functions
%%%============================================================================

start_link(GID) ->
    Name = dxl_util:module_reg_name(GID, ?MODULE),
    gen_server:start_link({local, Name}, ?MODULE, [self(), GID], []).

register_service(Pid, #service_registry{}=Service, Timeout) ->
    gen_server:call(Pid, {register, Service, Timeout}, ?ADJUSTED_TIMEOUT(Timeout)).

register_service_async(Pid, #service_registry{}=Service) ->
    gen_server:call(Pid, {register_async, Service}).

unregister_service(Pid, Id) ->
    gen_server:call(Pid, {unregister, Id}).

update_service(Pid, Id, #service_registry{} = Service) ->
    gen_server:call(Pid, {update, Id, Service}).

%%%============================================================================
%%% gen_server functions
%%%============================================================================
init([Parent, GID]) ->
    DxlClient = dxl_util:module_reg_name(GID, dxl_client),
    NotifMan = dxl_util:module_reg_name(GID, dxl_notif_man),
    State = #state{parent=Parent, gid=GID, dxl_client=DxlClient, notif_man=NotifMan},
    {ok, State}.

handle_call({register, Service, Timeout}, From, State) ->
    #state{notif_man=NotifMan} = State,
    {Id, State1} = do_register_service(Service, State),
    Filter = fun({_, ServiceId, _}) -> ServiceId =:= Id end,
    Fun = fun({_, ServiceId, _}) -> gen_server:reply(From, {ok, ServiceId}) end,
    Opts = [{filter, Filter}, {timeout, Timeout}, {one_time_only, true}],
    dxl_notif_man:subscribe(NotifMan, service_registered, Fun, Opts),
    {noreply, State1, Timeout};

handle_call({register_async, Service}, _From, State) ->
    {Id, State1} = do_register_service(Service, State),
    {reply, {ok, Id} , State1};

handle_call({unregister, Id}, _From, State) ->
    {Response, State1} = do_unregister_service(Id, State),
    {reply, Response, State1};

handle_call({update, Id, Service}, _From, State) ->
    {ok, State1} = do_update_service(Id, Service, State),
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

do_register_service(Service, State) ->
    #state{gid=GID, services=Services} = State,
    {ok, {Id, Pid}} = dxl_service:start_link(GID, Service),
    {Id, State#state{services=maps:put(Id, {Pid, Service}, Services)}}.

do_unregister_service(Id, State) ->
    #state{services=Services} = State,
    case maps:get(Id, Services) of
        {badkey,_} -> 
	    {{err, unknown}, State};
	{Pid,_} -> 
	    gen_server:cast(Pid, shutdown),
	    {ok, State#state{services=maps:remove(Id, Services)}}
    end.

do_update_service(Id, Service, State) ->
    #state{services=Services} = State,
    case maps:get(Id, Services) of
        {badkey, _} -> {err, unknown};
        Pid ->
            ok = gen_server:call(Pid, {update, Service}),
	    ok
    end.
