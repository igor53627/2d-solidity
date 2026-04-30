## Doc-staleness check

Before marking a task Done or creating a PR, scan for stale documentation:

1. For every file you modified, check if its NatSpec (`@notice`, `@param`, `@dev`) or inline comments reference behavior that changed (event signatures, function parameters, access control, storage layout, etc.).
2. Check `README.md` for references to changed behavior (function signatures, event ABI, deployment steps).
3. Check the `2d-docs` repo (`~/pse/2d-docs/src/content/docs/`) for public articles that describe the changed contract (EN + RU versions).
4. Check the `2d` repo (`~/pse/2d/`) for verifier code that parses events emitted by this contract (`lib/chain/verifier/ethereum_rpc/http.ex`, config for topic0/contract address).
5. If any doc describes behavior that no longer matches the code, update it in the same PR or flag it explicitly.
