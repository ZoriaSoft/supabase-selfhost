# Security / Güvenlik

**English first, Türkçe aşağıda.**

## Before you expose this stack to a network

1. **Never reuse default secrets.** `setup.sh` generates fresh secrets —
   if you created `.env` by hand, change `JWT_SECRET`, `POSTGRES_PASSWORD`,
   `DASHBOARD_PASSWORD`, `SECRET_KEY_BASE`, `VAULT_ENC_KEY`,
   `PG_META_CRYPTO_KEY`, `LOGFLARE_*`, `S3_PROTOCOL_*` before first boot.
   Rotating `JWT_SECRET` invalidates all issued tokens — regenerate
   `ANON_KEY`/`SERVICE_ROLE_KEY` together with it.
2. **Put the gateway behind TLS.** Terminate HTTPS at a reverse proxy
   (Caddy, nginx, Traefik) in front of `:8000`. Do not expose plain HTTP
   to the internet.
3. **Never expose Postgres publicly.** `:5432`/`:6543` should be bound to
   localhost or firewalled to your app servers only. The Supavisor port
   mapping exists for convenience — restrict it (e.g.
   `127.0.0.1:5432:5432`) on any host with a public interface.
4. **Protect the Studio dashboard.** Studio has full database access.
   Through the gateway (`:8000`) it sits behind HTTP basic auth
   (`DASHBOARD_USERNAME`/`DASHBOARD_PASSWORD`). The direct `:3000` port has
   **no auth at all** — it is bound to `127.0.0.1` by default; reach it via
   an SSH tunnel (`ssh -L 3000:localhost:3000 <host>`). Never change that
   mapping to a public interface. Prefer restricting Studio to
   VPN/localhost or an authenticated proxy.
5. **`.env` is a secret.** It is gitignored — keep it that way. Do not
   commit, paste, or log it. Rotate if it ever leaks.
6. **`SERVICE_ROLE_KEY` bypasses Row Level Security.** Never ship it in
   client code, mobile apps, or public repos.
7. **Email auth needs real SMTP.** With the default fake SMTP values,
   signup emails are not delivered — for a private instance
   `ENABLE_EMAIL_AUTOCONFIRM=true` (default in `setup.sh`) or configure a
   real SMTP provider in `.env`.
8. **Keep images updated.** `docker compose pull && docker compose up -d`
   picks up new upstream image tags. Follow
   https://github.com/supabase/supabase/releases for the `docker/` dir.
9. **Backups.** At minimum `pg_dump` via the pooler port and a copy of
   `volumes/storage/` + `.env`. Test restores.

## If you run GoTrue standalone (Path A, no Docker)

**Zo note:** Zo Computer is a gVisor sandbox — Docker containers do not
run there. Path A (this binary GoTrue flow) is the Zo-compatible path;
Path B (`docker compose` / `./setup.sh`) needs a real-kernel VPS.
Referral for the $18/mo Zo package: https://zo-computer.cello.so/rWtkIf0NXRp

Scaffold with `./scripts/setup-gotrue.sh` (downloads a prebuilt
`supabase/auth` binary into `bin/gotrue`, writes `gotrue.env` from
`scripts/gotrue.env.example`). SQL helper: `scripts/create-auth-role.sql`.

- **Bind to loopback.** Set `GOTRUE_API_HOST=127.0.0.1` and put a TLS-
  terminating reverse proxy in front — GoTrue must never listen on a
  public interface in plain HTTP.
- **Least-privilege DB role.** Give GoTrue a dedicated Postgres role
  (e.g. `supabase_auth_admin`) scoped to the `auth` schema — not a
  superuser.
- **`GOTRUE_JWT_SECRET` is the master key.** Anyone holding it can mint
  admin tokens. Store it in a root-only env file (`chmod 600`), never in
  a repo, client bundle, or log.
- **Mailer links need a public URL.** Set `GOTRUE_SITE_URL` /
  `API_EXTERNAL_URL` to the HTTPS origin, or confirmation/recovery
  emails will point at localhost.
