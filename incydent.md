# Incydent: wolne menu i błędy (ns `pawel`), 2026-10-16

Czasy w UTC (PL = UTC+2). Legenda: **[D]** potwierdzone danymi, **[H]** hipoteza bez potwierdzenia, **[AI]** napisane przez agenta, do przeglądu przez człowieka.

## Dziennik

| Godzina | Hipoteza | Komenda / zapytanie | Wynik | Status |
|---|---|---|---|---|
| 12:24 | Start: `check.sh` | `setup/check.sh pawel` | 11/11. Check nie widzi problemu: menu zwraca 200 | objaw niewidoczny w check.sh |
| 12:24 | Zmiana konfiguracji na klastrze | `kubectl get cm kantyna-flags` | `db_pool_leak: true`, `slow_menu_query: true`. Domyślnie w repo i w manifeście Helma `false` | **[D] dryf** |
| 12:24 | Kto i kiedy zmienił | `kubectl get cm kantyna-flags -o jsonpath='{.metadata.managedFields}'` | manager `kubectl-patch`, 12:17:50Z; Helm nie ustawiał `true` | **[D]** |
| 12:24 | Wyciek puli DB (30% żądań `/api/menu` zatrzymuje połączenie) | czytanie `main.py:145-153`, `db.py:214` | mechanizm w kodzie, pula `max=10` na pod | [D] kod |
| 12:25 | Loadgen pokazuje awarię | `kubectl logs deploy/kantyna-loadgen` | `ConnectTimeout`. Loadgen celuje w `orders-api:8000`, a NetworkPolicy wpuszcza tylko `web`. To artefakt generatora, **nie** objaw użytkowników | **[D] fałszywy trop** |
| 12:25 | Bezpośrednio na orders-api menu jest szybkie | `curl` przez port-forward | 200, ~0,1 s, pula 0/1 | [D] stan początkowy |
| 12:25-12:27 | Pula się wyczerpuje przy ruchu przez web | 60× `GET /api/menu` przez `svc/kantyna-web` | 7×200, 1×500, 1×504 (30 s), 51×502; `db_pool_connections_in_use 10/10`; `/readyz`: „couldn't get a connection after 30.00 sec"; oba pody `0/1` | **[D] przyczyna 1** |
| 12:27 | `slow_menu_query` (N+1) spowalnia menu | porównanie czasu menu z flagą (~0,09 s) i bez (~0,08 s) | różnica pomijalnie mała przy tak małym menu | **[H] niepotwierdzone jako przyczyna wolnego ładowania**. To dryf, ale wpływ nieudowodniony |
| 12:28:02 | Mitygacja | `kubectl patch cm kantyna-flags` (obie flagi `false`) + `rollout restart deploy/kantyna-orders-api` | rollout OK; flagi zgodne z manifestem Helma | wykonane |
| 12:28:34 | Weryfikacja | 100× menu przez web; `check.sh` | 100×200, śr. 0,082 s, max 0,108 s; `SUKCES: 11/11` | [D] |

Brak dostępu do Prometheusa: `kubectl get --raw .../services/proxy` zwraca Forbidden dla użytkownika `pawel`. Blokady nie obchodziłem. Metryki pochodzą z `/metrics` poda (port-forward), a nie z Grafany.

## Diagnoza (szablon `docs/prompts/diagnoza.md`, runbooki `KantynaDBPoolExhausted.md` i `KantynaHighLatencyP95.md`)

Uwaga o kolejności: komendy z tabeli wykonałem przed mitygacją (12:24-12:27 UTC), ale tabelę uporządkowałem po fakcie. Hipotezy nie powstały jako 3 prognozy z modelu, tylko z danych na bieżąco.

**Wypełniony szablon:** Środowisko: EKS `aiops`, ns `pawel`, orders-api `eeefdb5`, release Helm rev 7. Objaw: wolne menu i błędy, bez zmiany w repo i bez nowego wdrożenia. Dane: `kantyna-flags`, `managedFields`, `/metrics`, logi orders-api. Już sprawdziłem: pody Running, brak restartów, CPU/pamięć niskie (`kubectl top`), `check.sh` 11/11.

