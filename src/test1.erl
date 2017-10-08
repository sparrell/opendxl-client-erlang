-module(test1).

-export([ foo/2 ]).

foo({Type, Topic, Message}, DxlClient) ->
    io:format("test:foo() called: Type=~p, Topic=~p~n", [Type, Topic]),
    ok.
