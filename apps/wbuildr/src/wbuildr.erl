-module(wbuildr).

%% Application callbacks
%-export([main/0]).

-compile(export_all).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include_lib("kernel/include/file.hrl" ).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% entrypoint

main(Arg) ->
    Numarg = erlang:length(Arg),

    if
        Numarg < 2 orelse Numarg > 3 ->
            help(),
            halt();
        true ->
            ok
    end,

    [W,R|C] = Arg,

    Watch = case W of
        "watch" ->
            true;
        "build" ->
            false;
        _ ->
            io:format("invalid command: ~p~n", [W]),
            help(),
            halt()
    end,

    Runtype = case R of
        "devel" ->
            devel;
        "prod" ->
            prod;
        _ ->
            io:format("invalid runtype: ~p~n", [R]),
            help(),
            halt()
    end,

    Configfile = case C of
        [] ->
            "wbuildr.conf";
        _ ->
            lists:flatten(C)
    end,

    % io:format("watch: ~p runtype: ~p configfile: ~p~n", [Watch,Runtype,Configfile]),

    runwbuildr(Watch,Runtype,Configfile),
    ok.

runwbuildr(Watch,Runtype,Configfile) ->
    Config = parse_conf_file(Configfile),
    Commands = init_commands(Runtype,Config),
    Operations = init_operations(Runtype,Config),

    % io:format("Operations: ~p~n", [Operations]),
    % io:format("Commands: ~p~n", [Commands]),

    Actions = merge_commands_operations(Commands,Operations,[]),

    % io:format("Actions: ~p~n", [Actions]),

    if
        Watch ->
            loop(Actions);
        true ->
            build(Actions)
    end,
    ok.

help() ->
    io:format("usage: wbuildr watch|build devel|prod [wbuildr.conf]~n"),
    ok.

testme() ->
    io:format("running wbuilder~n"),

    Configfile = "wbuildr.conf",

    Runtype = prod,
    Watch = false,

    runwbuildr(Watch,Runtype,Configfile),
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% loop and build

loop(Actions) ->
    Newactions = build(Actions),
    sleep(500),
    loop(Newactions).

build(Actions) ->
    % io:format("running build~n"),
    _Newactions = lists:map(fun build_action/1, Actions).

build_action({Command,Triggers,Inputs,Output}) ->
    % io:format("action: ~p~n", [Output]),

    {Newtriggers,Forcerebuild} = build_check_triggers(Triggers),

    Newinputs1 = case Forcerebuild of
        true ->
            lists:map(fun({A,_B,C}) -> {A,{{0,0,0},{0,0,0}},C} end, Inputs);
        false ->
            Inputs
    end,

    {Newinputs2,Rebuild} = build_inputs(Command,Newinputs1),

    if
        Rebuild ->
            Data = lists:map(fun({_,_,D}) -> [D,<<"\n">>] end, Newinputs2),
            Bindata = erlang:list_to_binary(Data),
            build_write_output(Bindata,Output);
        true ->
            ok
    end,

    {Command,Newtriggers,Newinputs2,Output}.

build_check_triggers([]) ->
    {[],false};
build_check_triggers(Triggers) ->
    build_check_triggers(Triggers,[],false).

build_check_triggers([],Newtriggers,Forcerebuild) ->
    {lists:reverse(Newtriggers),Forcerebuild};
build_check_triggers([Trigger|T],Newtriggers,Forcerebuild) ->
    {Fname,Mtime} = Trigger,
    Filemtime = build_get_max_mtime(Fname),
    if 
        Filemtime > Mtime ->
            Newtrigger = {Fname,Filemtime},
            build_check_triggers(T,[Newtrigger] ++ Newtriggers, true);
        true ->
            build_check_triggers(T,[Trigger] ++ Newtriggers, Forcerebuild)
    end.

build_write_output(Data,Filename) ->
    if
        Filename == [] ->
            io:format("~s~n", [Data]);
        true ->
            io:format("writing ~p~n", [Filename]),
            filelib:ensure_dir(Filename),
            {ok, S} = file:open(Filename, write),
            io:format(S, "~s~n" ,[Data]),
            file:close(S)
    end.

build_inputs(Command,Inputs) ->
    build_inputs(Command,Inputs,[],false).

build_inputs(_Command,[],Newinputs,Rebuild) ->
    {lists:reverse(Newinputs),Rebuild};
build_inputs(Command,[Input|T],Newinputs,Rebuild) ->
    {Fname,Mtime,Build} = Input,
    Filemtime = build_get_max_mtime(Fname),
    if 
        Filemtime > Mtime ->
            Minput = {Fname,Filemtime,Build},
            Newinput = build_input(Command,Minput),
            build_inputs(Command,T,[Newinput] ++ Newinputs,true);
        true ->
            build_inputs(Command,T,[Input] ++ Newinputs,Rebuild)
    end.

build_get_max_mtime(Fname) ->
    case Fname of
        dummyinput ->
            {{1,1,1},{1,1,1}};
        _ ->
            List = re:split(Fname, " ", [{return,list}]),
            build_get_max_mtime(List,{{0,0,0},{0,0,0}})
    end.
build_get_max_mtime([],Mtime) ->
    Mtime;
build_get_max_mtime([Fname|T],Mtime) ->
    Filemtime = case file:read_file_info(Fname)  of
        {ok,Facts} ->
            Facts#file_info.mtime;
        _ -> 
            io:format("File: ~p not found~n",[Fname]),
            exit("Fatal error: file not found")
    end,
    if
        Filemtime > Mtime ->
            build_get_max_mtime(T,Filemtime);
        true ->
            build_get_max_mtime(T,Mtime)
    end.

