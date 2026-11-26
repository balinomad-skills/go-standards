# CLI Applications

Covers building command-line tools: the `flag` package, Cobra conventions, exit codes, and stream discipline. For loading configuration that a CLI tool also needs (env vars, config files), see `references/configuration.md`.

## flag Package

The standard `flag` package is sufficient for a tool with a handful of top-level options and no subcommands:

```go
var (
    verbose = flag.Bool("verbose", false, "enable verbose logging")
    output  = flag.String("output", "", "output file path (required)")
)

func main() {
    flag.Parse()
    if *output == "" {
        fmt.Fprintln(os.Stderr, "error: -output is required")
        flag.Usage()
        os.Exit(2)
    }
    args := flag.Args() // positional arguments after flags
    // ...
}
```

Reach for Cobra (or a similar framework) once the tool needs subcommands, persistent flags shared across them, or shell completion; hand-rolling that on top of `flag` reproduces most of what Cobra already provides.

## Cobra Conventions

```go
var rootCmd = &cobra.Command{
    Use:   "mytool",
    Short: "mytool does X",
}

var deployCmd = &cobra.Command{
    Use:   "deploy",
    Short: "Deploy the application",
    RunE: func(cmd *cobra.Command, args []string) error {
        return runDeploy(cmd.Context(), args)
    },
}

func init() {
    rootCmd.AddCommand(deployCmd)
    deployCmd.Flags().StringP("env", "e", "staging", "target environment")
    rootCmd.PersistentFlags().Bool("json", false, "output as JSON")
}
```

Use `RunE`, not `Run`, on every command that can fail. `RunE` returns an `error`, which Cobra surfaces through `Execute()`'s return value; `Run` has no return path for failure short of calling `os.Exit` directly inside the handler, which bypasses cleanup and makes the command untestable as a plain function call.

### Non-runnable parent commands silently exit 0 on a typo

A parent command that only groups subcommands, and declares no `RunE` of its own, is not "runnable." Cobra's dispatch checks runnability before argument validation: a non-runnable command with an unrecognized subcommand falls through to printing help and returning `nil`, which the process reports as a successful exit.

```go
// Bug: "mytool db" with a mistyped subcommand, e.g. "mytool db mgirate",
// prints db's help text and exits 0. A CI script checking $? sees success.
var dbCmd = &cobra.Command{
    Use:   "db",
    Short: "Database operations",
}
```

Give every group command an explicit `RunE` (even one that just returns `cmd.Help()`) plus an `Args` validator that rejects unrecognized subcommands, so a typo produces a non-zero exit instead of a quiet no-op:

```go
var dbCmd = &cobra.Command{
    Use:       "db",
    Short:     "Database operations",
    ValidArgs: []string{"migrate", "seed"},
    Args:      cobra.MatchAll(cobra.OnlyValidArgs, rejectUnknownSubcommand),
    RunE: func(cmd *cobra.Command, args []string) error {
        return cmd.Help()
    },
}

// rejectUnknownSubcommand turns "mytool db <typo>" into a non-zero exit.
func rejectUnknownSubcommand(cmd *cobra.Command, args []string) error {
    if len(args) == 0 {
        return nil
    }
    for _, sub := range cmd.Commands() {
        if sub.Name() == args[0] || sub.HasAlias(args[0]) {
            return nil
        }
    }
    return fmt.Errorf("unknown subcommand %q for %q", args[0], cmd.Name())
}
```

`ValidArgs` drives shell completion and `cobra.OnlyValidArgs`; keep it in sync with the actual subcommand names. The helper catches a typo even when `ValidArgs` is stale.

Any CLI whose exit code gates a pipeline step, including one driven by an agent or a script reading `$?`, depends on this being correct; a "successful" exit on a mistyped subcommand is a silent failure one level up.

## Exit Codes and defer

**Deferred functions do not run after `os.Exit`.** `os.Exit` terminates the process immediately; it does not unwind the goroutine stack, so any `defer` registered up to that point, including cleanup, flushes, and unlocks, never executes.

```go
// Bug: file.Close() never runs; os.Exit terminates before the defer fires
func main() {
    file, _ := os.Create("out.txt")
    defer file.Close()
    if err := process(); err != nil {
        os.Exit(1)
    }
}

// Fix: return the error from a run() function; call os.Exit only at the
// very top level, after run() (and every defer inside it) has returned
func main() {
    if err := run(); err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }
}

func run() error {
    file, err := os.Create("out.txt")
    if err != nil {
        return err
    }
    defer file.Close() // runs correctly, because run() returns normally
    return process()
}
```

Reserve `os.Exit` for `main()` itself, called after every other function has already returned. Use standard exit codes:

| Code | Meaning                             |
| ---- | ----------------------------------- |
| 0    | Success                             |
| 1    | General error                       |
| 2    | Usage error, bad flags or arguments |

Define named constants for any domain-specific codes beyond these three, rather than scattering bare integers through the codebase.

## Signal Handling

```go
ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
defer stop()

if err := run(ctx); err != nil && !errors.Is(err, context.Canceled) {
    fmt.Fprintln(os.Stderr, err)
    os.Exit(1)
}
```

`signal.NotifyContext` (Go 1.16+) cancels the returned context on the first matching signal and restores default signal handling once `stop()` is called, so a second Ctrl-C during a slow shutdown still forces an immediate exit rather than being silently absorbed.

## stdin, stdout, stderr

Write data the caller may pipe or redirect to **stdout**. Write logs, progress, and diagnostics to **stderr**. Never mix the two; a tool that writes a log line to stdout corrupts the output of `mytool export | jq .` for every caller downstream.

```go
fmt.Println(result)                       // stdout: the actual output
fmt.Fprintln(os.Stderr, "processing...")  // stderr: progress, safe to ignore
```
