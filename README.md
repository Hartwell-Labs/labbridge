# LabBridge — Rust ⇄ Ruby bridge

> **"Can I write my talus plugin in Ruby?"** — yes. LabBridge translates a
> defined subset of Hartwell Labs Rust into clean, runnable Ruby — and Ruby
> plugins back into Rust for the hosts.

Part of the **Hartwell Labs** toolchain — built for
[talus](https://github.com/BartoszOsiej/talus-process-monitor) ·
[externum](https://github.com/BartoszOsiej/externum) ·
[Aurora OS](https://github.com/BartoszOsiej/Aurora).
A Hartwell Labs product. Ruby · zero runtime dependencies.

## Lab rule: verified targets only

LabBridge works **only and exclusively** on Hartwell Labs programs. Every
translation with `--target` verifies the target against the
[Products Registry API](https://github.com/Hartwell-Labs/products)
(`LabBridge::Registry`) — first the API, then the magic. Set
`PRODUCTS_API_URL` to point at a live registry; falls back to the built-in
catalog when unreachable.

```console
$ labbridge r2ruby tool.rs --target nuclear-plant
labbridge: target 'nuclear-plant' is not a verified Hartwell Labs product (allowed: talus, aurora, externum)

$ labbridge targets   # prints the verified catalog (live API or built-in)
```

## Usage

```console
$ labbridge r2ruby file.rs -o file.rb --target talus   # Rust -> Ruby (verified target)
$ labbridge r2rust plugin.rb -o plugin.rs              # Ruby plugin -> Rust (LabPlugin trait)
$ labbridge roundtrip plugin.rb                        # ruby -> rust -> ruby sanity check
$ labbridge manifest plugin.rb                         # print plugin manifest as JSON
$ labbridge targets                                    # list verified lab products
```

### Rust → Ruby

```rust
fn verdict_for(pid: i64, score: i64) -> String {
    if score > 900 { return format!("pid {}: SIGKILL", pid); }
    0
}
```
becomes runnable Ruby (`format!` → interpolation, `for` → `.each`, casts →
`to_i`/`to_f`, `Vec`/`HashMap` constructors, `println!` with args → string
interpolation). Unsupported constructs are never dropped silently — they
come out as `# TODO(labbridge)` comments, so generated code stays auditable.

### Ruby → Rust (plugin feedback coupling)

A Ruby plugin is any file with a manifest header:

```ruby
# hartwell-lab-plugin: name=event-counter target=talus version=1.0.0
class EventCounter
  def init; end
  def handle_event(event) = puts event
end
```

`labbridge r2rust` emits a Rust file implementing the `LabPlugin` trait
(`init`/`handle_event` returning `LabResult`, plus `LabPluginRegistration`
constants with name/target/version) — drop it into the host crate and go.

## Try it (60 seconds)

```bash
git clone https://github.com/Hartwell-Labs/labbridge && cd labbridge
bin/labbridge r2ruby examples/ransomware_score.rs --target talus | ruby
# total=970
# pid 4242: SIGKILL
bin/labbridge roundtrip examples/event_counter.rb
ruby -Ilib test/labbridge_test.rb   # 10 runs, 0 failures
```

## Design notes

- **Deterministic line-oriented translation** — same input, same output, no LLM in the loop.
- **Subset by design** — the supported Rust surface is explicit; anything
  outside it becomes a visible TODO, not a guess (the "only HL programs" contract).
- **Auditable output** — generated files read like hand-written code with
  `# returns:` type hints; roundtrip keeps `def handle_event` stable.
- **Registry gate** — translation targets are verified against the lab
  product catalog before any work happens.

## License

MIT — part of the Hartwell Labs toolset. Security reports: see
[hack-the-lab](https://github.com/Hartwell-Labs/hack-the-lab) (safe harbor).
