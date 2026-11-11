#!/bin/bash
# shellcheck disable=SC2016 # single-quoted payloads are literal commands to judge
# Feed block-test-weakening.sh payloads and check its exit code: 2 blocks, 0 passes.
#   block-test-weakening.test.sh [hook]   (default: the hook beside it)
DIR=$(cd "$(dirname "$0")" && pwd)
HOOK=${1:-$DIR/block-test-weakening.sh}
FAIL=0 RUN=0
T=$(mktemp -d)
trap 'rm -rf -- "$T"' EXIT
mkdir -p "$T/tests" "$T/src"
printf 'def test_a():\n    assert 1 == 1\n' >"$T/tests/test_a.py"
printf 'print(1)\n' >"$T/src/app.py"
ln -s tests "$T/lnk"
printf 'def test_b():\n    assert 2 == 2\n' >"$T/tests/test_b.py"
printf '@pytest.mark.skip\ndef test_s():\n    assert 3 == 3\n' >"$T/tests/test_skipped.py"
mkdir -p "$T/tests/__pycache__" "$T/build/lib/tests" "$T/node_modules/foo/tests"
: >"$T/tests/__pycache__/x.pyc"
: >"$T/tests/tmp.txt"
: >"$T/UPPER_TEST.PY"
mkdir "$T/.git"

# check <want> <worker: 1|0> <prune: 1|0> <json>
check() {
  local got err
  RUN=$((RUN + 1))
  err=$(printf '%s' "$4" | HERDR_WORKER=$2 HERDR_TEST_PRUNE=$3 "$HOOK" 2>&1 >/dev/null)
  got=$?
  if [[ $got != "$1" ]]; then
    echo "FAIL want $1 got $got: ${4:0:200}"
    FAIL=$((FAIL + 1))
  elif [[ $got == 2 && ($err != BLOCKED* || $err == *$'\n'*) ]]; then
    echo "FAIL a refusal must be one BLOCKED line, got: $err"
    FAIL=$((FAIL + 1))
  fi
}
bash_pl() { jq -nc --arg c "$1" --arg d "$T" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}'; }
write_pl() { jq -nc --arg f "$1" --arg c "$2" --arg d "$T" '{tool_name:"Write",cwd:$d,tool_input:{file_path:$f,content:$c}}'; }
edit_pl() { jq -nc --arg f "$1" --arg o "$2" --arg n "$3" --arg d "$T" '{tool_name:"Edit",cwd:$d,tool_input:{file_path:$f,old_string:$o,new_string:$n}}'; }
blocks() { check 2 1 0 "$(bash_pl "$1")"; }
passes() { check 0 1 0 "$(bash_pl "$1")"; }

# Deleting a test.
blocks 'rm tests/test_a.py'
blocks 'rm -rf tests'
blocks 'rm -rf ./tests/'
blocks 'rm test_x.py'
blocks 'rm pkg/app_test.go'
blocks 'rm web/app.test.ts'
blocks 'rm web/app.spec.js'
blocks 'rm hooks/x.test.sh'
blocks 'git rm tests/test_a.py'
blocks 'git rm -f src/test_a.py'
blocks 'git rm --cached tests/test_a.py'
blocks 'git -C src rm test_a.py'
blocks 'unlink tests/test_a.py'
blocks 'rm -f -- tests/test_a.py'
blocks 'rm src/app.py tests/test_a.py'
blocks 'rm src/app.py build/x.o tests/a.py src/y.py'
blocks 'rm "tests/my file.py"'
blocks "rm 'tests/it'\\''s.py'"
blocks 'rm tests/*.py'
blocks 'rm test_*.py'
blocks 'rm *.spec.ts'
blocks 'ls && rm tests/test_a.py'
blocks 'ls; rm tests/test_a.py'
blocks $'ls\nrm tests/test_a.py'
blocks '(rm tests/test_a.py)'
blocks 'FOO=1 rm tests/test_a.py'
blocks 'HERDR_TEST_PRUNE=1 rm tests/test_a.py'
blocks 'env HERDR_TEST_PRUNE=1 rm tests/test_a.py'
blocks 'sudo rm tests/test_a.py'
blocks 'command rm tests/test_a.py'
blocks "bash -c 'rm tests/test_a.py'"
blocks 'sh -c "rm tests/test_a.py"'
blocks 'echo $(rm tests/test_a.py)'
blocks 'echo "$(rm tests/test_a.py)"'
blocks 'echo `rm tests/test_a.py`'
blocks 'rm tests/$(touch /nonexistent/never).py'
blocks 'rm tests/`id`.py'
blocks 'cd tests && rm test_a.py'
blocks 'cd tests && rm *'
blocks 'rm lnk/test_a.py'
blocks 'rm -r lnk'
blocks "find tests -name '*.py' -delete"
blocks "find . -name 'test_*' -exec rm {} \;"
blocks "find . -name '*.spec.ts' -delete"

