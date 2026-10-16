# Dziennik — lab05: incydenty z logów alertów (`alert-log`)

Źródło: Loki `{container="alert-log"} | json`, plik `Logs-2026-10-16 11_27_04.json`.
Zakres: 13.10 09:35 – 16.10 09:07 UTC (**czas w tabelach: polski, UTC+2**). Wpisów: 700 (wszystkie `level=INFO`, także dla `critical`, więc poziomu logu nie da się użyć do priorytetyzacji; liczy się `severity` z alertu), unikalnych alertów (fingerprint): 109.

## Podsumowanie

| Kategoria | Wpisów | Udział |
|---|---|---|
| Burza po awarii w namespace'ach uczestników (INC-3, INC-3b, INC-6) | 585 | 84% |
| Szum: `KubeSchedulerDown`, `KubeControllerManagerDown` | 36 | 5% |
| `demo-k8sgpt` (celowo zepsute demo?) | 56 | 8% |
| Namespace `demo` (realne incydenty Kantyny) | 23 | 3% |

Najmniej wpisów mają incydenty, które mają największe znaczenie biznesowe (`demo`). Reszta to powtórzenia (Alertmanager ponawia powiadomienie co ok. 4 h) i alerty pochodne.

## Incydenty — według priorytetu

| Prio | # | Incydent | Kiedy (PL) | Alerty | Dowody | Hipoteza (do potwierdzenia) |
|---|---|---|---|---|---|---|
| **P1** | INC-1 | **OOM orders-api (demo)**, powtarzalny | 13.10 19:09–19:54; 14.10 14:01–14:41 | `KantynaPodOOMKilled` (critical) ×2 wystąpienia, pody `…-7c96b54996-vxtcm` i `…-fb96d` (oba za każdym razem) | Ten sam deployment i te same dwa pody w dwóch dniach; 2. okno pokrywa się z `momenty.md` (14.10 14:00–14:36, ~368 MiB, restart OOMKilled 14:25) | Wyciek pamięci w orders-api (flaga runtime?) albo za niski limit pamięci. Sprawdź `container_memory_working_set_bytes` i limit w `values.yaml`. |
| **P1** | INC-2 | **Wyczerpana pula połączeń DB (demo)**, flapping | 15.10 16:23–16:28, 16:41–16:48, 16:54–16:55 | `KantynaDBPoolExhausted` (critical), pod `kantyna-orders-api-5d87d9d47d-85r5n` | 3 odpalenia w 30 min, każde kończy się samo; nowy hash ReplicaSetu (`5d87d9d47d`), czyli po nowym wdrożeniu | Wyciek połączeń (flaga `db_pool_leak`), pula wraca po restarcie/zwolnieniu. Potwierdź metryką puli i logami ERROR orders-api. |
| **P2** | INC-3 | **Awaria Kantyny w namespace'ach uczestników** (9 ns) | start 14.10 15:05–15:15; **rozwiązane** w większości 15.10 09:17–09:55 (ok. 18 h) | `TargetDown`, `KubePodCrashLooping` (`orders-api`, `CrashLoopBackOff`), `KubePodNotReady`, `KubeDeploymentReplicasMismatch` (`kantyna-web`/`orders-api`) | Wszystkie ns (`dawid-k, jan, marek, michal, pawel, piotr-k, piotr-z, waldemar` + `proba`) w tej samej minucie, więc przyczyna wspólna (np. wspólny deploy/obraz/konfiguracja), a nie przypadkowa. `marek` i `pawel` naprawione po 20–40 min (13:31 / 13:46 UTC). | Wspólny czynnik z labu (zepsuty obraz/wariant/zasób), nie awaria klastra. Dla jednego ns do sprawdzenia w logach poda `orders-api` (`kubectl logs --previous`), potem porównać z resztą. |
| **P2** | INC-3b | **`TargetDown` nadal aktywny** w 6 ns | od 14.10 15:06, **nie rozwiązany do 16.10 11:07** | `TargetDown` `kantyna-orders-api`: `dawid-k, marek, pawel, piotr-k, piotr-z, waldemar` (po 12 powtórzeń) | Pozostałe alerty tych ns (NotReady, CrashLoop, Mismatch) rozwiązały się, a `TargetDown` nie. | Orders-api nie ma żadnych celów scrape'u (skalowanie do 0? ServiceMonitor/etykiety usługi?). Dla ns `pawel`: sprawdź `kubectl get svc,endpoints,servicemonitor -n pawel`. |
| **P3** | INC-4 | **Opóźnienie + kolejka + płatności (demo)**, jeden łańcuch | 13.10 11:42–12:14 (p95 2,19 s); 13.10 13:12–14:40 (kolejka 2,5 tys. → 65); 13.10 14:37–15:04 (płatności 26% błędów) | `KantynaHighLatencyP95`, `KantynaQueueBacklog`, `KantynaPaymentsFailing` (warning) | Okna następują po sobie: opóźnienie → kolejka → płatności. W `momenty.md` kolejka dobiła do 10 783. Wszystkie rozwiązały się same. | Najpierw wolna odpowiedź, potem zator w workerze i błędy `payments`. Wymaga korelacji z metrykami `payments` i `worker`, bo logi alertów nie wystarczą. |
| **P3** | INC-5 | **Skok 5xx w orders-api (demo)** | 15.10 08:32–08:48 | `KantynaHighErrorRate` (warning), do 14,81% (próg 5%) | Jedno odpalenie, rozwiązane po ok. 16 min, 5,4% przy rozwiązaniu | Krótka awaria zależności (`UpstreamUnavailableError`?). Potwierdź `{namespace="demo", app="orders-api"} \| json \| level="ERROR"`. |
| **P3** | INC-6 | **`proba`: Postgres niegotowy + crashloop** | 13.10 07:34 → 15.10 09:47–09:55 (~50 h) | `KubePodNotReady` (`kantyna-postgres-0` + 4 pody orders-api + 2 web), `KubeStatefulSetReplicasMismatch`, `KubePodCrashLooping`, `TargetDown` | Jako jedyny ns zaczyna się dzień wcześniej niż INC-3 i ma w sobie `kantyna-postgres-0` | Zepsuta baza (pod niegotowy) → orders-api w crashloopie. Ns testowy/próbny, niski wpływ. |
| **P4** | INC-7 | **`demo-k8sgpt`: `raport-dzienny` w crashloopie** | od 14.10 06:08, **trwa do 16.10 10:18** | `KubePodCrashLooping` (kontener `raport`), `KubePodNotReady`, `KubeDeploymentReplicasMismatch`, `KubeDeploymentRolloutStuck` (`ProgressDeadlineExceeded`); po 14 powtórzeń | Ponad 2 doby bez rozwiązania, jeden pod `raport-dzienny-db6499754-82k4p`. Nazwa ns sugeruje celowo zepsute demo do ćwiczenia K8sGPT. | Zepsute celowo (demo). Jeśli nie, najpierw `kubectl describe` i `logs --previous` poda. |

