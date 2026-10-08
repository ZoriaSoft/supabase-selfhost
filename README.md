# supabase-selfhost

**Türkçe** · [English below](#english)

**Supabase'e $25/ay verme.** Aynı stack'i kendi sunucunda çalıştır —
verin sende, kota yok, root sende.

Resmi [`supabase/supabase`](https://github.com/supabase/supabase)
`docker/` dizini temellidir; ek olarak tek komutla kurulum (`setup.sh`),
uçtan uca doğrulama (`verify.sh`) ve Docker'sız GoTrue kurulumu
(`scripts/`) bu repoda paketlenmiştir; Studio'ya doğrudan `:3000`
port eşlemesi (yalnız localhost) de eklenmiştir.

## İki yol — hangisi sana?

### Yol A — Hafif: sadece Auth (GoTrue tek binary)

Supabase'in Auth servisi olan **GoTrue, aslında tek bir Go binary'si** —
Docker gerektirmez. Tek bağımlılığı bir Postgres veritabanı (mevcut bir
Postgres de olur; GoTrue kendi migration'larını `auth` schema'sına koşar).
`GOTRUE_*` env değişkenleriyle yapılandırılır; `supabase/auth`
reposunun GitHub release'lerinde hazır binary olarak yayınlanır.

- **Alırsın:** e-posta/OAuth kayıt-giriş, JWT üretimi (JWKS endpoint'i
  dahil), refresh token, MFA — istemci tarafında `supabase-js` /
  `auth-js` aynen bağlanır.
- **Almazsın:** PostgREST, Realtime, Storage, Studio — yok. Bu yol
  yalnız kimlik doğrulamasıdır.
- **Nerede çalışır:** her yerde — özellikle **Zo** (zo computer):
  Zo bir gVisor sandbox'ıdır; Docker container çalıştıramaz. Yol A
  binary GoTrue, Zo-uyumlu yoldur (Docker gerekmez).
- **Kanıt:** production'da aktif — Zoria uygulamalarının auth'u bu
  kurulumla çalışıyor. Yol A e2e testi Zo üzerinde de geçti
  ([DOGRULAMA.md](DOGRULAMA.md)).


**Kurulum (Yol A):** Docker gerekmez — prebuilt binary indirilir:

```bash
./scripts/setup-gotrue.sh   # bin/gotrue + gotrue.env (chmod 600)
# psql -f scripts/create-auth-role.sql   # şifreyi önce düzenle
# gotrue.env dosyasını doldur, sonra:
#   set -a; . ./gotrue.env; set +a
#   ./bin/gotrue migrate    # ilk açılışta auth şeması (zorunlu)
#   ./bin/gotrue
```

Ayrıntı: [SECURITY.md](SECURITY.md) (loopback bind, JWT secret, mailer URL).

### Yol B — Full stack: Docker Compose

Bu repo'nun asıl konusu. Tek komutla **11 servis** ayağa kalkar:
Postgres 17, GoTrue, PostgREST, Realtime, Storage, Edge Functions,
Studio paneli, Supavisor (connection pooler), Meta, ImgProxy +
Envoy API gateway.

- **Alırsın:** managed Supabase'in self-hosted karşılığının tamamı —
  Studio dahil.
- **Şart:** Docker çalıştırabilen **gerçek kernel'lı bir VPS/host**
  (Docker Engine ≥ 24 + Compose v2). **Zo (gVisor sandbox) üzerinde
  Yol B çalışmaz** — container mount namespace izni yoktur (doğrulandı,
  bkz. [DOGRULAMA.md](DOGRULAMA.md)). Zo'da Yol A kullan; gerçek
  kernel'lı VPS'te `./setup.sh` (veya `DOCKER_HOST` ile uzak daemon).
- **Kanıt:** gerçek bir Docker host'unda uçtan uca **5/5 test geçti**
  (compose healthcheck, Studio, GoTrue signup→JWT, PostgREST CRUD,
  Storage upload) — [DOGRULAMA.md](DOGRULAMA.md).

| | Yol A — GoTrue binary | Yol B — Full stack |
|---|---|---|
| Zo (gVisor) | Uyumlu (önerilen) | Çalışmaz |
| Docker | Gerekmez | Şart |
| Postgres | Gerekir (mevcut DB de olur) | Dahili, container içinde |
| Kapsam | Sadece Auth | Auth + REST + Realtime + Storage + Functions + Studio |
| Ortam | Sandbox dahil her yer | Gerçek kernel'lı host |
| Ne zaman | "Bana sadece login lazım" | "Supabase'in tamamını istiyorum" |

## Maliyet

| | Supabase Cloud (Pro) | Zo Computer | Gerçek kernel'lı VPS |
|---|---|---|---|
| Fiyat | $25/ay + kullanım ücretleri | $18/ay sabit | Sağlayıcıya göre |
| Ne çalışır | Her şey (managed) | **Yalnız Yol A** (Auth) | **Yol A + Yol B** (full stack) |
| Paket | Managed servis + plan limitleri | 4 CPU / 32 GB RAM + $10 AI kredisi (sohbet + görsel üretim) + uzaktan terminal | Seçtiğin plan |
| Limit | Plan kotası (DB boyutu, bandwidth, MAU…) | Donanımın | Donanımın |
| Veri | Supabase altyapısında | **Kendi ortamında** | **Kendi sunucunda**, tam root |

> **Dikkat:** Zo bir gVisor sandbox'ıdır ve Docker container
> çalıştıramaz — $18'lık Zo paketiyle Supabase'in **tamamını** değil,
> yalnız Auth'u (GoTrue) host edersin. Studio, Storage, Realtime,
> PostgREST için gerçek kernel'lı bir VPS gerekir.

Dürüst notlar:

- Supabase'in ücretsiz katmanı var — küçük denemeler için yeterli
  olabilir. Bu repo, ücretsiz katmanın yetmediği ya da altyapının sende
  olmasını istediğin nokta için.
- Kendi host etmek = operasyon sorumluluğu. Güncelleme, yedek ve
  güvenlik (TLS, firewall) sana aittir — bkz. [SECURITY.md](SECURITY.md).

## Zo Computer (Yol A için)

> **$18/ay paket (Zo Computer):** 4 CPU / 32 GB RAM + $10 AI kredisi
> (sohbet + görsel üretim) + uzaktan terminal erişimi.
>
> Zo bir **gVisor sandbox**'tır — Docker container çalıştırmaz; bu
> ortamda **Yol A (GoTrue binary)** uyumludur, Yol B (full Docker stack)
> değildir. Kayıt / referral:
> [https://zo-computer.cello.so/rWtkIf0NXRp](https://zo-computer.cello.so/rWtkIf0NXRp)
>
> Full stack (Yol B) için Docker çalıştırabilen herhangi bir gerçek
> kernel'lı VPS (Hetzner, DigitalOcean, Contabo vb.) kullanılabilir.

## Kurulum (Yol B)

```bash
git clone https://github.com/ZoriaSoft/supabase-selfhost.git
cd supabase-selfhost
./setup.sh
```

`setup.sh` Docker'ı kontrol eder, `.env`'i oluşturur, **tüm secret'ları
üretir** (JWT secret + ANON/SERVICE anahtarları resmî yöntemle,
HS256-imzalı JWT'ler), stack'i ayağa kaldırır ve URL'leri basar.

Bittiğinde:

- **Studio panel:** `http://<sunucu>:8000` (gateway, basic auth:
  `.env`'deki `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD`). Doğrudan
  `:3000` portu şifresizdir ve yalnız localhost'a açıktır — SSH tünelle
  eriş: `ssh -L 3000:localhost:3000 <sunucu>`
- **API gateway:** `http://<sunucu>:8000` (`/rest/v1`, `/auth/v1`,
  `/storage/v1`, `/realtime/v1`, `/functions/v1`)
- **Postgres:** `localhost:5432` (Supavisor session) / `:6543`
  (transaction pooler)

Secret'lar `.env` dosyasında (git'e girmez). Üretim ortamına çıkmadan önce
[SECURITY.md](SECURITY.md)'yi oku: TLS reverse proxy şart, Postgres'i
dışarıya asla açma.

## İçerik

```
docker-compose.yml   # temizlenmiş, yorumlu — resmi stack'in tamamı
.env.example         # tüm ayarların açıklamalı şablonu
setup.sh             # tek-komut kurulum (secret üretimi dahil)
verify.sh            # kurulum sonrası uçtan uca test
utils/               # upstream key üretim script'leri
scripts/             # Yol A: GoTrue binary setup (Docker'sız)
volumes/             # db init SQL, envoy config, edge function örnekleri
```

## Gereksinimler (Yol B)

- Docker Engine ≥ 24 + Compose v2 (`docker compose version`)
- Gerçek Linux kernel'lı host — gVisor/sandbox ortamlarında çalışmaz
- ~4 GB disk (image'lar) + DB verisi

## Doğrulama

Bu stack'in uçtan uca çalıştığı (compose healthcheck'ler, Studio, GoTrue
signup→JWT, PostgREST CRUD, Storage upload) [DOGRULAMA.md](DOGRULAMA.md)'de
belgelendi. Kendi kurulumunu test etmek için:

```bash
# Önce PostgREST test tablosunu hazırla (host'ta, bir kez):
docker exec supabase-db psql -U postgres -c \
  "CREATE TABLE IF NOT EXISTS public.verify_items(id bigserial primary key, name text, created_at timestamptz default now()); NOTIFY pgrst, 'reload schema';"

docker run --rm --network supabase_default -v "$PWD:/v" \
  --entrypoint sh curlimages/curl:8.14.1 /v/verify.sh
```

## Lisans

Apache License 2.0 — bkz. [LICENSE](LICENSE). Upstream Supabase
`docker/` dizini de Apache-2.0 altındadır.

---

<a id="english"></a>
## English

**Stop paying Supabase $25/mo.** Run the same stack on your own server —
your data, no quotas, you own root.

Based on the official `supabase/supabase` repo's `docker/` directory,
packaged here with a one-command setup (`setup.sh`), end-to-end
verification (`verify.sh`), a Docker-less GoTrue installer (`scripts/`),
and a direct (localhost-only) `:3000` port mapping for Studio.

### Two paths — which one is yours?

#### Path A — Lightweight: Auth only (single GoTrue binary)

Supabase's Auth server, **GoTrue, is a single Go binary** — no Docker
required. Its only dependency is a Postgres database (an existing one
works fine; GoTrue runs its own migrations into the `auth` schema). It is
configured via `GOTRUE_*` env vars and ships as a prebuilt binary in
the `supabase/auth` GitHub releases.

- **You get:** email/OAuth signup & login, JWT issuance (including a JWKS
  endpoint), refresh tokens, MFA — `supabase-js` / `auth-js` clients
  connect as usual.
- **You don't get:** PostgREST, Realtime, Storage, Studio. This path is
  authentication only.
- **Runs anywhere** — especially on **Zo** (zo computer): Zo is a
  gVisor sandbox and cannot run Docker containers. Path A (binary
  GoTrue) is the Zo-compatible path.
- **Proof:** running in production — Zoria apps authenticate via this
  setup. Path A e2e also passed on Zo
  ([DOGRULAMA.md](DOGRULAMA.md)).


**Setup (Path A):** no Docker — downloads a prebuilt binary:

```bash
./scripts/setup-gotrue.sh   # bin/gotrue + gotrue.env (chmod 600)
# psql -f scripts/create-auth-role.sql   # edit the password first
# fill gotrue.env, then:
#   set -a; . ./gotrue.env; set +a
#   ./bin/gotrue migrate    # first boot: auth schema (required)
#   ./bin/gotrue
```

Details: [SECURITY.md](SECURITY.md) (loopback bind, JWT secret, mailer URL).

#### Path B — Full stack: Docker Compose

The main subject of this repo. A single command brings up **11
services**: Postgres 17, GoTrue, PostgREST, Realtime, Storage, Edge
Functions, the Studio dashboard, Supavisor (connection pooler), Meta,
ImgProxy, plus an Envoy API gateway.

- **You get:** the full self-hosted equivalent of managed Supabase —
  Studio included.
- **Requirement:** a host with a **real Linux kernel** that can run
  Docker (Engine ≥ 24 + Compose v2). **Path B does not run on Zo**
  (gVisor sandbox) — no mount-namespace permissions (verified, see
  [DOGRULAMA.md](DOGRULAMA.md)). On Zo use Path A; on a real-kernel VPS
  run `./setup.sh` (or point `DOCKER_HOST` at a remote daemon).
- **Proof:** **5/5 end-to-end tests passed** on a real Docker host
  (compose healthchecks, Studio, GoTrue signup→JWT, PostgREST CRUD,
  Storage upload) — [DOGRULAMA.md](DOGRULAMA.md).

| | Path A — GoTrue binary | Path B — Full stack |
|---|---|---|
| Zo (gVisor) | Compatible (recommended) | Does not run |
| Docker | Not needed | Required |
| Postgres | Required (existing DB works) | Bundled, in-container |
| Scope | Auth only | Auth + REST + Realtime + Storage + Functions + Studio |
| Environment | Anywhere, incl. sandboxes | Real-kernel host |
| When | "I just need login" | "I want all of Supabase" |

### Cost

| | Supabase Cloud (Pro) | Zo Computer | Real-kernel VPS |
|---|---|---|---|
| Price | $25/mo + usage fees | $18/mo flat | Depends on provider |
| What runs | Everything (managed) | **Path A only** (Auth) | **Path A + Path B** (full stack) |
| Package | Managed service + plan limits | 4 CPU / 32 GB RAM + $10 AI credit (chat + image gen) + remote terminal | Your chosen plan |
| Limits | Plan quotas (DB size, bandwidth, MAU…) | Your hardware | Your hardware |
| Data | Supabase infrastructure | **Your environment** | **Your box**, full root |

> **Note:** Zo is a gVisor sandbox and cannot run Docker containers —
> the $18 Zo package hosts **Auth (GoTrue) only**, not all of Supabase.
> Studio, Storage, Realtime and PostgREST need a real-kernel VPS.

Honest notes:

- Supabase has a free tier — it may be enough for small experiments.
  This repo is for when the free tier isn't enough, or when you want to
  own the infrastructure.
- Self-hosting means operational responsibility: updates, backups and
  hardening (TLS, firewall) are on you — see [SECURITY.md](SECURITY.md).

### Zo Computer (for Path A)

> **$18/mo package (Zo Computer):** 4 CPU / 32 GB RAM + $10 AI credit
> (chat + image generation) + remote terminal access.
>
> Zo is a **gVisor sandbox** — it cannot run Docker containers; **Path A
> (GoTrue binary)** is the Zo-compatible path, Path B (full Docker stack)
> is not. Sign-up / referral:
> [https://zo-computer.cello.so/rWtkIf0NXRp](https://zo-computer.cello.so/rWtkIf0NXRp)
>
> For the full stack (Path B), any real-kernel VPS that can run Docker
> (Hetzner, DigitalOcean, Contabo, etc.) works.

### Quickstart (Path B)

```bash
git clone https://github.com/ZoriaSoft/supabase-selfhost.git
cd supabase-selfhost
./setup.sh
```

`setup.sh` checks Docker, creates `.env`, **generates all secrets** (JWT
secret + anon/service keys via the official HS256 method), starts the
stack and prints your URLs.

- **Studio:** `http://<host>:8000` (gateway, basic auth:
  `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD` from `.env`). The direct
  `:3000` port has no auth and is localhost-only — use an SSH tunnel:
  `ssh -L 3000:localhost:3000 <host>`
- **API gateway:** `http://<host>:8000` (`/rest/v1`, `/auth/v1`,
  `/storage/v1`, `/realtime/v1`, `/functions/v1`)
- **Postgres:** `localhost:5432` (Supavisor session) / `:6543`
  (transaction pooler)

Secrets live in `.env` (gitignored). Before exposing anything to a
network, read [SECURITY.md](SECURITY.md): put the gateway behind a TLS
reverse proxy and never expose Postgres publicly.

### Requirements (Path B)

- Docker Engine ≥ 24 + Compose v2
- A host with a real Linux kernel — gVisor/sandbox environments won't work
- ~4 GB disk for images + your data

### Verification

End-to-end verification results (healthchecks, Studio, GoTrue
signup→JWT, PostgREST CRUD, Storage upload) are documented in
[DOGRULAMA.md](DOGRULAMA.md) (Turkish). To test your own install:

```bash
# First prepare the PostgREST test table (on the host, once):
docker exec supabase-db psql -U postgres -c \
  "CREATE TABLE IF NOT EXISTS public.verify_items(id bigserial primary key, name text, created_at timestamptz default now()); NOTIFY pgrst, 'reload schema';"

docker run --rm --network supabase_default -v "$PWD:/v" \
  --entrypoint sh curlimages/curl:8.14.1 /v/verify.sh
```

### License

Apache License 2.0 — see [LICENSE](LICENSE).
