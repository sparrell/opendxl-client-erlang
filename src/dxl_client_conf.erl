-module(dxl_client_conf).

-export([read_from_file/1,
	 get_value/3
	]).

read_from_file(Filename) ->
    case dxl_util:parse_ini(Filename) of
        {ok, Config} ->
            BrokerCertChain = get_value('Certs', 'BrokerCertChain', Config, []),
            CertFile = get_value('Certs', 'CertFile', Config, []),
            PrivateKey = get_value('Certs', 'PrivateKey', Config, []),

            Brokers = get_value('Brokers', Config, []),
            Hosts = parse_brokers(Brokers),

            ClientId = get_value('General', 'ClientId', Config, dxl_util:generate_uuid()),
            KeepAlive = binary_to_integer(get_value('General', 'KeepAlive', Config, <<"600">>)),
            ConnectRetries = binary_to_integer(get_value('General', 'ConnectRetries', Config, <<"3">>)),
            ReconnDelayMin = binary_to_integer(get_value('General', 'ReconnectDelayMin', Config, <<"1">>)),
            ReconnDelayMax = binary_to_integer(get_value('General', 'ReconnectDelayMax', Config, <<"30">>)),

	    {ok, [{client_id, ClientId},
              {brokers, Hosts},
              {keepalive, KeepAlive},
              {ssl, [
                  {cacertfile, BrokerCertChain},
                  {certfile, CertFile},
                  {keyfile, PrivateKey}
              ]},
              {reconnect, {ReconnDelayMin, ReconnDelayMax, ConnectRetries}}]};
        Error ->
            Error
    end.

get_value(SectionName, Config, Default) ->
    proplists:get_value(SectionName, Config, Default).

get_value(SectionName, KeyName, Config, Default) ->
    Section = proplists:get_value(SectionName, Config, []),
    proplists:get_value(KeyName, Section, Default).

parse_brokers(Brokers) ->
    parse_brokers(Brokers, []).

parse_brokers([{_, BrokerStr} | Brokers], Hosts) ->
    [_Id, Port, _Hostname, Addr] = binary:split(BrokerStr, <<";">>, [global]),
    parse_brokers(Brokers, [{binary_to_list(Addr), binary_to_integer(Port)} | Hosts]);

parse_brokers([], Hosts) ->
    Hosts.
