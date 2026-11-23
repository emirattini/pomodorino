# Rust notes: a tour of this server

Each section shows an idiom used in the code, why Rust does it that way, and where to find it.
A good reading order is the same as the spec's §7.6: `model.rs` → `error.rs` → `store.rs` →
`providers/` → `api.rs` → `lib.rs`.

---

## 1. Data types with `derive` and serde (`model.rs`)

```rust
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Task {
    pub id: String,
    pub estimate_min: Option<u32>,
    ...
}
```

- `#[derive(...)]` asks the compiler to write trait implementations for you. `Debug` gives `{:?}`
  printing, `Clone` gives `.clone()`, and `PartialEq` gives `==`. `Serialize` and `Deserialize` come
  from serde and generate the JSON conversion code at compile time (no runtime reflection).
- `rename_all = "camelCase"` lets Rust keep its `snake_case` naming while the JSON uses `estimateMin`.
- **There is no `null` in Rust.** A value that may be missing is an `Option<T>`: either `Some(30)` or
  `None`. Serde maps `None` to JSON `null`. The compiler makes you handle the `None` case before you
  can use the value, which removes a whole class of crashes.
- `#[serde(default)]` on `interrupted` means a missing field becomes `false` instead of an error.

## 2. `String` vs `&str`: owning vs borrowing (everywhere)

```rust
pub fn truncate(s: &str, max: usize) -> String
```

- `String` owns its text (heap memory that it frees when dropped). `&str` is a *borrowed view* into
  text someone else owns.
- Functions that only read take `&str`, so callers can pass a `String` (`&my_string`), a literal, or a
  slice without copying. Functions return `String` when they create new text.
- Rule of thumb: **take borrowed, return owned.**

## 3. UTF-8 and `chars()` (`model.rs`, `truncate`)

```rust
if s.chars().count() <= max { return s.to_string(); }
let mut out: String = s.chars().take(max - 1).collect();
```

Rust strings are UTF-8. `"è"` is 2 bytes, so slicing by byte position (`&s[..10]`) can land inside a
character and **panic**. `.chars()` iterates real characters. The test
`truncate_counts_chars_not_bytes` checks this with Italian accents.

## 4. Methods that consume `self` (`model.rs`, `Task::normalized`)

```rust
pub fn normalized(mut self) -> Self {
    self.title = truncate(&self.title, MAX_TITLE);
    self
}
// used as: tasks.into_iter().map(Task::normalized).collect()
```

`self` (not `&self`) means the method *takes ownership* of the value, changes it, and hands it back.
Nothing is copied, and the caller can't accidentally keep using the old version. Note also
`.map(Task::normalized)`: a method name can be passed wherever a function is expected.

## 5. Enums that carry data, and exhaustive `match` (`error.rs`)

```rust
pub enum ProviderError {
    Unreachable(String),
    Status { status: u16, body: String },
    NotFound,
    Decode(String),
}

match self {
    ApiError::Unauthorized => 401,
    ApiError::NotFound | ApiError::Provider(ProviderError::NotFound) => 404,
    ApiError::Provider(ProviderError::Unreachable(_)) => 503,
    ApiError::Provider(_) => 502,
    ...
}
```

- Rust enums are *sum types*: each variant can hold different data. They're closer to TypeScript's
  tagged unions than to C enums.
- `match` must cover **every** variant. Add a `Jira` error variant and the compiler lists every
  `match` you forgot to update.
- Patterns can look *inside* nested values (`Provider(NotFound)`), combine with `|`, and ignore parts
  with `_`. Arms are tried top to bottom, so the specific `NotFound` arm wins over `Provider(_)`.

## 6. `Result`, `?` and `From`: error handling without exceptions (`error.rs`, `api.rs`)

```rust
impl From<KvError> for ApiError {
    fn from(e: KvError) -> Self { ApiError::Internal(format!("kv: {e}")) }
}

// in a handler returning Result<Response, ApiError>:
let spent = app.store.spent(provider, &task.id).await?;
```

- A function that can fail returns `Result<T, E>`: `Ok(value)` or `Err(error)`. Errors are ordinary
  values, not exceptions, so you can see in each signature what can fail.
- `?` means: "if this is `Err`, return it from my function now; otherwise unwrap the `Ok`". On the way
  out it calls `From::from`, so a `KvError` turns into an `ApiError` by itself.
- The result is one *error funnel*: every handler just writes `?`, and `ApiError::into_response` is the
  only place that decides status codes (spec §7.5: "a single point").
- `.map_err(|e| ...)` converts an error by hand when there's no `From` impl, or when you want a
  specific variant (`ProviderError::Unreachable`).

## 7. `Option` and `Result` combinators (`store.rs`, `api.rs`, `todoist.rs`)

