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
-module(openweather_service_invoker).

%% API
-export([start/0]).

-include("dxl.hrl").
-include("openweather.hrl").

start() ->
    Config = load_config(),
    {ok, Client} = dxlc:start(Config),
    Response = dxlc:send_request(Client, ?SERVICE_CURRENT_WEATHER_TOPIC, <<"zip=97140,us">>),
    process_response(Response),
    ok.

process_response(#dxlmessage{type = response, payload = Payload}) ->
    lager:info("Response: ~p.", [dxl_util:json_bin_to_term(Payload)]);

process_response(#dxlmessage{type = error, error_code = ErrCode, error_message = ErrMsg}) ->
    lager:info("Error: ~p (~p).", [ErrMsg, ErrCode]).

load_config() ->
    Dir = filename:dirname(filename:absname(".")),
    File = filename:join([Dir, "test", "dxlclient.config"]),
    lager:info("Reading configuration from file: ~s.", [File]),
    {ok, Config} = dxl_client_conf:read_from_file(File),
    Config.
