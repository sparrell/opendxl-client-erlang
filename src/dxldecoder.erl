-module(dxldecoder).

-include("dxl.hrl").

-export([decode/1]).

decode(Binary) when is_binary(Binary) ->
    {Version, Rest0} = msgpack:unpack_stream(Binary),
    {Type, Rest1} = msgpack:unpack_stream(Rest0),
    {MessageId, Rest2} = msgpack:unpack_stream(Rest1),
    {SrcClientId, Rest3} = msgpack:unpack_stream(Rest2),
    {SrcBrokerId, Rest4} = msgpack:unpack_stream(Rest3),
    {BrokerIds, Rest5} = msgpack:unpack_stream(Rest4),
    {ClientIds, Rest6} = msgpack:unpack_stream(Rest5),
    {Payload, Rest7} = msgpack:unpack_stream(Rest6, [{unpack_str, as_binary}]),

    Data0 = #{type => dxlutil:message_type(Type),
	      version => Version,
	      message_id => MessageId,
	      src_client_id => SrcClientId,
	      src_broker_id => SrcBrokerId,
	      broker_ids => BrokerIds,
	      client_ids => ClientIds,
	      payload => Payload},

    {Data1,_} = decode(Version, dxlutil:message_type(Type), Data0, Rest7),
    Data1.


decode(0=_Version, request, Data0, Binary) ->
    {ReplyToTopic, Rest0} = msgpack:unpack_stream(Binary),
    {ServiceId, Rest1} = msgpack:unpack_stream(Rest0),
    Data1 = Data0#{reply_to_topic => ReplyToTopic, service_id => ServiceId},
    {Data1, Rest1};

decode(0=_Version, response, Data0, Binary) ->
    {ReqMessageId, Rest0} = msgpack:unpack_stream(Binary),
    {ServiceId, Rest1} = msgpack:unpack_stream(Rest0),
    Data1 = Data0#{request_message_id => ReqMessageId, service_id => ServiceId},
    {Data1, Rest1};

decode(0=_Version, error, Data0, Binary) ->
    {ErrCode, Rest0} = msgpack:unpack_stream(Binary),
    {ErrMsg, Rest1} = msgpack:unpac_stream(Rest0),
    Data1 = Data0#{error_code => ErrCode, error_message => ErrMsg},
    {Data1, Rest1};
 
decode(0=_Version, _Type, Data0, Binary) ->
    {Data0, Binary};

decode(1=_Version, Type, Data0, Binary) ->
    {Data1, Rest0} = decode(0, Type, Data0, Binary),
    {OtherFields, Rest1} = msgpack:unpack_stream(Rest0),
    Data2 = Data1#{other_fields => OtherFields},
    {Data2, Rest1};

decode(2=_Version, Type, Data0, Binary) ->
    {Data1, Rest0} = decode(1, Type, Data0, Binary),
    {SrcTenantId, Rest1} = msgpack:unpack_stream(Rest0),
    {DstTenantIds, Rest2} = msgpack:unpack_stream(Rest1),
    Data2 = Data1#{src_tenant_id => SrcTenantId, dst_tenant_ids => DstTenantIds},
    {Data2, Rest2}.