## Szum (do wyciszenia lub strojenia)

| Szum | Dlaczego | Co zrobić |
|---|---|---|
| `KubeSchedulerDown`, `KubeControllerManagerDown` (critical, 18 + 18 wpisów, aktywne od 12.10 09:30, **nigdy nie rozwiązane**) | Fałszywy alarm. Cały cluster działa, a to alerty z domyślnego `kube-prometheus-stack`: na zarządzanym EKS control plane nie jest scrape'owalny. Alert „critical” zawsze aktywny uczy ignorowania krytycznych. | Wyłączyć w Helm chart (`kubeScheduler.enabled=false`, `kubeControllerManager.enabled=false`) albo wyciszyć w Alertmanagerze. |
| Powtórzenia tego samego alertu | 700 wpisów to 109 unikalnych alertów; powiadomienia ponawiane co ok. 4 h dla alertów aktywnych dłużej. | Dłuższy `repeat_interval` dla `warning`; to przyspieszy czytanie, nie zmieni samych incydentów. |
| Alerty pochodne w INC-3, INC-6, INC-7 (`NotReady`, `ReplicasMismatch`, `RolloutStuck`, `TargetDown`) | Jedna przyczyna daje 3–4 alerty naraz (np. crashloop → pod niegotowy → replik mniej → brak celów). Razem to ok. 3/4 wszystkich wpisów. | Grupować po `namespace` i traktować `KubePodCrashLooping` jako alert przyczynowy; inhibit rule dla pochodnych. |
| `level=INFO` dla każdego alertu | Pole `level` w logu nie niesie informacji. | Filtrować po `severity` / `alertname`, nie po `level`. |

