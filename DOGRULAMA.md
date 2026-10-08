# DOGRULAMA — supabase-selfhost test raporu

**Tarih:** 2026-10-05

## Özet

| # | Test | Sonuç |
|---|------|-------|
| 1 | `docker compose ps` — tüm servisler healthy | **PASS** (11/11) |
| 2 | Studio HTTP 200 | **PASS** |
| 3 | GoTrue: kullanıcı aç → giriş → JWT | **PASS** |
| 4 | PostgREST: tablo aç → insert/select (user JWT) | **PASS** |
| 5 | Storage: bucket aç → dosya yükle → public oku | **PASS** |
| A | Yol A: GoTrue binary, Docker'sız (Zo üzerinde) | **PASS** (7/7) |

Stack resmi `supabase/supabase` reposunun `docker/` dizinine dayanır
(snapshot: `supabase@master`, 2026-10-05, gotrue v2.196.0, postgrest v14.17,
postgres 17.6.1.136, envoy v1.39.1). Upstream'e göre fark: Studio'ya
doğrudan `:3000` port eşlemesi (loopback) ve Supavisor portlarının
loopback'e bağlanması.

## Ortam notu — Zo Computer'da Docker çalışmaz

Zo Computer klasik bir VPS değil, **gVisor sandbox**'tır (kernel
`4.19.0-gvisor`, `SYS_ADMIN` / `NET_ADMIN` capability'leri yok).
Deneme (2026-10-05, Debian 12, `docker.io` 20.10.24):

- `dockerd --storage-driver=vfs --iptables=false --bridge=none`
  **başlıyor**, socket dinliyor, image pull çalışıyor;
- ama `docker run hello-world` layer apply'de ölüyor:

  ```
  docker: failed to register layer: ApplyLayer exit status 1
  Error creating mount namespace before pivot: operation not permitted
  ```

Yani Zo'da Docker **kurulabilir ama container çalıştıramaz**. Normal
Linux kernel'lı bir VPS'te bu engel yoktur — Yol B doğrulaması bu yüzden
gerçek bir Docker host'unda koşuldu:

**Doğrulama host'u:** Windows makinede Docker Desktop 4.90.0,
Engine **29.7.2**, Compose **v5.5.1**, linux/amd64 container'lar.
Geçici bir deploy dizini kullanıldı
(scratch — doğrulama sonrası `down -v` ile kaldırıldı). Gerekli portlar
(3000/8000/5432/6543) önceden boş doğrulandı, mevcut servis yoktu.

## Kurulum adımları (yeniden üretilebilir)

```bash
# bundle: docker-compose.yml + .env (utils/generate-keys.sh ile üretilmiş
# gerçek secret'lar) + volumes/ → hedef host'a kopyala, sonra:
docker compose up -d        # ilk çalıştırma ~9 dk sürdü (image pull'lar)
```

## Kanıtlar

### 1. Compose sağlık — 11/11 healthy

```
realtime-dev.supabase-realtime   Up (healthy)
supabase-auth      (gotrue)      Up (healthy)
supabase-db        (pg 17)       Up (healthy)
supabase-edge-functions          Up (healthy)
supabase-envoy     api-gw        Up (healthy)   0.0.0.0:8000->8000
supabase-imgproxy                Up (healthy)
supabase-meta                    Up (healthy)
supabase-pooler    supavisor     Up (healthy)   0.0.0.0:5432, :6543
supabase-rest      postgrest     Up (healthy)
supabase-storage                 Up (healthy)
supabase-studio                  Up (healthy)   0.0.0.0:3000->3000
```

> Not: bu çıktı doğrulama gününden kalmadır. Repo bugünkü hâliyle meta
> servisine healthcheck ekledi; supavisor (`:5432`/`:6543`) ve Studio
> (`:3000`) portlarını loopback'e bağladı — güncel kurulumda bu satırlar
> `127.0.0.1` önekli görünür.

### 2. Studio

