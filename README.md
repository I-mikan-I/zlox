# ZLox

A stack-based bytecode Virtual Machine for the [Lox Programming Language](https://craftinginterpreters.com/the-lox-language.html) written in [Zig](https://ziglang.org/).

## Run

Start REPL:  
```bash
$ zig build run
> print 1+1;
2
>
```

## Test

```bash
$ zig build test
All tests passed.
```

## Troubleshoot

Enable tracing:  
```bash
$ zig build -Denable-tracing
```

Enable disassembly:  
```bash
$ zig build -Denable-dump
```

For more build options use `zig build --help`