## Co dalej (propozycja kolejności)

1. INC-1 i INC-2: potwierdzić metrykami (pamięć, pula DB) i flagami w `FLAGS_FILE`, zanim ktokolwiek poprawia kod. Oba mają runbooki w `app/runbooks/` (`KantynaPodOOMKilled.md`, `KantynaDBPoolExhausted.md`).
2. INC-3b: sprawdzić własny namespace (`pawel`), bo `TargetDown` tam wciąż świeci.
3. Szum: wyłączyć alerty scheduler/controller-manager, bo bez tego lista „critical” jest nieczytelna.

## Czego ten dziennik nie rozstrzyga

Logi alertów mówią tylko, **że** i **kiedy** alert się odpalił, nie dlaczego. Wszystkie kolumny „Hipoteza” wymagają potwierdzenia metrykami lub logami aplikacji (zgodnie z `CLAUDE.md`). Pierwszy i ostatni wpis zakresu to ograniczenie eksportu (3 dni), więc starsze alerty (np. start `KubeSchedulerDown` 12.10) są widoczne tylko przez `starts_at`.

## Tabela incydentów (zbiorcza)

Czasy polskie (UTC+2). „Do” = ostatni wpis `resolved`; „trwa” = brak `resolved` do końca eksportu (16.10 11:07).

| # | Od | Do | Alerty | Prio | Uzasadnienie priorytetu |
|---|---|---|---|---|---|
| INC-1 | 13.10 19:09 | 13.10 19:54, potem 14.10 14:01–14:41 | `KantynaPodOOMKilled` (critical) | P1 | Realny wpływ na `demo`: kontenery ubijane przez OOM, powtórka po dobie, więc problem nie zniknął sam. Severity critical. |
| INC-2 | 15.10 16:23 | 15.10 17:00 (3 odpalenia) | `KantynaDBPoolExhausted` (critical) | P1 | Pula DB na 100% blokuje obsługę zamówień. Flapping mówi, że przyczyna nadal jest. |
| INC-3 | 14.10 15:05 | 15.10 09:17–09:55 (marek, pawel: 14.10 15:31–15:46) | `TargetDown`, `KubePodCrashLooping`, `KubePodNotReady`, `KubeDeploymentReplicasMismatch` w 9 ns | P2 | Pełna niedostępność orders-api w ns uczestników (100% celów w dół), ale środowiska ćwiczeniowe, bez wpływu na `demo`. Wspólny czas startu wskazuje na jedną przyczynę. |
| INC-3b | 14.10 15:06 | trwa | `TargetDown` w `dawid-k, marek, pawel, piotr-k, piotr-z, waldemar` | P2 | Jedyny alert z INC-3, który się nie rozwiązał. Wymaga sprawdzenia, czy to realny brak celów, czy zostawiony stan. |
| INC-4 | 13.10 11:42 | 13.10 15:04 | `KantynaHighLatencyP95`, `KantynaQueueBacklog`, `KantynaPaymentsFailing` (warning) | P3 | Trzy alerty warning w kolejnych oknach, wszystkie rozwiązały się same. Pogorszenie jakości usługi bez ciągłej niedostępności, ale płatności 26% błędów są poważne. |
| INC-5 | 15.10 08:32 | 15.10 08:48 | `KantynaHighErrorRate` (warning) | P3 | Jedno krótkie odpalenie (16 min), samo wygasło. |
| INC-6 | 13.10 07:34 | 15.10 09:47–09:55 | `KubePodNotReady` (postgres), `KubeStatefulSetReplicasMismatch`, `KubePodCrashLooping`, `TargetDown` w `proba` | P3 | Długi, ale namespace próbny. Bez wpływu na `demo`. |
| INC-7 | 14.10 06:08 | trwa | `KubePodCrashLooping`, `KubePodNotReady`, `KubeDeploymentReplicasMismatch`, `KubeDeploymentRolloutStuck` w `demo-k8sgpt` | P4 | Jeden pod, wygląda na celowo zepsute demo. Do wyciszenia, gdy potwierdzone. |
| SZUM | 12.10 09:30 | trwa | `KubeSchedulerDown`, `KubeControllerManagerDown` (critical) | — | Fałszywy alarm na zarządzanym EKS. Nie ma priorytetu, trzeba usunąć regułę. |

