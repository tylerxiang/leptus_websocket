%% Copyright (c) 2013-2015 Sina Samavati <sina.samv@gmail.com>
%%
%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:
%%
%% The above copyright notice and this permission notice shall be included in
%% all copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%% THE SOFTWARE.

-module(leptus_router).

%% -----------------------------------------------------------------------------
%% API
%% -----------------------------------------------------------------------------
-export([paths/1]).
-export([sort_dispatch/1]).
-export([static_file_routes/1]).

-include("leptus.hrl").

%% -----------------------------------------------------------------------------
%% types
%% -----------------------------------------------------------------------------
-type path_rule() :: {[atom() | binary()], term(), module(), any()}.
-type routes() :: cowboy_router:routes().
-type dispatch() :: cowboy_router:dispatch_rules().

%% -----------------------------------------------------------------------------
%% API
%% -----------------------------------------------------------------------------
-spec paths(leptus:handlers()) -> routes().
paths(Handlers) ->
    handle_routes(Handlers, []).

%% -----------------------------------------------------------------------------
%% order routes the way it matters in cowboy
%% -----------------------------------------------------------------------------
-spec sort_dispatch(Dispatch) -> Dispatch when Dispatch :: dispatch().
sort_dispatch(Dispatch) ->
    %% merge duplicate HostMatches
    F = fun(E = {HostMatch, _, Paths}, Acc) ->
                case lists:keyfind(HostMatch, 1, Acc) of
                    {HostMatch, Constraints, Paths1} ->
                        lists:keystore(HostMatch, 1, Acc, {HostMatch,
                                                           Constraints,
                                                           Paths1 ++ Paths});
                    _ ->
                        [E|Acc]
                end
        end,
    Dispatch1 = lists:foldr(F, [], Dispatch),
    sort_dispatch(Dispatch1, []).

%% -----------------------------------------------------------------------------
%% make routes to serve static files using cowboy static handler
%% -----------------------------------------------------------------------------
static_file_routes({HostMatch, {priv_dir, App, Dir}}) ->
    Dir1 = filename:join(leptus_utils:priv_dir(App), Dir),
    static_file_routes({HostMatch, Dir1});
static_file_routes({HostMatch, Dir}) ->
    Files = static_files(Dir),
    F = fun(E, Acc) ->
                Acc1 = [static_route("/" ++ E, filename:join(Dir, E))|Acc],
                case is_index_file(E) of
                    true ->
                        [static_route(index_url(E), filename:join(Dir, E))|Acc1];
                    false ->
                        Acc1
                end
        end,
    [{HostMatch, lists:foldr(F, [], Files)}].

%% -----------------------------------------------------------------------------
%% internal
%% -----------------------------------------------------------------------------
handle_routes([], Acc) ->
    Acc;
handle_routes([{HostMatch, X}|T], Acc) ->
    %% each module must have routes/0 -> [string()].
    F = fun({Handler, State}, AccIn) ->
                Prefix = handler_prefix(Handler),
                AccIn ++ [new_route(Prefix, Route, Handler, State) ||
                             Route <- Handler:routes()]
        end,
    handle_routes(T, Acc ++ [{HostMatch, lists:foldl(F, [], X)}]).

new_route(Prefix, Route, Handler, HandlerState) ->
    {Prefix ++ Route, leptus_handler, #resrc{route=Route, handler=Handler,
                                             handler_state=HandlerState}}.

%% -----------------------------------------------------------------------------
%% get handler's prefix
%%
%% optional callback: Handler:prefix/0 -> string()
%% e.g. Handler:prefix() -> "/v1"
%% -----------------------------------------------------------------------------
-spec handler_prefix(handler()) -> string().
handler_prefix(Handler) ->
    try Handler:prefix() of
        Prefix -> Prefix
    catch
        error:undef -> ""
    end.

sort_dispatch([], Acc) ->
    Acc;
sort_dispatch([{HM, C, PathRules}|Rest], Acc) ->
    sort_dispatch(Rest, Acc ++ [{HM, C, sort_path_rules(PathRules)}]).

-spec sort_path_rules([path_rule()]) -> [path_rule()].
sort_path_rules([]) ->
    [];
sort_path_rules([Pivot|Rest]) ->
    Y = segments_length(Pivot),
    sort_path_rules([PathRule || PathRule <- Rest, lt(PathRule, Y)])
        ++ [Pivot] ++
        sort_path_rules([PathRule || PathRule <- Rest, egt(PathRule, Y)]).

-spec segments_length(path_rule()) -> integer().
segments_length({['...'], _, _, _}) -> -1;
segments_length({Segments, _, _, _}) ->
    F = fun(Segment, N) ->
                N + segment_val(Segment)
        end,
    lists:foldl(F, 0, Segments).

segment_val(A) when is_atom(A) -> 1;
segment_val(_) -> 0.5.

%% less than
-spec lt(path_rule(), integer()) -> boolean().
lt(_, -1) -> true;
lt(PathRule, Y) ->
    case segments_length(PathRule) of
        -1 -> false;
        N when N < Y -> true;
        _ -> false
    end.

%% equal greater than
-spec egt(path_rule(), integer()) -> boolean().
egt(_, -1) -> false;
egt(PathRule, Y) ->
    case segments_length(PathRule) of
        -1 -> true;
        N when N >= Y -> true;
        _ -> false
    end.

%% -----------------------------------------------------------------------------
%% collect static file names
%% -----------------------------------------------------------------------------
static_files(Dir) ->
    Files = filelib:fold_files(Dir, ".*", true, fun(F, Acc) -> [F|Acc] end, []),
    DirComponentsLength = length(filename:split(Dir)),
    F = fun(File, Acc) ->
                FileComponents = filename:split(File),
                FileComponentsLength = length(FileComponents),
                [filename:join(lists:sublist(FileComponents,
                                             DirComponentsLength + 1,
                                             FileComponentsLength))|Acc]
        end,
    lists:usort(lists:foldr(F, [], Files)).

%% -----------------------------------------------------------------------------
%% check if a file is an index file
%% -----------------------------------------------------------------------------
is_index_file(File) ->
    case filename:basename(File) of
        "index.html" -> true;
        "index.htm" -> true;
        _ -> false
    end.

%% -----------------------------------------------------------------------------
%% prepare index url
%% -----------------------------------------------------------------------------
index_url(File) ->
    case filename:dirname(File) of
        "." -> "/";
        Else -> "/" ++ Else
    end.

%% -----------------------------------------------------------------------------
%% cowboy static handler
%% -----------------------------------------------------------------------------
static_route(Path, File) ->
    {Path, cowboy_static, {file, File}}.

