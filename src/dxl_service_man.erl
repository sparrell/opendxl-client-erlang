-module(dxl_service_man).

-behaviour(gen_server).

%% API
-export([start_link/1,
         register_service/3,
         register_service/4,
         register_service_async/2,
         register_service_async/4,
         unregister_service/4,
         unregister_service_async/2,
         unregister_service_async/4,
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
    parent :: pid(),
    gid :: binary(),
    client :: pid(),
    notif_man :: pid(),
    services = maps:new() :: map()
}).

%%%============================================================================
%%% API functions
%%%============================================================================

start_link(GID) ->
    Name = dxl_util:module_reg_name(GID, ?MODULE),
    gen_server:start_link({local, Name}, ?MODULE, [self(), GID], []).

register_service(Pid, Sender, #service_registry{} = Service) ->
    register_service(Pid, Sender, Service, ?DEF_SVC_REG_TIMEOUT).

register_service(Pid, Sender, #service_registry{} = Service, Timeout) ->
    gen_server:call(Pid, {register, Sender, Service, Timeout}, Timeout).

register_service_async(Pid, #service_registry{} = Service) ->
    register_service_async(Pid, Service, undefined, ?DEF_SVC_REG_TIMEOUT).

register_service_async(Pid, #service_registry{} = Service, Callback, Timeout) ->
    gen_server:call(Pid, {register_async, Service, Callback, Timeout}, Timeout).

unregister_service(Pid, Sender, Id, Timeout) ->
    gen_server:call(Pid, {unregister, Sender, Id, Timeout}, Timeout).

unregister_service_async(Pid, Id) ->
    unregister_service_async(Pid, Id, undefined, ?DEF_SVC_REG_TIMEOUT).

unregister_service_async(Pid, Id, Callback, Timeout) ->
    gen_server:call(Pid, {unregister_async, Id, Callback, Timeout}, Timeout).

update_service(Pid, Id, #service_registry{} = Service, Timeout) ->
    gen_server:call(Pid, {update, Id, Service}, Timeout).

%%%============================================================================
%%% gen_server functions
%%%============================================================================
init([Parent, GID]) ->
    Client = dxl_util:module_reg_name(GID, dxlc),
    NotifMan = dxl_util:module_reg_name(GID, dxl_notif_man),
    State = #state{parent = Parent, gid = GID, client = Client, notif_man = NotifMan},
    {ok, State}.

handle_call({register, Sender, Service, Timeout}, _From, State) ->
    #state{notif_man = NotifMan} = State,
    Id = dxl_util:generate_uuid(),
    Filter = fun({_, ServiceId, _}) -> ServiceId =:= Id end,
    Fun = fun({service_registered, ServiceId, _}) -> gen_server:reply(Sender, {ok, ServiceId});
             ({service_registration_failed, _ServiceId, Error}) -> gen_server:reply(Sender, Error)
          end,
    Opts = [{filter, Filter}, {one_time_only, true}],
    dxl_notif_man:subscribe(NotifMan, service_registered, Fun, Opts),
    dxl_notif_man:subscribe(NotifMan, service_registration_failed, Fun, Opts),

    State1 = do_register_service(Id, Service, Timeout, State),
    {reply, ok, State1};

handle_call({register_async, Service, Callback, Timeout}, _From, State) ->
    #state{notif_man = NotifMan} = State,
    Id = dxl_util:generate_uuid(),
    Filter = fun({_, ServiceId, _}) -> ServiceId =:= Id end,
    Opts = [{filter, Filter}, {one_time_only, true}],
    dxl_notif_man:subscribe(NotifMan, service_registered, Callback, Opts),
    dxl_notif_man:subscribe(NotifMan, service_registration_failed, Callback, Opts),

    State1 = do_register_service(Id, Service, Timeout, State),
    {reply, {ok, Id}, State1};

handle_call({unregister, Sender, Id, Timeout}, _From, State) ->
    #state{services = Services, notif_man = NotifMan} = State,
    case maps:get(Id, Services, undefined) of
        undefined ->
            gen_server:reply(Sender, {error, unknown_service}),
            {reply, ok, State};
        {Pid, _} ->
            Filter = fun({_, ServiceId, _}) -> ServiceId =:= Id end,
            Fun = fun({service_unregistered, _ServiceId, _}) -> gen_server:reply(Sender, ok);
                     ({service_unregistration_failed, _ServiceId, Error}) -> gen_server:reply(Sender, Error)
                  end,
            Opts = [{filter, Filter}, {one_time_only, true}],
            dxl_notif_man:subscribe(NotifMan, service_unregistered, Fun, Opts),
            dxl_notif_man:subscribe(NotifMan, service_unregistration_failed, Fun, Opts),
            State1 = do_unregister_service(Id, Pid, Timeout, State),
            {reply, ok, State1}
    end;

handle_call({unregister_async, Id, Callback, Timeout}, _From, State) ->
    #state{services = Services, notif_man = NotifMan} = State,
    case maps:get(Id, Services, undefined) of
        undefined ->
            {{error, unknown_service}, State};
        {Pid, _} ->
            Filter = fun({_, ServiceId, _}) -> ServiceId =:= Id end,
            Opts = [{filter, Filter}, {one_time_only, true}],
            dxl_notif_man:subscribe(NotifMan, service_unregistered, Callback, Opts),
            dxl_notif_man:subscribe(NotifMan, service_unregistration_failed, Callback, Opts),
            State1 = do_unregister_service(Id, Pid, Timeout, State),
            {reply, ok, State1}
    end;

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

do_register_service(Id, Service, Timeout, State) ->
    #state{gid = GID, services = Services} = State,
    {ok, Pid} = dxl_service:start_link(GID, Id, Service, Timeout),
    State#state{services = maps:put(Id, {Pid, Service}, Services)}.

do_unregister_service(Id, Pid, Timeout, State) ->
    #state{services = Services} = State,
    dxl_service:stop(Pid, Timeout),
    State#state{services = maps:remove(Id, Services)}.

do_update_service(Id, Service, State) ->
    #state{services = Services} = State,
    case maps:get(Id, Services, undefined) of
        undefined -> {err, unknown};
        {Pid, _} ->
            ok = dxl_service:update(Pid, Service),
            ok
    end.
