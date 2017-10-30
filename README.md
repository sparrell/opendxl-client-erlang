# OpenDXL Erlang Client
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

## Overview

The OpenDXL Erlang Client enables the development of applications that connect to the [McAfee Data Exchange Layer](http://www.mcafee.com/us/solutions/data-exchange-layer.aspx) messaging fabric for the purposes of sending/receiving events and invoking/providing services.

opendxl-client-erlang requires Erlang R17+.

## Documentation

See the [Wiki](https://github.com/waymirec/opendxl-client-erlang/wiki) for an overview of the Data Exchange Layer (DXL), the OpenDXL Erlang client, and examples.

See the [Erlang Client SDK Documentation](https://waymirec.github.io/opendxl-client-erlang/) for API documentation.

## Installation
To start using the OpenDXL Erlang Client Library:
* Download [Rebar3](https://www.rebar3.org/)
* Modify the rebar.config and add opendxl-erlang-client to the deps tuple.
* From your root source directory run <code>rebar3 compile</code>

Review the [OpenWeatherMap Service Example](https://github.com/waymirec/opendxl-client-erlang/tree/master/examples/service_wrapper) for a complete example on how to use the OpenDXL Erlang client including
a sample rebar.config. 

```
C02VCDMNHTD6:service_wrapper cwaymire$ pwd
/source/opendxl/opendxl-client-erlang/examples/service_wrapper
C02VCDMNHTD6:service_wrapper cwaymire$ rebar3 compile
===> Verifying dependencies...
===> Fetching eini ({git,"https://github.com/erlcloud/eini.git",
                                {branch,"master"}})
===> Fetching emqttc ({git,"https://github.com/waymirec/emqttc.git",
                                  {branch,"master"}})
===> Fetching jiffy ({git,"https://github.com/davisp/jiffy.git",
                                 {branch,"master"}})
===> Fetching lager ({git,"https://github.com/erlang-lager/lager.git",
                                 {tag,"3.5.1"}})
===> Fetching msgpack ({git,"git://github.com/msgpack/msgpack-erlang.git",
                                   {branch,"master"}})
===> Fetching gen_logger ({git,"https://github.com/emqtt/gen_logger.git",
                                      {branch,"master"}})
===> Fetching goldrush ({pkg,<<"goldrush">>,<<"0.1.9">>})
===> Downloaded package, caching at /Users/cwaymire/.cache/rebar3/hex/default/packages/goldrush-0.1.9.tar
===> Skipping lager (from {git,"https://github.com/basho/lager.git",
                                      {branch,"master"}}) as an app of the same name has already been fetched
===> Compiling eini
===> Compiling goldrush
===> Compiling lager
===> Compiling gen_logger
===> Compiling msgpack
===> Compiling jiffy
Compiling c_src/decoder.c
Compiling c_src/encoder.c
Compiling c_src/jiffy.c
Compiling c_src/utf8.c
Compiling c_src/util.c
Compiling c_src/doubles.cc
Compiling c_src/objects.cc
Compiling c_src/double-conversion/bignum-dtoa.cc
Compiling c_src/double-conversion/bignum.cc
Compiling c_src/double-conversion/cached-powers.cc
Compiling c_src/double-conversion/diy-fp.cc
Compiling c_src/double-conversion/double-conversion.cc
Compiling c_src/double-conversion/fast-dtoa.cc
Compiling c_src/double-conversion/fixed-dtoa.cc
Compiling c_src/double-conversion/strtod.cc
===> Compiling emqttc
_build/default/lib/emqttc/src/emqttc_socket.erl:205: Warning: gen_fsm:send_all_state_event/2 is deprecated and will be removed in a future release; use gen_statem:cast/2
_build/default/lib/emqttc/src/emqttc_socket.erl:216: Warning: gen_fsm:send_all_state_event/2 is deprecated and will be removed in a future release; use gen_statem:cast/2
_build/default/lib/emqttc/src/emqttc_socket.erl:234: Warning: gen_fsm:send_event/2 is deprecated and will be removed in a future release; use gen_statem:cast/2
_build/default/lib/emqttc/src/emqttc_socket.erl:243: Warning: gen_fsm:send_all_state_event/2 is deprecated and will be removed in a future release; use gen_statem:cast/2

_build/default/lib/emqttc/src/emqttc.erl:173: Warning: gen_fsm:start_link/3 is deprecated and will be removed in a future release; use gen_statem:start_link/3
_build/default/lib/emqttc/src/emqttc.erl:184: Warning: gen_fsm:start_link/4 is deprecated and will be removed in a future release; use gen_statem:start_link/4
_build/default/lib/emqttc/src/emqttc.erl:192: Warning: gen_fsm:sync_send_all_state_event/2 is deprecated and will be removed in a future release; use gen_statem:call/2
_build/default/lib/emqttc/src/emqttc.erl:245: Warning: gen_fsm:send_event/2 is deprecated and will be removed in a future release; use gen_statem:cast/2
_build/default/lib/emqttc/src/emqttc.erl:253: Warning: gen_fsm:sync_send_event/2 is deprecated and will be removed in a future release; use gen_statem:call/2
_build/default/lib/emqttc/src/emqttc.erl:326: Warning: gen_fsm:send_event/2 is deprecated and will be removed in a future release; use gen_statem:cast/2
_build/default/lib/emqttc/src/emqttc.erl:329: Warning: gen_fsm:sync_send_event/3 is deprecated and will be removed in a future release; use gen_statem:call/3
_build/default/lib/emqttc/src/emqttc.erl:341: Warning: gen_fsm:send_event/2 is deprecated and will be removed in a future release; use gen_statem:cast/2
_build/default/lib/emqttc/src/emqttc.erl:349: Warning: gen_fsm:sync_send_event/3 is deprecated and will be removed in a future release; use gen_statem:call/3
_build/default/lib/emqttc/src/emqttc.erl:357: Warning: gen_fsm:send_event/2 is deprecated and will be removed in a future release; use gen_statem:cast/2
_build/default/lib/emqttc/src/emqttc.erl:365: Warning: gen_fsm:sync_send_all_state_event/2 is deprecated and will be removed in a future release; use gen_statem:call/2
_build/default/lib/emqttc/src/emqttc.erl:489: Warning: gen_fsm:cancel_timer/1 is deprecated and will be removed in a future release; use erlang:cancel_timer/1
_build/default/lib/emqttc/src/emqttc.erl:506: Warning: gen_fsm:send_event/2 is deprecated and will be removed in a future release; use gen_statem:cast/2
_build/default/lib/emqttc/src/emqttc.erl:771: Warning: gen_fsm:cancel_timer/1 is deprecated and will be removed in a future release; use erlang:cancel_timer/1
_build/default/lib/emqttc/src/emqttc.erl:979: Warning: gen_fsm:start_timer/2 is deprecated and will be removed in a future release; use erlang:start_timer/3
_build/default/lib/emqttc/src/emqttc.erl:1069: Warning: gen_fsm:reply/2 is deprecated and will be removed in a future release; use gen_statem:reply/2
_build/default/lib/emqttc/src/emqttc.erl:1082: Warning: gen_fsm:reply/2 is deprecated and will be removed in a future release; use gen_statem:reply/2
_build/default/lib/emqttc/src/emqttc.erl:1093: Warning: gen_fsm:reply/2 is deprecated and will be removed in a future release; use gen_statem:reply/2
```

## Connect to Broker

```
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


## Usage

### events
The DXL fabric allows for event-based communication, typically referred to as “publish/subscribe” model wherein clients 
register interest by subscribing to a particular topic and publishers periodically send events to that topic. The event 
is delivered by the DXL fabric to all of the currently subscribed clients for the topic. Therefore, a single event sent 
can reach multiple clients (one-to-many). It is important to note that in this model the client passively receives events 
when they are sent by a publisher.

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
The DXL fabric allows for “services” to be registered and exposed that respond to requests sent by invoking clients. 
This communication is point-to-point (one-to-one), meaning the communication is solely between an invoking client and 
the service that is being invoked. It is important to note that in this model the client actively invokes the service 
by sending it requests.
```erlang
%% load config from file
{ok, Config} = dxl_client_conf:read_from_file(<<"/path/to/config">>),

%% connect to broker
{ok, Client} = dxlc:start(Config),

Fun = fun({message_in, {Topic, Message, ClientIn}}) ->
         #dxlmessage{message_id=MessageId, payload=Payload, reply_to_topic=ReplyToTopic} = Message,
         lager:info("Request received: Topic=~s, ID=~s, Payload=~s", [Topic, MessageId, Payload]),
         lager:info("Creating a response for request ~s on ~s.", [MessageId, ReplyToTopic]),
         dxlc:send_response(ClientIn, Message, <<"Sample Response Payload"/utf8>>),
         lager:info("Response sent.", []),
          ok
 	  end,

ServiceRegistry = #service_registration{type = <<"/mycompany/myservice">>, 
                                        topics=#{?SERVICE_TOPIC => Fun}},
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
The OpenDXL Erlang Client leverages a notification system that is used to register callbacks for internal notices by 
category. Examples of categories that you can subscribe to would be <i>message_in</i> for inbound DXL messages,
<i>connection</i> for client connection events, and <i>service</i> for service related events.

```erlang
dxlc:subscribe_notification(Client, Category, Callback, Opts)
```
<i>Callback</i> can be one of the following:
* Pid - called via normal message pattern (e.g. Pid ! Data)
* Function - function executed (e.g. Function(Data))
* {M,F,A} - standard erlang:apply call (e.g. M:F([Data | A]))

<i>Opts</i> is a list of tagged-tuple options:
* single_use - if set to true this callback will deregister after it's first use. (e.g. {single_use, true})
* filter - specify a function that will be used to filter matches for this callback (e.g. {filter, fun filter_func/1})
* timeout - specify a timeout (in ms) before deregistering this callback. Also allows for providing a callback to 
execute if a timeout occurs (e.g. {timeout, 5000} or {timeout, {5000, fun timeout_func/1})


<b>Notification Categories</b>
* <code>connection</code> - published when the DXL client connects or disconnects. The payload is a tagged tuple with the 
first element being <code>connected</code> or <code>disconneced</code> and the second element being the pid of the DXL 
client.
* <code>service</code> - published for service related events; currently only registration and deregistration 
notifications are published. The payload is a tagged tuple with the first element being <code>service_registered</code>,
<code>service_deregistered</code>, <code>service_registration_failed</code> or <code>service_deregistration_failed</code>.
For the success notices the remaining elements in the payload tuple are the service id and service type. For the failure 
notices there is a fourth element containing the reason for failure, which is typically of the form {Error, Reason}.
* <code>message_in</code> - published for any incoming messages on the DXL fabric. The payload contains the message
topic, the message packet, and the DXL client pid in the form {Topic, Message, Client}.

<b><u>Notifications :: Connection Events (with pid callback)</b></u>
```erlang
-module(example).

-behaviour(gen_server).

-export([start_link/0]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-record(state, {}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    Config = load_config(),
    {ok, Client} = dxlc:start(Config),
    dxlc:subscribe_notification(Client, connection, self()),
    {ok, #state{}}.

handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({connected, _Client}, State) ->
    do_something(),
    {noreply, State};

handle_info({disconnected, _Client}, State) ->
    do_something_else(),
    {noreply, State};
    
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
```

<b><u>Notifications :: Service Events (with function callback)</b></u>
```erlang
-module(example).

-behaviour(gen_server).

-export([start_link/0]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-record(state, {}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    Config = load_config(),
    {ok, Client} = dxlc:start(Config),
    dxlc:subscribe_notification(Client, service, fun process_service_notice/1),
    {ok, #state{}}.

handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({connected, _Client}, State) ->
    do_something(),
    {noreply, State};

handle_info({disconnected, _Client}, State) ->
    do_something_else(),
    {noreply, State};
    
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
    
process_service_notice({service_registered, ServiceId, ServiceType}) ->
    lager:debug("Sevice Registered: ~p (~p).", [ServiceType, ServiceId]),
    ok;
    
process_service_notice({service_registration_failed, ServiceId, ServiceType, Reason}) ->
    lager:debug("Service failed to register: ~p (~p) => ~p.", [ServiceType, ServiceId, Reason]),
    ok;
    
process_service_notice({service_deregistered, ServiceId, ServiceType}) ->
    lager:debug("Sevice Deregistered: ~p (~p).", [ServiceType, ServiceId]),
    ok;

process_service_notice({service_deregistration_failed, ServiceId, ServiceType, Reason}) ->
lager:debug("Service failed to deregister: ~p (~p) => ~p.", [ServiceType, ServiceId, Reason]),
    ok.
```

<b><u>Notifications :: Message Events (with MFA callback)</b></u>
```erlang
-module(example).

-behaviour(gen_server).

-export([start_link/0]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-export([process_message/2]).

-record(state, {}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    Config = load_config(),
    {ok, Client} = dxlc:start(Config),
    dxlc:subscribe_notification(Client, message_in, {?MODULE, process_message, [self()]}),
    {ok, #state{}}.
    {ok, #state{}}.

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

%% Match messages of any type to a specific topic
process_message({<<"/my/topic">>, #dxlmessage{type=Type} = Message, Client}, MyPid) ->
    lager:debug("Got a message of type ~p for topic ~p.", [Type, Topic]),
    ok;
    
%% Match messages of specific type to a specific topic
process_message({<<"/my/topic">>, #dxlmessage{type=event} = Message, Client}, MyPid) ->
    lager:debug("Got an event for topic ~p.", [Topic]),
    ok;

%% Match messages of any type from a specific client id.
process_message({_Topic, #dxlmessage{client_ids = [<<"target_client_id">> | _]} = _M, Client}, MyPid) ->
    lager:debug("Got message from client: ~p.", [ClientId]),
    ok;

%% Match anything else
process_message({Topic, Message, Client}, MyPid) ->
    ok.
```
<b><u>Notifications :: Filter examples</b></u>
```erlang
%% Filter messages by topic
Filter = fun({Topic, _Message, _Client}) -> Topic =:= <<"/my/topic">> end,
dxlc:subscribe_notifiation(Client, message_in, self(), [{filter, Filter}]),
```

```erlang
%% Filter messages by topic using helper
Filter = dxl_util:create_topic_filter(<<"/my/topic">>),
dxlc:subscribe_notifiation(Client, message_in, self(), [{filter, Filter}]),

Filter = dxl_util:create_topic_filter(event, <<"/my/topic">>),
dxlc:subscribe_notifiation(Client, message_in, self(), [{filter, Filter}]),
```

```erlang
%% Filter messages by ClientId
Filter = fun({_Topic, #dxlmessag{client_ids=ClientIds}, _Client}) -> 
                lists:member(<<"target_client_id">>, ClientIds)
         end,
dxlc:subscribe_notifiation(Client, message_in, self(), [{filter, Filter}]),
```

```erlang
%% Filter service events by registration
Filter = fun(Data) -> 
            (element(1, Data) =:= service_registered) or
            (element(1, Data) =:= service_registration_failed)
         end,
dxlc:subscribe_notifiation(Client, service, self(), [{filter, Filter}]),
```

## Bugs and Feedback

For bugs, questions and discussions please use the [Github Issues](https://github.com/waymirec/opendxl-client-erlang/issues).

## LICENSE

Copyright 2017 McAfee, Inc.

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.