# Other commands pass.
passes 'rm -rf build'
passes 'rm src/app.py'
passes 'rm /tmp/x.log'
passes 'git rm src/app.py'
passes 'rm contest.py'
passes 'rm src/testing.py'
passes 'echo "rm tests/test_a.py"'
passes 'git commit -m "rm tests/test_a.py; rm test_x"'
passes 'echo rm tests/test_a.py'
passes 'grep -r rm tests'
passes 'ls tests'
passes 'cat tests/test_a.py'
passes 'pytest tests/'
passes 'git status'
passes 'cd tests && ls'
passes 'cat > tests/test_new.py <<EOF'
passes $'cat <<\'EOF\' > notes.txt\ndon\'t rm tests\nEOF'
passes "find src -name '*.o' -delete"
passes 'rm -rf node_modules'
passes ''
passes 'echo "unbalanced'

# The escape lets a worker delete a test, and nothing else.
check 0 1 1 "$(bash_pl 'rm tests/test_a.py')"
check 0 1 1 "$(bash_pl 'git rm tests/test_a.py src/app.py')"
check 0 1 1 "$(write_pl "$T/tests/test_a.py" '')"
check 2 1 1 "$(edit_pl "$T/tests/test_a.py" 'assert 1 == 1' 'pytest.skip("x")')"
check 2 1 0 "$(bash_pl 'rm tests/test_a.py')"
# Only the exact value 1 is the escape.
check 2 1 yes "$(bash_pl 'rm tests/test_a.py')"
check 2 1 0 "$(bash_pl 'HERDR_TEST_PRUNE=1 rm tests/test_a.py')"

# Write.
check 2 1 0 "$(write_pl tests/test_a.py '')"
check 2 1 0 "$(write_pl "$T/tests/test_a.py" '')"
check 2 1 0 "$(write_pl "$T/tests/test_a.py" $' \n\t\n')"
check 2 1 0 "$(write_pl "$T/lnk/test_a.py" '')"
check 2 1 0 "$(write_pl "$T/web/app.test.ts" '')"
check 2 1 0 "$(write_pl "$T/web/app.spec.ts" '  ')"
check 0 1 0 "$(write_pl "$T/src/app.py" '')"
check 0 1 0 "$(write_pl "$T/tests/test_a.py" $'def test_a():\n    assert 2 == 2\n')"
check 0 1 0 "$(write_pl "$T/tests/test_new.py" $'def test_b():\n    assert True\n')"

