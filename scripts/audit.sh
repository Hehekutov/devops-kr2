#!/usr/bin/env bash
# Audit effective settings. Exit 1 means at least one failed condition.
set -uo pipefail
PASS=0; FAIL=0
check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf '[OK] %s\n' "$desc"; PASS=$((PASS+1))
  else
    printf '[FAIL] %s expected=%s actual=%s\n' "$desc" "$expected" "$actual"; FAIL=$((FAIL+1))
  fi
}
echo "Audit: $(hostname -f) $(date -Is)"
cfg=$(sudo /usr/sbin/sshd -T)
value() { awk -v key="$1" '$1==key {print $2}' <<< "$cfg"; }
echo '[1] SSH'
check 'Root login prohibited' no "$(value permitrootlogin)"
check 'Password authentication disabled' no "$(value passwordauthentication)"
check 'Nonstandard SSH port' yes "$([[ $(value port) != 22 ]] && echo yes || echo no)"
check 'MaxAuthTries' 3 "$(value maxauthtries)"
echo '[2] Firewall'
check 'UFW active' active "$(sudo env LC_ALL=C ufw status | awk '/^Status:/{print $2}')"
check 'Default deny incoming' yes "$(sudo env LC_ALL=C ufw status verbose | grep -q 'Default: deny (incoming)' && echo yes || echo no)"
echo '[3] Accounts'
awk -F: '$3>=1000 && $3<65534 {printf "  %s uid=%s\n",$1,$3}' /etc/passwd
if [[ -f /etc/nginx/sites-available/devops-site ]]; then
  echo '[4] Web server'
  check 'Nginx active' active "$(systemctl is-active nginx)"
  check 'Nginx syntax' 0 "$(sudo nginx -t >/dev/null 2>&1; echo $?)"
  check 'Certificate validity threshold' 0 "$(openssl x509 -in /etc/ssl/certs/devops.crt -checkend "${CERT_THRESHOLD:-2592000}" -noout >/dev/null 2>&1; echo $?)"
  bad=$(find /var/www/devops-site -perm -o+w -print)
  keymode=$(sudo stat -c '%a' /etc/ssl/private/devops.key)
  check 'No world writable content and key mode 600' yes "$([[ -z "$bad" && "$keymode" == 600 ]] && echo yes || echo no)"
fi
if [[ -f /home/devops/app/docker-compose.yml ]]; then
  echo '[5] Containers'
  check 'Docker active' active "$(systemctl is-active docker)"
  dbid=$(sudo docker compose --project-directory /home/devops/app ps -q db)
  health=$(sudo docker inspect -f '{{.State.Health.Status}}' "$dbid" 2>/dev/null || true)
  check 'Database healthy' healthy "$health"
  appaddr=$(sudo docker compose --project-directory /home/devops/app port app 5000 2>/dev/null)
  # Compose v5 may print :0 for an unpublished port. Inspect real bindings instead.
  dbaddr=$(sudo docker inspect -f '{{range (index .NetworkSettings.Ports "5432/tcp")}}{{.HostIp}}:{{.HostPort}}{{end}}' "$dbid" 2>/dev/null || true)
  exposed=$(ss -H -tln | awk '$4 ~ /:(5000|5432)$/ && $4 !~ /^127[.]0[.]0[.]1:/ {print $4}')
  check 'App bound to loopback and database unpublished' yes "$([[ "$appaddr" == '127.0.0.1:5000' && -z "$dbaddr" && -z "$exposed" ]] && echo yes || echo no)"
  check 'Environment file mode' 600 "$(stat -c '%a' /home/devops/app/.env)"
fi
echo '[6] Control work 2'
kr2_dir=/home/devops/kr2
redis_id=$(sudo docker compose --project-directory "$kr2_dir" ps -q redis)
kr2_health=$(sudo docker inspect -f '{{.State.Health.Status}}' "$redis_id" 2>/dev/null || true)
check 'KR2 Redis healthy' healthy "$kr2_health"
kr2_bind=$(sudo docker compose --project-directory "$kr2_dir" port app 8002 2>/dev/null || true)
check 'KR2 app bound to loopback' '127.0.0.1:8002' "$kr2_bind"
check 'KR2 environment mode' 600 "$(stat -c '%a' "$kr2_dir/.env")"
check 'KR2 certificate valid for 30 days' 0 "$(openssl x509 -in /etc/ssl/certs/kr2.crt -checkend 2592000 -noout >/dev/null 2>&1; echo $?)"
check 'KR2 Nginx site enabled' yes "$([[ -L /etc/nginx/sites-enabled/kr2 ]] && echo yes || echo no)"

echo "Passed: $PASS; failed: $FAIL"
[[ $FAIL -eq 0 ]]
