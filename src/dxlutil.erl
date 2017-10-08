-module(dxlutil).

-export([message_type/1]).

-include("dxl.hrl").

message_type(0) -> request;
message_type(1) -> response;
message_type(2) -> event;
message_type(3) -> error;
message_type(request) -> 0;
message_type(response) -> 1;
message_type(event) -> 2;
message_type(error) -> 3;
message_type(_) -> invalid.