| # | Hipoteza | Dowód z danych | Komenda weryfikująca | Status |
|---|---|---|---|---|
| 1 | Zmiana konfiguracji poza repo (dryf) włączyła flagi awarii | ConfigMap: `db_pool_leak: true`, `slow_menu_query: true`; manifest Helma: `false`; manager `kubectl-patch` 12:17:50Z; `helm history`: ostatnia zmiana rev 7 z 15.10 10:52 | `kubectl -n pawel get cm kantyna-flags -o jsonpath='{.metadata.managedFields}'`, `helm -n pawel get manifest kantyna`, `helm -n pawel history kantyna` | **potwierdzone** |
| 2 | Wyciek połączeń DB wyczerpuje pulę (krok runbooka: „Usage that only grows") | `main.py:147-151`; w teście `in_use` 0→2→10 przy `size=10`; logi `couldn't get a connection after 30.00 sec`; oba pody `0/1`; 52/60 żądań 5xx | `curl localhost:18000/metrics \| grep ^db_pool` (port-forward), `kubectl -n pawel logs -l app.kubernetes.io/name=orders-api \| grep -i pool`, `kubectl get pods` | **potwierdzone**, po zmianie flag i restarcie 100/100 OK |
| 3 | N+1 w menu (`slow_menu_query`) spowalnia odpowiedź (runbook HighLatencyP95, krok 4) | menu ~0,09 s z flagą, ~0,08 s bez; kod `fetch_menu(slow=True)` robi 1 zapytanie na pozycję | 30-100× `curl` menu przez web przed i po | **niepotwierdzone**. Wpływ pomijalny przy małym menu |
| 4 | Wolność wynika z oczekiwania na pulę, nie z wolnych zapytań (przyczyna współistniejąca) | stałe 30 s przy 504; domyślny timeout puli | j.w. + log `Readiness check failed` | **potwierdzone** jako wzmacniacz. Stąd planowany krok „krótszy timeout" |
| 5 | Loadgen/NetworkPolicy jako przyczyna błędów (fałszywy trop) | `ConnectTimeout` w logach loadgena; `BASE_URL=orders-api:8000`; NetworkPolicy wpuszcza tylko `web` | `kubectl -n pawel get netpol ... -o yaml`, `kubectl -n pawel logs deploy/kantyna-loadgen` | **odrzucone** (artefakt generatora) |

**Kroki runbooka, których nie dało się wykonać:**
- PromQL na Prometheusie (`services/proxy` w `monitoring`: Forbidden) → zastępnik: `/metrics` poda.
- `psql` w poście postgres (`kubectl exec` zablokowany w `.claude/settings.json`) → bez widoku `pg_stat_activity`. Liczba `idle in transaction` nieznana.

**Wniosek:** przyczyna 1 (dryf) uruchomiła przyczynę 2 (wyciek puli). Przyczyna 4 zamieniła ją w 30-sekundowe zawieszenia. Hipoteza 3 nie ma dowodu.

## Mitygacja (wykonana 12:28 UTC = 14:28 PL)

Zasada: najpierw przywrócić usługę, przyczyna może zostać.

| Krok | Komenda | Wynik |
|---|---|---|
| 1. Flagi zgodne z repo (`db_pool_leak`, `slow_menu_query` → `false`; reszta bez zmian) | `kubectl -n pawel patch configmap kantyna-flags --type merge -p <flags.json z dwiema flagami zmienionymi>` | ConfigMap zgodna z manifestem Helma |
| 2. Zwolnienie wyciekłych połączeń (zmiana flag ich nie zwalnia) | `kubectl -n pawel rollout restart deploy/kantyna-orders-api` + `rollout status` | rollout OK, 2 nowe pody `1/1` |
| 3. Weryfikacja | 100× `GET /api/menu` przez `svc/kantyna-web`; `setup/check.sh pawel` | 100×200, śr. 0,082 s, max 0,108 s; `SUKCES: 11/11` |
| 4. Powtórna weryfikacja 8 min później (12:36 UTC) | 40× menu przez web; flagi; pody | 40×200, flagi `false`, pody `1/1`, 0 restartów, `check.sh` 11/11 |

| 5. Wyrównanie bajtów z Helmem (12:39 UTC) | `helm template ... \| kubectl -n pawel diff -f -` pokazał różnice `\|-` vs `\|` i `0.0` vs `0`, które dałyby konflikt SSA z `kubectl-patch` przy pipeline; potem `kubectl patch` tekstem z `helm template` | `kubectl diff` → brak różnic, `check.sh` 11/11 |

**Odstępstwa od procedury:**
- Mitygacja poszła ręcznym `kubectl patch`, nie commitem przez pipeline (repo już było poprawne). To nowy zapis w `managedFields` od managera `kubectl-patch`, ale z wartościami równymi manifestowi, więc kolejny `helm upgrade` nie powinien dać konfliktu (nieprzetestowane).
- Nie sprawdziłem metryk w Grafanie (brak dostępu), więc „5 minut stabilności" potwierdzają tylko testy przez web.

**Nie zrobiono (przyczyna zostaje):**
- brak krótkiego timeoutu puli: przy kolejnym wycieku wróci 30-sekundowe zawieszenie,
- nic nie wykrywa dryfu konfiguracji; nie wiemy, kto zrobił `patch` o 12:17:50Z i po co,
- `check.sh` nie wykryłby takiej awarii,
- hipoteza N+1 (`slow_menu_query`) bez dowodu wpływu.

## Komunikat nr 2: mitygacja (szkic [AI], do przeglądu)

> Usługa menu w Kantynie działa normalnie od 14:28 (PL). Przywróciliśmy poprawną konfigurację usługi zamówień i zrestartowaliśmy ją, a testy menu (100 i 40 żądań) kończą się bez błędów w ok. 0,1 s. Przyczyną była ręczna zmiana konfiguracji na klastrze, która wyczerpywała pulę połączeń z bazą. Nie wiemy jeszcze, ilu użytkowników była dotknięta, ani czy zamówienia też zawodziły. Nadal pracujemy nad zabezpieczeniem, żeby to się nie powtórzyło: skrócenie oczekiwania na bazę, wykrywanie ręcznych zmian konfiguracji i rozszerzenie testu kontrolnego. Następna aktualizacja o 15:15 (PL).

Do sprawdzenia przez człowieka:
- czy zdanie o przyczynie jest już dopuszczalne: potwierdzone danymi (wiersze 1 i 2 diagnozy), ale nie wiadomo, **kto** i **po co** zmienił konfigurację, więc nie wskazuję osób,
- godzina „15:15" to propozycja, nie ustalenie,
- „bez błędów" dotyczy testów menu, a nie ruchu użytkowników.

## Komunikat (szkic [AI], do poprawy)

**Wersja 1 [AI]** (z szablonu `docs/prompts/komunikat-incydentu.md`, odbiorca: zespoły):

> Część użytkowników widzi wolne ładowanie menu lub błąd. Problem trwa od ok. 14:18 (PL). Menu bywa niedostępne, zamówienia mogą się nie udawać. Zespół zawęził problem do konfiguracji usługi zamówień i przywraca ją. Następna aktualizacja o 14:45 (PL).

**Poprawki człowieka** (powód: komunikat nie ma obiecywać nic, czego jeszcze nie wiemy):
- „od ok. 14:18" → „najwcześniej od 14:18 (PL)". To czas zmiany konfiguracji z `managedFields`, a początek wpływu na użytkowników jest nieznany.
- „zamówienia mogą się nie udawać" → usunięte. Menu zostało zmierzone, zamówień nie testowałem pod awarią.
- „zawęził problem do konfiguracji… i przywraca ją" → „badamy". To była hipoteza, a „przywraca" obiecuje naprawę.
- Dodano, że skala wpływu jest nieznana (brak dostępu do metryk).

**Wersja 2 (do wysłania):**

> Zgłoszono, że menu w Kantynie ładuje się bardzo wolno, a część użytkowników dostaje błąd. W naszym środowisku testowym potwierdziliśmy to dla menu, a zakres poza nim jest jeszcze nieznany. Problem występuje najwcześniej od 14:18 (PL), a dokładnego początku i liczby poszkodowanych użytkowników jeszcze nie znamy. Badamy przyczynę i na razie nie podajemy jej ani terminu naprawy. Następna aktualizacja o 14:50 (PL), nawet jeśli nie będzie nowych ustaleń.

## Post-mortem (szkic, blameless)

**Podsumowanie.** Ręczna zmiana ConfigMapy `kantyna-flags` na klastrze włączyła flagi `db_pool_leak` i `slow_menu_query`. Pule połączeń `orders-api` wyczerpały się, `/readyz` zaczęło zwracać 503 i Service przestał mieć endpointy.

**Wpływ [D].** W teście przez `web`: 52 z 60 żądań menu zakończyło się 5xx (87%), jedno trwało 30 s. Oba pody orders-api `0/1`. Liczba realnych użytkowników i dokładny czas trwania są nieznane: brak dostępu do metryk Prometheusa.

**Oś czasu.**

| UTC | Zdarzenie |
|---|---|
| 12:17:50 | `kubectl patch` na ConfigMapie flag (dane: `managedFields`) |
| 12:24 | Wykrycie, `check.sh` 11/11, flagi `true` w ConfigMapie |
| 12:25-12:27 | Odtworzenie: pula 10/10, oba pody NotReady, 502 |
| 12:28:02 | Przywrócenie flag i restart orders-api |
| 12:28:34 | 100/100 żądań 200, `check.sh` 11/11 |

**Przyczyna źródłowa [D].** Konfiguracja na klastrze rozjechała się z repo (dryf) i nic tego nie wykrywa. Wyciek połączeń (`db_pool_leak`) wyczerpuje pulę po ok. 33 żądaniach menu na pod, a odpowiedź na wyczerpanie to 30 s oczekiwania, które kończy się 5xx i NotReady.

**Przyczyna współistniejąca [H].** `slow_menu_query` (N+1). Nie udało się wykazać wpływu na czas odpowiedzi.

**Co zadziałało.** Metadane `managedFields` wskazały moment i źródło zmiany. Odtwarzanie przez `web` ujawniło problem, którego nie widział `check.sh`.

**Co nie zadziałało.**
- `check.sh` daje 11/11 przy aktywnych flagach, bo sprawdza pojedyncze żądanie.
- Loadgen z `BASE_URL` na orders-api nie przechodzi przez NetworkPolicy i dawał mylący sygnał.
- Brak dostępu do Prometheusa/Grafany z konta uczestnika.

**Akcje (właściciele i terminy do ustalenia).**
1. Rozszerzyć `check.sh` o serię np. 50 żądań menu i sprawdzenie błędów.
2. Alert na dryf: porównanie flag w ConfigMapie z manifestem Helma, albo `helm diff` w pipeline'ie.
3. Zmiana flag wyłącznie przez commit i `helm upgrade` (bez `--reuse-values` dla `flags`).
4. Poprawić `BASE_URL` loadgena na `kantyna-web:8080`.
5. Krótszy timeout puli (`pool.open`/`connection(timeout=...)`), żeby wyczerpanie szybko zwracało 503 zamiast 30 s oczekiwania.

**Pytania otwarte.** Kto i po co zrobił `kubectl patch` o 12:17:50Z? Czy `slow_menu_query` ma wpływ przy większym menu? Jaki był ruch użytkowników?

## Do zrobienia przez człowieka (nie wykonane)

- Naprawa „commitem przez pipeline": w repo nie było co poprawić (`values.yaml` ma flagi `false`). Mitygacja została zrobiona ręcznie `kubectl patch`, więc **dryf konfiguracji zniknął, ale nie przez pipeline**. Pipeline reaguje tylko na zmiany w `app/**`. Zdecyduj, czy akcje 1-5 mają wejść jako commit.
- Metryki stabilne 5 minut na dashboardzie (brak dostępu do Grafany z tej sesji).
- Oznaczyć w tekście, co dopisało AI, a co poprawiłeś.
