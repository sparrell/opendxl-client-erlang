-module(dxl_service_man).

-behaviour(gen_server).

%% API
-export([start_link/1,
	 register_service/3,
	 register_service_async/3,
	 unregister_service/3,
	 update_service/4
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
	client					:: pid(),
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
    dxl_util:safe_gen_server_call(Pid, {register, Service, Timeout}, Timeout).

register_service_async(Pid, #service_registry{}=Service, Timeout) ->
    dxl_util:safe_gen_server_call(Pid, {register_async, Service, Timeout}, Timeout).

unregister_service(Pid, Id, Timeout) ->
    dxl_util:safe_gen_server_call(Pid, {unregister, Id}, Timeout).

update_service(Pid, Id, #service_registry{} = Service, Timeout) ->
    dxl_util:safe_gen_server_call(Pid, {update, Id, Service}, Timeout).

%%%============================================================================
%%% gen_server functions
%%%============================================================================
init([Parent, GID]) ->
    Client = dxl_util:module_reg_name(GID, dxl_client),
    NotifMan = dxl_util:module_reg_name(GID, dxl_notif_man),
    State = #state{parent=Parent, gid=GID, client=Client, notif_man=NotifMan},
    {ok, State}.

handle_call({register, Service, Timeout}, From, State) ->
    #state{notif_man=NotifMan} = State,
    {Id, State1} = do_register_service(Service, State),
    Filter = fun({_, ServiceId, _}) -> ServiceId =:= Id end,
    Fun = fun({_, ServiceId, _}) -> gen_server:reply(From, {ok, ServiceId}) end,
    TimeoutFun = fun(_) ->  dxl_service_man:unregister_service(self(), Id, ?DEF_SVC_REG_TIMEOUT) end,
    Opts = [{filter, Filter}, {timeout, {Timeout, TimeoutFun}}, {one_time_only, true}],
    dxl_notif_man:subscribe(NotifMan, service_registered, Fun, Opts),
    {noreply, State1, Timeout};

handle_call({register_async, Service, Timeout}, _From, State) ->
    #state{notif_man=NotifMan} = State,
    {Id, State1} = do_register_service(Service, State),
    Filter = fun({_, ServiceId, _}) -> ServiceId =:= Id end,
    TimeoutFun = fun(_) ->  dxl_service_man:unregister_service(self(), Id, ?DEF_SVC_REG_TIMEOUT) end,
    Opts = [{filter, Filter}, {timeout, {Timeout, TimeoutFun}}, {one_time_only, true}],
    dxl_notif_man:subscribe(NotifMan, service_registered, undefined, Opts),
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
