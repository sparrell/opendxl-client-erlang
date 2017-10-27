%%%-------------------------------------------------------------------
%%% @author Chris Waymire <chris@waymire.net>
%%% @doc
%%% This sample demonstrates wrapping an existing service and exposing it on the
%%% DXL fabric.
%%%
%%% In this particular case, the "openweathermap.org" current weather data is
%%% exposed as a DXL service. This service wrapper delegates to the
%%% OpenWeatherMap REST API.
%%% @end
%%%-------------------------------------------------------------------

% The API key for invoking the weather service
-define(API_KEY, "212dfb8d098e739ffb462b4b6cf36d4c").

% The name of the OpenWeatherMap service
-define(SERVICE_NAME, <<"/openweathermap/service/openweathermap">>).

% The "current weather" topic
-define(SERVICE_CURRENT_WEATHER_TOPIC, <<?SERVICE_NAME/binary, "/current">>).

%-define(SERVICE_CURRENT_WEATHER_URL_PREFIX, "http://api.openweathermap.org/data/2.5/weather?").
-define(SERVICE_CURRENT_WEATHER_URL_PREFIX, "http://162.243.53.59/data/2.5/weather?").
