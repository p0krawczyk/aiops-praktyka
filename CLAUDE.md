# CLAUDE.md
Repo szkolenia Sages „AIOps w praktyce” (treści po polsku). `app/` — aplikacja Kantyna (opis: `app/README.md`), `labs/` — laby z sekcją `## SUKCES`, `docs/` — materiały i `prompts/`, `setup/check.sh [ns]` — test Kantyny na EKS (oczekiwane `SUKCES: 11/11`). Nowe laby: `git pull upstream main`.

## Wersje narzędzi
- Zainstalowany kubectl to wersja: v1.36.1 (Kustomize v5.8.1).
- Zainstalowany helm to wersja: v4.3.0+gbec5b06.
- Zainstalowany docker to wersja: v29.8.2.
- Zainstalowany AWS CLI to wersja: v2.38.0.
- Zainstalowany git to wersja: v2.56.0.
- Zainstalowany python to wersja: v3.13.5.

## Komendy (w `app/`)
- Lokalnie: `docker compose up -d --build` (UI :8088, orders-api :8000/docs); ruch: `docker compose --profile loadgen up -d loadgen`; stop: `docker compose down -v`
- Testy: `make test` | `make test-orders-api` | `make test-payments`; pojedynczy: `cd orders-api && uv run pytest tests/test_api.py::test_healthz` (bez bazy — `SKIP_DB_INIT=1` w conftest, mocki przez `monkeypatch`)
- Helm: `make helm-lint`, `make helm-template REGISTRY=<reg> VERSION=1.0.0`, `helm lint app/deploy/helm/kantyna`

## Architektura
- `web` (nginx, proxy `/api/*`) → `orders-api` (FastAPI) → `payments` (Go) + PostgreSQL + SQS → `worker` (paragony do S3). Lokalnie brak SQS/S3 — worker czeka, to nie błąd.
- Flagi runtime w `FLAGS_FILE` (lokalnie `deploy/local/flags.json`, na klastrze ConfigMap z `values.yaml`) celowo wstrzykują awarie (`error_rate`, `db_pool_leak`, `latency_ms`…), przeładowują się bez restartu; plik wygrywa z env. Kod: `orders-api/app/runtime.py`, `payments/flags.go`, `worker/app/flags.py`.
- `APP_VARIANT` (`stable`/`receipt-v2`/`menu-v2`) zmienia zachowanie; widać w `/version` i `kantyna_build_info`.
- Alerty z `prometheusrule.yaml` mają runbooki w `app/runbooks/<Alert>.md` (używa ich agent z lab06). `Dockerfile.legacy` jest celowo przestarzały (lab Trivy) — nie poprawiaj.

## Zasady
- Klaster wspólny: tylko własny namespace; nie obchodź blokad z `.claude/settings.json` (delete/exec/sekrety).
- `app/.env` ma fałszywe sekrety — i tak nie wysyłaj ich do modelu. Hipotezy potwierdzaj logami/metrykami przed poprawką.
- nie uruchamiaj `kubectl delete`