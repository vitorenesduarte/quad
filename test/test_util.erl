%% -------------------------------------------------------------------
%%
%% Copyright (c) 2018 Vitor Enes. All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-module(test_util).
-author("Vitor Enes <vitorenesduarte@gmail.com>").

-include("tricks.hrl").

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(LOCALHOST, {127, 0, 0, 1}).

%% API
-export([event_register/2,
         event_subscribe/2,
         event_expect/2,
         event_expect/3,
         discovery_register/3,
         discovery_unregister/3,
         discovery_expect/3,
         discovery_expect/4,
         client_event_register/2,
         client_event_subscribe/2,
         client_event_expect/2,
         client_discovery_expect/3,
         client_connect/0,
         client_disconnect/0,
         example_run/1,
         start/0,
         stop/0]).

%% @doc Register an event.
event_register(ExpId, EventName0) ->
    EventName = tricks_util:parse_binary(EventName0),
    ok = rpc:call(get(node),
                  tricks_event_manager,
                  register,
                  [ExpId, EventName]).

%% @doc Subscribe to an event.
event_subscribe(ExpId, Event0) ->
    Event = tricks_util:parse_event(Event0),
    ok = rpc:call(get(node),
                  tricks_event_manager,
                  subscribe,
                  [ExpId, Event, self()]).

%% @doc Expect an event.
%%      Fail if it does not meet expectations after 1 second.
event_expect(ExpId, Event) ->
    event_expect(ExpId, Event, 1).

