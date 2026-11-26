# Configuration Management

Covers loading and validating runtime configuration for services and CLI tools. For secrets specifically (never logging them, sourcing them safely), see `references/security.md`.

## Precedence

When more than one configuration source exists, resolve them in a fixed, documented order, highest priority first:

1. Explicit command-line flags
2. Environment variables
3. A config file
4. Hardcoded defaults

Implement the precedence once, in one place, rather than letting each config field pick its own resolution order; a reader debugging a wrong value should not have to check five different code paths to find out which source won.

## Environment Variables as the Primary Source

For a service intended to run in a container or orchestrator, treat environment variables as the primary configuration channel (the 12-factor convention), and treat a config file as optional, for local development convenience only.

```go
type Config struct {
    Port           int
    DatabaseURL    string
    LogLevel       string
    RequestTimeout time.Duration
}

func Load() (*Config, error) {
    cfg := &Config{
        Port:           envInt("PORT", 8080),
        LogLevel:       envString("LOG_LEVEL", "info"),
        RequestTimeout: envDuration("REQUEST_TIMEOUT", 30*time.Second),
    }
    cfg.DatabaseURL = os.Getenv("DATABASE_URL")
    if cfg.DatabaseURL == "" {
        return nil, errors.New("DATABASE_URL is required")
    }
    return cfg, nil
}
```

A struct-tag-driven loader (`caarlos0/env`, `kelseyhightower/envconfig`, or similar) removes the boilerplate of a hand-written `env*` helper per field once a config struct grows past a handful of fields:

```go
type Config struct {
    Port           int           `env:"PORT" envDefault:"8080"`
    DatabaseURL    string        `env:"DATABASE_URL,required"`
    LogLevel       string        `env:"LOG_LEVEL" envDefault:"info"`
    RequestTimeout time.Duration `env:"REQUEST_TIMEOUT" envDefault:"30s"`
}
```

Either approach is acceptable; do not mix them within the same service; pick one so every field's source is discoverable the same way.

## Fail Fast

Validate every required setting once, at startup, before the service accepts any traffic or the CLI tool begins its work. A missing or malformed value discovered lazily, on the first request that happens to need it, turns a deployment-time configuration mistake into a production incident hours or days later.

```go
func (c *Config) Validate() error {
    var errs []error
    if c.Port < 1 || c.Port > 65535 {
        errs = append(errs, fmt.Errorf("PORT %d out of range", c.Port))
    }
    if c.DatabaseURL == "" {
        errs = append(errs, errors.New("DATABASE_URL is required"))
    }
    return errors.Join(errs...)
}

func main() {
    cfg, err := Load()
    if err != nil {
        log.Fatalf("load config: %v", err)
    }
    if err := cfg.Validate(); err != nil {
        log.Fatalf("invalid config: %v", err)
    }
    // start serving
}
```

`errors.Join` (Go 1.20+) collects every validation failure into one error, so a misconfigured deployment sees all the problems at once rather than fixing them one restart at a time.

## Secrets in Config Structs

Never let a config struct's default `%v`/`%+v` formatting, or an accidental `slog.Info("config loaded", "config", cfg)` call, print a database password or API key to logs. Implement `String()` (and, if the struct also needs redacted JSON, a custom `MarshalJSON`) to mask sensitive fields:

```go
type Config struct {
    DatabaseURL string
    APIKey      string
}

func (c Config) String() string {
    return fmt.Sprintf("Config{DatabaseURL: %s, APIKey: [REDACTED]}", redactDSN(c.DatabaseURL))
}
```

See `references/security.md` for sourcing secrets (environment variables or a secrets manager, never hardcoded) and for the broader rule against logging credentials.

## Config for Libraries vs Services

A library package should accept configuration through its constructor (functional options or a config struct, see `references/interfaces.md`), never by reading environment variables or files itself. Environment-variable and config-file loading belongs exclusively in `main` or in a dedicated `config` package that `main` calls; a library that reads `os.Getenv` internally cannot be reused in a context with a different configuration source, and cannot be unit tested without mutating process-global state.
