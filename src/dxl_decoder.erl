%%%----------------------------------------------------------------------------
%%% @author Chris Waymire <chris@waymire.net>
%%% @private
%%%----------------------------------------------------------------------------
-module(dxl_decoder).

-include("dxl.hrl").

-export([decode/1]).

decode(Binary) when is_binary(Binary) ->
    {Version, Rest0} = unpack(Binary),
    {Type, Rest1} = unpack(Rest0),
    {MessageId, Rest2} = unpack(Rest1),
    {SrcClientId, Rest3} = unpack(Rest2),
    {SrcBrokerId, Rest4} = unpack(Rest3),
    {BrokerIds, Rest5} = unpack(Rest4),
    {ClientIds, Rest6} = unpack(Rest5),
    {Payload, Rest7} = unpack(Rest6),

    TypeAtom = dxl_util:message_type(Type),
    Message0 = #dxlmessage{type=TypeAtom,
			   message_id=MessageId,
			   src_client_id=SrcClientId,
			   src_broker_id=SrcBrokerId,
			   broker_ids=BrokerIds,
			   client_ids=ClientIds,
			   payload=Payload},

    {Message1, _} = decode(Version, TypeAtom, Message0, Rest7),
    Message1.


decode(0=_Version, request, Message0, Binary) ->
    {ReplyToTopic, Rest0} = unpack(Binary),
    {ServiceId, Rest1} = unpack(Rest0),
    Message1 = Message0#dxlmessage{reply_to_topic=ReplyToTopic, service_id=ServiceId},
    {Message1, Rest1};

decode(0=_Version, response, Message0, Binary) ->
    {ReqMessageId, Rest0} = unpack(Binary),
    {ServiceId, Rest1} = unpack(Rest0),
    Message1 = Message0#dxlmessage{request_message_id=ReqMessageId, service_id=ServiceId},
    {Message1, Rest1};

decode(0=_Version, error, Message0, Binary) ->
    {Message1, Rest0} = decode(0, response, Message0, Binary),
    {ErrCode, Rest1} = unpack(Rest0),
    {ErrMsg, Rest2} = unpack(Rest1),
    ErrCode2 = <<ErrCode/unsigned>>,
    Message2 = Message1#dxlmessage{error_code=ErrCode2, error_message=ErrMsg},
    {Message2, Rest2};
 
decode(0=_Version, _Type, Message0, Binary) ->
    {Message0, Binary};

decode(1=_Version, Type, Message0, Binary) ->
    {Message1, Rest0} = decode(0, Type, Message0, Binary),
    {OtherFields, Rest1} = unpack(Rest0),
    Message2 = Message1#dxlmessage{other_fields=OtherFields},
    {Message2, Rest1};

decode(2=_Version, Type, Message0, Binary) ->
    {Message1, Rest0} = decode(1, Type, Message0, Binary),
    {SrcTenantId, Rest1} = unpack(Rest0),
    {DstTenantIds, Rest2} = unpack(Rest1),
    Message2 = Message1#dxlmessage{src_tenant_id=SrcTenantId, dst_tenant_ids=DstTenantIds},
    {Message2, Rest2}.


unpack(Binary) ->
    msgpack:unpack_stream(Binary, [{unpack_str, as_binary}, {spec, old}]).
