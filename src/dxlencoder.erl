-module(dxlencoder).

-include("dxl.hrl").

-export([encode/1]).

encode(Input) when is_map(Input) ->
    Input1 = set_defaults(Input),
    Version = msgpack:pack(maps:get(version, Input1)),
    Type = msgpack:pack(dxlutil:message_type(maps:get(type, Input1))),
    MessageId = msgpack:pack(maps:get(message_id, Input1)),
    SrcClientId = msgpack:pack(maps:get(src_client_id, Input1)),
    SrcBrokerId = msgpack:pack(maps:get(src_broker_id, Input1)),
    BrokerIds = msgpack:pack(maps:get(broker_ids, Input1)),
    ClientIds = msgpack:pack(maps:get(client_ids, Input1)),
    Payload = msgpack:pack(maps:get(payload, Input1)),
    
    
    Binary0 = <<Version/binary, 
		Type/binary, 
		MessageId/binary, 
		SrcClientId/binary,
		SrcBrokerId/binary, 
		BrokerIds/binary, 
		ClientIds/binary,
		Payload/binary>>,
    
    Binary1 = encode(2, dxlutil:message_type(Type), Input1, Binary0),
    Binary1.

encode(0=_Version, request, Input, Binary) ->
    ReplyToTopic = msgpack:pack(maps:get(reply_to_topic, Input)),
    ServiceId = msgpack:pack(maps:get(service_id, Input)),
    <<Binary/binary, ReplyToTopic/binary, ServiceId/binary>>;

encode(0=_Version, response, Input, Binary) ->
    ReqMessageId = msgpack:pack(maps:get(request_message_id, Input)),
    ServiceId = msgpack:pack(maps:get(service_id, Input)),
    <<Binary/binary, ReqMessageId/binary, ServiceId/binary>>;

encode(0=_Version, error, Input, Binary) ->
    ErrorCode = msgpack:pack(maps:get(error_code, Input)),
    ErrorMsg = msgpack:pack(maps:get(error_message, Input)),
    <<Binary/binary, ErrorCode/binary, ErrorMsg/binary>>;

encode(1=_Version, Type, Input, Binary0) ->
    Binary1 = encode(0, Type, Input, Binary0),
    OtherFields = msgpack:pack(maps:get(other_fields, Input)),
    <<Binary1/binary, OtherFields/binary>>;

encode(2=_Version, Type, Input, Binary0) ->
    Binary1 = encode(1, Type, Input, Binary0),
    SrcTenantId = msgpack:pack(maps:get(src_tenant_id, Input)),
    <<Binary1/binary, SrcTenantId/binary>>;

encode(_Version, _Type, _Input, Binary) ->
    Binary.

set_defaults(Input) ->
    Defaults = #{version		=> ?DEF_VERSION,
		 message_id 		=> ?DEF_MESSAGE_ID,
		 src_client_id 		=> ?DEF_SRC_CLIENT_ID,
		 src_broker_id 		=> ?DEF_SRC_BROKER_ID,
		 broker_ids 		=> ?DEF_BROKER_IDS,
		 client_ids 		=> ?DEF_CLIENT_IDS,
		 payload 		=> ?DEF_PAYLOAD,
		 other_fields 		=> ?DEF_OTHER_FIELDS,
	 	 src_tenant_id 		=> ?DEF_SRC_TENANT_ID,
		 dst_tenant_ids 	=> ?DEF_DST_TENANT_IDS,
		 reply_to_topic 	=> ?DEF_REPLY_TO_TOPIC,
		 service_id 		=> ?DEF_SERVICE_ID,
	 	 request_message_id 	=> ?DEF_REQ_MESSAGE_ID,
		 error_code 		=> ?DEF_ERR_CODE,
		 error_message 		=> ?DEF_ERR_MESSAGE},
    maps:merge(Defaults, Input).