build_input(Command,Input) ->
    {Fname,Mtime,_Build} = Input,

    Newbuild = case Command of
        concat ->
            {ok,Data} = file:read_file(Fname),
            Data;
        _ ->
            build_port(Command,Fname)
    end,

    {Fname,Mtime,Newbuild}.

build_port(Command,Target) ->
    Cmd = case Target of
        dummyinput ->
            Command;
        _ ->
            lists:flatten([Command," ",Target])
    end,

    io:format("executing ~p~n",[Cmd]),

    Port = open_port({spawn, Cmd}, [use_stdio, exit_status, binary, stderr_to_stdout]),
    Output = build_port_loop(Port),
    % io:format("Output: ~n~s~n", [Output]).
    Output.

build_port_loop(Port) ->
    build_port_loop(Port,[]).

build_port_loop(Port,Output) ->
    % io:format("entering loop~n"),
    receive
        {Port, {data, Data}} ->
            % {_,Bindata} = split_binary(term_to_binary(Data), 6),
            % io:format("Bindata: ~n~s~n", [Bindata]),
            build_port_loop(Port,Output ++ [Data]);
        {Port, {exit_status, Status}} ->
            % io:format("Exit status: ~n~p~n", [Status]),
            if
                Status =/= 0 ->
                    io:format("~nERROR: NON ZERO EXIT CODE~n~n~s~n", [erlang:list_to_binary(Output)]);
                true ->
                    ok
            end,
            erlang:list_to_binary(Output);
        WTF ->
            io:format("WTF: ~p~n",[WTF]),
            build_port_loop(Port,Output)
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% commands and operations

init_commands(Runtype,Config) ->
    Rawcommands = lists:flatten([X || {commands,X} <- Config]),
    F1 = filter_commands(Runtype,Rawcommands),
    F2 = lists:merge(F1, [{concat,concat}]),
    F2.

init_operations(Runtype,Config) ->
    Rawoperations = [X || {operation,X} <- Config],
    Filteroperations = filter_operations(Runtype,Rawoperations),
    lists:map(fun expand_operation/1, Filteroperations).

merge_commands_operations(_Commands,[],Merged) ->
    lists:reverse(Merged);
merge_commands_operations(Commands,[Operation|T],Merged) ->
    {Command,Triggers,Inputs,Output} = Operation,
    Clinecommand = find_command(Command,Commands),
    Newoperation = {Clinecommand,Triggers,Inputs,Output},
    Newmerged = [Newoperation] ++ Merged,
    merge_commands_operations(Commands,T,Newmerged).

find_command(Command,Commands) ->
    L = lists:filter(fun({Match,_X}) when Match =:= Command -> true; (_) -> false end, Commands),
    if
        L == [] ->
            io:format("Command ~p not found~n", [Command]),
            exit("Fatal error: command not found");
        true ->
            ok
    end,
    [{_,C}] = L,
    C.

filter_commands(Runtype,List) ->
    L1 = lists:foldl(fun({Match,X},Acc) when Match =:= Runtype -> Acc ++ X; (_,Acc) -> Acc end, [], List),
    L2 = lists:foldl(fun({both,X},Acc) -> Acc ++ X; (_,Acc) -> Acc end, [], List),
    lists:merge(L1, L2).

filter_operations(Runtype,Operations) ->
    L1 = lists:filter(fun({Match,_X,_Y}) when Match =:= Runtype -> true; (_) -> false end, Operations),
    L2 = lists:filter(fun({both,_X,_Y}) -> true; (_) -> false end, Operations),
    Clist = lists:merge(L1,L2),
    lists:map(fun({_A,B,C}) -> {B,C} end, Clist).

expand_operation({Command,List}) ->
    Triggers = expand_operation_triggers(List),
    Inputs = expand_operation_inputs(List),
    Output = expand_operation_output(List),
    {Command,Triggers,Inputs,Output}.

expand_operation_output(List) ->
    lists:foldl(fun({output,X},_Acc) -> X; (_,Acc) -> Acc end, [], List).
expand_operation_inputs(List) ->
    Inputmap = fun(I) -> {I,{{0,0,0},{0,0,0}},<<>>} end,
    Inputs = lists:foldl(fun select_and_format_inputs/2, [], List),
    Inputs1 = case Inputs of
        [] ->
            [dummyinput];
        _ ->
            Inputs
    end,
    lists:map(Inputmap, Inputs1).
expand_operation_triggers(List) ->
    Trigmap = fun(I) -> {I,{{0,0,0},{0,0,0}}} end,
    Triggers = lists:foldl(fun({triggers,X},Acc) -> Acc ++ X; (_,Acc) -> Acc end, [], List),
    lists:map(Trigmap, Triggers).

select_and_format_inputs({inputs,X},Acc) ->
    X1 = lists:map(fun trim_whitespace/1, X),
    Acc ++ X1;
select_and_format_inputs(_,Acc) ->
    Acc.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% misc

trim_whitespace(X) ->
    X1 = re:replace(X,"\n", " ",[global,{return,list}]),
    X2 = re:replace(X1,"\r", " ",[global,{return,list}]),
    X3 = re:replace(X2,"\t", " ",[global,{return,list}]),
    X4 = re:replace(X3," +", " ",[global,{return,list}]),
    X4.

parse_conf_file(FN) ->
    case file:consult(FN) of
        {ok,C} ->
            C;
        {error,Reason} ->
            io:format("error reading: ~p~n",[FN]),
            exit(Reason)  
    end.

sleep(T) ->
    receive
    after T -> true
    end.

-ifdef(TEST).

main_test() ->
    ?_assert(1==1).

-endif.