%% @doc Expect an event.
%%      Fail if it does not meet expectations after `Wait' seconds.
event_expect(ExpId, Event0, Wait) ->
    Event = tricks_util:parse_event(Event0),
    receive
        {notification, ExpId, Event} ->
            ok;
        {notification, A, B} ->
            ct:fail("Wrong event [~p] ~p", [A, B])
    after
        Wait * 1000 ->
            ct:fail("No event")
    end.

%% @doc Register a pod.
discovery_register(ExpId, Tag0, Body) ->
    Tag = tricks_util:parse_binary(Tag0),
    ok = rpc:call(get(node),
                  tricks_discovery_manager,
                  register,
                  [ExpId, Tag, Body]).

%% @doc Unregister a pod.
discovery_unregister(ExpId, Tag0, Body) ->
    Tag = tricks_util:parse_binary(Tag0),
    ok = rpc:call(get(node),
                  tricks_discovery_manager,
                  unregister,
                  [ExpId, Tag, Body]).

%% @doc Expect a discovery.
%%      Fail if it does not meet expectations.
discovery_expect(ExpId, Tag, Ids) ->
    discovery_expect(ExpId, Tag, Ids, 0).

%% @doc Expect a discovery.
%%      Fail if it does not meet expectations.
discovery_expect(ExpId, Tag0, IdsExpected, Seconds) ->
    Tag = tricks_util:parse_binary(Tag0),
    {ok, Data} = rpc:call(get(node),
                          tricks_discovery_manager,
                          discover,
                          [ExpId, Tag]),

    %% extract ids from pod data
    Ids = [Id || {Id, _Ip} <- Data],

    case lists:sort(Ids) == lists:sort(IdsExpected) of
        true ->
            ok;
        false ->
            case Seconds of
                0 ->
                    ct:fail("Wrong discovery [~p] ~p",
                            [ExpId, Ids]);
                _ ->
                    %% wait 1 second and try again
                    timer:sleep(1000),
                    discovery_expect(ExpId,
                                     Tag,
                                     IdsExpected,
                                     Seconds - 1)
            end
    end.

%% @doc Register an event by client.
client_event_register(ExpId, EventName0) ->
    EventName = tricks_util:parse_binary(EventName0),
    Message = tricks_client_message:encode(ExpId, {event, EventName}),
    ok = tricks_client_socket:send(get(socket), Message).

%% @doc Subscribe to an event by client.
client_event_subscribe(ExpId, Event0) ->
    Event = tricks_util:parse_event(Event0),
    Message = tricks_client_message:encode(ExpId, {subscription, Event}),
    ok = tricks_client_socket:send(get(socket), Message).

%% @doc Expect an event by client.
%%      Fail if it does not meet expectations.
client_event_expect(ExpId, Event0) ->
    Event = tricks_util:parse_event(Event0),
    {ok, Bin} = tricks_client_socket:recv(get(socket)),

    #{expId := MExpId,
      type := <<"notification">>,
      eventName := MEventName,
      value := MValue} = tricks_client_message:decode(Bin),
    MEvent = {MEventName, MValue},

    case ExpId == MExpId andalso
         Event == MEvent of
        true ->
            ok;
        false ->
            ct:fail("Wrong event [~p] ~p", [MExpId, MEvent])
    end.

%% @doc Expect a discovery by client.
%%      Fail if it does not meet expectations.
client_discovery_expect(ExpId, Tag0, IdsExpected) ->
    Tag = tricks_util:parse_binary(Tag0),

    %% send request
    Message = tricks_client_message:encode(ExpId, {discovery, Tag}),
    ok = tricks_client_socket:send(get(socket), Message),

    %% receive reply
    {ok, Bin} = tricks_client_socket:recv(get(socket)),

    #{expId := MExpId,
      type := <<"pods">>,
      tag := MTag,
      pods := Data} = tricks_client_message:decode(Bin),

    %% extract ids from pod data
    Ids = [Id || #{id := Id,
                   ip := _Ip} <- Data],

    case ExpId == MExpId andalso
         Tag == MTag andalso
         lists:sort(Ids) == lists:sort(IdsExpected) of
        true ->
            ok;
        false ->
            ct:fail("Wrong discovery [~p] ~p", [ExpId, Ids])
    end.

%% @doc Connect to tricks.
client_connect() ->
    Port = rpc:call(get(node),
                    tricks_config,
                    get,
                    [port]),
    {ok, Socket} = tricks_client_socket:connect(?LOCALHOST, Port),
    ok = tricks_client_socket:configure(Socket),
    put(socket, Socket),
    ok.

%% @doc Disconnect from tricks.
client_disconnect() ->
    ok = tricks_client_socket:disconnect(get(socket)).

%% @doc Run an example.
example_run(Name) ->
    {ok, ExpId} = rpc:call(get(node),
                           tricks_example,
                           run,
                           [home_dir(), Name]),
    ExpId.

%% @doc Start app.
start() ->
    start_erlang_distribution(),

    Config = [{monitor_master, true},
              {boot_timeout, 10},
              {startup_functions, [{code, set_path, [codepath()]}]}],

    %% start node
    Node = case ct_slave:start(?APP, Config) of
        {ok, N} ->
            N;
        Error ->
            ct:fail(Error)
    end,

    %% load tricks 
    ok = rpc:call(Node, application, load, [?APP]),

    %% set lager log dir
    NodeDir = filename:join([home_dir(),
                             ".lager",
                             Node]),
    ok = rpc:call(Node,
                  application,
                  set_env,
                  [lager, log_root, NodeDir]),

    %% ensure started
    {ok, _} = rpc:call(Node,
                       application,
                       ensure_all_started,
                       [?APP]),

    put(node, Node),
    ok.

%% @doc Stop app.
stop() ->
    case ct_slave:stop(?APP) of
        {ok, _} ->
            ok;
        Error ->
            ct:fail(Error)
    end.

%% @private Start erlang distribution.
start_erlang_distribution() ->
    os:cmd(os:find_executable("epmd") ++ " -daemon"),

    {ok, Hostname} = inet:gethostname(),
    Runner = list_to_atom("runner@" ++ Hostname),

    case net_kernel:start([Runner, shortnames]) of
        {ok, _} ->
            ok;
        {error, {already_started, _}} ->
            ok
    end.

%% @private
codepath() ->
    lists:filter(fun filelib:is_dir/1, code:get_path()).

%% @private
home_dir() ->
    os:getenv("TRICKS_HOME", "~/tricks").
