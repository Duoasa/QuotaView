# Shared native question fixtures

`server.py` is the private Unix WebSocket fixture used by `SharedQuestionAnswerSmokeTests`. It checks `/rpc` and records requests in the test's temporary directory. It never contacts Codex or a model provider.

For the optional integration against the installed native Codex binary, run from the repository root:

```sh
swift test --filter SharedQuestionAnswerSmokeTests
python3 Tests/Fixtures/codex-shared-answers/native_probe.py .build/shared-answers-native
```

`native_probe.py` expects Codex at `/Applications/ChatGPT.app` and reads one model schema from `~/.codex/models_cache.json`. It redirects the child service's configuration, history, database and logs to its own private temporary directory and replaces the model backend with a loopback HTTP fixture. No real model requests or user-thread writes occur. It starts only its own isolated server, emits a native async question, invokes the production Swift client test, checks the original-turn accepted reply and rejects a wrong turn, then stops its own server. Logs and a JSON result are written to the requested evidence directory; the private fixture directory is retained for diagnosis.

This verifies native protocol compatibility. It does not switch the running desktop into shared mode or prove desktop UI closure. The user must validate those with the opt-in launcher and a real test question.