```
host:  curl -L http://localhost:3000/  -> 307 -> /project/default -> 200 (12168 bayt)
iç ağ: curl -L http://studio:3000/     -> 200
```

### 3. GoTrue

```
POST /auth/v1/signup                       -> user oluştu (autoconfirm)
POST /auth/v1/token?grant_type=password    -> access_token, 821 karakter JWT
  user=verify-ab6a49aa@example.com  iss=http://localhost:8000/auth/v1
```

### 4. PostgREST

```
docker exec supabase-db psql -c "CREATE TABLE public.verify_items(...)"
POST /rest/v1/verify_items  (Bearer=user JWT)
  -> [{"id":1,"name":"hello-vps","created_at":"2026-10-05T15:42:32Z"}]
GET  /rest/v1/verify_items?select=id,name
  -> [{"id":1,"name":"hello-vps"}]
```

Not: yeni tablo oluşturduktan sonra PostgREST schema cache'i tazelemek
gerekir (`NOTIFY pgrst, 'reload schema'` veya `docker restart
supabase-rest`) — yoksa 404 döner. Doğrulamada restart kullanıldı.

### 5. Storage

```
POST /storage/v1/bucket {id:verify-bucket, public:true}     -> HTTP 200
POST /storage/v1/object/verify-bucket/hello.txt 'selfhost-ok'
  -> {"Key":"verify-bucket/hello.txt","Id":"d6ef36e1-..."}
GET  /storage/v1/object/public/verify-bucket/hello.txt      -> 'selfhost-ok'
```


## verify.sh — POSIX uyumluluk notu

`verify.sh` Alpine ash / POSIX `sh` altında koşacak şekilde yazıldı
(`#!/bin/sh`, `curlimages/curl` entrypoint). Bash-only `${var:0:N}`
substring'leri **kullanılmaz** — ash'te `Bad substitution` verir.
Kısaltma için `clip()` yardımcısı (`printf | cut -c1-N`) kullanılıyor;
bu düzeltme 2026-10-05 doğrulamasında sabitlendi.

## Yol A — GoTrue e2e (Zo üzerinde, Docker yok) — 2026-10-05

**Host:** Zo Computer (gVisor sandbox) · Postgres 16.14 (Docker'sız) ·
GoTrue binary `bin/gotrue` **v2.197.0** (`scripts/setup-gotrue.sh`).

Test, mevcut hiçbir veritabanına dokunmadan geçici bir DB + rol ve
loopback bir port üzerinde koşuldu; test sonunda DB ve rol silindi.

| # | Adım | Sonuç |
|---|------|-------|
| A1 | `scripts/setup-gotrue.sh` (binary + env iskeleti) | **PASS** |
| A2 | `create-auth-role.sql` ile ayrı rol/DB | **PASS** |
| A3 | `gotrue migrate` → 75 migration, `auth.*` tabloları | **PASS** |
| A4 | `gotrue` start → `GET /health` 200 | **PASS** |
| A5 | `POST /signup` (autoconfirm) → user + access_token | **PASS** |
| A6 | `POST /token?grant_type=password` → access_token | **PASS** |
| A7 | Tear-down (gotrue durdur, DB/rol sil) | **PASS** |

**Önemli:** `gotrue serve` / düz start migration koşturmaz; ilk
açılıştan önce `./bin/gotrue migrate` gerekir (README ve
`setup-gotrue.sh` sonraki adımlarında yazılı).

## Sonuç

- **Yol B (full stack):** gerçek bir Docker host'unda uçtan uca
  çalışıyor; temiz klon → `./setup.sh` ile tek komut kurulum hedefi
  karşılanıyor. Zo/gVisor üzerinde çalışmaz — gerçek kernel'lı bir VPS
  gerekir (ya da `DOCKER_HOST` ile uzak daemon).
- **Yol A (yalnız Auth):** Zo dahil Docker'sız ortamlarda çalışıyor.
