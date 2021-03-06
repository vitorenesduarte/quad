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

-module(tricks_event_manager).
-author("Vitor Enes <vitorenesduarte@gmail.com>").

-include("tricks.hrl").

-behaviour(gen_server).

%% API
-export([start_link/0,
         register/2,
         subscribe/3]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2]).

-type exp_data() :: #{events => dict:dict(event_name(), integer()),
                      subs   => dict:dict(event(),      [pid()])}.
-define(EMPTY_EXP_DATA,
        #{events => dict:new(),
          subs   => dict:new()}).

-record(state, {exp_to_data :: dict:dict(exp_id(), exp_data())}).


-spec start_link() -> {ok, pid()} | ignore | error().
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Register the occurrence of an event.
-spec register(exp_id(), event_name()) -> ok | error().
register(ExpId, EventName)
  when is_binary(ExpId), is_binary(EventName) ->
    gen_server:cast(?MODULE, {register, ExpId, EventName}).

%% @doc Subscribe an event.
%%      When and event has occurred a certain
%%      number of times, a message {notification, exp_id(), event()}
%%      is sent to the process with the pid
%%      passed as argument.
%%
%%      IMPORTANT: if there are two subscriptions from the same
%%      process for the same event,
%%      only one notification is sent.
-spec subscribe(exp_id(), event(), pid()) -> ok | error().
subscribe(ExpId, {Name, Value}=Event, Pid)
  when is_binary(ExpId), is_binary(Name), is_integer(Value), is_pid(Pid) ->
    gen_server:call(?MODULE, {subscribe, ExpId, Event, Pid}, infinity).

init([]) ->
    lager:info("tricks event manager initialized!"),

    {ok, #state{exp_to_data=dict:new()}}.

handle_call({subscribe, ExpId, {EventName, Value}=Event , Pid}, _From,
            #state{exp_to_data=ETD0}=State) ->
    lager:info("Subscription [~p] ~p", [ExpId, Event]),

    D0 = tricks_util:dict_find(ExpId, ETD0, ?EMPTY_EXP_DATA),
    #{events := Events,
      subs := Subs0} = D0,

    Current = tricks_util:dict_find(EventName, Events, 0),
    Subs1 = case Current >= Value of
        true ->
            %% event has already happen,
            %% send notification
            %% and don't subscribe
            notify(Pid, ExpId, Event),
            Subs0;
        false ->
            %% otherwise subscribe
            dict:append(Event, Pid, Subs0)
    end,

    %% update subs
    D1 = D0#{subs => Subs1},
    ETD1 = dict:store(ExpId, D1, ETD0),
    {reply, ok, State#state{exp_to_data=ETD1}}.

handle_cast({register, ExpId, EventName}, #state{exp_to_data=ETD0}=State) ->
    lager:info("Event [~p] ~p", [ExpId, EventName]),

    D0 = tricks_util:dict_find(ExpId, ETD0, ?EMPTY_EXP_DATA),
    #{events := Events0,
      subs := Subs} = D0,

    Events1 = dict:update_counter(EventName, 1, Events0),
    Value = dict:fetch(EventName, Events1),

    %% check if there's a subscription on this event
    Event = {EventName, Value},
    case dict:find(Event, Subs) of
        {ok, Pids} ->
            %% if there is, notify all pids
            UniquePids = ordsets:from_list(Pids),
            lager:info("Notifying ~p!", [length(UniquePids)]),

            [notify(Pid, ExpId, Event) || Pid <- UniquePids];
        error ->
            ok
    end,

    %% remove subscription
    Subs1 = dict:erase(Event, Subs),

    %% update events and subs
    D1 = D0#{events => Events1,
             subs => Subs1},
    ETD1 = dict:store(ExpId, D1, ETD0),
    {noreply, State#state{exp_to_data=ETD1}}.

%% @private
notify(Pid, ExpId, Event) ->
    Pid ! {notification, ExpId, Event}.