# Edit: a skip, an xfail or a commented assert.
check 2 1 0 "$(edit_pl "$T/tests/test_a.py" 'def test_a' $'@pytest.mark.skip\ndef test_a')"
check 2 1 0 "$(edit_pl "$T/tests/test_a.py" 'def test_a' $'@pytest.mark.xfail\ndef test_a')"
check 2 1 0 "$(edit_pl "$T/tests/test_a.py" 'def test_a' $'@pytest.mark.skipif(True, reason="x")\ndef test_a')"
check 2 1 0 "$(edit_pl "$T/tests/test_a.py" 'assert 1 == 1' 'pytest.skip("later")')"
check 2 1 0 "$(edit_pl "$T/tests/test_a.py" 'assert 1 == 1' 'pytest.xfail("later")')"
check 2 1 0 "$(edit_pl "$T/tests/test_a.py" 'assert 1 == 1' 'self.skipTest("later")')"
check 2 1 0 "$(edit_pl "$T/web/a.test.ts" "it('x'" "it.skip('x'")"
check 2 1 0 "$(edit_pl "$T/web/a.test.ts" "it('x'" "xit('x'")"
check 2 1 0 "$(edit_pl "$T/web/a.test.ts" "describe('x'" "describe.skip('x'")"
check 2 1 0 "$(edit_pl "$T/pkg/a_test.go" 'x := 1' $'t.Skip("later")\nx := 1')"
check 2 1 0 "$(edit_pl "$T/pkg/a_test.go" 'x := 1' $'t.Skipf("later")\nx := 1')"
check 2 1 0 "$(edit_pl "$T/tests/test_a.py" '    assert 1 == 1' '    # assert 1 == 1')"
check 2 1 0 "$(edit_pl "$T/web/a.test.ts" '  expect(a).toBe(1)' '  // expect(a).toBe(1)')"
check 2 1 0 "$(edit_pl "$T/lnk/test_a.py" 'def test_a' $'@pytest.mark.skip\ndef test_a')"
check 2 1 0 "$(jq -nc --arg f "$T/tests/test_a.py" '{tool_name:"MultiEdit",tool_input:{file_path:$f,edits:[{old_string:"a",new_string:"b"},{old_string:"def test_a",new_string:"@pytest.mark.skip\ndef test_a"}]}}')"
check 0 1 0 "$(jq -nc --arg f "$T/tests/test_a.py" '{tool_name:"MultiEdit",tool_input:{file_path:$f,edits:[{old_string:"a",new_string:"b"}]}}')"

# Edit: other changes pass.
check 0 1 0 "$(edit_pl "$T/tests/test_a.py" 'assert 1 == 1' 'assert 2 == 2')"
check 0 1 0 "$(edit_pl "$T/tests/test_a.py" 'def test_a' 'def test_b')"
check 0 1 0 "$(edit_pl "$T/src/app.py" 'print(1)' '@pytest.mark.skip')"
check 0 1 0 "$(edit_pl "$T/src/skip.py" 'x' 'skip = True')"
check 0 1 0 "$(edit_pl "$T/tests/test_a.py" '# note: it.skip(' '# note: it.skip(')"
check 0 1 0 "$(edit_pl "$T/tests/test_a.py" 'assert 1 == 1' $'# why\nassert 1 == 1')"
check 0 1 0 "$(edit_pl "$T/tests/test_a.py" 'x' 'a skipped_count of 3')"
check 0 1 0 "$(edit_pl "$T/tests/test_a.py" '# assert 1 == 1' '# assert 1 == 1')"
# An Edit that leaves the file empty.
check 2 1 0 "$(edit_pl "$T/tests/test_a.py" "$(cat "$T/tests/test_a.py")" '')"
check 2 1 0 "$(edit_pl "$T/tests/test_a.py" "$(cat "$T/tests/test_a.py")" '   ')"
check 0 1 0 "$(edit_pl "$T/tests/test_a.py" '    assert 1 == 1' '')"

# V1: a Write over a test file is judged like an Edit.
SKIPPED=$'@pytest.mark.skip\ndef test_a():\n    assert 1 == 1\n'
check 2 1 0 "$(write_pl "$T/tests/test_a.py" "$SKIPPED")"
check 2 1 1 "$(write_pl "$T/tests/test_a.py" "$SKIPPED")"
check 2 1 0 "$(write_pl "$T/tests/test_a.py" $'def test_a():\n    # assert 1 == 1\n    pass\n')"
check 2 1 0 "$(write_pl "$T/tests/test_a.py" $'def test_a():\n    pytest.skip("x")\n')"
check 2 1 0 "$(write_pl "$T/web/new.test.ts" "it.skip('x', () => {})")"
check 2 1 0 "$(write_pl "$T/tests/test_fresh.py" "$SKIPPED")"
check 0 1 0 "$(write_pl "$T/tests/test_fresh.py" $'def test_f():\n    assert 1\n')"
# The file already has one skip: a Write that keeps one passes; a Write that adds one does not.
check 0 1 0 "$(write_pl "$T/tests/test_skipped.py" $'@pytest.mark.skip\ndef test_s():\n    assert 4 == 4\n')"
check 2 1 0 "$(write_pl "$T/tests/test_skipped.py" $'@pytest.mark.skip\ndef test_s():\n    pytest.skip("more")\n')"
check 0 1 0 "$(write_pl "$T/src/app.py" "$SKIPPED")"

# V2: a shell write onto a test file.
blocks 'truncate -s0 tests/test_a.py'
blocks 'truncate -s 0 tests/test_a.py'
blocks '> tests/test_a.py'
blocks ': > tests/test_a.py'
blocks ':>tests/test_a.py'
blocks 'cat /dev/null > tests/test_a.py'
blocks 'echo > tests/test_a.py'
blocks 'echo hi >tests/test_a.py'
blocks 'echo hi 1> tests/test_a.py'
blocks 'echo hi >| tests/test_a.py'
blocks 'echo hi &> tests/test_a.py'
blocks 'echo hi > "tests/test_a.py"'
blocks 'cd tests && : > test_a.py'
blocks "bash -c ': > tests/test_a.py'"
blocks 'echo $(: > tests/test_a.py)'
blocks 'cp /dev/null tests/test_a.py'
blocks 'cp src/app.py tests/test_a.py'
blocks 'mv src/app.py tests/test_a.py'
blocks 'mv tests/test_a.py /tmp/x'
blocks 'mv tests/test_a.py src/x.py'
blocks 'git mv tests/test_a.py src/x.py'
blocks 'git mv src/app.py tests/test_a.py'
blocks 'echo x | tee tests/test_a.py'
blocks 'echo x | tee -i tests/test_a.py'
blocks 'sed -i s/a/b/ tests/test_a.py'
blocks 'sed -i.bak s/a/b/ tests/test_a.py'
blocks 'sed -ni 1p tests/test_a.py'
blocks 'sed --in-place -e s/a/b/ tests/test_a.py'
blocks "perl -pi -e 's/a/b/' tests/test_a.py"
blocks "perl -i.bak -pe 's/a/b/' tests/test_a.py"
blocks 'git checkout -- tests/test_a.py'
blocks 'git checkout HEAD -- tests/test_a.py'
blocks 'git checkout -- tests'
blocks 'git restore tests/test_a.py'
blocks 'git restore --source=HEAD~1 tests/test_a.py'
blocks 'git restore --worktree --staged tests/test_a.py'
blocks 'git -C tests restore test_a.py'
# What stays allowed.
passes 'echo hi >> tests/test_a.py'
passes 'echo hi | tee -a tests/test_a.py'
passes 'echo hi | tee --append tests/test_a.py'
passes 'cat > tests/test_new.py <<EOF'
passes 'echo hi > tests/new_dir_test.py'
passes 'echo hi > src/app.py'
passes 'echo hi > /dev/null'
passes 'ls 2>&1'
passes 'ls tests 2>/dev/null'
passes 'ls tests >&2'
passes 'cp tests/test_a.py /tmp/y'
passes 'cp tests/test_a.py src/copy.py'
passes "grep '>' tests/test_a.py"
passes 'echo "a > tests/test_a.py"'
passes $'cat <<EOF\na > tests/test_a.py\nEOF'
passes 'sed s/a/b/ tests/test_a.py'
passes 'sed -n 1p tests/test_a.py'
passes 'sed -i s/a/b/ src/app.py'
passes 'git checkout main'
passes 'git checkout -b fix/x'
passes 'git checkout -- src/app.py'
passes 'git restore src/app.py'
passes 'git restore --staged tests/test_a.py'
passes 'truncate -s0 src/app.py'
passes 'mv src/app.py src/b.py'
passes 'mv tests/test_a.py tests/test_renamed.py'
passes 'git mv tests/test_a.py tests/test_renamed.py'
blocks 'mv tests/test_a.py tests/test_b.py'
passes 'tee src/out.txt'
# Prune lets a worker move a test away. It never lets one be truncated, overwritten, edited in place or reverted.
check 2 1 1 "$(bash_pl 'truncate -s0 tests/test_a.py')"
check 2 1 1 "$(bash_pl ': > tests/test_a.py')"
check 0 1 1 "$(bash_pl 'mv tests/test_a.py /tmp/x')"
check 0 1 1 "$(bash_pl 'git mv tests/test_a.py src/x.py')"
check 2 1 1 "$(bash_pl 'cp src/app.py tests/test_a.py')"
check 2 1 1 "$(bash_pl 'mv src/app.py tests/test_a.py')"
check 2 1 1 "$(bash_pl 'echo x | tee tests/test_a.py')"
check 2 1 1 "$(bash_pl 'sed -i s/a/b/ tests/test_a.py')"
check 2 1 1 "$(bash_pl 'git checkout -- tests/test_a.py')"
check 2 1 1 "$(bash_pl 'git restore tests/test_a.py')"

# V3: clean-up that is not a test.
passes 'rm -rf tests/__pycache__'
passes 'rm -rf tests/__pycache__/x.pyc'
passes 'rm tests/tmp.txt'
passes 'rm tests/a.pyc'
passes 'rm tests/run.log'
passes 'rm -rf build/lib/tests'
passes 'rm -rf dist/tests'
passes 'rm -rf node_modules/foo/tests'
passes 'rm -rf tests/.pytest_cache'
passes 'rm -rf .pytest_cache'
passes 'rm -rf /tmp/xyz/tests'
passes 'rm /tmp/test_x.py'
passes 'rm test_output.txt'
passes 'find tests -name __pycache__ -exec rm -rf {} +'
passes 'echo x > tests/__pycache__/x.pyc'
blocks 'rm tests/test_a.py tests/__pycache__/x.pyc'
blocks 'rm tests/__pycache__/../test_a.py'
blocks 'rm build/../tests/test_a.py'
blocks 'rm tests/test_a.py.bak.py'
blocks 'rm -rf tests/../tests'
blocks 'rm tests/test_a.txt.py'
# A test reached from a subfolder still counts.
mkdir -p "$T/sub"
check 2 1 0 "$(jq -nc --arg c 'rm ../tests/test_a.py' --arg d "$T/sub" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}')"

# V4: names match in any case.
blocks 'rm UPPER_TEST.PY'
blocks 'rm -rf TESTS'
blocks 'rm TESTS/a.py'
blocks 'rm Tests/a.py'
blocks 'rm Foo.Test.ts'
blocks 'rm A.SPEC.js'
blocks 'rm B_TEST.go'
blocks ': > UPPER_TEST.PY'
passes 'rm Contest.py'
passes 'rm LATEST.PY'
check 2 1 0 "$(write_pl "$T/UPPER_TEST.PY" '')"
check 2 1 0 "$(write_pl "$T/TESTS/a.py" '   ')"
check 2 1 0 "$(edit_pl "$T/Tests/X.py" 'a' 'pytest.skip("x")')"
check 2 1 0 "$(edit_pl "$T/web/A.TEST.TS" "it('x'" "it.skip('x'")"

# Not a worker, other tools, bad payloads.
check 0 0 0 "$(bash_pl 'rm tests/test_a.py')"
check 0 0 0 "$(write_pl "$T/tests/test_a.py" '')"
check 0 1 0 '{"tool_name":"Read","tool_input":{"file_path":"tests/test_a.py"}}'
check 0 1 0 '{"tool_name":"mcp__other__rm","tool_input":{"command":"rm tests/a"}}'
check 0 1 0 '{"tool_name":"Bash","tool_input":{}}'
check 0 1 0 '{"tool_name":"Bash","tool_input":{"command":42}}'
check 2 1 0 'not json'
check 2 1 0 ''
check 0 1 0 '{"tool_name":"Write","tool_input":{"file_path":42,"content":1}}'
check 0 1 0 '{"tool_name":"Edit","tool_input":{}}'
check 0 1 0 '{"tool_name":"Edit","tool_input":{"file_path":"tests/a.py","old_string":3,"new_string":null}}'

# The command is data: it is never run.
PWN="$T/pwned"
blocks "rm tests/\$(touch $PWN).py"
passes "echo \$(touch $PWN)"
blocks "bash -c 'touch $PWN; rm tests/test_a.py'"
if [[ -e $PWN ]]; then
  echo "FAIL the hook ran the command text"
  FAIL=$((FAIL + 1))
fi
# Long input stays fast and judged.
long=$(head -c 100000 /dev/zero | tr '\0' 'a')
passes "echo $long"
blocks "echo $long; rm tests/test_a.py"
# Long path names and an empty path.
passes "rm $(printf 'x%.0s' {1..300})"
passes 'rm ""'

echo "$RUN cases, $FAIL failed"
[[ $FAIL == 0 ]] && echo "all test-weakening-gate tests pass"
((FAIL == 0))
