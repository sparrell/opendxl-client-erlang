-module(dxl_service).

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
	dxl_client,
	info = #svc_reg_info{}				:: svc_reg_info()
      }).

%%%============================================================================
%%% API functions
%%%============================================================================
start_link(Info) ->
    Id = dxl_util:generate_uuid(),
    Result = gen_server:start_link(?MODULE, [Info#svc_reg_info{service_id=Id}], []),
    case Result of
        {ok, Pid} -> {ok, {Id, Pid}};
                _ -> Result
    end.

%%%============================================================================
%%% gen_server functions
%%%============================================================================
init([Info]) ->
    {ok, #state{info=Info}}.

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

send_registration_request(Info, State) ->
    #state{dxl_client=DxlClient} = State,
    Payload = build_registration_payload(Info),
    Request = #dxlmessage{payload=Payload, dst_tenant_ids=Info#svc_reg_info.dst_tenant_ids},
    Response = dxl_client:send_request(DxlClient, ?SVC_REG_REQ_TOPIC, Request),
    ok.

send_unregister_request(Id, State) ->
    #state{dxl_client=DxlClient} = State,
    Payload = jiffy:encode({serviceGuid, Id}),
    Request = #dxlmessage{payload=Payload},
    Response = dxl_client:send_request(DxlClient, ?SVC_UNREG_REQ_TOPIC, Request),
    ok.

build_registration_payload(Info) ->
    jiffy:encode({{serviceType, Info#svc_reg_info.service_type},
                 {serviceGuid, Info#svc_reg_info.service_id},
                 {metaData, Info#svc_reg_info.metadata},
                 {ttlMins, Info#svc_reg_info.ttl},
                 {requestChannels, Info#svc_reg_info.topics}}).
