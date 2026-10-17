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
set -a
# shellcheck source=/dev/null
. /v/.env
set +a
GW="http://api-gw:8000"   # internal gateway address on the compose network

# --- 2. Studio (internal + we separately check host :3000 from outside) ---
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -L "http://studio:3000/")
if [ "$CODE" = "200" ]; then CODE_OK=0; else CODE_OK=1; fi
result "$CODE_OK" 'studio-http-200' "http://studio:3000 -L -> HTTP $CODE"

# --- 3. GoTrue: signup + password signin -> user JWT ---
EMAIL="verify-$(head -c4 /dev/urandom | od -An -tx1 | tr -d ' \n')@example.com"
PW="SupaVerify!$(head -c4 /dev/urandom | od -An -tx1 | tr -d ' \n')"
BODY="{\"email\":\"$EMAIL\",\"password\":\"$PW\"}"
SIGNUP_CODE=$(curl -s -o /tmp/.verify_signup -w '%{http_code}' --max-time 20 -X POST "$GW/auth/v1/signup" -H "apikey: $ANON_KEY" -H 'Content-Type: application/json' -d "$BODY")
SIGNIN_CODE=$(curl -s -o /tmp/.verify_signin -w '%{http_code}' --max-time 20 -X POST "$GW/auth/v1/token?grant_type=password" -H "apikey: $ANON_KEY" -H 'Content-Type: application/json' -d "$BODY")
SIGNIN=$(cat /tmp/.verify_signin 2>/dev/null || true)
JWT=$(printf '%s' "$SIGNIN" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
if [ -n "$JWT" ] && [ ${#JWT} -gt 100 ]; then JWT_OK=0; else JWT_OK=1; fi
result "$JWT_OK" 'gotrue-signup-signin' "user=$EMAIL token_len=${#JWT} signup_http=$SIGNUP_CODE signin_http=$SIGNIN_CODE"
rm -f /tmp/.verify_signup /tmp/.verify_signin

# Run-unique marker: stale rows/files from earlier runs can never
# satisfy the select/download checks below.
RUN_ID="verify-$(date +%s)-$$"
ROW_NAME="$RUN_ID"
BUCKET="$RUN_ID"
FILE_NAME="hello-$RUN_ID.txt"
FILE_CONTENT="selfhost-ok-$RUN_ID"

# --- 4. PostgREST: insert + select with user JWT (table created host-side) ---
INS_CODE=$(curl -s -o /tmp/.verify_ins -w '%{http_code}' --max-time 20 -X POST "$GW/rest/v1/verify_items" -H "apikey: $ANON_KEY" -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' -H 'Prefer: return=representation' -d "{\"name\":\"$ROW_NAME\"}")
INS=$(cat /tmp/.verify_ins 2>/dev/null || true)
SEL_CODE=$(curl -s -o /tmp/.verify_sel -w '%{http_code}' --max-time 20 "$GW/rest/v1/verify_items?select=id,name&name=eq.$ROW_NAME" -H "apikey: $ANON_KEY" -H "Authorization: Bearer $JWT")
SEL=$(cat /tmp/.verify_sel 2>/dev/null || true)
CRUD_OK=1
if [ "$INS_CODE" = "201" ] && [ "$SEL_CODE" = "200" ]; then
  if printf '%s' "$SEL" | grep -q "$ROW_NAME"; then CRUD_OK=0; fi
fi
result "$CRUD_OK" 'postgrest-crud' "insert_http=$INS_CODE select_http=$SEL_CODE name=$ROW_NAME insert=$(clip "$INS" 140) select=$(clip "$SEL" 140)"
ROW_ID=$(printf '%s' "$INS" | sed -n 's/.*"id": *\([0-9][0-9]*\).*/\1/p')

# --- 5. Storage: create bucket + upload + public read ---
B=$(curl -s --max-time 20 -o /dev/null -w '%{http_code}' -X POST "$GW/storage/v1/bucket" -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" -H 'Content-Type: application/json' -d "{\"id\":\"$BUCKET\",\"name\":\"$BUCKET\",\"public\":true}")
UP_CODE=$(curl -s -o /tmp/.verify_up -w '%{http_code}' --max-time 20 -X POST "$GW/storage/v1/object/$BUCKET/$FILE_NAME" -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" -H 'Content-Type: text/plain' --data-binary "$FILE_CONTENT")
UP=$(cat /tmp/.verify_up 2>/dev/null || true)
DL_CODE=$(curl -s -o /tmp/.verify_dl -w '%{http_code}' --max-time 20 "$GW/storage/v1/object/public/$BUCKET/$FILE_NAME")
DL=$(cat /tmp/.verify_dl 2>/dev/null || true)
DL_OK=1
if { [ "$B" = "200" ] || [ "$B" = "201" ]; } && { [ "$UP_CODE" = "200" ] || [ "$UP_CODE" = "201" ]; } && [ "$DL_CODE" = "200" ] && [ "$DL" = "$FILE_CONTENT" ]; then DL_OK=0; fi
result "$DL_OK" 'storage-bucket-upload' "bucket_http=$B upload_http=$UP_CODE download_http=$DL_CODE bucket=$BUCKET file=$FILE_NAME upload=$(clip "$UP" 120) read=$(clip "$DL" 80)"

# --- cleanup: remove the row, object and bucket created by this run ---
if [ -n "${ROW_ID:-}" ]; then
  curl -s -o /dev/null --max-time 20 -X DELETE "$GW/rest/v1/verify_items?id=eq.$ROW_ID" -H "apikey: $ANON_KEY" -H "Authorization: Bearer $JWT" || true
fi
curl -s -o /dev/null --max-time 20 -X DELETE "$GW/storage/v1/object/$BUCKET/$FILE_NAME" -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" || true
curl -s -o /dev/null --max-time 20 -X DELETE "$GW/storage/v1/bucket/$BUCKET" -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" -H 'Content-Type: application/json' -d '{}' || true
rm -f /tmp/.verify_ins /tmp/.verify_sel /tmp/.verify_up /tmp/.verify_dl

echo "----"
echo "TOTAL FAILURES: $FAILS"
exit $FAILS
