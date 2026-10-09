#!/bin/sh
set -e

# Generate SHA1 base64 hash for Envoy basic auth user list
PASSWORD_HASH=$(printf '%s' "${DASHBOARD_PASSWORD}" | openssl sha1 -binary | openssl base64)
DASHBOARD_BASIC_AUTH="${DASHBOARD_USERNAME}:{SHA}${PASSWORD_HASH}"

echo "Generating Envoy configuration..."

# Process the lds.yaml template with environment variables using sed
# Using | as delimiter since JWT tokens contain /
# supabase-selfhost: escape sed replacement metachars (\ & |) so values like
# a SUPABASE_PUBLIC_URL containing '&' cannot corrupt the generated config.
sedesc() { printf '%s' "$1" | sed -e 's/[\&|]/\\&/g'; }
sed -e "s|\${ANON_KEY}|$(sedesc "$ANON_KEY")|g" \
    -e "s|\${ANON_KEY_ASYMMETRIC}|$(sedesc "$ANON_KEY_ASYMMETRIC")|g" \
    -e "s|\${SERVICE_ROLE_KEY}|$(sedesc "$SERVICE_ROLE_KEY")|g" \
    -e "s|\${SERVICE_ROLE_KEY_ASYMMETRIC}|$(sedesc "$SERVICE_ROLE_KEY_ASYMMETRIC")|g" \
    -e "s|\${SUPABASE_PUBLISHABLE_KEY}|$(sedesc "$SUPABASE_PUBLISHABLE_KEY")|g" \
    -e "s|\${SUPABASE_SECRET_KEY}|$(sedesc "$SUPABASE_SECRET_KEY")|g" \
    -e "s|\${SUPABASE_PUBLIC_URL}|$(sedesc "$SUPABASE_PUBLIC_URL")|g" \
    -e "s|\${DASHBOARD_BASIC_AUTH}|$(sedesc "$DASHBOARD_BASIC_AUTH")|g" \
    /etc/envoy/lds.template.yaml > /etc/envoy/lds.yaml

if [ -n "$SUPABASE_SECRET_KEY" ] && \
   [ -n "$SUPABASE_PUBLISHABLE_KEY" ] && \
   [ -n "$SERVICE_ROLE_KEY_ASYMMETRIC" ] && \
   [ -n "$ANON_KEY_ASYMMETRIC" ]; then
  echo "Envoy sb_ key translation enabled"
else
  echo "Envoy running in legacy API key mode (sb_ keys disabled)"
fi

echo "Envoy configuration generated successfully"
echo "Starting Envoy..."

# Start Envoy
exec envoy -c /etc/envoy/envoy.yaml "$@"
