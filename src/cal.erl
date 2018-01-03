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

-module(cal).
-author("Vitor Enes <vitorenesduarte@gmail.com>").

-include("cal.hrl").

-behaviour(gen_server).

%% API
-export([start_link/0,
         run/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2]).

-record(state, {kuberl_cfg :: maps:map()}).

-spec start_link() -> {ok, pid()} | ignore | error().
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Run an experiment.
-spec run(exp_spec()) -> ok | error().
run(Exp) ->
    gen_server:call(?MODULE, {run, Exp}, infinity).

init([]) ->
    lager:info("cal initialized!"),

    %% init kuberl
    %Cfg = kuberl:cfg_with_host("kubernetes.default"),
    Cfg = #{},

    {ok, #state{kuberl_cfg=Cfg}}.

handle_call({run, Experiment}, _From, #state{kuberl_cfg=Cfg}=State) ->
    run(Experiment, Cfg),
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private Run an experiment given its config and kuberl config.
run(Experiment, Cfg) ->
    #{<<"experiment">> := EntrySpecs} = Experiment,
    ExpId = cal_exp:exp_id(),

    lists:foreach(
        fun(EntrySpec) ->
            %% extract number of replicas of this entry
            #{<<"replicas">> := Replicas} = EntrySpec,

            lists:foreach(
                fun(PodId) ->
                    %% pod body
                    Body = cal_exp:pod_body(ExpId,
                                            PodId,
                                            EntrySpec),

                    %% create pod
                    Ctx = ctx:background(),
                    Namespace = <<"default">>,
                    R = kuberl_core_v1_api:create_namespaced_pod(
                        Ctx,
                        Namespace,
                        Body,
                        #{cfg => Cfg}
                    ),
                    lager:info("Response ~p", [R])

                end,
                lists:seq(1, Replicas)
            )
        end,
        EntrySpecs
    ).