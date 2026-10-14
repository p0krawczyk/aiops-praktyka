>> zly.yaml ma wskazany namespace na sztywno, wymyślony a nie prawdziwy.
>> dobry.yaml ma securityContext.
>> dobry.yaml ma wartości env (część wskazana wprost, część z sekretów po jego referencji).

>> dobry.yaml przydzielił dziwną ilość cpu i memory (100 milionów cpu, 384 MB RAM?).

# Wypełnij szablon docs/prompts/diagnoza.md. W polu „Dane” wskaż tylko plik lab01b/awaria-zred.txt. Oczekiwany format odpowiedzi to tabela: hipoteza · dowód z danych · komenda weryfikująca.
⧉ Selected 1 lines from labs\lab01b-prompty\README.md in Visual Studio Code

  Read 2 files

Wypełniony szablon diagnoza.md

Jesteś SRE. Środowisko: Kubernetes/EKS 1.36 (węzły v1.36.1-eks), eu-central-1, namespace kantyna, orders-api 1.0.0 (variant default), postgres:17-alpine jako StatefulSet, PVC gp3 5Gi RWO.
Objaw: od ok. 07:10 502 na /api/menu i /api/orders. Wczoraj o 18:00 wymieniono node group (nowy typ instancji), od tego czasu nikt nic nie wdrażał.
Dane:
lab01b/awaria-zred.txt   (get pods, logs --previous orders-api, describe pod postgres-0, get pvc, get nodes -L zone,instance-type)
Już sprawdziłem: Ingress i Service web działają, web zwraca stronę, błąd pojawia się dopiero przy wywołaniu orders-api.
Zadanie: podaj 3 najbardziej prawdopodobne hipotezy, od najbardziej prawdopodobnej.
Ograniczenia: proponuj tylko komendy read-only. Nie proponuj jeszcze poprawki.
Jeśli brakuje danych, napisz, jakiej komendy potrzebujesz, zamiast zgadywać.
Format: tabela | hipoteza | dowód z danych powyżej | komenda weryfikująca |.

Diagnoza na podstawie lab01b/awaria-zred.txt

┌────────────────────────────────────────────────────────────────────────────┬──────────────────────────────────────────────────────────┬───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                  hipoteza                                  │                                    dowód z danych                                    │                                               komenda weryfikująca                                                │
├────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 1. Konflikt strefy PV i węzłów (najbardziej prawdopodobna). Wolumen EBS    │ postgres-0 jest Pending i ma Node: <none>. Zdarzenia: 0/3 nodes ... had volume node  │                                                                                                                   │
│ jest przypięty do strefy, w której nie ma już żadnego węzła. Nowa node     │ affinity conflict (x9). Wszystkie 3 węzły są w euod 19   │ kubectl get pv pvc-3e8a91c4-27d5-4b0f-9c6e-5a1f0d7b2e48 -o jsonpath='{.spec.nodeAffinity}' oraz kubectl get pv    │
│ group działa tylko w eu-central-1a, więc postgres-0 nie może się           │ dni, czyli PV powstał przed wymianą node group. Strefa PV nie jest w danych, więc to │ pvc-3e8a91c4-27d5-4b0f-9c6e-5a1f0d7b2e48 -L topology.kubernetes.io/zone                                           │
│ zaplanować.                                                                │  wniosek pośredni.                                       │                                                                                                                   │
├────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 2. Awaria orders-api to skutek, nie przyczyna. Baza nie działa, więc       │ W logach --previous jest 5x Connection refused do        │                                                                                                                   │
│ orders-api kończy start po 5 nieudanych próbach i wchodzi w                │ (172.20.41.118:5432). Potem startup failed: database unavailable. Obie repliki mają  │ kubectl -n kantyna get endpoints kantyna-postgres (puste endpoints potwierdzą brak backendu) oraz kubectl -n      │
│ CrashLoopBackOff. Błąd nie leży w samej aplikacji ani w jej konfiguracji.  │ CrashLoopBackOff (11 restartów, 41 min), a paymenzas     │ kantyna get svc kantyna-postgres -o wide                                                                          │
│                                                                            │ pokrywa się z Pending bazy (41 min). Konfiguracja (db_url, port) wygląda poprawnie.  │                                                                                                                   │
├────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 3. Inna blokada schedulera przy StatefulSecie, np. zone-aware StorageClass │ Zdarzenie podaje tylko ogólne volume node affinity conflict i nie wskazuje strefy.   │                                                                                                                   │
│  lub selektory i taints nowej node group. Przyczyną mogłaby być zmiana,    │ Wszystkie 3 węzły są w jednej strefie (1a) i mająe. W    │ kubectl get storageclass gp3 -o yaml (sprawdź volumeBindingMode i allowedTopologies) oraz kubectl -n kantyna get  │
│ która nie dotyczy samej strefy: brak węzłów w wymaganej strefie, inna      │ danych brakuje StorageClass, nodeAffinity w PV i definicji StatefulSetu.             │ sts kantyna-postgres -o jsonpath='{.spec.template.spec.nodeSelector}{"\n"}{.spec.template.spec.tolerations}'      │
│ etykieta strefy albo WaitForFirstConsumer w StorageClass.                  │                                                          │                                                                                                                   │
└────────────────────────────────────────────────────────────────────────────┴──────────────────────────────────────────────────────────────────────────────────────┴───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Braki w danych

- Nie ma strefy PV. Komendy z hipotezy 1 rozstrzygną, czy to konflikt stref.
- Nie ma informacji, w jakich strefach działała poprzednia node group ani jakie strefy obejmuje obecna (aws eks describe-nodegro
- Daty w logach (2026-10-05) nie zgadzają się z dzisiejszą (2026-10-14). Zgłoszenie jest opisane jako poniedziałek 07:52, więc to prawdopodobnie zanonimizowany lub zmieniony przykład. Warto to sprawdzić, zanim uznasz korelację czasową za twardy dowód.

Zgodnie z ograniczeniami nie proponuję jeszcze poprawki.

✻ Sautéed for 20s · done 1:45 PM

※ recap: Cel to diagnoza awarii Kantyny (502) z szablonu `diagnoza.md` na danych z `lab01b/awaria-zred.txt`; tabelę z trzema hipotezami już podałem. Następny krok: uruchom pierwszą komendę weryfikującą, czyli sprawdź strefę PV przez `kubectl get pv ... -L topology.kubernetes.io/zone`. (disable recaps in /config)

>> Brak halucynacyji, wszystkie dowody pokrywają się z plikiem awaria-zred.txt
>> Ponownie brak halucynacji, dowody są w innej kolejności