-module(dxl_util).

-export([message_type/1,
	 generate_uuid/0,
	 unique_registration_name/2
	]).

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

generate_uuid() ->
  <<A:32, B:16, C:16, D:16, E:48>> = crypto:strong_rand_bytes(16),
  Str = io_lib:format("~8.16.0b-~4.16.0b-4~3.16.0b-~4.16.0b-~12.16.0b", [A, B, C band 16#0fff, D band 16#3fff bor 16#8000, E]),
  list_to_binary(Str).

unique_registration_name(Mod, UUID) when is_atom(Mod), is_binary(UUID) ->
    Sep = <<"_">>,
    ModName = atom_to_binary(Mod, utf8),
    binary_to_atom(<<UUID/binary, Sep/binary, ModName/binary>>, utf8).
