# Bugs found by the suite

None open. Every bug the suite found while it was written (15, see the git
history of this file on `feature/test-suite`) is fixed on `feature/bugfixes`
and its test now runs without a skip.

When a test finds a new bug: mark it `skip "bug: <one line>"` with the intended
expectation, add a row here (where, what, test file), fix the code on a branch,
remove the skip and the row.
