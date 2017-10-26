%%%----------------------------------------------------------------------------
%%% @author Chris Waymire <chris@waymire.net>
%%% @private
%%%----------------------------------------------------------------------------
-module(dxl_service_man).

-behaviour(gen_server).

%% API
-export([start_link/1,
         register_service/3,
         register_service/4,
         register_service_async/2,
         register_service_async/4,
         deregister_service/4,
         deregister_service_async/2,
         deregister_service_async/4
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
    services = maps:new() :: map(),
    monitors = [] :: list()
}).

%%%============================================================================
%%% API functions
%%%============================================================================

start_link(GID) ->
    Name = dxl_util:module_reg_name(GID, ?MODULE),
    gen_server:start_link({local, Name}, ?MODULE, [self(), GID], []).

register_service(Pid, Sender, #service_registration{} = Registration) ->
    register_service(Pid, Sender, Registration, ?DEF_SVC_REG_TIMEOUT).

register_service(Pid, Sender, #service_registration{} = Registration, Timeout) ->
    gen_server:call(Pid, {register, Sender, Registration, Timeout}, Timeout).

register_service_async(Pid, #service_registration{} = Registration) ->
    register_service_async(Pid, Registration, undefined, ?DEF_SVC_REG_TIMEOUT).

register_service_async(Pid, #service_registration{} = Registration, Callback, Timeout) ->
    gen_server:call(Pid, {register_async, Registration, Callback, Timeout}, Timeout).

deregister_service(Pid, Sender, Id, Timeout) ->
    gen_server:call(Pid, {deregister, Sender, Id, Timeout}, Timeout).

deregister_service_async(Pid, Id) ->
    deregister_service_async(Pid, Id, undefined, ?DEF_SVC_REG_TIMEOUT).

deregister_service_async(Pid, Id, Callback, Timeout) ->
    gen_server:call(Pid, {deregister_async, Id, Callback, Timeout}, Timeout).

%%%============================================================================
%%% gen_server functions
%%%============================================================================
init([Parent, GID]) ->
    Client = dxl_util:module_reg_name(GID, dxlc),
    NotifMan = dxl_util:module_reg_name(GID, dxl_notif_man),
    State = #state{parent = Parent, gid = GID, client = Client, notif_man = NotifMan},
    process_flag(trap_exit, true),
    {ok, State}.

handle_call({register, Sender, Registration, Timeout}, _From, State) ->
    #state{notif_man = NotifMan} = State,
    Id = dxl_util:generate_uuid(),
    Filter = fun({_, ServiceId, _}) -> ServiceId =:= Id end,
    Fun = fun({service_registered, ServiceId, _}) -> gen_server:reply(Sender, {ok, ServiceId});
             ({service_registration_failed, _ServiceId, Error}) -> gen_server:reply(Sender, Error)
          end,
    Opts = [{filter, Filter}, {one_time_only, true}],
    dxl_notif_man:subscribe(NotifMan, service, Fun, Opts),

    State1 = do_register_service(Id, Registration, Timeout, State),
    {reply, ok, State1};

handle_call({register_async, Registration, Callback, Timeout}, _From, State) ->
    #state{notif_man = NotifMan} = State,
    Id = dxl_util:generate_uuid(),
    Filter = fun({_, ServiceId, _}) -> ServiceId =:= Id end,
    Opts = [{filter, Filter}, {one_time_only, true}],
    dxl_notif_man:subscribe(NotifMan, service, Callback, Opts),

    State1 = do_register_service(Id, Registration, Timeout, State),
    {reply, {ok, Id}, State1};

handle_call({deregister, Sender, Id, Timeout}, _From, State) ->
    #state{services = Services, notif_man = NotifMan} = State,
    case maps:get(Id, Services, undefined) of
        undefined ->
            gen_server:reply(Sender, {error, unknown_service}),
            {reply, ok, State};
        {_, Pid, _} ->
            Filter = fun({_, ServiceId, _}) -> ServiceId =:= Id end,
            Fun = fun({service_deregistered, _ServiceId, _}) -> gen_server:reply(Sender, ok);
                     ({service_deregistration_failed, _ServiceId, Error}) -> gen_server:reply(Sender, Error)
                  end,
            Opts = [{filter, Filter}, {one_time_only, true}],
            dxl_notif_man:subscribe(NotifMan, service, Fun, Opts),
            State1 = do_unregister_service(Id, Pid, Timeout, State),
            {reply, ok, State1}
    end;

handle_call({deregister_async, Id, Callback, Timeout}, _From, State) ->
    #state{services = Services, notif_man = NotifMan} = State,
    case maps:get(Id, Services, undefined) of
        undefined ->
            {reply, {error, unknown_service}, State};
        {_, Pid, _} ->
            Filter = fun({_, ServiceId, _}) -> ServiceId =:= Id end,
            Opts = [{filter, Filter}, {one_time_only, true}],
            dxl_notif_man:subscribe(NotifMan, service, Callback, Opts),
            State1 = do_unregister_service(Id, Pid, Timeout, State),
            {reply, ok, State1}
    end.

handle_cast(_, State) ->
    {noreply, State}.

handle_info({'EXIT', Parent, Reason}, #state{parent = Parent} = State) ->
    lager:critical("Received EXIT signal from parent process. Exiting...", []),
    {stop, {parent_exited, Reason}, State};

handle_info({'EXIT', ExitedPid, _Reason}, State) ->
    #state{services = Services, monitors = Monitors} = State,
    State1 = case lists:member(ExitedPid, Monitors) of
        false ->
            lager:info("Received EXIT signal for unknown pid: ~p.", [ExitedPid]),
            State;
        true ->
            case get_service_id_by_pid(ExitedPid, Services) of
                unknown ->
                    lager:info("EXIT signal matches a monitored pid but no service found: ~p.", [ExitedPid]),
                    State;
                Id ->
                    do_unregister_service(Id, ExitedPid, infinity, State)
            end
    end,
    {noreply, State1#state{monitors = lists:delete(ExitedPid, Monitors)}}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%============================================================================
%%% Internal functions
%%%============================================================================

do_register_service(Id, Registration, Timeout, State) ->
    #state{gid = GID, services = Services, monitors = Monitors} = State,
    {ok, Pid} = dxl_service:start_link(GID, Id, Registration, Timeout),

    State#state{services = maps:put(Id, {Id, Pid, Registration}, Services),
                monitors = [Pid | Monitors]}.

do_unregister_service(Id, Pid, Timeout, State) ->
    #state{services = Services} = State,
    case dxl_util:process_is_alive(Pid) of
        true -> dxl_service:stop(Pid, Timeout);
        false -> ok
    end,
    State#state{services = maps:remove(Id, Services)}.

get_service_id_by_pid(TargetPid, Services) ->
    Matches = lists:filter(fun({Pid,_}) -> Pid =:= TargetPid end, lists:flatten(maps:values(Services))),
    case Matches of
        [{Id, TargetPid, _} | _] -> Id;
        _ -> unknown
    end.
