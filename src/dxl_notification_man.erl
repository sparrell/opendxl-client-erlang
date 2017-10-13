-module(dxl_notification_man).
-behaviour(gen_server).

-export([create_topic_filter/1,
	 create_topic_filter/2,
	 create_request_filter/1,
	 create_response_filter/1,
	 start_link/1,
	 subscribe/3,
	 subscribe/4,
	 unsubscribe/2,
	 publish/3
	]).

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
	gid					:: binary(),
	parent					:: pid(),
	module					:: atom(),
        subscriptions = maps:new()		:: map()
      }).

-record(sub, {
        id					:: reference(),
	event					:: term(),
	callback				:: term(),
	filter = none				:: term(),
	one_time_only = false			:: true | false
      }).

%%%============================================================================
%%% API functions
%%%============================================================================
create_topic_filter(TopicIn) ->
    fun({Topic, _, _}) -> TopicIn =:= Topic end.

create_topic_filter(TypeIn, TopicIn) ->
    fun({Topic, #dxlmessage{type=Type}, _}) -> ((TypeIn =:= Type) and (TopicIn =:= Topic)) end.

create_request_filter(Topic) ->
    create_topic_filter(request, Topic).

create_response_filter(MessageIdIn) ->
    fun({_, #dxlmessage{type=Type, request_message_id=MessageId}, _}) -> ((Type =:= response) and (MessageIdIn =:= MessageId)) end.

start_link(GID) ->
    gen_server:start_link(?MODULE, [self(), GID], []).

subscribe(Pid, Event, Callback) ->
    gen_server:call(Pid, {subscribe, Event, Callback, []}).

subscribe(Pid, Event, Callback, Opts) ->
    gen_server:call(Pid, {subscribe, Event, Callback, Opts}).

unsubscribe(Pid, Id) ->
    gen_server:call(Pid, {unsubscribe, Id}).

publish(Pid, Event, Data) ->
    gen_server:call(Pid, {publish, Event, Data}).

%%%============================================================================
%%% gen_server functions
%%%============================================================================
init([Parent, GID]) ->
    State = #state{parent=Parent, gid=GID},
    process_flag(trap_exit, true),
    dxl_registry:register_process({GID, ?MODULE}),
    {ok, State}.

handle_call({subscribe, Event, Callback, Opts}, _From, State) ->
    {ok, Id, State1} = do_subscribe(Event, Callback, Opts, State),
    {reply, {ok, Id}, State1};

handle_call({unsubscribe, Id}, _From, State) ->
    {ok, State1} = do_unsubscribe(Id, State),
    {reply, ok, State1};

handle_call({publish, Event, Data}, _From, State) ->
    ok = do_publish(Event, Data, State),
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'EXIT', Parent, Reason}, #state{parent=Parent}=State) ->
    {stop, {parent_exited, Reason}, State};

handle_info({'EXIT', ExitedPid, _Reason}, State) ->
    {ok, State1} = do_unsubscribe(ExitedPid, State),
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
do_subscribe(Event, Callback, Opts, State) ->
    #state{subscriptions=Subscriptions} = State,
    Filter = proplists:get_value(filter, Opts, none),
    OneTimeOnly = proplists:get_value(one_time_only, Opts, false),
    Timeout = proplists:get_value(timeout, Opts, infinity),
    Id = make_ref(),
    Sub = #sub{id=Id, event=Event, callback=Callback, filter=Filter, one_time_only=OneTimeOnly},
    lager:info("Timeout == ~p", [Timeout]),
    Sub1 = case Timeout of
	       I when is_integer(I) ->
	           {ok, Pid} = dxl_timed_callback:start_link(Callback, Timeout),
	 	   Sub#sub{callback=Pid};
	       _ -> Sub
	   end,
		
    NewSubs =  maps:put(Event, [Sub1 | maps:get(Event, Subscriptions, [])], Subscriptions),
    {ok, Id, State#state{subscriptions=NewSubs}}.

do_unsubscribe(Id, State) when is_reference(Id) ->
    #state{subscriptions=Subscriptions} = State,
    Matches = lists:filter(fun(#sub{id=I}) -> Id =:= I end, lists:flatten(maps:values(Subscriptions))),
    do_unsubscribe(Matches, State);

do_unsubscribe(Pid, State) when is_pid(Pid) ->
    #state{subscriptions=Subscriptions} = State,
    Matches = lists:filter(fun(#sub{callback=Callback}) -> Pid =:= Callback end, lists:flatten(maps:values(Subscriptions))),
    do_unsubscribe(Matches, State);

do_unsubscribe([#sub{id=Id,event=Event} | Rest], State) ->
    #state{subscriptions=Subscriptions} = State,
    F1 = fun(#sub{id=Id2}) -> Id =/= Id2 end,
    List = lists:filter(F1, maps:get(Event, Subscriptions, [])),
    State1 = State#state{subscriptions=maps:put(Event, List, Subscriptions)},
    do_unsubscribe(Rest, State1);

do_unsubscribe([], State) ->
    {ok, State}.

do_publish(Event, Data, State) ->
    #state{subscriptions=Subscriptions} = State,
    List = lists:filter(fun(#sub{event=Event2}) -> Event =:= Event2 end, lists:flatten(maps:values(Subscriptions))),
    do_publish(Event, Data, List, State).

do_publish(Event, Data, [Sub | Rest], State) ->
    #sub{id=Id, callback=Callback, filter=Filter, one_time_only=Once} = Sub,
    Self = self(),
    F = fun() ->
            MatchesFilter = meets_filter_criteria(Filter, Data),
            case MatchesFilter of
                false -> ok;
                true -> 
		    try
	                execute_callback(Callback, Data)
		    catch
		        _ -> unsubscribe(Self, Id)
		    end,
	            case Once of
                        false -> ok;
                        true -> unsubscribe(Self, Id)
                    end
            end
        end,
    erlang:spawn(F),
    do_publish(Event, Data, Rest, State);

do_publish(_Event, _Data, [], _State) ->
    ok.

meets_filter_criteria({M,F,A}, Data) ->
    M:F([Data | A]);

meets_filter_criteria(Func, Data) when is_function(Func, 1) ->
    Func(Data);

meets_filter_criteria(_Func, _Data) ->
    true.

execute_callback({M,F,A}, Data) ->
    erlang:apply(M, F, [Data | A]);

execute_callback(Callback, Data) when is_function(Callback, 1) ->
    Callback(Data);

execute_callback(Pid, Data) when is_pid(Pid) ->
    Pid ! {notification, Data}.

