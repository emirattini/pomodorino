# Pomodorino — Integrazione Task (specifica)

> Documento di specifica per estendere **Pomodorino** (app Connect IQ già pubblicata) con la possibilità di lavorare su task provenienti da servizi esterni (Todoist, TickTick, Jira, YouTrack…) e registrare il tempo effettivo dedicato a ciascuna task.
>
> ⚠️ Gli endpoint dei servizi esterni indicati qui sono un riferimento: **verificarli sulla documentazione ufficiale** prima di implementare.

---

## 1. Obiettivo

Chiudere il ciclo **stima → esecuzione → misura**:

1. La sera l'utente pianifica le task del giorno dopo nel proprio task manager, con una **durata stimata**.
2. Sull'orologio sceglie una task e lavora a pomodori.
3. Pomodorino registra il **tempo di focus reale** sulla task.
4. A fine sessione mostra **stimato vs reale**, così l'utente impara le proprie durate e pianifica in modo più realistico.

Il valore distintivo non è il timer (esiste già), ma il confronto stima/reale.

## 2. Principi

- **Modalità opzionale.** Senza configurazione Pomodorino resta identico a oggi. Nessuna regressione per gli utenti attuali.
- **Timer separato dalle task.** Il core del timer non conosce i provider: riceve al massimo un `taskId` e un titolo, ed emette una sessione a fine lavoro.
- **Orologio "stupido", server "intelligente".** Tutta la logica specifica dei provider (auth, mapping, API) sta in un server proxy. L'orologio parla un solo formato JSON minimale.
- **Offline-first.** Il timer funziona sempre; le sessioni si accodano e si sincronizzano quando il telefono è raggiungibile.
- **Nessun segreto sull'orologio.** I token dei provider stanno solo sul server.

## 3. Architettura

```
┌──────────────┐  BLE   ┌─────────────────┐  HTTPS  ┌──────────────────┐  HTTPS  ┌────────────┐
│  Pomodorino  │ ─────► │ Garmin Connect  │ ──────► │  Proxy server    │ ──────► │  Provider  │
│ (Connect IQ) │ ◄───── │ (telefono)      │ ◄────── │ (es. CF Worker)  │ ◄────── │ Todoist,   │
└──────────────┘        └─────────────────┘         │  + adapter       │         │ Jira, ...  │
                                                    │  + KV storage    │         └────────────┘
                                                    └──────────────────┘
```

- **Orologio**: `Communications.makeWebRequest` (passa dal telefono via Garmin Connect).
- **Proxy**: **Rust su Cloudflare Workers** (crate `worker`, piano gratuito) + **KV** per configurazione utente, deduplica delle sessioni e tempo cumulativo dove il provider non lo supporta. Dettagli in §7.
- **Adapter**: un modulo per provider che implementa lo stesso trait (vedi §6).

> Il contratto orologio ↔ server (§5) è indipendente dal linguaggio: Pomodorino non sa e non deve sapere in cosa è scritto il server.

## 4. Specifiche lato orologio (Connect IQ)

### 4.1 Dispositivo di riferimento
- Forerunner 165 / 165 Music — 390×390 AMOLED, touchscreen + 5 tasti, API level 5.2.
- Mantenere compatibilità con i dispositivi già supportati da Pomodorino.

### 4.2 Impostazioni (modificabili da Garmin Connect, `settings.xml`)
| Chiave | Tipo | Descrizione |
|---|---|---|
| `tasksEnabled` | bool | Attiva la modalità task (default `false`) |
| `serverUrl` | string | URL base del proxy (HTTPS) |
| `apiKey` | string | Chiave utente generata dal proxy |

Se `tasksEnabled == false` o mancano `serverUrl`/`apiKey` → comportamento attuale.

### 4.3 Flusso utente
1. **Avvio app** (modalità task attiva) → schermata **Lista task di oggi**.
   - Ogni riga: titolo (troncato), `stimato / speso` (es. `30' · 15'`).
   - Voce fissa in fondo: **"Senza task"** → pomodoro classico.
   - Pull/tasto per ricaricare. Mostrare ultima lista in cache se offline (con indicatore).
