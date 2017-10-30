# OpenDXL Erlang Client
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

## Overview

The OpenDXL Erlang Client enables the development of applications that connect to the [McAfee Data Exchange Layer](http://www.mcafee.com/us/solutions/data-exchange-layer.aspx) messaging fabric for the purposes of sending/receiving events and invoking/providing services.

opendxl-client-erlang requires Erlang R17+.

## Documentation

See the [Wiki](https://github.com/waymirec/opendxl-client-erlang/wiki) for an overview of the Data Exchange Layer (DXL), the OpenDXL Erlang client, and examples.

See the [Erlang Client SDK Documentation](https://waymirec.github.io/opendxl-client-erlang/) for API documentation.
## Usage

### events
The DXL fabric allows for event-based communication, typically referred to as “publish/subscribe” model wherein clients register interest by subscribing to a particular topic and publishers periodically send events to that topic. The event is delivered by the DXL fabric to all of the currently subscribed clients for the topic. Therefore, a single event sent can reach multiple clients (one-to-many). It is important to note that in this model the client passively receives events when they are sent by a publisher.

```erlang
%% load config from file
{ok, Config} = dxl_client_conf:read_from_file(<<"/path/to/config">>),

%% connect to broker
{ok, Client} = dxlc:start(Config),

%% subscribe
F = fun({message_in, {_Topic,Message,_}}) -> dxl_util:log_dxlmessage("Received Event", Message) end,
dxlc:subscribe(Client, ?EVENT_TOPIC, F),
    
%% publish
dxlc:send_event(Client, ?EVENT_TOPIC, <<"Test Message.">>),

%% disconnect from broker
dxlc:stop(Client).
```

### services
The DXL fabric allows for “services” to be registered and exposed that respond to requests sent by invoking clients. This communication is point-to-point (one-to-one), meaning the communication is solely between an invoking client and the service that is being invoked. It is important to note that in this model the client actively invokes the service by sending it requests.
```erlang
%% load config from file
{ok, Config} = dxl_client_conf:read_from_file(<<"/path/to/config">>),

%% connect to broker
{ok, Client} = dxlc:start(Config),

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
```

### Notifications

## Build
```

$ rebar3 compile

```

## Connect to Broker

Connect to DXL Broker:

```erlang
%% with config file
{ok, Config} = dxl_client_conf:read_from_file(<<"/path/to/config">>)
{ok, Client} = dxlc:start(Config)
```
```erlang
%% without confifg file

Config = [{client_id, <<"my-client-id">>},
          {brokers, {"127.0.0.1", 8883}},
          {keepalive, 60 * 30},
          {ssl, [{cacertfile, <<"/path/to/cacertfile">>},
                 {certfile, <<"/path/to/certfile">>},
                 {keyfile, <<"/path/to/privatekey">>}]},
          {reconnect, {1, 60, 5}}],

{ok, Client} = dxlc:start(Config)

```

### Connect Options

```erlang

-type dxlc_opt() ::   {brokers, [{inet:ip_address() | string(), inet:port_number()}]}
                    | {client_id, binary()}
                    | {keepalive, non_neg_integer()}
                    | {reconnect, non_neg_integer() | {non_neg_integer(), non_neg_integer()} | false}
                    | ssl | {ssl, [dxl_sslopt()]}.
                  

-type dxl_sslopt() :: {cacertfile, binary()}
                    | {certfile, binary()}
                    | {keyfile, binary()}.
```

Option | Value | Default | Description | Example
-------|-------|---------|-------------|---------
brokers | list(tuple()) | {"localhost", 1883} | List of brokers | {"localhost", 1883}
client_id | binary() | random clientId | DXL ClientId | <<"slimpleClientId">>
keepalive | non_neg_integer() | 60 | MQTT KeepAlive(secs) 
ssl | list(dxl_sslopt()) | [] | SSL Options | [{certfile, "path/to/ssl.crt"}, {keyfile,  "path/to/ssl.key"}]}]
reconnect | tuple() | {1, 60, 5} | Client Reconnect | {1, 60, 5}


## Bugs and Feedback

For bugs, questions and discussions please use the [Github Issues](https://github.com/waymirec/opendxl-client-erlang/issues).

## LICENSE

Copyright 2017 McAfee, Inc.

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.