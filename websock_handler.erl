-module(websock_handler).
-author("tyler.xiang").
-behaviour(cowboy_http_handler).
-behaviour(cowboy_websocket_handler).

-export([init/3,handle/2,terminate/3]).
-export([websocket_init/3,websocket_handle/3,websocket_info/3,websocket_terminate/3]).

init({tcp,http}, _Req, _Opts) ->
	{upgrade, protocol, cowboy_websocket}.

handle(_, State) ->  
	{ok, Req2} = cowboy_http_req:reply(404, [{'Content-Type', <<"text/html">>}]),  
	{ok, Req2, State}.  
  
websocket_init(_TransportName, Req, _Opts) ->  
	{ok, Req, undefined_state}.  
  
websocket_terminate(_Reason, _Req, _State) ->  
	ok.  

websocket_handle({text, Msg}, Req, State) ->  
	{reply, {text, << Msg/binary >>}, Req, State };

websocket_handle(_Any, Req, State) ->  
	{ok, Req, State}.
	%{reply, {text, << "whut?">>}, Req, State, hibernate }.  
  
websocket_info(_Info, Req, State) ->  
	{ok, Req, State}.  
  
  
terminate(_Reason, _Req, _State) ->  
	ok.  

