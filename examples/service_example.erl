-module(service_example).

-export([start/0]).

-include("dxl.hrl").

-define(SERVICE_TOPIC, <<"/isecg/sample/service">>).

start() ->
    Config = load_config(),
    lager:info("Connecting to broker...", []),
    {ok, Client} = dxlc:start(Config),
    lager:info("Connected.", []),
    Fun = fun({message_in, {Topic, Message, ClientIn}}) ->
              #dxlmessage{message_id=MessageId, payload=Payload, reply_to_topic=ReplyToTopic} = Message,
              lager:info("Service Provider - Request received: Topic=~s, ID=~s, Payload=~s", [Topic, MessageId, Payload]),
              lager:info("Service Provider - Creating a response for request ~s on ~s.", [MessageId, ReplyToTopic]),
              dxlc:send_response(ClientIn, Message, <<"Sample Response Payload"/utf8>>),
	      lager:info("Response sent.", []),
              ok
 	  end,

    ServiceRegistry = #service_registration{type = <<"/mycompany/myservice">>, topics=#{?SERVICE_TOPIC => Fun}},
    lager:info("Registering service: ~s", [ServiceRegistry#service_registration.type]),
    {ok, ServiceId} = dxlc:register_service(Client, ServiceRegistry, 10000), 
    lager:info("Successfully registered service: ~s", [ServiceId]),
    lager:info("Sending request to service.", []),
    Response = dxlc:send_request(Client, ?SERVICE_TOPIC, <<"test message.">>),
    dxl_util:log_dxlmessage("Got Response", Response),
    dxlc:unregister_service(Client, ServiceId),
    ok.

load_config() ->
    Dir = filename:dirname(filename:absname(".")),
    File = filename:join([Dir, "test", "dxlclient.config"]),
    lager:info("Reading configuration from file: ~s.", [File]),
    {ok, Config} = dxl_client_conf:read_from_file(File),
    Config.