## Propozycje zmian reguł

Nic z poniższych nie jest jeszcze wdrożone. Zmiany w `app/deploy/helm/kantyna/templates/prometheusrule.yaml` i w konfiguracji Alertmanagera/kube-prometheus-stack (ta ostatnia nie leży w tym repo) trzeba najpierw przejrzeć i przetestować w swoim namespace.

### R1. `KantynaDBPoolExhausted`: dodać `keep_firing_for` (powód: INC-2)

W INC-2 alert odpalał się i gasł trzy razy w 30 minut (16:23, 16:41, 16:54), choć wyciek połączeń trwał cały czas. Każde zgaszenie wygląda jak naprawa, a po minutach wraca ten sam alarm.

```yaml
- alert: KantynaDBPoolExhausted
  expr: ( ... ) > 0.9        # bez zmian
  for: 5m
  keep_firing_for: 10m       # NOWE: nie gaś alertu, dopóki pula nie jest niska 10 min
```

Efekt: jeden incydent zamiast trzech, a „resolved” oznacza, że pula faktycznie wróciła do normy. Wymaga Prometheusa ≥ 2.42 (do sprawdzenia w klastrze).

### R2. Alertmanager: reguła tłumienia (powód: INC-3, INC-6, INC-7 i 84% wpisów)

Jedna przyczyna (crashloop) generowała 3–4 osobne alerty w każdym namespace. Alert przyczynowy powinien tłumić pochodne:

```yaml
inhibit_rules:
  - source_matchers: ['alertname = "KubePodCrashLooping"']
    target_matchers: ['alertname =~ "KubePodNotReady|KubeDeploymentReplicasMismatch|KubeDeploymentRolloutStuck|TargetDown"']
    equal: ['namespace']
```

Efekt: w INC-3 zamiast ok. 530 wpisów pozostałyby te z `KubePodCrashLooping`. Uwaga: `TargetDown` bywa też jedynym objawem (INC-3b, brak crashloopu), więc przy tym alercie reguła tłumi tylko wtedy, gdy crashloop faktycznie trwa.

### R3. Wyłączyć reguły scheduler / controller-manager (powód: szum)

W wartościach `kube-prometheus-stack` (nie w tym repo):

```yaml
kubeScheduler:
  enabled: false
kubeControllerManager:
  enabled: false
defaultRules:
  rules:
    kubeSchedulerAlerting: false
    kubeControllerManager: false
```

Efekt: znikają dwa wiecznie „critical” alerty (36 wpisów), więc `critical` znów coś znaczy.

### R4. Nowy alert wyprzedzający OOM (powód: INC-1)

`KantynaPodOOMKilled` odpala się dopiero po ubiciu kontenera. W `momenty.md` pamięć rosła z ok. 135 do 368 MiB przez 36 minut, więc jest czas na ostrzeżenie:

```yaml
- alert: KantynaPodMemoryNearLimit
  expr: |
    max by (namespace, pod, container) (container_memory_working_set_bytes{namespace="{{ $ns }}", container="orders-api"})
    /
    max by (namespace, pod, container) (kube_pod_container_resource_limits{namespace="{{ $ns }}", container="orders-api", resource="memory"})
    > 0.85
  for: 10m
  labels:
    severity: warning
```

Próg 0,85 jest zgadnięty. Przed wdrożeniem sprawdź na wykresie, jak wygląda norma, bo inaczej dojdzie kolejny szum.
