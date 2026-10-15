# Dziennik — lab04 (IaC z AI)

| # | Bramka / krok | Co złapała (albo co poprawiłem sam) | Poprawka |
|---|---|---|---|
| 1 | `kubectl-ai --model=claude-haiku-4-5 --enable-tool-use-shim` | `parsing ReAct response ... no JSON code block found`. Model odpowiedział prozą i kilkoma blokami `<function_calls>` (w tym nieznanym narzędziem `bash`), a na końcu zapytał o namespace zamiast sprawdzić kontekst | zmiana modelu na `claude-sonnet-5-5` |
| 2 | `kubectl-ai --model=claude-sonnet-5-5 --enable-tool-use-shim` | Ten sam błąd, ale dopiero na końcu: model zebrał dane (`get`/`describe` w `pawel`) i napisał raport zwykłym markdownem, a shim oczekuje bloku `json` także dla odpowiedzi końcowej | ponowne zapytanie z prośbą o odpowiedź końcową w formacie ReAct, po czym raport się sparsował |
| 3 | Weryfikacja tez raportu AI (`kubectl get pdb,hpa,networkpolicy -n pawel`) | Potwierdzone: brak PDB, brak HPA, tylko jedna NetworkPolicy (`kantyna-orders-api-ingress`, wpuszcza tylko `web` na 8000), Postgres bez żadnej polityki. Sam wstępnie założyłem, że HPA może istnieć (chart ma `hpa-orders-api.yaml`), ale autoscaling nie jest włączony w tym wydaniu | bez zmiany w raporcie, poprawiona moja hipoteza |
| 4 | Pytanie AI: czy `worker` łączy się z Postgresem | Sprawdziłem w repo: w `app/worker` nie ma klienta bazy, a `deployment-worker.yaml` nie ma `DATABASE_URL` (ma go tylko `orders-api`) | NetworkPolicy dla Postgresa wpuszcza wyłącznie `orders-api` na 5432 |
| 5 | Zakres PDB (`k8s/pdb-orders-api.yaml`) | `worker` i `postgres` mają 1 replikę (`replicas: 1` na stałe w StatefulSecie), więc `minAvailable: 1` zablokowałby drain węzła | PDB tylko dla `orders-api` (2 repliki, `minAvailable: 1`, `unhealthyPodEvictionPolicy: AlwaysAllow`) |
| 6 | `terraform plan` w `tf/` | `will be created` dla `kubernetes_network_policy_v1.postgres_ingress`, choć polityka już była w klastrze po `kubectl apply -f k8s/`. Przyczyna: pusty plik stanu (`No state file was found`), Terraform porównuje konfigurację ze stanem, a nie z klastrem. Gdyby poszedł `apply`, skończyłby się błędem `already exists` | `terraform import kubernetes_network_policy_v1.postgres_ingress pawel/kantyna-postgres-ingress`, potem `plan` → `No changes` |
| 7 | `setup/check.sh` po `kubectl apply -f k8s/` | `SUKCES: 11/11`. `kubectl get pdb,networkpolicy` pokazuje `kantyna-orders-api` (ALLOWED DISRUPTIONS 1) i `kantyna-postgres-ingress` | bez poprawek |

Wyniki bramek z kroku 3 (`kubectl apply --dry-run=server -f k8s/`, `trivy config k8s/`): uzupełnij, jeśli którąś coś złapała.

## Sugestie AI, których nie wdrożyłem

1. **PDB `minAvailable: 1` dla `worker` i `postgres`** (z raportu kubectl-ai). Nie wdrożyłem, bo przy jednej replice PDB blokuje drain węzła.
2. **Dodanie PDB i NetworkPolicy do chartu Helm** (flagi w `values.yaml`). Nie wdrożyłem, bo lab każe trzymać pliki w `k8s/` i `tf/`. To czystsze rozwiązanie na przyszłość, bo `kubectl apply` i Terraform tworzą obiekty nieznane Helmowi.
3. **Reguła dla Prometheusa (namespace `monitoring`) w NetworkPolicy** `orders-api`. Nie wdrożyłem, bo nie sprawdziłem, czy scrape z `monitoring` jest tam faktycznie blokowany. Raport sam zaznaczył, że to niezweryfikowane. Do sprawdzenia przy alertach z `prometheusrule.yaml`.
4. **`default-deny` i polityki egress** dla całego namespace. Poza zakresem laba i mogłyby zepsuć smoke testy, które idą przez `exec` w podzie `web`.

## Uwagi

- Obiekt `kantyna-postgres-ingress` jest zarządzany z dwóch miejsc: `k8s/netpol-postgres.yaml` (`kubectl`) i `tf/main.tf` (Terraform, po imporcie). Przy zmianie reguły trzeba zmienić oba albo wybrać jedno źródło prawdy.
- PDB nie ma w konfiguracji Terraform, więc `plan` go nie dotyczy i import nie był potrzebny.
