-module(dxl_callback_man).

-behaviour(gen_server).

-export([start_link/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3
        ]).

-include("dxl.hrl").

-record(state, {
	parent					:: pid,
        handlers = maps:new()			:: map()
      }).

%%%============================================================================
%%% API functions
%%%============================================================================
start_link(GID) ->
    Name = dlx_util:unique_registration_name(?MODULE, GID),
    gen_server:start_link({local, Name}, ?MODULE, [self()], []).

%%%============================================================================
%%% gen_server functions
%%%============================================================================
init([Parent]) ->
    process_flag(trap_exit, true),
    {ok, #state{parent=Parent}}.

handle_call({add_callback, Info}, _From, State) ->
    {HandlerId, State1} = add_handler(Info, State),
    {reply, {ok, HandlerId}, State1};

handle_call({remove_callback, IdOrPid}, _From, State) ->
    State1 = remove_handler(IdOrPid, State),
    {reply, ok, State1};

handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast({notify, Topic, Message, DxlClient}, State) ->
    notify(Topic, Message, DxlClient, State),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'EXIT', Parent, Reason}, #state{parent=Parent}=State) ->
    {stop, {parent_exited, Reason}, State};

handle_info({'EXIT', ExitedPid, Reason}, State) ->
    lager:error("Callback handler [~p] exited: ~p", [ExitedPid, Reason]),
    State1 = remove_handler(ExitedPid, State),
    {noreply, State1};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%============================================================================
%%% Internal functions
%%%============================================================================
create_lookup_key(Type, Topic) when is_atom(Topic) ->
    create_lookup_key(Type, atom_to_binary(Topic, utf8));

create_lookup_key(Type, Topic) when is_binary(Topic)->
    TypeBin = atom_to_binary(Type, utf8),
    Sep = <<":">>,
    <<TypeBin/binary, Sep/binary, Topic/binary>>.

add_handler(Info, State) ->
    #state{handlers=Handlers} = State,
    #callback_info{type=Type, topic=Topic, callback=Callback} = Info,
    lager:debug("Adding message callback [~p] for type [~p] and topic [~p].", [Callback, Type, Topic]),
    {ok, {Id, Pid}} = dxl_callback:start_link(Info),
    Key = create_lookup_key(Type, Topic),
    lager:debug("Handler ID = ~p, Pid = ~p, Key=~p", [Id, Pid, Key]),
    List = maps:get(Key, Handlers, []),
    NewList = [{Id, Pid, Key} | List],
    NewHandlers = maps:put(Key, NewList, Handlers),
    State1 = State#state{handlers=NewHandlers},
    {Id, State1}.

remove_handler(Pid, State) when is_pid(Pid) ->
    #state{handlers=Handlers} = State,
    Matches = lists:filter(fun({_Id,Pid2,_Key}) -> Pid == Pid2 end, lists:flatten(maps:values(Handlers))),
    remove_handlers(Matches, State);

remove_handler(Id, State) when is_reference(Id) ->
    #state{handlers=Handlers} = State,
    Matches = lists:filter(fun({Id2,_Pid,_Key}) -> Id == Id2 end, lists:flatten(maps:values(Handlers))),
    remove_handlers(Matches, State).

remove_handlers([], State) ->
    State;

remove_handlers([{Id, Pid, Key} | Rest], State) ->
    #state{handlers=Handlers} = State,
    lager:debug("Removing message callback ~p.", [Id]),
    List = maps:get(Key, Handlers, []),
    F1 = fun({Id2, _Pid2, _Key2}) -> Id =/= Id2 end,
    NewList = lists:filter(F1, List),
    NewHandlers = maps:put(Key, NewList, Handlers),
    gen_server:cast(Pid, shutdown),
    remove_handlers(Rest, State#state{handlers=NewHandlers}).

notify(Topic, Message, DxlClient, State) ->
    #state{handlers=Handlers} = State,
    #dxlmessage{type=Type} = Message,
    Key1 = create_lookup_key(Type, Topic),
    List1 = maps:get(Key1, Handlers, []),
    Key2 = create_lookup_key(Type, any),
    List2 = maps:get(Key2, Handlers, []),
    Key3 = create_lookup_key(any, Topic),
    List3 = maps:get(Key3, Handlers, []),
    List = lists:append([List1,List2,List3]),
    lager:info("Callbacks: ~p", [List]),
    notify_handlers(Topic, Message, DxlClient, List).

notify_handlers(_Topic, _Message, _DxlClient, []) ->
    ok;

notify_handlers(Topic, Message, DxlClient, [Info | Rest]) ->
    Pid = element(2, Info),
    gen_server:cast(Pid, {recv, Topic, Message, DxlClient}),
    notify_handlers(Topic, Message, DxlClient, Rest).