```rust
Ok(value.and_then(|v| v.parse().ok()))                                  // store.rs
let given = req.headers().get("X-Api-Key")?.unwrap_or_default();       // api.rs
if scope.as_deref().is_some_and(|s| s != "today") { ... }               // api.rs
let projects = self.project_names().await.unwrap_or_default();         // todoist.rs
```

Read them like this:
- `and_then(f)`: if `Some(v)`, run `f(v)`, which itself returns an `Option`. Otherwise stay `None`.
- `.ok()`: turns `Result<T, E>` into `Option<T>`, dropping the error. Here a non-numeric value counts
  as "no value".
- `unwrap_or_default()`: the value, or the type's default (`""`, `0`, an empty map).
- `as_deref()`: `Option<String>` → `Option<&str>`, so you can compare with a literal without moving
  the `String`.
- `is_some_and(f)`: `true` only if it's `Some` and `f` agrees.

They replace chains of `if x != null` with expressions. Avoid `.unwrap()` in server code: it panics
on `None`/`Err`. This server only uses it in tests.

## 8. Iterators (`todoist.rs`, `api.rs`)

```rust
let tasks = page.results
    .into_iter()
    .take(MAX_TASKS)
    .map(|t| Task {
        estimate_min: t.duration.as_ref().and_then(Duration::minutes),
        project: projects.get(&t.project_id).cloned(),
        spent_min: None,
        id: t.id,        // moved out of `t`, no copy
        title: t.content,
    })
    .collect();
```

- `iter()` borrows the items, `iter_mut()` borrows them mutably, and `into_iter()` *consumes* the
  collection and gives you owned items. Here we no longer need Todoist's struct, so we move its
  `String`s straight into our `Task` instead of cloning them.
- **Partial moves:** inside the closure we first *borrow* `t.duration` and `t.project_id`, then *move*
  `t.id` and `t.content`. Rust tracks ownership per field, so this is allowed.
- Iterators are lazy. Nothing runs until `.collect()`, which builds whatever type is expected: a
  `Vec<Task>` here, a `HashMap` in `project_names` (from `(key, value)` tuples).
- `api.rs` uses `tasks.iter_mut().filter(|t| t.spent_min.is_none())` to change only some items in place.
- `constant_time_eq` uses `zip` + `fold` to combine all bytes without stopping early, so timing
  doesn't reveal how many characters of the key were right.

Sorting (`todoist.rs`):

```rust
page.results.sort_by_key(|t| Reverse(t.priority));
```

- `sort_by_key` sorts in place by whatever the closure returns. `std::cmp::Reverse` is a tiny wrapper
  whose ordering is the opposite of what it wraps, so this sorts by priority, highest first, without
  writing a comparison function.
- Rust's `sort` family is *stable*: items with equal keys keep their order. That's why tasks with the
  same priority stay in Todoist's order (`sort_unstable_by_key` is a bit faster but doesn't promise it).
- Sorting needs `mut page`: the `let` binding has to be declared mutable to change what it owns.

## 9. Closures (`api.rs`, `todoist.rs`)

```rust
let var = |name: &str, default: &str| {
    env.var(name).map(|v| v.to_string()).unwrap_or_else(|_| default.to_string())
};
let unreachable = |e: worker::Error| ProviderError::Unreachable(e.to_string());
headers.set(...).map_err(unreachable)?;
```

A closure is an anonymous function that can use variables from where it's defined (here `env`).
Naming one avoids repeating the same `map_err` three times.

## 10. Traits and `async fn` (`providers/mod.rs`)

```rust
#[allow(async_fn_in_trait)]
pub trait TaskProvider {
    fn name(&self) -> &'static str;
    async fn list_today(&self) -> Result<Vec<Task>, ProviderError>;
    ...
}
```

- A trait is an interface: a set of methods a type promises to have. `Todoist` and `Demo` both
  implement it.
- `&'static str` is a string that lives for the whole program (a literal like `"todoist"`), so it can be
  returned without allocating.
- `async fn` returns a *future*: a value that represents the work. Nothing runs until someone
  `.await`s it. In Workers, awaiting hands control back to the JavaScript event loop while the
  network request is in flight.
- The `allow` silences a lint about `Send` (whether a future may move between threads). Workers is
  single-threaded, so we never need it.

## 11. Enum dispatch vs `Box<dyn Trait>` (`providers/mod.rs`)

```rust
pub enum Provider { Demo(Demo), Todoist(Todoist) }

impl TaskProvider for Provider {
    async fn list_today(&self) -> ... {
        match self {
            Provider::Demo(p) => p.list_today().await,
            Provider::Todoist(p) => p.list_today().await,
        }
    }
}
```

