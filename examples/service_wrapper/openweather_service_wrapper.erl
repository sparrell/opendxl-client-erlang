%%%-------------------------------------------------------------------
%%% @author Chris Waymire <chris@waymire.net>
%%% @doc
%%% This sample demonstrates wrapping an existing service and exposing it on the
%%% DXL fabric.
%%%
%%% In this particular case, the "openweathermap.org" current weather data is
%%% exposed as a DXL service. This service wrapper delegates to the
%%% OpenWeatherMap REST API.
%%%
%%% openweather.hrl must be edited to include the OpenWeatherMap API
%%% key (see http://openweathermap.org/appid)
%%% @end
%%%-------------------------------------------------------------------

-module(openweather_service_wrapper).

-export([start/0]).

-include("dxl.hrl").
-include("openweather.hrl").


start() ->
    Config = load_config(),
    {ok, Client} = dxlc:start(Config),

    inets:start(),
    Fun = fun({message_in, {_, Message, ClientIn}}) ->
                 #dxlmessage{payload=Payload} = Message,
                 HttpRequest = {build_url(Payload), [{"Content-Type", "application/json"}]},
                 {ok, {{_Version, ResultCode, ReasonPhrase}, _Headers, Body}} = httpc:request(get, HttpRequest, [], []),
                 case ResultCode of
                     200 -> dxlc:send_response(ClientIn, Message, list_to_binary(Body));
                     _ -> dxlc:send_error(ClientIn, Message, #dxlmessage{error_code = ResultCode, error_message = ReasonPhrase})
                 end,
                 ok
          end,

    inets:start(),
    ServiceRegistry = #service_registration{type = ?SERVICE_NAME, topics=#{?SERVICE_CURRENT_WEATHER_TOPIC => Fun}},
    lager:info("Registering service: ~s", [ServiceRegistry#service_registration.type]),
    {ok, ServiceId} = dxlc:register_service(Client, ServiceRegistry, 10000),

    receive
        _ ->
            dxlc:deregister_service_async(Client, ServiceId),
            exit(normal)
    end,
    ok.

build_url(Arg) ->
    binary_to_list(<<?SERVICE_CURRENT_WEATHER_URL_PREFIX, Arg/binary, "&APPID=", ?API_KEY>>).


load_config() ->
    Dir = filename:dirname(filename:absname(".")),
    File = filename:join([Dir, "test", "dxlclient.config"]),
    lager:info("Reading configuration from file: ~s.", [File]),
    {ok, Config} = dxl_client_conf:read_from_file(File),
    Config.