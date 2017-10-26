%%%----------------------------------------------------------------------------
%%% @author Chris Waymire <chris@waymire.net>
%%% @private
%%%----------------------------------------------------------------------------
-module(dxl_encoder).

-include("dxl.hrl").

-export([encode/1]).

encode(Message) when is_record(Message, dxlmessage) ->
    Version = ?DEF_VERSION,
    Type = Message#dxlmessage.type,
    TypeVal = dxl_util:message_type(Type),

    VersionBin = pack(Version),
    TypeBin = pack(TypeVal),
    MessageIdBin = pack(Message#dxlmessage.message_id),
    SrcClientIdBin = pack(Message#dxlmessage.src_client_id),
    SrcBrokerIdBin = pack(Message#dxlmessage.src_broker_id),
    BrokerIdsBin = pack(Message#dxlmessage.broker_ids),
    ClientIdsBin = pack(Message#dxlmessage.client_ids),
    PayloadBin = pack(Message#dxlmessage.payload),

    Binary0 = <<VersionBin/binary, 
		TypeBin/binary, 
		MessageIdBin/binary,
		SrcClientIdBin/binary,
		SrcBrokerIdBin/binary,
		BrokerIdsBin/binary,
		ClientIdsBin/binary,
		PayloadBin/binary>>,
    
    Binary1 = encode(Version, Type, Message, Binary0),
    Binary1.

encode(0=_Version, request, Message, Binary) ->
    ReplyToTopic = pack(Message#dxlmessage.reply_to_topic),
    ServiceId = pack(Message#dxlmessage.service_id),
    <<Binary/binary, ReplyToTopic/binary, ServiceId/binary>>;

encode(0=_Version, response, Message, Binary) ->
    ReqMessageId = pack(Message#dxlmessage.request_message_id),
    ServiceId = pack(Message#dxlmessage.service_id),
    <<Binary/binary, ReqMessageId/binary, ServiceId/binary>>;

encode(0=_Version, error, Message, Binary) ->
    Binary1 = encode(0, response, Message, Binary),
    ErrorCode = pack(Message#dxlmessage.error_code),
    ErrorMsg = pack(Message#dxlmessage.error_message),
    <<Binary1/binary, ErrorCode/binary, ErrorMsg/binary>>;

encode(1=_Version, Type, Message, Binary0) ->
    Binary1 = encode(0, Type, Message, Binary0),
    OtherFields = pack(Message#dxlmessage.other_fields),
    <<Binary1/binary, OtherFields/binary>>;

encode(2=_Version, Type, Message, Binary0) ->
    Binary1 = encode(1, Type, Message, Binary0),
    SrcTenantId = pack(Message#dxlmessage.src_tenant_id),
    DstTenantIds = pack(Message#dxlmessage.dst_tenant_ids),
    <<Binary1/binary, SrcTenantId/binary, DstTenantIds/binary>>;

encode(_Version, _Type, _Message, Binary) ->
    Binary.

pack(Value) -> msgpack:pack(Value, [{spec, old}]).
