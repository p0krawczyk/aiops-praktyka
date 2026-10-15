# Dziennik — lab03 (pipeline z AI)

| # | Objaw (krok, komunikat) | Hipoteza (AI / ja) | Jak sprawdziłem | Poprawka | Status |
|---|---|---|---|---|---|
| 1 | `docker run ... zizmor /work`: `invalid input: C:/Program Files/Git/work` | ja: Git Bash (MSYS) zamienia argument `/work` na ścieżkę Windows | komunikat błędu pokazuje przetworzoną ścieżkę `C:/Program Files/Git/work` | `MSYS_NO_PATHCONV=1` przed `docker run` | ✅ |
| 2 | `actionlint`: `label "ubuntu-26.04" is unknown` po zmianie runnera | AI/ja: `actionlint` ma starszą listę etykiet niż dokumentacja GitHuba | `winget upgrade` (brak nowszej wersji), tagi `rhysd/actionlint` (v1.7.12 najnowszy), źródło `rule_runner_label.go` na `main` (brak 26.04) | cofnięcie do `ubuntu-24.04` (wersja wspierana, `ubuntu-latest`) | ✅ |
| 3 | Deploy (`helm upgrade`): `conflict with "kubectl-annotate" ... inbound-cidrs` na Ingress `kantyna-web` | ja: ktoś zmienił adnotację `kubectl annotate` poza Helmem, a Helm 4 stosuje server-side apply i `--reuse-values` przywraca stare 9 adresów | `kubectl get ingress -o yaml --show-managed-fields` (manager `kubectl-annotate`, 07:13:58) i `helm get values` (9 vs 10 CIDR) | jednorazowy `helm upgrade --reuse-values -f ingress-cidrs.yaml` z wartością z klastra (10 adresów) | ✅ |
| 4 | Smoke test wisi ok. 3 min: `curl: (28) Failed to connect to kantyna-orders-api port 8000 after 134237 ms` | ja: NetworkPolicy blokuje ruch z poda `smoke-*` | `kubectl get svc,endpoints` (endpointy są, pody Ready), `kubectl get networkpolicy ... -o yaml`: do orders-api wpuszcza tylko pody z etykietą `app.kubernetes.io/name=web` | smoke test przez `kubectl exec deploy/kantyna-web -- wget ... /healthz` (5 prób, timeout kroku 3 min) | ✅ |

## Sugestie AI, których nie wdrożyłem

1. **`--force-conflicts` w `helm upgrade`** (rozwiązanie konfliktu z wiersza 3). Nie wdrożyłem, bo przejęłoby pole `inbound-cidrs` i cofnęło listę z 10 do 9 adresów, czyli wycięło dostęp dodany ręcznie przez prowadzącego. Dodatkowo pipeline zmieniałby przy każdym przebiegu coś, co ktoś ustawia poza Helmem.
2. **Etykieta `app.kubernetes.io/name=web` na podzie smoke** (wariant B). Nie wdrożyłem, bo pod podszywałby się pod web, żeby obejść NetworkPolicy. Wybrałem `kubectl exec` do prawdziwego poda web.
3. **Podniesienie Pythona i Go oraz runnera do najnowszych wersji** (checklista, punkt 6). Zostawiłem Python 3.12 i Go 1.23 zgodne z aplikacją (Dockerfile'e, `pyproject.toml`, `go.mod`), bo CI ma testować to, co trafia na klaster. Runner `ubuntu-26.04` odrzuciłem, bo `actionlint` jeszcze go nie zna.
