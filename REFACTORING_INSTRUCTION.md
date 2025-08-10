This is a nixos configuration that needs to be refactored. First read through major files. Find duplicated code (primarily in `devices`).

Split the dependencies based on profiles, currently a lot of them are bundled together in `setup-*.nix` instead they should be groupable by things like `gui`, `development` etc. (They can have sub-profiles if required like `k8s`, `gui-development`).


Do it this way:
1. Create a document named `REFACTORING.md`
2. Read through relevant codebase and make a plan in `REFACTORING.md`
3. Start making changes while verifying that the derivations match the original ones.
4. Use git to track changes, commit often with clear messages.
5. At each step, test the derivation has not changed.