There are two ways to say "one of several providers, chosen at runtime":
- `Box<dyn TaskProvider>`: a heap pointer plus a table of functions (like a Java interface). It's open
  to types you don't know about, but `async fn` in `dyn` traits needs the `async-trait` crate.
- **An enum**: a closed list of variants, with no allocation, and the compiler checks every `match`.
  When you own all the implementations, as here, it's the simpler choice. The cost is one line per
  method when you add a provider.

## 12. Generics with trait bounds (`api.rs`, `todoist.rs`)

```rust
pub async fn run<F, Fut>(req: Request, ctx: RouteContext<()>, handler: F) -> worker::Result<Response>
where
    F: FnOnce(App, Request, RouteContext<()>) -> Fut,
    Fut: Future<Output = Result<Response, ApiError>>,
```

`run` accepts *any* function with that shape. Every `async fn ping(app: App, req: Request, ctx: ...)`
fits, because an `async fn` is a function returning some `Future`. `lib.rs` can then write
`api::run(req, ctx, api::ping)`, and authentication plus error conversion are written only once.
The compiler generates a specialised copy of `run` per handler, so there's no runtime cost.

```rust
async fn get_json<T: DeserializeOwned>(&self, url: &str) -> Result<T, ProviderError>
let page: Page<TodoistTask> = self.get_json(url.as_str()).await?;
```

Here the caller's type annotation picks `T`. The same function decodes tasks or projects.
`Page<T>` is a generic struct for Todoist's `{ "results": [...] }` wrapper.

## 13. `#[serde(untagged)]` for "number or string" (`todoist.rs`)

```rust
#[derive(Deserialize)]
#[serde(untagged)]
enum Amount { Number(u32), Text(String) }
```

The Todoist docs say `duration.amount` may be either. `untagged` tries each variant in order, and a
`match` later handles both. This is a common way to model loosely typed JSON precisely.

## 14. Shadowing and immutability by default

```rust
let s = s.trim();      // a new `s` that hides the parameter; the old one is untouched
let mut out = ...;     // `mut` must be explicit to change a variable
```

Variables are immutable unless marked `mut`, so the places where state changes stand out.
Shadowing reuses a name for a transformed value without needing `mut`.

## 15. Parsing text without regexes, and overflow-safe arithmetic (`estimate.rs`)

```rust
fn tag_minutes(word: &str) -> Option<u32> {
    let value = word.strip_prefix('~')?;
    let value = value.strip_suffix('m').unwrap_or(value);
    let minutes = match value.split_once('h') {
        None => value.parse::<u32>().ok()?,
        Some((hours, "")) => hours.parse::<u32>().ok()?.checked_mul(60)?,
        Some((hours, mins)) => hours.parse::<u32>().ok()?.checked_mul(60)?.checked_add(mins.parse().ok()?)?,
    };
    (1..=MAX_MIN).contains(&minutes).then_some(minutes)
}
```

- `?` also works on `Option`: in a function returning `Option`, `x?` means "if `None`, return `None`".
  So every step that might not match (no `~`, not a number) simply ends the function.
- `strip_prefix`, `strip_suffix` and `split_once` return borrowed slices of the original `&str`. No new
  strings are allocated while parsing.
- `match` on a tuple can test a *value* inside it: `Some((hours, ""))` only matches `"1h"`, with nothing
  after the `h`.
- `checked_mul` / `checked_add` return `None` on overflow instead of wrapping around or panicking.
  `~99999999999h` is just "not a tag" (there's a test for it).
- `(1..=MAX_MIN).contains(&x)` reads better than `x >= 1 && x <= MAX_MIN`, and `cond.then_some(v)` turns a
  `bool` into `Some(v)` or `None`.
- `find_map` (in `find`) stops at the first word for which the closure returns `Some`. In
  `todoist.rs`, `.or_else(|| ...)` chains the three places an estimate can come from: the first one
  that's `Some` wins, and the later closures don't even run.

## 16. Tests next to the code

```rust
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn truncate_counts_chars_not_bytes() { ... }
}
```

`#[cfg(test)]` compiles the module only for `cargo test`. `use super::*` brings in the parent module,
private items included, so pure logic (truncation, validation, status codes, Todoist JSON parsing) is
tested without a Workers runtime. Anything that touches KV or `fetch` was checked end to end with
`wrangler dev` and curl.

---

### Exercises, if you want to practise

1. Add a `GET /v1/stats` endpoint that returns the total minutes spent on a task (`?task=...`) from
   KV. Touches: router, handler, `Store`.
2. Make `Demo::complete` return `ProviderError::NotFound` for unknown ids, like `log_session` does.
   Then write a test for it. Tip: `async` tests need an executor, so test a plain helper function
   instead.
3. Add a `Jira` variant to `Provider` with every method returning `todo!()`. Watch the compiler point
   you at every `match` to update.
