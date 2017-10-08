-define(MESSAGE_TYPE_REQUEST,  0).
-define(MESSAGE_TYPE_RESPONSE, 1).
-define(MESSAGE_TYPE_EVENT,    2).
-define(MESSAGE_TYPE_ERROR,    3).

-define(DXL_PROTO_VERSION, 2).

-define(DEF_VERSION, 2).
-define(DEF_MESSAGE_ID, <<"">>).
-define(DEF_SRC_CLIENT_ID, <<"">>).
-define(DEF_SRC_BROKER_ID, <<"">>).
-define(DEF_BROKER_IDS, []).
-define(DEF_CLIENT_IDS, []).
-define(DEF_PAYLOAD, <<"">>).
-define(DEF_OTHER_FIELDS, []).
-define(DEF_SRC_TENANT_ID, <<"">>).
-define(DEF_DST_TENANT_IDS, []).
-define(DEF_REPLY_TO_TOPIC, <<"">>).
-define(DEF_SERVICE_ID, <<"">>).
-define(DEF_REQ_MESSAGE_ID, <<"">>).
-define(DEF_ERR_CODE, <<"">>).
-define(DEF_ERR_MESSAGE, <<"">>).

-define(DEF_REQ_TIMEOUT, (60 * 60 * 1000)).