2. **Selezione task** → schermata timer standard con il **titolo della task** visibile.
3. **Pomodori e pause** come oggi.
4. **Fine sessione** (utente termina, cambia task o chiude l'app):
   - Riepilogo: `Stimato 30' · Reale 45' (+15')`, n. pomodori.
   - Azioni: **Completa task** / **Continua più tardi**.
5. La sessione viene inviata al server (o accodata).

### 4.4 Regole di conteggio del tempo
- Si conta **solo il tempo di focus** effettivamente trascorso. Le pause non contano.
- Pomodoro interrotto: si conta il focus trascorso, arrotondato per difetto al minuto (minimo 1 min se > 30 s).
- Pausa del timer (se supportata): il tempo in pausa non conta.
- **Una sessione = una task**, aggregata: si invia un solo record a fine sessione, non uno per pomodoro (meno richieste, meno batteria).

### 4.5 Coda offline
- Le sessioni si salvano in `Application.Storage` (lista `pendingSessions`).
- Ogni sessione ha un `sessionId` univoco generato sull'orologio, per l'**idempotenza** (i retry non duplicano).
- Si ritenta l'invio all'avvio dell'app, a fine sessione e al ritorno della connessione.
- Limite coda: es. 50 sessioni; oltre, scartare le più vecchie con avviso.

### 4.6 Vincoli Connect IQ da rispettare
- Solo HTTPS, risposte JSON.
- **Memoria limitata**: il server deve restituire payload piccoli (max ~20 task, campi corti, titoli troncati lato server a ~60 caratteri).
- Gestire tutti i codici d'errore di `makeWebRequest` (telefono non connesso, timeout, 4xx/5xx) senza bloccare il timer.

### 4.7 Avvio da altre app (futuro, a basso costo)
- Accettare parametri di avvio via **Intent** (`System.exitTo` dall'app chiamante): `taskId`, `title`, opzionale `estimateMin`.
- Se presenti → saltare la lista e aprire direttamente il timer su quella task.
- Pensato per un'eventuale integrazione con ComingUp o altre app. Verificare nella doc Connect IQ come l'app lanciata riceve gli argomenti.

## 5. API del proxy (contratto orologio ↔ server)

Autenticazione: header `X-Api-Key: <apiKey>` su ogni richiesta.

### `GET /v1/ping`
```json
{ "ok": true, "provider": "todoist" }
```

### `GET /v1/tasks?scope=today`
```json
{
  "fetchedAt": "2026-11-23T08:00:00Z",
  "tasks": [
    { "id": "t_123", "title": "Scrivere report Q4", "estimateMin": 30, "spentMin": 15, "project": "Lavoro" }
  ]
}
```
- `estimateMin` / `spentMin` possono essere `null`.
- Ordine: quello del provider (priorità/ordine manuale).

### `POST /v1/sessions`
```json
{
  "sessionId": "b3f1…",
  "taskId": "t_123",
  "startedAt": "2026-11-23T09:00:00Z",
  "endedAt": "2026-11-23T10:05:00Z",
  "focusMin": 50,
  "pomodori": 2,
  "interrupted": false
}
```
Risposta:
```json
{ "ok": true, "spentMin": 65, "duplicate": false }
```
- Se `sessionId` è già stato ricevuto → `200` con `duplicate: true` (nessuna doppia registrazione).

### `POST /v1/tasks/{id}/complete`
```json
{ "ok": true }
```

### Errori
`401` api key non valida · `404` task non trovata · `502` errore del provider · `503` provider non raggiungibile. Corpo: `{ "ok": false, "error": "codice" }`.

## 6. Adapter dei provider

Trait comune (lato server, Rust):

```rust
pub trait TaskProvider {
    async fn list_today(&self) -> Result<Vec<Task>, ProviderError>;
    async fn log_session(&self, task_id: &str, s: &Session) -> Result<Option<u32>, ProviderError>; // spent_min
    async fn complete(&self, task_id: &str) -> Result<(), ProviderError>;
}
```

Dispatch consigliato: un **enum** con una variante per provider. È semplice, non serve `Box<dyn …>` e funziona con gli `async fn` nativi nei trait.

```rust
pub enum Provider {
    Todoist(Todoist),
    // Jira(Jira), YouTrack(YouTrack), TickTick(TickTick)
}
```

Alternativa: `Box<dyn TaskProvider>` con il crate `async-trait` in modalità `#[async_trait(?Send)]` (il runtime Workers è single-thread).

### Mapping per provider

| | Lista "oggi" | Stima | Registrazione tempo | Tempo speso |
|---|---|---|---|---|
| **Todoist** (primo da fare) | filtro `today` | campo `duration` della task | commento sulla task (es. `🍅 2 · 50 min`) | cumulato in KV sul server |
| **TickTick** (API V1 ufficiale) | lista dedicata (es. "Oggi"); l'Inbox non è accessibile da V1 | convenzione nel titolo/descrizione (es. `[30m]`) | aggiornamento descrizione della task | cumulato in KV |
| **Jira Cloud** | JQL (es. `assignee = currentUser() AND labels = oggi`) | `timetracking.originalEstimate` | **worklog nativo** (`POST /rest/api/3/issue/{key}/worklog`) | `timetracking.timeSpent` |
| **YouTrack** | query (es. `for: me tag: oggi`) | campo Estimation | **work item nativo** (`/api/issues/{id}/timeTracking/workItems`) | campo Spent time |

Note:
- **Todoist**: API v1 con token personale. Verificare endpoint task, filtri e commenti sulla doc attuale.
- **TickTick**: il focus tracking nativo è solo nell'API V2 non ufficiale (email/password, fragile) → **non usarla**.
- **Jira / YouTrack**: sono i casi migliori perché hanno il time tracking nativo.

## 7. Server — Rust su Cloudflare Workers

### 7.1 Stack
| Cosa | Scelta |
|---|---|
| Runtime | Cloudflare Workers (compilazione Rust → WebAssembly) |
| SDK | crate [`worker`](https://github.com/cloudflare/workers-rs) (workers-rs) |
| JSON | `serde` + `serde_json` |
| HTTP verso i provider | `worker::Fetch` (**non** `reqwest`: nel runtime Workers si usa il fetch della piattaforma) |
| Storage | Workers KV (binding `POMODORINO_KV`) |
| Segreti | `wrangler secret put …` |
| Build/deploy | `wrangler` + `worker-build` (`npx wrangler dev` / `npx wrangler deploy`) |

### 7.2 Struttura del progetto
```
pomodorino-server/
├── Cargo.toml
├── wrangler.toml          # nome worker, binding KV, build command
└── src/
    ├── lib.rs             # entry point #[event(fetch)] + Router
    ├── api.rs             # handler degli endpoint §5, auth X-Api-Key
    ├── model.rs           # Task, Session, risposte (serde)
    ├── error.rs           # ProviderError / ApiError → codici HTTP §5
    ├── store.rs           # wrapper KV: user config, dedup, spent
    └── providers/
        ├── mod.rs         # trait TaskProvider + enum Provider
        └── todoist.rs     # primo adapter
```

### 7.3 Modello dati (serde)
```rust
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Task {
    pub id: String,
    pub title: String,
    pub estimate_min: Option<u32>,
    pub spent_min: Option<u32>,
    pub project: Option<String>,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Session {
    pub session_id: String,
    pub task_id: String,
    pub started_at: String, // ISO 8601, passato così com'è
    pub ended_at: String,
    pub focus_min: u32,
    pub pomodori: u32,
    pub interrupted: bool,
}
```
`rename_all = "camelCase"` fa combaciare i campi Rust (`snake_case`) con il JSON del contratto.

### 7.4 Storage KV
- `user:{apiKey}` → `{ provider, providerToken, config }`
- `session:{sessionId}` → marker per la deduplica (TTL es. 30 giorni)
- `spent:{provider}:{taskId}` → minuti cumulati (solo per i provider senza tempo nativo)

**MVP single-user**: invece di `user:{apiKey}` bastano due segreti (`API_KEY`, `TODOIST_TOKEN`) con `wrangler secret put`. KV si usa solo per dedup e `spent`.

### 7.5 Vincoli e buone pratiche
- **Dimensione del Worker**: piano gratuito max **3 MB compressi**. Tenere poche dipendenze: niente `reqwest`, `tokio`, `chrono`. Per le date basta `worker::Date` o le stringhe ISO già fornite dall'orologio.
- Profilo release ottimizzato per dimensione in `Cargo.toml` (`opt-level = "z"`, `lto = true`, `strip = true`).
- **Single-thread**: niente `Send`/`Sync` da rincorrere, ma niente thread o `tokio`.
- **Normalizzazione**: titoli troncati (~60 caratteri), massimo 20 task, solo i campi del contratto.
- Errori: `Result` e `?` ovunque; un solo punto (`error.rs`) converte gli errori in risposte HTTP §5.
- Verificare le firme esatte dell'API di `worker` (Router, KV, Fetch) sulla versione corrente del crate.

### 7.6 Ordine di sviluppo consigliato (anche come percorso di apprendimento Rust)
1. `GET /v1/ping` con Router e controllo `X-Api-Key` → setup, deploy, primo handler.
2. `model.rs` + `GET /v1/tasks` con dati finti → serde e risposte JSON.
3. Adapter Todoist reale (`list_today`) con `worker::Fetch` → async, deserializzazione della risposta esterna, mapping verso `Task`.
4. `POST /v1/sessions` + dedup KV + commento Todoist → KV, idempotenza, gestione errori.
5. `POST /v1/tasks/{id}/complete`.
6. Solo dopo: secondo adapter (Jira), quando il trait è collaudato.

## 8. Roadmap

| Fase | Contenuto |
|---|---|
| **MVP** | Server Rust single-user (segreti, no onboarding). Todoist: lista oggi, timer su task, invio sessione (commento + KV), riepilogo stimato/reale, coda offline |
| **v2** | Completa task dall'orologio, statistiche semplici (scarto medio stima/reale sugli ultimi 7 giorni) |
| **v3** | Adapter Jira e YouTrack (worklog nativo) |
| **v4** | TickTick (V1), avvio via Intent, pagina web di onboarding multi-utente |

## 9. Domande aperte

- Pomodoro interrotto: va contato, oppure contano solo i pomodori completi? (proposta: contare i minuti reali)
- Su Todoist il tempo va scritto come commento per sessione o come totale aggiornato nella descrizione?
- Statistiche stima/reale: tenerle sull'orologio, sul server o in entrambi?
- Multi-utente pubblico (store) o, almeno all'inizio, uso personale? Cambia il lavoro di onboarding e sicurezza del server.
