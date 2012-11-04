wbuildr
=======

web build manager (coffeescript, lesscss ... etc)

Wbuildr is yet another web builder/concatenating/minifying build tool meant mostly for web development. There are an increasing amount of useful server side development libraries like coffee script, uglifyjs, handlebars, sass and lesscss … and many more. There are quite a few build tools for managing these already, but they all suck so I had to make “yet another” one. The others, at least the ones I looked at, tried to do too many things and/or imposed their structure on my projects. I wanted something that was more simple but flexible enough to build and concatenate anything. Below are the requirements I had in mind when developing wbuildr.

1. Different options for development(devel) and production(prod). This would allow me to work with unminified content during development and then get minified versions by simply calling the tool with a different parameter.
2. Flexible enough to work with pretty much any command line tool by tweaking a config file, not just the ones that are baked in.
3. The ability to watch input files and rebuild only the necessary files when something changes so I do not have to deal with a compile step.
4. Should not impose any structure on my project. Just input files and output files.
5. Not try to do other things like include a web server inside the build tool.

running wbuildr with no options gives the following output:

usage: wbuildr watch|build devel|prod [wbuildr.conf]

There are two mandatory parameters and optionally a config file. 

1. watch|build – build triggers a one time build and then terminates. Watch triggers a one time build and then watches all the input files and rebuilds the relevant ones when an input file changes.
2. devel|prod – it is possible to specify different command line options for the tools depending on whether we are developing or making a production build. Commands can also be specified as being the same for devel and prod.
3. [wbuildr.conf] – if no config file is specified, wbuildr.conf is used as the default file.

The primary use case for wbuildr is programs that take filenames as input and print the compiled output to stdout. The contents of stdout are then saved to the output file. With some compilers, like coffee script, you will have to specify an option to have it print the output to stdout. For coffee script this is the “-p” option.

Below is a simple example demonstrating how wbuildr can build a project with coffee script and uglifyjs. The basic idea is to define a set of commands and operations that build something useful with those commands. In this example coffee script uses the same command for devel and prod compiles because it is specified under “both” in the commands section. Uglifyjs uses different options so we have a nice and readable version of the javascript for development and a minified one for production. First the two coffee script files are compiled separately and the output of both commands is stored in an intermediate build folder. When this file has been generated, uglifyjs builds the actual output file and stores it in the output folder.

{commands, [ 
    {both, 
        [{coffee,"coffee -p"}] 
    }, 
    {devel, 
        [{uglify,"uglifyjs -b -nm -nmf -ns"}] 
    }, 
    {prod, 
        [{uglify,"uglifyjs -nc"}] 
    } 
]}. 

{operation, 
    {both, coffee, [ 
        {triggers,[]}, 
        {inputs,["input/coffee1.coffee","input/coffee2.coffee"]}, 
        {output,"build/coffee.js"} 
]}}. 

{operation, 
    {both, uglify, [ 
        {triggers,[]}, 
        {inputs,["build/coffee.js"]}, 
        {output,"output/javascript.js"} 
]}}.

The configuration format is a very human readable set of Erlang tuples (yes, wbuildr is written in Erlang). Remember to include the .'s and ,'s or the Erlang interpreter will punish you. If you get weird pattern matching errors, you probably have a typo in your config file. Below we have a slightly more complicated example demonstrating some more of wbuildr's features.

{commands, [ 
    {both, 
        [{coffee,"coffee -p"}, 
         {handlebars,"handlebars"}] 
    }, 
    {devel, 
        [{uglify,"uglifyjs -b -nm -nmf -ns"}, 
         {lesscss,"lessc"}] 
    }, 
    {prod, 
        [{uglify,"uglifyjs -nc"}, 
         {lesscss,"lessc -yui-compress"}] 
    } 
]}. 

{operation, 
    {both, handlebars, [ 
        {inputs,["input/htest1.handlebars 
                  input/htest2.handlebars"]}, 
        {output,"build/templates.js"} 
]}}. 

{operation, 
    {both, coffee, [ 
        {triggers,[]}, 
        {inputs,["input/coffee1.coffee","input/coffee2.coffee"]}, 
        {output,"build/coffee.js"} 
]}}. 

{operation, 
    {both, uglify, [ 
        {triggers,[]}, 
        {inputs,["build/templates.js","build/coffee.js"]}, 
        {output,"output/javascript.min.js"} 
]}}. 

{operation, 
    {both, concat, [ 
        {inputs,["input/coffee1.coffee","input/coffee2.coffee"]}, 
        {output,"build/coffeeconcat.coffee"} 
]}}. 

{operation, 
    {both, lesscss, [ 
        {triggers,["input/includedfile1.less", "input/includedfile2.less"]}, 
        {inputs,["input/lesscss.less"]}, 
        {output,"output/lesscss.css"} 
]}}. 

The concat command is the only built in command, it will simply generate an output which is a concatenated version of all the inputs.

Observe the following things about this example:

1. The handlebars input has two input files in one input. This will be compiled as one operation "handlebars input/htest1.handlebars input/htest2.handlebars" with only a single space between them (extra white space is stripped away). The files will still be monitored separately. We could have compiled the coffee script files with a single command but I am demonstrating both ways.
2. The coffee script files are compiled separately as "coffee -p input/coffee1.coffee" and "coffee -p input/coffee2.coffee".
3. When either coffee script input changes, a concatenated version is generated. We are not using it for anything, but demonstrating its use.
4. The lesscss input file is recompiled when either trigger file is modified. This is useful if we are using included files in our less files.

This functionality should be flexible enough to work with pretty much any command line tool. Difficult tools may require you to include file names in a command and rebuild based triggers. If the output of the tool is always a file and can not be redirected to stdout, the concat command can be used to move/rename the output file alone or along with other files. Just make sure they are listed in the order that wbuildr should generate them.

To run wbuildr you will need to have Erlang installed (sudo apt-get install erlang under Ubuntu). It should work under windows also, but I have not tested it. Under windows you may need to call the compiled file as “escript.exe wbuildr” (for convenience you can store that command in a wbuildr.bat file). From what I have read, file paths should be cross platform if you consistently use / as the folder separator. You could also use \\, but then it would only work under windows.

Either download the compiled binary (an embedded Erlang escript) located in the rel folder or compile it yourself using rebar. Rebar is the new defacto Erlang build tool, but it is not in any repositories so you will need to download and compile it manually before you can build wbuildr. Once you have done that, compile wbuildr with the following command.

rebar compile escriptize

The output of the compile will be a single binary (wbuildr) stored in apps/wbuildr. Put this in the root of your web development project or somewhere in your path.

