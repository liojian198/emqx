%%--------------------------------------------------------------------
%% Copyright (c) 2020 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_coap_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("gen_coap/include/coap.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("emqx_libs/include/emqx.hrl").

-define(LOGT(Format, Args), ct:pal(Format, Args)).

all() -> emqx_ct:all(?MODULE).

init_per_suite(Config) ->
    emqx_ct_helpers:start_apps([emqx_coap], fun set_sepecial_cfg/1),
    Config.

set_sepecial_cfg(emqx_coap) ->
    Opts = application:get_env(emqx_coap, dtls_opts,[]),
    Opts2 = [{keyfile, emqx_ct_helpers:deps_path(emqx, "etc/certs/key.pem")},
             {certfile, emqx_ct_helpers:deps_path(emqx, "etc/certs/cert.pem")}],
    application:set_env(emqx_coap, dtls_opts, emqx_misc:merge_opts(Opts, Opts2)),
    application:set_env(emqx_coap, enable_stats, true);
set_sepecial_cfg(_) ->
    ok.

end_per_suite(Config) ->
    emqx_ct_helpers:stop_apps([emqx_coap]),
    Config.

%%--------------------------------------------------------------------
%% Test Cases
%%--------------------------------------------------------------------

t_publish(_Config) ->
    Topic = <<"abc">>, Payload = <<"123">>,
    TopicStr = binary_to_list(Topic),
    URI = "coap://127.0.0.1/mqtt/"++TopicStr++"?c=client1&u=tom&p=secret",

    %% Sub topic first
    emqx:subscribe(Topic),

    Reply = er_coap_client:request(put, URI, #coap_content{format = <<"application/octet-stream">>, payload = Payload}),
    {ok, changed, _} = Reply,

    receive
        {deliver, Topic, Msg} ->
            ?assertEqual(Topic, Msg#message.topic),
            ?assertEqual(Payload, Msg#message.payload)
    after
        500 ->
            ?assert(false)
    end.

t_observe(_Config) ->
    Topic = <<"abc">>, TopicStr = binary_to_list(Topic),
    Payload = <<"123">>,
    Uri = "coap://127.0.0.1/mqtt/"++TopicStr++"?c=client1&u=tom&p=secret",
    {ok, Pid, N, Code, Content} = er_coap_observer:observe(Uri), 
    ?LOGT("observer Pid=~p, N=~p, Code=~p, Content=~p", [Pid, N, Code, Content]),

    [SubPid] = emqx:subscribers(Topic),
    ?assert(is_pid(SubPid)),

    %% Publish a message
    emqx:publish(emqx_message:make(Topic, Payload)),

    Notif = receive_notification(),
    ?LOGT("observer get Notif=~p", [Notif]),
    {coap_notify, _, _, {ok,content}, #coap_content{payload = PayloadRecv}} = Notif,
    ?_assertEqual(Payload, PayloadRecv),

    er_coap_observer:stop(Pid),
    timer:sleep(100),

    [] = emqx:subscribers(Topic).

t_observe_wildcard(_Config) ->
    Topic = <<"+/b">>, TopicStr = http_uri:encode(binary_to_list(Topic)),
    Payload = <<"123">>,
    Uri = "coap://127.0.0.1/mqtt/"++TopicStr++"?c=client1&u=tom&p=secret",
    {ok, Pid, N, Code, Content} = er_coap_observer:observe(Uri),
    ?LOGT("observer Uri=~p, Pid=~p, N=~p, Code=~p, Content=~p", [Uri, Pid, N, Code, Content]),

    [SubPid] = emqx:subscribers(Topic),
    ?assert(is_pid(SubPid)),

    %% Publish a message
    emqx:publish(emqx_message:make(Topic, Payload)),

    Notif = receive_notification(),
    ?LOGT("observer get Notif=~p", [Notif]),
    {coap_notify, _, _, {ok,content}, #coap_content{payload = PayloadRecv}} = Notif,
    ?_assertEqual(Payload, PayloadRecv),

    er_coap_observer:stop(Pid),
    timer:sleep(100),

    [] = emqx:subscribers(Topic).

t_observe_pub(_Config) ->
    Topic = <<"+/b">>, TopicStr = http_uri:encode(binary_to_list(Topic)),
    Uri = "coap://127.0.0.1/mqtt/"++TopicStr++"?c=client1&u=tom&p=secret",
    {ok, Pid, N, Code, Content} = er_coap_observer:observe(Uri),
    ?LOGT("observer Pid=~p, N=~p, Code=~p, Content=~p", [Pid, N, Code, Content]),

    [SubPid] = emqx:subscribers(Topic),
    ?assert(is_pid(SubPid)),

    Topic2 = <<"a/b">>, Payload2 = <<"UFO">>,
    TopicStr2 = http_uri:encode(binary_to_list(Topic2)),
    URI2 = "coap://127.0.0.1/mqtt/"++TopicStr2++"?c=client1&u=tom&p=secret",

    Reply2 = er_coap_client:request(put, URI2, #coap_content{format = <<"application/octet-stream">>, payload = Payload2}),
    {ok,changed, _} = Reply2,

    Notif2 = receive_notification(),
    ?LOGT("observer get Notif2=~p", [Notif2]),
    {coap_notify, _, _, {ok,content}, #coap_content{payload = PayloadRecv2}} = Notif2,
    ?_assertEqual(Payload2, PayloadRecv2),

    Topic3 = <<"j/b">>, Payload3 = <<"ET629">>,
    TopicStr3 = http_uri:encode(binary_to_list(Topic3)),
    URI3 = "coap://127.0.0.1/mqtt/"++TopicStr3++"?c=client2&u=mike&p=guess",
    Reply3 = er_coap_client:request(put, URI3, #coap_content{format = <<"application/octet-stream">>, payload = Payload3}),
    {ok,changed, _} = Reply3,

    Notif3 = receive_notification(),
    ?LOGT("observer get Notif3=~p", [Notif3]),
    {coap_notify, _, _, {ok,content}, #coap_content{payload = PayloadRecv3}} = Notif3,
    ?_assertEqual(Payload3, PayloadRecv3),

    er_coap_observer:stop(Pid).

t_one_clientid_sub_2_topics(_Config) ->
    Topic1 = <<"abc">>, TopicStr1 = binary_to_list(Topic1),
    Payload1 = <<"123">>,
    Uri1 = "coap://127.0.0.1/mqtt/"++TopicStr1++"?c=client1&u=tom&p=secret",
    {ok, Pid1, N1, Code1, Content1} = er_coap_observer:observe(Uri1),
    ?LOGT("observer 1 Pid=~p, N=~p, Code=~p, Content=~p", [Pid1, N1, Code1, Content1]),

    [SubPid] = emqx:subscribers(Topic1),
    ?assert(is_pid(SubPid)),

    Topic2 = <<"x/y">>, TopicStr2 = http_uri:encode(binary_to_list(Topic2)),
    Payload2 = <<"456">>,
    Uri2 = "coap://127.0.0.1/mqtt/"++TopicStr2++"?c=client1&u=tom&p=secret",
    {ok, Pid2, N2, Code2, Content2} = er_coap_observer:observe(Uri2),
    ?LOGT("observer 2 Pid=~p, N=~p, Code=~p, Content=~p", [Pid2, N2, Code2, Content2]),

    [SubPid] = emqx:subscribers(Topic2),
    ?assert(is_pid(SubPid)),

    emqx:publish(emqx_message:make(Topic1, Payload1)),

    Notif1 = receive_notification(),
    ?LOGT("observer 1 get Notif=~p", [Notif1]),
    {coap_notify, _, _, {ok,content}, #coap_content{payload = PayloadRecv1}} = Notif1,
    ?_assertEqual(Payload1, PayloadRecv1),

    emqx:publish(emqx_message:make(Topic2, Payload2)),

    Notif2 = receive_notification(),
    ?LOGT("observer 2 get Notif=~p", [Notif2]),
    {coap_notify, _, _, {ok,content}, #coap_content{payload = PayloadRecv2}} = Notif2,
    ?_assertEqual(Payload2, PayloadRecv2),

    er_coap_observer:stop(Pid1),
    er_coap_observer:stop(Pid2).

t_invalid_parameter(_Config) ->
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% "cid=client2" is invaid
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    Topic3 = <<"a/b">>, Payload3 = <<"ET629">>,
    TopicStr3 = http_uri:encode(binary_to_list(Topic3)),
    URI3 = "coap://127.0.0.1/mqtt/"++TopicStr3++"?cid=client2&u=tom&p=simple",
    Reply3 = er_coap_client:request(put, URI3, #coap_content{format = <<"application/octet-stream">>, payload = Payload3}),
    ?assertMatch({error,bad_request}, Reply3),

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% "what=hello" is invaid
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    URI4 = "coap://127.0.0.1/mqtt/"++TopicStr3++"?what=hello",
    Reply4 = er_coap_client:request(put, URI4, #coap_content{format = <<"application/octet-stream">>, payload = Payload3}),
    ?assertMatch({error, bad_request}, Reply4).

t_invalid_topic(_Config) ->
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% "a/b" is a valid topic string
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    Topic3 = <<"a/b">>, Payload3 = <<"ET629">>,
    TopicStr3 = binary_to_list(Topic3),
    URI3 = "coap://127.0.0.1/mqtt/"++TopicStr3++"?c=client2&u=tom&p=simple",
    Reply3 = er_coap_client:request(put, URI3, #coap_content{format = <<"application/octet-stream">>, payload = Payload3}),
    ?assertMatch({ok,changed,_Content}, Reply3),

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% "+?#" is invaid topic string
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    URI4 = "coap://127.0.0.1/mqtt/"++"+?#"++"?what=hello",
    Reply4 = er_coap_client:request(put, URI4, #coap_content{format = <<"application/octet-stream">>, payload = Payload3}),
    ?assertMatch({error,bad_request}, Reply4).

t_stats(_) ->
    ok.

t_auth_failure(_) ->
    ok.

t_qos_supprot(_) ->
    ok.

%%--------------------------------------------------------------------
%% Helpers

receive_notification() ->
    receive
        {coap_notify, Pid, N2, Code2, Content2} ->
            {coap_notify, Pid, N2, Code2, Content2}
    after 2000 ->
        receive_notification_timeout
    end.

