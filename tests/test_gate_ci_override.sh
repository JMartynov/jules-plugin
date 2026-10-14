#!/usr/bin/env bash
# Protected-path behaviour of scripts/worktree_gate.sh, with a fake `jules` CLI and a throwaway repo.
set -uo pipefail
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
GATE="$ROOT/scripts/worktree_gate.sh"
PASS=0; FAIL=0
ok(){ echo "  ✅ [PASS] $1"; PASS=$((PASS+1)); }
bad(){ echo "  ❌ [FAIL] $1"; FAIL=$((FAIL+1)); }
T=$(mktemp -d /tmp/jules-gate-ci-XXXXXX)
mkdir -p "$T/bin"
cat > "$T/bin/jules" <<'EOS'
#!/usr/bin/env bash
cat "$FAKE_PATCH"
EOS
chmod +x "$T/bin/jules"
mkpatch(){ printf 'diff --git a/%s b/%s\nnew file mode 100644\nindex 0000000..e69de29\n--- /dev/null\n+++ b/%s\n@@ -0,0 +1 @@\n+x\n' "$1" "$1" "$1" > "$2"; }
mkpatch .github/workflows/ci.yml "$T/ci.patch"
mkpatch .env "$T/env.patch"
mkpatch docs/ok.md "$T/ok.patch"
git init -q -b main "$T/repo" && cd "$T/repo" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
run(){ PATH="$T/bin:$PATH" FAKE_PATCH="$1" JULES_GATE_TEST_CMD="true" "${@:2}" bash "$GATE" s1 main >"$T/out" 2>&1; echo $?; }
rc=$(FAKE_PATCH="$T/ci.patch" PATH="$T/bin:$PATH" JULES_GATE_TEST_CMD=true bash "$GATE" s1 main >"$T/out" 2>&1; echo $?)
[[ "$rc" == 6 ]] && ok "workflow file blocked by default (exit 6)" || bad "workflow file default rc=$rc"
rc=$(FAKE_PATCH="$T/ci.patch" JULES_GATE_ALLOW_CI=1 PATH="$T/bin:$PATH" JULES_GATE_TEST_CMD=true bash "$GATE" s1 main >"$T/out" 2>&1; echo $?)
[[ "$rc" != 6 ]] && grep -q "JULES_GATE_ALLOW_CI=1" "$T/out" && ok "workflow file allowed with JULES_GATE_ALLOW_CI=1 (and warned)" || bad "override rc=$rc"
rc=$(FAKE_PATCH="$T/env.patch" JULES_GATE_ALLOW_CI=1 PATH="$T/bin:$PATH" JULES_GATE_TEST_CMD=true bash "$GATE" s1 main >"$T/out" 2>&1; echo $?)
[[ "$rc" == 6 ]] && ok ".env always blocked, even with the override" || bad ".env rc=$rc"
rc=$(FAKE_PATCH="$T/ok.patch" PATH="$T/bin:$PATH" JULES_GATE_TEST_CMD=true bash "$GATE" s1 main >"$T/out" 2>&1; echo $?)
[[ "$rc" != 6 ]] && ok "ordinary path not blocked" || bad "ordinary rc=$rc"
cd /; rm -rf "$T"
echo " Passed: $PASS  Failed: $FAIL"; [[ $FAIL -eq 0 ]]
