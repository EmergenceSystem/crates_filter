%%%-------------------------------------------------------------------
%%% @doc crates.io Rust package search agent.
%%%
%%% Searches the crates.io API for Rust crates and returns embryos
%%% with name, description, version, and download count.
%%%
%%% Deduplication by URL is handled upstream by the Emquest pipeline.
%%%
%%% === Capability cascade ===
%%%
%%%   base_capabilities/0 extends em_filter:base_capabilities().
%%%
%%% Handler contract: handle/2 (Body, Memory) -> {RawList, Memory}.
%%% @end
%%%-------------------------------------------------------------------
-module(crates_filter_app).
-behaviour(application).

-export([start/2, stop/1]).
-export([handle/2, base_capabilities/0]).

-define(SEARCH_URL,
    "https://crates.io/api/v1/crates?per_page=10&q=").

%%====================================================================
%% Capability cascade
%%====================================================================

-spec base_capabilities() -> [binary()].
base_capabilities() ->
    em_filter:base_capabilities() ++ [<<"crates">>, <<"rust">>,
                                      <<"packages">>, <<"cargo">>].

%%====================================================================
%% Application behaviour
%%====================================================================

start(_Type, _Args) ->
    em_filter:start_agent(crates_filter, ?MODULE, #{
        capabilities => base_capabilities()
    }),
    {ok, self()}.

stop(_State) ->
    em_filter:stop_agent(crates_filter).

%%====================================================================
%% Agent handler
%%====================================================================

handle(Body, Memory) when is_binary(Body) ->
    {generate_embryo_list(Body), Memory};
handle(_Body, Memory) ->
    {[], Memory}.

%%====================================================================
%% Search and processing
%%====================================================================

generate_embryo_list(JsonBinary) ->
    {Query, Timeout} = extract_params(JsonBinary),
    fetch_results(Query, Timeout).

extract_params(JsonBinary) ->
    try json:decode(JsonBinary) of
        Map when is_map(Map) ->
            Query   = binary_to_list(maps:get(<<"value">>, Map,
                          maps:get(<<"query">>, Map, <<"">>))),
            Timeout = case maps:get(<<"timeout">>, Map, undefined) of
                undefined            -> 10;
                T when is_integer(T) -> T;
                T when is_binary(T)  -> binary_to_integer(T)
            end,
            {Query, Timeout};
        _ ->
            {binary_to_list(JsonBinary), 10}
    catch
        _:_ -> {binary_to_list(JsonBinary), 10}
    end.

fetch_results("", _) -> [];
fetch_results(Query, Timeout) ->
    Url = lists:flatten(io_lib:format("~s~s", [?SEARCH_URL, uri_string:quote(Query)])),
    %% crates.io requires a User-Agent identifying the application
    Headers = [{"User-Agent", "crates_filter/1.0 (EmergenceSystem)"}],
    case httpc:request(get, {Url, Headers},
                       [{timeout, Timeout * 1000},
                        {ssl, [{verify, verify_none}]}],
                       [{body_format, binary}]) of
        {ok, {{_, 200, _}, _, Body}} ->
            parse_results(Body);
        _ ->
            []
    end.

parse_results(JsonBin) ->
    try json:decode(JsonBin) of
        #{<<"crates">> := Crates} when is_list(Crates) ->
            lists:filtermap(fun build_embryo/1, Crates);
        _ ->
            []
    catch
        _:_ -> []
    end.

build_embryo(#{<<"name">> := Name} = Crate) ->
    Desc      = maps:get(<<"description">>,   Crate, <<"">>),
    Version   = maps:get(<<"newest_version">>, Crate, <<"">>),
    Downloads = maps:get(<<"downloads">>,      Crate, 0),
    Url       = lists:flatten(io_lib:format(
        "https://crates.io/crates/~s", [binary_to_list(Name)])),
    Resume    = format_resume(Desc, Version, Downloads),
    {true, #{
        <<"properties">> => #{
            <<"url">>       => list_to_binary(Url),
            <<"resume">>    => Resume,
            <<"title">>     => Name,
            <<"version">>   => Version,
            <<"downloads">> => Downloads,
            <<"source">>    => <<"crates.io">>
        }
    }};
build_embryo(_) ->
    false.

format_resume(Desc, Version, Downloads) ->
    D = if is_binary(Desc) -> binary_to_list(Desc); true -> "" end,
    V = if is_binary(Version) -> " v" ++ binary_to_list(Version); true -> "" end,
    Dl = if is_integer(Downloads), Downloads > 0 ->
                " — " ++ integer_to_list(Downloads) ++ " downloads";
            true -> ""
         end,
    list_to_binary(D ++ V ++ Dl).
