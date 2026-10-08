#!/bin/sh
# supabase-selfhost end-to-end verification — runs INSIDE the compose network
# (docker run --rm --network supabase_default -v <dir>:/v --entrypoint sh curlimages/curl /v/verify.sh)
# Prints PASS/FAIL per step with evidence. Exit code = number of failures.
#
# Written for POSIX sh / Alpine ash (curlimages/curl). Do not use bash-only
# ${var:0:N} substrings — they fail with "Bad substitution" under dash/ash.
# Prerequisite (run once on the HOST before this script): create the
# PostgREST test table + reload the schema cache (see README "Verification"
# for the copy-paste docker exec command).
set -u
FAILS=0
clip() { printf '%s' "$1" | cut -c1-"$2"; }
result() { if [ "$1" = "0" ]; then echo "PASS  $2  :: $3"; else echo "FAIL  $2  :: $3"; FAILS=$((FAILS+1)); fi; }

# --- load .env (mounted at /v) ---
set -a; . /v/.env; set +a
GW="http://api-gw:8000"   # internal gateway address on the compose network

# --- 2. Studio (internal + we separately check host :3000 from outside) ---
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -L "http://studio:3000/")
[ "$CODE" = "200" ]; result $? 'studio-http-200' "http://studio:3000 -L -> HTTP $CODE"

# --- 3. GoTrue: signup + password signin -> user JWT ---
EMAIL="verify-$(head -c4 /dev/urandom | od -An -tx1 | tr -d ' \n')@example.com"
PW="SupaVerify!$(head -c4 /dev/urandom | od -An -tx1 | tr -d ' \n')"
BODY="{\"email\":\"$EMAIL\",\"password\":\"$PW\"}"
SIGNUP=$(curl -s --max-time 20 -X POST "$GW/auth/v1/signup" -H "apikey: $ANON_KEY" -H 'Content-Type: application/json' -d "$BODY")
SIGNIN=$(curl -s --max-time 20 -X POST "$GW/auth/v1/token?grant_type=password" -H "apikey: $ANON_KEY" -H 'Content-Type: application/json' -d "$BODY")
JWT=$(printf '%s' "$SIGNIN" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
[ -n "$JWT" ] && [ ${#JWT} -gt 100 ]; result $? 'gotrue-signup-signin' "user=$EMAIL token_len=${#JWT} signup=$(clip "$SIGNUP" 120)"

# --- 4. PostgREST: insert + select with user JWT (table created host-side) ---
INS=$(curl -s --max-time 20 -X POST "$GW/rest/v1/verify_items" -H "apikey: $ANON_KEY" -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' -H 'Prefer: return=representation' -d '{"name":"hello-vps"}')
SEL=$(curl -s --max-time 20 "$GW/rest/v1/verify_items?select=id,name" -H "apikey: $ANON_KEY" -H "Authorization: Bearer $JWT")
printf '%s' "$SEL" | grep -q 'hello-vps'; result $? 'postgrest-crud' "insert=$(clip "$INS" 140) select=$(clip "$SEL" 140)"

# --- 5. Storage: create bucket + upload + public read ---
B=$(curl -s --max-time 20 -o /dev/null -w '%{http_code}' -X POST "$GW/storage/v1/bucket" -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" -H 'Content-Type: application/json' -d '{"id":"verify-bucket","name":"verify-bucket","public":true}')
UP=$(curl -s --max-time 20 -X POST "$GW/storage/v1/object/verify-bucket/hello.txt" -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" -H 'Content-Type: text/plain' --data-binary 'selfhost-ok')
DL=$(curl -s --max-time 20 "$GW/storage/v1/object/public/verify-bucket/hello.txt")
[ "$DL" = "selfhost-ok" ]; result $? 'storage-bucket-upload' "bucket_http=$B upload=$(clip "$UP" 120) read='$DL'"

echo "----"
echo "TOTAL FAILURES: $FAILS"
exit $FAILS