- **Rate-limit the public surface.** `/signup`, `/token` and
  `/magiclink` are abuse targets — throttle and (for public apps)
  captcha-gate them at the proxy layer.


## GoTrue tek başına (Yol A, Docker yok)

**Zo notu:** Zo Computer bir gVisor sandbox'tır — Docker container
çalışmaz. Yol A (binary GoTrue) Zo-uyumlu yoldur; Yol B gerçek kernel'lı
VPS ister. Zo $18/ay paket referral: https://zo-computer.cello.so/rWtkIf0NXRp

Ayrıntılar yukarıdaki Path A maddeleriyle aynıdır (`scripts/setup-gotrue.sh`,
loopback bind, least-privilege DB rolü, JWT secret).

## Üretime çıkmadan önce

1. **Varsayılan secret'ları asla kullanma.** `setup.sh` taze üretir; elle
   oluşturduysan ilk açılıştan önce tümünü değiştir. `JWT_SECRET`
   döndürülürse `ANON_KEY`/`SERVICE_ROLE_KEY` de birlikte yenilenmelidir.
2. **TLS'siz dışa açma.** `:8000` önüne Caddy/nginx/Traefik ile HTTPS
   sonlandırması koy.
3. **Postgres'i asla internete açma.** `:5432`/`:6543` yalnız localhost veya
   uygulama sunucularına açık olsun (`127.0.0.1:5432:5432` gibi kısıtla).
4. **Studio panelini koru.** Studio veritabanına tam erişir. Gateway
   (`:8000`) üzerinden basic-auth arkasındadır; doğrudan `:3000` portunda
   **hiç şifre yoktur** — bu yüzden varsayılan olarak `127.0.0.1`'e
   bağlıdır, SSH tünelle eriş (`ssh -L 3000:localhost:3000 <sunucu>`).
   Bu eşlemeyi asla public arayüze açma.
5. **`.env` gizlidir.** Git'e girmez; sızdıysa rotate et.
6. **`SERVICE_ROLE_KEY` RLS'i bypass eder.** İstemci koduna asla koyma.
7. **SMTP'siz e-posta auth çalışmaz.** Gerçek SMTP gir ya da
   `ENABLE_EMAIL_AUTOCONFIRM=true` (setup.sh varsayılanı) kullan.
8. **Image'ları güncel tut:** `docker compose pull && docker compose up -d`.
9. **Yedek:** en az `pg_dump` + `volumes/storage/` + `.env` kopyası;
   restore'u test et.

## GoTrue tek binary çalıştırıyorsan (Yol A, Docker'sız)

İskelet: `./scripts/setup-gotrue.sh` (prebuilt `supabase/auth` binary
`bin/gotrue` + `gotrue.env`). SQL yardımcısı: `scripts/create-auth-role.sql`.

- **Loopback'e bind et.** `GOTRUE_API_HOST=127.0.0.1` kullan ve önüne TLS
  sonlandıran bir reverse proxy koy — GoTrue public arayüzde asla düz
  HTTP dinlememeli.
- **En az yetkili DB rolü.** GoTrue'ya ayrı bir Postgres rolü ver
  (`supabase_auth_admin` gibi, `auth` schema'sıyla sınırlı) — süper
  kullanıcı değil.
- **`GOTRUE_JWT_SECRET` ana anahtardır.** Elinde tutan admin token
  basabilir. Yalnız root-okur env dosyasında tut (`chmod 600`); repo'ya,
  client bundle'a, log'a girmez.
- **Mailer linkleri public URL ister.** `GOTRUE_SITE_URL` /
  `API_EXTERNAL_URL`'i HTTPS origin'e ayarla; yoksa onay/kurtarma
  e-postaları localhost'a işaret eder.
- **Public yüzü rate-limit'le.** `/signup`, `/token`, `/magiclink`
  istismar hedefidir — proxy katmanında throttle + (herkese açık
  uygulamada) captcha uygula.
