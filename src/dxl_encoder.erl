-module(dxl_encoder).

-include("dxl.hrl").

-export([encode/1]).

encode(Message) when is_record(Message, dxlmessage) ->
    Version = ?DEF_VERSION,
    Type = Message#dxlmessage.type,
    TypeVal = dxl_util:message_type(Type),

    VersionBin = msgpack:pack(Version),
    TypeBin = msgpack:pack(TypeVal),
    MessageIdBin = msgpack:pack(Message#dxlmessage.message_id),
    SrcClientIdBin = msgpack:pack(Message#dxlmessage.src_client_id),
    SrcBrokerIdBin = msgpack:pack(Message#dxlmessage.src_broker_id),
    BrokerIdsBin = msgpack:pack(Message#dxlmessage.broker_ids),
    ClientIdsBin = msgpack:pack(Message#dxlmessage.client_ids),
    PayloadBin = msgpack:pack(Message#dxlmessage.payload),

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
    ReplyToTopic = msgpack:pack(Message#dxlmessage.reply_to_topic),
    ServiceId = msgpack:pack(Message#dxlmessage.service_id),
    <<Binary/binary, ReplyToTopic/binary, ServiceId/binary>>;

encode(0=_Version, response, Message, Binary) ->
    ReqMessageId = msgpack:pack(Message#dxlmessage.request_message_id),
    ServiceId = msgpack:pack(Message#dxlmessage.service_id),
    <<Binary/binary, ReqMessageId/binary, ServiceId/binary>>;

encode(0=_Version, error, Message, Binary) ->
    ErrorCode = msgpack:pack(Message#dxlmessage.error_code),
    ErrorMsg = msgpack:pack(Message#dxlmessage.error_message),
    <<Binary/binary, ErrorCode/binary, ErrorMsg/binary>>;

encode(1=_Version, Type, Message, Binary0) ->
    Binary1 = encode(0, Type, Message, Binary0),
    OtherFields = msgpack:pack(Message#dxlmessage.other_fields),
    <<Binary1/binary, OtherFields/binary>>;

encode(2=_Version, Type, Message, Binary0) ->
    Binary1 = encode(1, Type, Message, Binary0),
    SrcTenantId = msgpack:pack(Message#dxlmessage.src_tenant_id),
    <<Binary1/binary, SrcTenantId/binary>>;

encode(_Version, _Type, _Message, Binary) ->
    Binary.

